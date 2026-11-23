require "rails_helper"

RSpec.describe Payments::EligibleGateways do
  let_it_be(:customer) { create(:customer) }

  def configured_account(provider)
    a = Payments::MerchantAccount.unscoped_by_tenant.create!(
      customer_id: customer.id, provider: provider, mode: "sandbox",
      merchant_id: "M-#{provider}", status: "active"
    )
    Payments::Gateways.for(provider).credential_fields.each { |f| a.write_credentials(f[:name] => "v") }
    a.save!
    a
  end

  it "returns only platform-available, active, configured gateways" do
    Payments::PlatformGateway.for_provider("alipay").update!(available: true)
    Payments::PlatformGateway.for_provider("stripe").update!(available: false)
    configured_account("alipay")
    configured_account("stripe") # configured but NOT platform-available

    keys = described_class.for(customer).map(&:key)
    expect(keys).to include("alipay")
    expect(keys).not_to include("stripe")
  end

  it "optionally filters by supported currency" do
    Payments::PlatformGateway.for_provider("alipay").update!(available: true)
    Payments::PlatformGateway.for_provider("stripe").update!(available: true)
    configured_account("alipay")
    configured_account("stripe")

    expect(described_class.for(customer, currency: "USD").map(&:key)).to include("stripe")
    expect(described_class.for(customer, currency: "USD").map(&:key)).not_to include("alipay")
    expect(described_class.for(customer, currency: "CNY").map(&:key)).to include("alipay", "stripe")
  end

  it "excludes a configured account whose mode is not CredentialResolver's env mode" do
    Payments::PlatformGateway.for_provider("alipay").update!(available: true)
    a = Payments::MerchantAccount.unscoped_by_tenant.create!(
      customer_id: customer.id, provider: "alipay", mode: "production",
      merchant_id: "M-alipay-prod", status: "active"
    )
    Payments::Gateways.for("alipay").credential_fields.each { |f| a.write_credentials(f[:name] => "v") }
    a.save!

    expect(described_class.for(customer).map(&:key)).not_to include("alipay")
  end

  it "excludes disabled or unconfigured accounts" do
    Payments::PlatformGateway.for_provider("alipay").update!(available: true)
    Payments::MerchantAccount.unscoped_by_tenant.create!(
      customer_id: customer.id, provider: "alipay", mode: "sandbox",
      merchant_id: "unset-alipay-sandbox-#{customer.id}", status: "disabled"
    )
    expect(described_class.for(customer).map(&:key)).not_to include("alipay")
  end
end
