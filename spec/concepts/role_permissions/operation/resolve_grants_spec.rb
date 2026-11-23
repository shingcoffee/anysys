# frozen_string_literal: true

require "rails_helper"

RSpec.describe RolePermissions::Operation::ResolveGrants do
  let_it_be(:customer) { create(:customer) }
  let(:role)     { create(:role, customer: customer) }

  it "returns role_permissions for the given role_ids" do
    rp1 = create(:role_permission, role: role, action: "read",   subject_key: "a")
    rp2 = create(:role_permission, role: role, action: "create", subject_key: "a")

    grants = described_class.call(role_ids: [role.id])
    expect(grants).to contain_exactly(rp1, rp2)
  end

  it "returns empty for unknown role_ids" do
    expect(described_class.call(role_ids: [-1])).to eq([])
  end

  it "returns multiple grant rows when same key exists across roles" do
    role2 = create(:role, customer: customer)
    rp = create(:role_permission, role: role, action: "read", subject_key: "x")
    create(:role_permission, role: role2, action: "read", subject_key: "x")
    grants = described_class.call(role_ids: [role.id, role2.id])
    expect(grants.size).to eq(2)
    expect(grants).to include(rp)
  end

  it "returns empty when role_ids is an empty array" do
    create(:role_permission, role: role, action: "read", subject_key: "a")
    expect(described_class.call(role_ids: [])).to eq([])
  end

  it "returns empty when role_ids is nil" do
    expect(described_class.call(role_ids: nil)).to eq([])
  end
end
