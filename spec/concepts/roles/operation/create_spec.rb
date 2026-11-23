# frozen_string_literal: true

require "rails_helper"

RSpec.describe Roles::Operation::Create do
  let_it_be(:customer) { create(:customer) }

  it "creates a custom role" do
    result = described_class.call(
      customer: customer,
      params: { name: "Manager", key: "manager", description: "Mid-level admin" }
    )
    expect(result.success?).to be true
    role = result[:model]
    expect(role.persisted?).to be true
    expect(role).not_to be_system
    expect(role).not_to be_locked_grants
  end

  it "rejects when key is missing" do
    result = described_class.call(customer: customer, params: { name: "X", key: "" })
    expect(result.success?).to be false
  end

  it "rejects when key duplicates an existing role for the same customer" do
    create(:role, customer: customer, key: "manager")
    result = described_class.call(customer: customer, params: { name: "M", key: "manager" })
    expect(result.success?).to be false
  end

  it "routes the duplicate-key error through I18n (B11)" do
    create(:role, customer: customer, key: "manager")
    result = described_class.call(customer: customer, params: { name: "M", key: "manager" })
    expect(result[:errors][:key]).to include(I18n.t("auth.errors.role_key_taken"))
  end

  it "allows the same key for a different customer (no cross-tenant uniqueness)" do
    other_customer = create(:customer)
    create(:role, customer: other_customer, key: "manager")
    result = described_class.call(customer: customer, params: { name: "Manager", key: "manager" })
    expect(result.success?).to be true
  end

  it "rejects when name is blank even if key is unique" do
    result = described_class.call(customer: customer, params: { name: "", key: "manager" })
    expect(result.success?).to be false
    expect(result[:errors]).to be_present
  end
end
