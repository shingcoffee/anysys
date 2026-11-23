# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsersRole, type: :model do
  let_it_be(:customer) { create(:customer) }

  let(:user) { create(:user, customer: customer) }
  let(:role) { create(:role, customer: customer) }

  describe "validations" do
    it "rejects cross-customer assignment" do
      other_customer = create(:customer)
      role_in_other = create(:role, customer: other_customer)

      ur = build(:users_role, user: user, role: role_in_other)
      expect(ur).not_to be_valid
      expect(ur.errors[:role]).to include(/customer/i)
    end

    it "permits same-customer assignment" do
      expect(build(:users_role, user: user, role: role)).to be_valid
    end

    it "enforces uniqueness of (user_id, role_id)" do
      create(:users_role, user: user, role: role)
      dup = build(:users_role, user: user, role: role)
      expect(dup).not_to be_valid
    end
  end

  describe "owner role pinning" do
    let(:platform_customer) do
      Customer.find_or_create_by!(id: ::Authentication::User::PLATFORM_CUSTOMER_ID) do |c|
        c.name = "Platform"
        c.industry = :technology
        c.tier = :basic
      end
    end
    let(:owner_role_in_platform) do
      platform_customer.roles.find_or_create_by!(key: "owner") do |r|
        r.name = "Owner"
        r.system = true
        r.locked_grants = true
      end
    end
    let(:owner_role_in_tenant) do
      customer.roles.find_or_create_by!(key: "owner") do |r|
        r.name = "Owner"
        r.system = true
        r.locked_grants = true
      end
    end

    it "permits owner only for the pinned email under customer 81721200" do
      pinned_user = ::Authentication::User.find_or_create_by!(
        customer: platform_customer,
        email: ::Authentication::User::PLATFORM_OWNER_EMAIL
      ) do |u|
        u.first_name = "Platform"
        u.last_name  = "Owner"
        u.password   = "password123"
      end
      pinned_user.users_roles.joins(:role).where(roles: { system: true }).delete_all
      ur = build(:users_role, user: pinned_user, role: owner_role_in_platform)
      expect(ur).to be_valid
    end

    it "rejects owner for any other email even on the platform customer" do
      other_user = create(:user,
                          customer: platform_customer,
                          email: "someone-else@example.com")
      ur = build(:users_role, user: other_user, role: owner_role_in_platform)
      expect(ur).not_to be_valid
      expect(ur.errors[:role].join).to match(/reserved for the platform owner/i)
    end

    it "rejects owner on a non-platform customer" do
      tenant_user = create(:user,
                           customer: customer,
                           email: ::Authentication::User::PLATFORM_OWNER_EMAIL)
      ur = build(:users_role, user: tenant_user, role: owner_role_in_tenant)
      expect(ur).not_to be_valid
      expect(ur.errors[:role].join).to match(/reserved for the platform owner/i)
    end

    it "still permits admin/member roles on any tenant" do
      user = create(:user, customer: customer)
      admin_role = customer.roles.find_or_create_by!(key: "admin") do |r|
        r.name = "Admin"
        r.system = true
        r.locked_grants = true
      end
      ur = build(:users_role, user: user, role: admin_role)
      expect(ur).to be_valid
    end
  end

  describe "reserved assignment invariants" do
    let(:member) { create(:user, :member, customer: customer) }
    let(:join) { member.users_roles.first }
    let(:admin_role) { customer.roles.system.find_by!(key: "admin") }

    it "rejects destroying the sole reserved assignment" do
      expect { join.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(UsersRole.exists?(join.id)).to be(true)
      expect(Authentication::User.find(member.id)).to be_member
    end

    it "rejects creating a second reserved assignment while preserving custom assignments" do
      custom = create(:role, customer: customer)
      member.users_roles.create!(role: custom)
      duplicate = member.users_roles.build(role: admin_role)

      expect(duplicate.save).to be(false)
      expect(duplicate.errors[:base]).to include(I18n.t("auth.errors.single_reserved_role"))
      expect(member.reload.role_ids).to contain_exactly(join.role_id, custom.id)
    end

    it "can replace the reserved role in place but cannot replace it with a custom role" do
      original_id = join.id
      join.update!(role: admin_role)
      expect(join.id).to eq(original_id)

      expect(join.update(role: role)).to be(false)
      expect(join.reload.role_id).to eq(admin_role.id)
    end

    it "uses persisted assignment state when a stale instance attempts removal" do
      stale = UsersRole.find(join.id)
      join.update!(role: admin_role)

      expect { stale.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(join.reload.role_id).to eq(admin_role.id)
    end

    it "does not allow moving a reserved assignment to another account" do
      other = create(:user, customer: customer)
      expect(join.update(user: other)).to be(false)
      expect(join.reload.user_id).to eq(member.id)
    end

    it "prevents owner deletion and reassignment even by direct model mutation" do
      owner = find_or_create_platform_owner
      owner_join = owner.users_roles.joins(:role).find_by!(roles: { key: "owner" })
      expect { owner_join.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(owner_join.update(role: owner.customer.roles.system.find_by!(key: "admin"))).to be(false)
      expect(owner_join.reload.role.key).to eq("owner")
    end

    it "permits cascading removal when the account itself is destroyed" do
      join_id = join.id
      member.destroy!
      expect(UsersRole.exists?(join_id)).to be(false)
    end

    it "protects assignments from standalone reserved-role deletion" do
      assigned_role = join.role
      expect { assigned_role.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(UsersRole.exists?(join.id)).to be(true)
    end

    it "permits the role cascade of a customer that is being destroyed with its users" do
      assigned_role = join.role
      assigned_role.destroyed_by_association = Customer.reflect_on_association(:roles)
      assigned_role.destroy!
      expect(UsersRole.exists?(join.id)).to be(false)
    end

    it "clears reserved-role predicate state on reload" do
      expect(member.member?).to be(true)
      join.update!(role: admin_role)
      expect(member.reload.member?).to be(false)
      expect(member.admin?).to be(true)
    end
  end
end
