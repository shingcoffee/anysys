require "rails_helper"

RSpec.describe Payments::DefaultGateway do
  let_it_be(:customer) { create(:customer) }

  it "stores one default per customer (unique)" do
    described_class.unscoped_by_tenant.create!(customer_id: customer.id, provider: "alipay")
    dup = described_class.unscoped_by_tenant.new(customer_id: customer.id, provider: "stripe")
    expect(dup).not_to be_valid
  end

  describe ".provider_for" do
    it "returns the stored provider or nil" do
      expect(described_class.provider_for(customer.id)).to be_nil
      described_class.unscoped_by_tenant.create!(customer_id: customer.id, provider: "alipay")
      expect(described_class.provider_for(customer.id)).to eq("alipay")
    end
  end
end
