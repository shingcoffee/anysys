# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ability do
  let_it_be(:customer) { create(:customer) }

  describe "anonymous" do
    it "grants nothing" do
      ability = described_class.new(nil)
      expect(ability.can?(:read, :route_admin_dashboards)).to be false
    end
  end

  describe "admin reserved role" do
    it "grants :manage, :all within the tenant" do
      user = create(:user, customer: customer, role: :admin)

      ability = described_class.new(user)
      expect(ability.can?(:manage, :anything)).to be true
      expect(ability.can?(:destroy, Entity)).to be true
    end

    it "denies platform-only subjects" do
      user = create(:user, customer: customer, role: :admin)

      ability = described_class.new(user)
      expect(ability.can?(:manage, :platform_customers)).to be false
      expect(ability.can?(:manage, :platform_announcements)).to be false
      expect(ability.can?(:manage, :platform_support_tickets)).to be false
      expect(ability.can?(:manage, :platform_ai_assistant)).to be false
    end

    it "denies flowchart route subjects that :manage, :all would otherwise allow" do
      user = create(:user, customer: customer, role: :admin)

      ability = described_class.new(user)
      expect(ability.can?(:read, :route_admin_maintenance_flowcharts)).to be false
      expect(ability.can?(:read, :route_admin_maintenance_flowchart_traces)).to be false
      expect(ability.can?(:read, :route_admin_dashboards)).to be true
    end
  end

  describe "data-driven grants" do
    let(:user) { create(:user, customer: customer) }
    let(:role) { create(:role, customer: customer) }

    before { user.users_roles.create!(role: role) }

    it "grants Route subject from RolePermission" do
      role.role_permissions.create!(
        subject_type: "Route", subject_key: "admin/maintenance/pages", action: "read"
      )
      ability = described_class.new(user)
      expect(ability.can?(:read, :route_admin_maintenance_pages)).to be true
      expect(ability.can?(:read, :route_admin_dashboards)).to be false
    end

    it "ignores leftover flowchart route grants for non-platform-owners" do
      role.role_permissions.create!(
        subject_type: "Route", subject_key: "admin/maintenance/flowcharts", action: "read"
      )
      ability = described_class.new(user)
      expect(ability.can?(:read, :route_admin_maintenance_flowcharts)).to be false
    end

    it "grants EntityClass subject" do
      role.role_permissions.create!(
        subject_type: "EntityClass", subject_key: "Entity", action: "manage"
      )
      ability = described_class.new(user)
      expect(ability.can?(:read, Entity)).to be true
      expect(ability.can?(:destroy, Entity)).to be true
    end

    it "grants Entity instance subject scoped to id" do
      e1 = create(:entity, customer: customer)
      e2 = create(:entity, customer: customer)
      role.role_permissions.create!(
        subject_type: "Entity", subject_id: e1.id, action: "update"
      )
      ability = described_class.new(user)
      expect(ability.can?(:update, e1)).to be true
      expect(ability.can?(:update, e2)).to be false
    end

    it "grants Module subject" do
      role.role_permissions.create!(
        subject_type: "Module", subject_key: "payments", action: "manage"
      )
      ability = described_class.new(user)
      expect(ability.can?(:manage, :module_payments)).to be true
    end

    it "grants FeaturePage subject" do
      role.role_permissions.create!(
        subject_type: "FeaturePage", subject_key: "billing_overview", action: "read"
      )
      ability = described_class.new(user)
      expect(ability.can?(:read, :feature_billing_overview)).to be true
    end

    it "grants Platform subject" do
      role.role_permissions.create!(
        subject_type: "Platform", subject_key: "code_generators", action: "manage"
      )
      ability = described_class.new(user)
      expect(ability.can?(:manage, :platform_code_generators)).to be true
    end
  end

  describe "tenant safety for instance grants" do
    let(:other_customer) { create(:customer) }
    let(:user)           { create(:user, customer: customer) }
    let(:role)           { create(:role, customer: customer) }

    before { user.users_roles.create!(role: role) }

    it "denies an Entity grant whose record belongs to another customer" do
      foreign_entity = create(:entity, customer: other_customer)
      # Bypass model validation to simulate stale or corrupted grant data —
      # cancancan must still refuse to honor it.
      grant = role.role_permissions.build(
        subject_type: "Entity", subject_id: foreign_entity.id, action: "update"
      )
      grant.save!(validate: false)

      ability = described_class.new(user)
      expect(ability.can?(:update, foreign_entity)).to be false
    end

    it "denies a Page grant whose record belongs to another customer" do
      foreign_page = create(:page, customer: other_customer)
      grant = role.role_permissions.build(
        subject_type: "Page", subject_id: foreign_page.id, action: "update"
      )
      grant.save!(validate: false)

      ability = described_class.new(user)
      expect(ability.can?(:update, foreign_page)).to be false
    end
  end

  describe "malformed action handling" do
    let(:user) { create(:user, customer: customer) }
    let(:role) { create(:role, customer: customer) }

    before { user.users_roles.create!(role: role) }

    it "ignores grants with non-allowlisted actions even when persisted unvalidated" do
      grant = role.role_permissions.build(
        subject_type: "Route", subject_key: "admin/anything", action: "exfiltrate"
      )
      grant.save!(validate: false)

      ability = described_class.new(user)
      expect(ability.can?(:exfiltrate, :route_admin_anything)).to be false
      expect(ability.can?(:read,        :route_admin_anything)).to be false
    end

    it "translates 'manage' string action to :manage symbol" do
      role.role_permissions.create!(
        subject_type: "Route", subject_key: "admin/entities", action: "manage"
      )
      ability = described_class.new(user)
      expect(ability.can?(:read,    :route_admin_entities)).to be true
      expect(ability.can?(:destroy, :route_admin_entities)).to be true
    end
  end

  describe "member reserved role" do
    it "grants access to member route subjects" do
      user = create(:user, customer: customer, role: :member)
      ability = described_class.new(user)
      expect(ability.can?(:manage, :route_member_dashboards)).to be true
      expect(ability.can?(:manage, :route_member_profiles)).to be true
    end

    it "does not grant access to admin routes" do
      user = create(:user, customer: customer, role: :member)
      ability = described_class.new(user)
      expect(ability.can?(:manage, :route_admin_dashboards)).to be false
    end
  end

  describe "PageClass grant" do
    let(:user) { create(:user, customer: customer) }
    let(:role) { create(:role, customer: customer) }

    before { user.users_roles.create!(role: role) }

    it "grants action on Page class" do
      role.role_permissions.create!(
        subject_type: "PageClass", subject_key: "Page", action: "read"
      )
      ability = described_class.new(user)
      expect(ability.can?(:read, Page)).to be true
    end
  end

  describe "platform owner" do
    let(:platform_customer) { Customer.find_by(id: 81_721_200) || create(:customer, id: 81_721_200) }

    it "grants :manage, :all including platform subjects" do
      Current.customer = platform_customer
      # Build a user stub so we avoid creating a duplicate platform owner email
      owner_user = build(:user, customer: platform_customer, email: "lingercoffee@gmail.com")
      allow(owner_user).to receive(:platform_owner?).and_return(true)
      ability = described_class.new(owner_user)
      expect(ability.can?(:manage, :platform_customers)).to be true
      expect(ability.can?(:manage, :platform_ai_assistant)).to be true
      expect(ability.can?(:destroy, Entity)).to be true
    end
  end

  describe "instance grant guards (grant_instance)" do
    let(:user) { create(:user, customer: customer) }
    let(:role) { create(:role, customer: customer) }

    before { user.users_roles.create!(role: role) }

    it "skips grant when subject_id is blank (guard 1)" do
      # Inject a fake grant with nil id bypassing DB check constraints
      fake_grant = instance_double(RolePermission,
                                   action: "read",
                                   subject_type: "Entity",
                                   subject_id: nil,
                                   subject_key: nil)
      allow_any_instance_of(described_class).to receive(:grants_for).and_return([fake_grant])
      e = create(:entity, customer: customer)
      ability = described_class.new(user)
      expect(ability.can?(:read, e)).to be false
    end

    it "skips grant when customer_id is blank (guard 2)" do
      e = create(:entity, customer: customer)
      fake_grant = instance_double(RolePermission,
                                   action: "read",
                                   subject_type: "Entity",
                                   subject_id: e.id,
                                   subject_key: nil)
      allow_any_instance_of(described_class).to receive(:grants_for).and_return([fake_grant])
      # Build a user with no customer_id
      no_cust_user = build(:user, customer: nil)
      no_cust_user.customer_id = nil
      # Ability will use user.customer_id which is nil, so grant_instance returns early
      ability = described_class.new(no_cust_user)
      expect(ability.can?(:read, e)).to be false
    end
  end

  describe "apply_grant — unknown subject_type falls through case/else (no grant)" do
    let(:user) { create(:user, customer: customer) }
    let(:role) { create(:role, customer: customer) }

    before { user.users_roles.create!(role: role) }

    it "ignores grants with unrecognized subject_type" do
      fake_grant = instance_double(RolePermission,
                                   action: "read",
                                   subject_type: "UnknownSubject",
                                   subject_id: nil,
                                   subject_key: "whatever")
      allow_any_instance_of(described_class).to receive(:grants_for).and_return([fake_grant])
      ability = described_class.new(user)
      expect(ability.can?(:read, :route_unknown)).to be false
    end
  end

  describe "normalize_action — blank raw returns nil" do
    let(:user) { create(:user, customer: customer) }
    let(:role) { create(:role, customer: customer) }

    before { user.users_roles.create!(role: role) }

    it "skips grant when action is blank" do
      fake_grant = instance_double(RolePermission,
                                   action: "",
                                   subject_type: "Route",
                                   subject_id: nil,
                                   subject_key: "admin/entities")
      allow_any_instance_of(described_class).to receive(:grants_for).and_return([fake_grant])
      ability = described_class.new(user)
      expect(ability.can?(:read, :route_admin_entities)).to be false
    end
  end
end
