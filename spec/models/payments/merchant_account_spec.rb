require "rails_helper"

RSpec.describe Payments::MerchantAccount, type: :model do
  let_it_be(:customer) { create(:customer) }

  let(:wechat_account) do
    described_class.create!(provider: "wechat_pay", mode: "sandbox", merchant_id: "m1")
  end

  before { Current.customer = customer }

  it "requires provider, mode, merchant_id" do
    acc = described_class.new(mode: nil)
    expect(acc.valid?).to be false
    expect(acc.errors.attribute_names).to include(:provider, :mode, :merchant_id)
  end

  it "validates provider inclusion against the gateway registry" do
    acc = described_class.new(provider: "not_a_real_gateway", mode: "sandbox", merchant_id: "x")
    expect(acc.valid?).to be false
    expect(acc.errors[:provider]).to be_present
  end

  it "accepts every registered gateway as a valid provider" do
    Payments::Gateways.keys.each do |key|
      acc = described_class.new(provider: key.to_s, mode: "sandbox", merchant_id: "m")
      acc.valid?
      expect(acc.errors[:provider]).to be_empty
    end
  end

  it "stores credentials encrypted at rest" do
    acc = wechat_account
    acc.write_credentials(api_key_v3: "secret")
    acc.save!
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT credentials FROM payment_merchant_accounts WHERE id=#{acc.id}"
    )
    expect(raw).not_to include("secret")
    expect(acc.reload.credential(:api_key_v3)).to eq("secret")
  end

  describe "#write_credentials" do
    it "merges into the existing JSON blob without clobbering unrelated keys" do
      acc = wechat_account
      acc.write_credentials(api_key_v3: "first", wechat_cert_serial: "S1")
      acc.save!
      acc.reload.write_credentials(api_key_v3: "second")
      acc.save!
      expect(acc.reload.credential(:api_key_v3)).to eq("second")
      expect(acc.credential(:wechat_cert_serial)).to eq("S1")
    end

    it "treats blank values as 'keep the existing one' (so the form does not clobber secrets)" do
      acc = wechat_account
      acc.write_credentials(api_key_v3: "first")
      acc.save!
      acc.reload.write_credentials(api_key_v3: "")
      acc.save!
      expect(acc.reload.credential(:api_key_v3)).to eq("first")
    end
  end

  describe "#gateway_class" do
    it "resolves to the registered gateway for the row's provider" do
      acc = described_class.new(provider: "alipay")
      expect(acc.gateway_class).to eq(Payments::Gateways::Alipay)
    end
  end

  def acct(status: "active", merchant_id: "M1")
    a = described_class.new(customer_id: customer.id, provider: "alipay", mode: "sandbox",
                            merchant_id: merchant_id, status: status)
    a.write_credentials(private_key_pem: "x", platform_public_key_pem: "y")
    a
  end

  describe "#configured?" do
    it "is true when enabled, real merchant_id, and all credentials present" do
      expect(acct).to be_configured
    end

    it "is false when disabled" do
      expect(acct(status: "disabled")).not_to be_configured
    end

    it "is false for the provisioner placeholder merchant_id" do
      expect(acct(merchant_id: "unset-alipay-sandbox-#{customer.id}")).not_to be_configured
    end

    it "is false when a required credential is missing" do
      a = described_class.new(customer_id: customer.id, provider: "alipay", mode: "sandbox",
                              merchant_id: "M1", status: "active")
      a.write_credentials(private_key_pem: "x") # platform_public_key_pem missing
      expect(a).not_to be_configured
    end
  end

  it "rejects a merchant_id already used on the same provider" do
    described_class.create!(provider: "alipay", mode: "sandbox", merchant_id: "TAKEN")
    other = create(:customer)
    Current.customer = other
    dup = described_class.new(provider: "alipay", mode: "sandbox", merchant_id: "TAKEN")
    expect(dup).not_to be_valid
    expect(dup.errors[:merchant_id]).to be_present
  end

  it "scopes to current customer via for_current_customer" do
    other = create(:customer)
    Current.customer = other
    described_class.create!(provider: "alipay", mode: "sandbox", merchant_id: "A", status: "active")
    Current.customer = customer
    expect(described_class.for_current_customer).to be_empty
  end
end
