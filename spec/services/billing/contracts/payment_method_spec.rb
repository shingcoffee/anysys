# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::Contracts::PaymentMethod do
  it "validates currency-aware provider descriptors and request identity" do
    customer = build_stubbed(:customer)
    allow(Billing::AvailableProviders).to receive(:call).with(customer: customer, currency: "USD").and_return([{ key: "stripe" }])
    form = described_class.new(Billing::PaymentMethod.new)
    form.customer, form.currency = customer, "USD"
    expect(form.validate(provider: "stripe", request_key: SecureRandom.uuid)).to be(true)
    expect(form.validate(provider: "alipay", request_key: SecureRandom.uuid)).to be(false)
    expect(form.errors[:provider]).to be_present
  end
end
