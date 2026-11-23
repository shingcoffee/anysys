# frozen_string_literal: true

require "rails_helper"

RSpec.describe Roles::Operation::Update do
  let_it_be(:customer) { create(:customer) }
  let(:role) { create(:role, customer: customer, key: "manager") }

  it "updates name and description on a custom role" do
    result = described_class.call(role: role, params: { name: "Senior Manager", description: "x" })
    expect(result.success?).to be true
    expect(role.reload.name).to eq("Senior Manager")
  end

  it "does not change key (key is immutable post-create)" do
    described_class.call(role: role, params: { key: "boss", name: "Boss" })
    expect(role.reload.key).to eq("manager")
  end

  it "rejects updates to system roles" do
    sys = customer.roles.find_by(key: "admin")
    result = described_class.call(role: sys, params: { name: "Hacked" })
    expect(result.success?).to be false
  end

  it "routes the system-role error through I18n (B11)" do
    sys = customer.roles.find_by(key: "admin")
    result = described_class.call(role: sys, params: { name: "Hacked" })
    expect(result[:errors][:base]).to include(I18n.t("auth.errors.system_role_uneditable"))
  end

  it "fails when contract validation rejects the params and returns errors" do
    # Blank name fails the Reform contract validation
    result = described_class.call(role: role, params: { name: "", description: "x" })
    expect(result.success?).to be false
    expect(result[:errors]).to be_present
  end
end
