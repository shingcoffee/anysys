# frozen_string_literal: true

require "rails_helper"

RSpec.describe Roles::Operation::Destroy do
  let_it_be(:customer) { create(:customer) }

  it "destroys a custom role" do
    role = create(:role, customer: customer, key: "tmp_role")
    expect { described_class.call(role: role) }.to change { Role.count }.by(-1)
  end

  it "rejects destroying a system role" do
    role = customer.roles.find_by(key: "admin")
    result = described_class.call(role: role)
    expect(result.success?).to be false
    expect(Role.exists?(role.id)).to be true
  end

  it "routes the system-role error through I18n (B11)" do
    role = customer.roles.find_by(key: "admin")
    result = described_class.call(role: role)
    expect(result[:errors][:base]).to include(I18n.t("auth.errors.system_role_undeletable"))
  end
end
