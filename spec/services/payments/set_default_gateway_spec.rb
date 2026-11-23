require "rails_helper"

RSpec.describe Payments::SetDefaultGateway do
  let_it_be(:customer) { create(:customer) }

  def make_eligible(provider)
    Payments::PlatformGateway.for_provider(provider).update!(available: true)
    a = Payments::MerchantAccount.unscoped_by_tenant.create!(
      customer_id: customer.id, provider: provider, mode: "sandbox",
      merchant_id: "M-#{provider}", status: "active"
    )
    Payments::Gateways.for(provider).credential_fields.each { |f| a.write_credentials(f[:name] => "v") }
    a.save!
  end

  it "sets an eligible provider as the default" do
    make_eligible("alipay")
    described_class.call(customer: customer, provider: "alipay")
    expect(Payments::DefaultGateway.provider_for(customer.id)).to eq("alipay")
  end

  it "replaces the existing default (single row)" do
    make_eligible("alipay"); make_eligible("wechat_pay")
    described_class.call(customer: customer, provider: "alipay")
    described_class.call(customer: customer, provider: "wechat_pay")
    expect(Payments::DefaultGateway.unscoped_by_tenant.where(customer_id: customer.id).count).to eq(1)
    expect(Payments::DefaultGateway.provider_for(customer.id)).to eq("wechat_pay")
  end

  it "raises for an ineligible (unconfigured) provider" do
    expect { described_class.call(customer: customer, provider: "stripe") }
      .to raise_error(ArgumentError)
  end
end
