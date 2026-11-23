# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserRoles::Operation::Assign do
  let_it_be(:customer) { create(:customer) }
  let(:user)     { create(:user, customer: customer) }
  let(:r1)       { create(:role, customer: customer, key: "a") }
  let(:r2)       { create(:role, customer: customer, key: "b") }

  it "replaces user's roles with the given role_ids set" do
    member_role = customer.roles.find_or_create_by!(key: "member") do |role|
      role.name = "Member"
      role.system = true
      role.locked_grants = true
    end
    user.users_roles.create!(role: r1)
    described_class.call(user: user, role_ids: [member_role.id, r2.id])
    expect(user.reload.role_ids).to match_array([member_role.id, r2.id])
  end

  it "rejects cross-customer role assignment" do
    other = create(:customer)
    other_role = create(:role, customer: other)
    result = described_class.call(user: user, role_ids: [other_role.id])
    expect(result.success?).to be false
    expect(result[:errors][:base]).to eq([I18n.t("admin_modules.flash.users.invalid_role")])
    expect(user.reload.role_ids).to be_empty
  end

  it "is atomic — invalid id rolls back partial inserts" do
    described_class.call(user: user, role_ids: [r1.id, -1])
    expect(user.reload.role_ids).to be_empty
  end

  it "does not leak ActiveRecord exception text for an unknown role id" do
    result = described_class.call(user: user, role_ids: [-1])
    expect(result.success?).to be false
    expect(result[:errors][:base]).to eq([I18n.t("admin_modules.flash.users.invalid_role")])
    expect(result[:errors][:base].join).not_to include("Couldn't find")
    expect(result[:errors][:base].join).not_to include("Validation failed")
  end

  it "rejects an assignment that would leave the user with no reserved role" do
    result = described_class.call(user: user, role_ids: [r1.id])
    expect(result.success?).to be false
    expect(result[:errors][:base]).to eq([I18n.t("auth.errors.reserved_role_required")])
    expect(user.reload.role_ids).to be_empty
  end

  # B4: a non-owner must not be able to strip/replace the platform owner's
  # roles through the multi-assign path (mirrors the single-user
  # Admin::Modules::Authentication::UsersController#assign_user_role guard).
  describe "owner-role protection" do
    let(:owner_user)  { find_or_create_platform_owner }
    let(:member_role) { owner_user.customer.roles.find_by!(key: "member") }
    let(:owner_role)  { owner_user.customer.roles.find_by!(key: "owner") }

    it "refuses when the actor is a non-owner admin — success? false with the reserved base error" do
      non_owner_admin = create(:user, :admin, customer: owner_user.customer)

      result = described_class.call(user: owner_user, role_ids: [member_role.id], actor: non_owner_admin)

      expect(result.success?).to be false
      expect(result[:errors][:base]).to include(I18n.t("auth.errors.owner_role_protected"))
    end

    it "does not destroy the owner's existing roles when refused" do
      non_owner_admin = create(:user, :admin, customer: owner_user.customer)

      described_class.call(user: owner_user, role_ids: [member_role.id], actor: non_owner_admin)

      expect(owner_user.reload.role_ids).to eq([owner_role.id])
      expect(owner_user.owner?).to be true
    end

    it "refuses when no actor is supplied at all (nil actor is never treated as owner)" do
      result = described_class.call(user: owner_user, role_ids: [])

      expect(result.success?).to be false
      expect(owner_user.reload.owner?).to be true
    end

    it "rejects demoting the pinned owner even when the actor is the owner" do
      result = described_class.call(user: owner_user, role_ids: [member_role.id], actor: owner_user)

      expect(result.success?).to be false
      expect(owner_user.reload.role_ids).to eq([owner_role.id])
    end

    it "preserves the fixed owner join while the owner edits supplementary custom roles" do
      custom = create(:role, customer: owner_user.customer)
      original_join = owner_user.users_roles.find_by!(role: owner_role)

      result = described_class.call(user: owner_user, role_ids: [owner_role.id, custom.id], actor: owner_user)
      expect(result.success?).to be(true)
      expect(owner_user.users_roles.find_by!(role: owner_role).id).to eq(original_join.id)

      result = described_class.call(user: owner_user, role_ids: [owner_role.id], actor: owner_user)
      expect(result.success?).to be(true)
      expect(owner_user.reload.role_ids).to eq([owner_role.id])
      expect(owner_user.users_roles.find_by!(role: owner_role).id).to eq(original_join.id)
    end

    it "does not block role changes for a non-owner target user" do
      non_owner_admin = create(:user, :admin, customer: customer)
      member_role = customer.roles.find_or_create_by!(key: "member") do |role|
        role.name = "Member"
        role.system = true
        role.locked_grants = true
      end
      result = described_class.call(user: user, role_ids: [member_role.id, r1.id], actor: non_owner_admin)

      expect(result.success?).to be true
      expect(user.reload.role_ids).to match_array([member_role.id, r1.id])
    end
  end

  it "rejects assigning more than one reserved role" do
    admin_role = customer.roles.find_or_create_by!(key: "admin") do |role|
      role.name = "Admin"
      role.system = true
      role.locked_grants = true
    end
    member_role = customer.roles.find_or_create_by!(key: "member") do |role|
      role.name = "Member"
      role.system = true
      role.locked_grants = true
    end
    user.users_roles.create!(role: admin_role)

    result = described_class.call(user: user, role_ids: [admin_role.id, member_role.id])

    expect(result.success?).to be false
    expect(result[:errors][:base]).to include(I18n.t("auth.errors.single_reserved_role"))
    expect(user.reload.role_ids).to eq([admin_role.id])
  end

  it "replaces a reserved role without deleting its join or retaining stale role predicates" do
    member_role = customer.roles.system.find_by!(key: "member")
    admin_role = customer.roles.system.find_by!(key: "admin")
    original = user.users_roles.create!(role: member_role)
    expect(user.member?).to be(true)

    result = described_class.call(user: user, role_ids: [admin_role.id, r1.id])

    expect(result.success?).to be(true)
    expect(user.users_roles.find(original.id).role_id).to eq(admin_role.id)
    expect(user.member?).to be(false)
    expect(user.admin?).to be(true)
  end

  it "rolls the reserved replacement back if inserting a custom assignment fails" do
    member_role = customer.roles.system.find_by!(key: "member")
    admin_role = customer.roles.system.find_by!(key: "admin")
    original = user.users_roles.create!(role: member_role)
    allow_any_instance_of(UsersRole).to receive(:save!).and_wrap_original do |method, *args|
      if method.receiver.role_id == r1.id
        raise ActiveRecord::RecordInvalid.new(method.receiver)
      end
      method.call(*args)
    end

    result = described_class.call(user: user, role_ids: [admin_role.id, r1.id])

    expect(result.success?).to be(false)
    expect(original.reload.role_id).to eq(member_role.id)
    expect(user.reload.role_ids).to eq([member_role.id])
  end
end
