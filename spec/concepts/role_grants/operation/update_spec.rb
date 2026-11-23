# frozen_string_literal: true

require "rails_helper"

RSpec.describe RoleGrants::Operation::Update do
  let_it_be(:customer) { create(:customer) }
  let(:role)     { create(:role, customer: customer) }

  it "adds new grants in a transaction" do
    result = described_class.call(role: role, added: [
      { subject_type: "Route", subject_key: "admin/maintenance/pages", action: "read" },
      { subject_type: "Module", subject_key: "payments", action: "manage" }
    ], removed: [])
    expect(result.success?).to be true
    expect(role.role_permissions.count).to eq(2)
  end

  it "removes grants by composite key" do
    rp = create(:role_permission, role: role,
                subject_type: "Route", subject_key: "admin/x", action: "read")
    described_class.call(role: role, added: [],
      removed: [{ subject_type: "Route", subject_key: "admin/x", subject_id: nil, action: "read" }])
    expect(RolePermission.exists?(rp.id)).to be false
  end

  it "rejects update on a locked role" do
    role.update!(locked_grants: true)
    result = described_class.call(role: role,
      added: [{ subject_type: "Route", subject_key: "admin/x", action: "read" }],
      removed: [])
    expect(result.success?).to be false
    expect(role.role_permissions).to be_empty
  end

  it "routes the locked-role error through I18n (B11)" do
    role.update!(locked_grants: true)
    result = described_class.call(role: role,
      added: [{ subject_type: "Route", subject_key: "admin/x", action: "read" }],
      removed: [])
    expect(result[:errors][:base]).to include(I18n.t("auth.errors.role_grants_locked"))
  end

  it "is atomic — failure inside a batch rolls back" do
    bad = { subject_type: "Bogus", subject_key: "x", action: "read" }
    described_class.call(role: role, added: [
      { subject_type: "Route", subject_key: "ok", action: "read" }, bad
    ], removed: [])
    expect(role.role_permissions.reload).to be_empty
  end

  describe "platform-scoped grant guard (S2 / privilege escalation)" do
    let(:owner) { find_or_create_platform_owner }
    let(:admin) { create(:user, :admin, customer: customer) }

    it "rejects a non-owner adding a Platform-scoped grant" do
      result = described_class.call(role: role, actor: admin, added: [
        { subject_type: "Platform", subject_key: "customers", action: "manage" }
      ], removed: [])

      expect(result.success?).to be false
      expect(result[:errors][:base]).to include(I18n.t("auth.errors.platform_grant_forbidden"))
      expect(role.role_permissions.reload).to be_empty
    end

    it "rejects a Platform grant when no actor is supplied (fail-closed)" do
      result = described_class.call(role: role, added: [
        { subject_type: "Platform", subject_key: "customers", action: "manage" }
      ], removed: [])

      expect(result.success?).to be false
      expect(role.role_permissions.reload).to be_empty
    end

    it "rolls back a whole batch when it contains a Platform grant" do
      described_class.call(role: role, actor: admin, added: [
        { subject_type: "Route", subject_key: "admin/ok", action: "read" },
        { subject_type: "Platform", subject_key: "customers", action: "manage" }
      ], removed: [])

      expect(role.role_permissions.reload).to be_empty
    end

    it "allows the platform owner to add a Platform-scoped grant" do
      result = described_class.call(role: role, actor: owner, added: [
        { subject_type: "Platform", subject_key: "customers", action: "manage" }
      ], removed: [])

      expect(result.success?).to be true
      expect(role.role_permissions.reload.count).to eq(1)
    end

    it "rejects a non-owner adding a flowchart route grant" do
      result = described_class.call(role: role, actor: admin, added: [
        { subject_type: "Route", subject_key: "admin/maintenance/flowcharts", action: "read" }
      ], removed: [])

      expect(result.success?).to be false
      expect(result[:errors][:base]).to include(I18n.t("auth.errors.platform_grant_forbidden"))
      expect(role.role_permissions.reload).to be_empty
    end

    it "rejects a nested flowchart controller grant when no actor is supplied" do
      result = described_class.call(role: role, added: [
        { subject_type: "Route", subject_key: "admin/maintenance/flowchart_traces", action: "create" }
      ], removed: [])

      expect(result.success?).to be false
      expect(role.role_permissions.reload).to be_empty
    end

    it "allows the platform owner to add a flowchart route grant" do
      result = described_class.call(role: role, actor: owner, added: [
        { subject_type: "Route", subject_key: "admin/maintenance/flowcharts", action: "read" }
      ], removed: [])

      expect(result.success?).to be true
      expect(role.role_permissions.reload.count).to eq(1)
    end
  end

  describe "instance-based cross-tenant grant guard" do
    it "rejects adding an instance grant referencing another customer's record" do
      other_customer = create(:customer)
      other_entity   = create(:entity, customer: other_customer)

      result = described_class.call(role: role, added: [
        { subject_type: "Entity", subject_id: other_entity.id.to_s, action: "read" }
      ], removed: [])

      expect(result.success?).to be false
      expect(role.role_permissions.reload).to be_empty
    end

    it "allows adding an instance grant referencing own tenant's record" do
      own_entity = create(:entity, customer: customer)

      result = described_class.call(role: role, added: [
        { subject_type: "Entity", subject_id: own_entity.id.to_s, action: "read" }
      ], removed: [])

      expect(result.success?).to be true
      expect(role.role_permissions.reload.count).to eq(1)
    end
  end
end
