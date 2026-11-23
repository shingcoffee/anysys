# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExtendableModelRegistry do
  let(:customer) { Customer.create!(id: 999001, name: "Acme", industry: :technology) }

  it "returns only flagged models from modules enabled for the customer" do
    mod = FeatureModules::Module.create!(key: "payment_test_#{Time.current.to_i}", name: "Payments", status: :active)
    FeatureModules::CustomerAssignment.create!(customer: customer, feature_module: mod, status: :active)
    mod.set_extendable_model!("Payments::Order", true)

    result = described_class.for_customer(customer.id)
    expect(result.map { |r| r[:class_name] }).to include("Payments::Order")
    expect(result.first).to include(:label, :module_key)
  end

  it "does not English-titleize an extendable class demodulize" do
    mod = FeatureModules::Module.create!(key: "pm_test_#{Time.current.to_i}", name: "Payments", status: :active)
    FeatureModules::CustomerAssignment.create!(customer: customer, feature_module: mod, status: :active)
    mod.set_extendable_model!("Payments::PaymentMethod", true)

    row = described_class.for_customer(customer.id).find { |r| r[:class_name] == "Payments::PaymentMethod" }
    expect(row[:label]).to eq("PaymentMethod")
  end

  it "excludes models from modules not enabled for the customer" do
    mod = FeatureModules::Module.create!(key: "sms_test_#{Time.current.to_i}", name: "SMS", status: :active)
    mod.set_extendable_model!("Sms::Message", true)
    # no CustomerAssignment for this customer
    expect(described_class.for_customer(customer.id).map { |r| r[:class_name] }).not_to include("Sms::Message")
  end
end
