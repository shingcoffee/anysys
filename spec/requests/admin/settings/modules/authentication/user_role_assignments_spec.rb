# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/modules/authentication/user_role_assignments", type: :request do
  include_context "as admin"

  let(:owner_role)  { customer.roles.find_by(key: "owner") }
  let(:target_user) { create(:user, customer: customer, role: :member) }
  let(:member_role) { customer.roles.find_by!(key: "member") }
  let(:custom_role) { create(:role, customer: customer, key: "manager", name: "Manager") }
  let(:guard_path) { "/#{customer.id}/admin/settings/modules/authentication/user_role_assignments" }

  it_behaves_like "an admin-guarded GET"
  it_behaves_like "an admin-guarded request", :post

  describe "DELETE destroy — auth guards" do
    let(:assignment) { target_user.users_roles.create!(role: custom_role) }
    let(:guard_path) { "/#{customer.id}/admin/settings/modules/authentication/user_role_assignments/#{assignment.id}" }

    it_behaves_like "an admin-guarded request", :delete
  end

  describe "GET index" do
    it "lists users and their roles" do
      target_user.users_roles.create!(role: custom_role) # keep this - it's assigning a custom role to target_user
      get "/#{customer.id}/admin/settings/modules/authentication/user_role_assignments"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(target_user.email).and include("Manager")
    end
  end

  describe "POST create" do
    it "does not emit a mutation event for an unchanged role set" do
      target_user
      expect {
        post guard_path, params: { user_id: target_user.id, role_ids: [member_role.id] }, as: :json
      }.not_to change { Authentication::Event.where(user_id: target_user.id, event: %w[role_granted role_revoked]).count }

      expect(response).to have_http_status(:ok)
    end

    it "replaces user's roles with the given set" do
      post "/#{customer.id}/admin/settings/modules/authentication/user_role_assignments",
           params: { user_id: target_user.id, role_ids: [member_role.id, custom_role.id] },
           as: :json
      expect(response).to have_http_status(:success)
      expect(target_user.reload.role_ids).to match_array([member_role.id, custom_role.id])
    end

    it "records a role_granted audit event on success" do
      expect {
        post "/#{customer.id}/admin/settings/modules/authentication/user_role_assignments",
             params: { user_id: target_user.id, role_ids: [member_role.id, custom_role.id] },
             as: :json
      }.to change {
        Authentication::Event.where(event: "role_granted", user_id: target_user.id).count
      }.by(1)
    end

    it "returns an I18n error for an unknown role id instead of a RecordNotFound message" do
      post "/#{customer.id}/admin/settings/modules/authentication/user_role_assignments",
           params: { user_id: target_user.id, role_ids: [-1] },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = response.parsed_body
      expect(body["ok"]).to eq(false)
      expect(body["errors"]["base"]).to eq([I18n.t("admin_modules.flash.users.invalid_role")])
      expect(response.body).not_to include("Couldn't find Role")
    end

    it "rejects owner self-demotion through the assignment API" do
      owner_user = find_or_create_platform_owner
      sign_in owner_user
      replacement = owner_user.customer.roles.find_by!(key: "member")

      expect {
        post admin_settings_modules_authentication_user_role_assignments_path(owner_user.customer_id),
             params: { user_id: owner_user.id, role_ids: [replacement.id] }, as: :json
      }.not_to change { Authentication::Event.where(event: "role_granted").count }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("errors", "base")).to eq([
        I18n.t("admin_settings.errors.validations.role_owner_reserved")
      ])
      expect(owner_user.reload.owner?).to be(true)
    end
  end

  describe "DELETE destroy — reserved assignments and model rejection" do
    it "rejects deleting a member's sole reserved assignment" do
      assignment = target_user.users_roles.find_by!(role: member_role)

      expect {
        delete "#{guard_path}/#{assignment.id}"
      }.not_to change { Authentication::Event.where(event: "role_revoked").count }

      expect(response).to redirect_to(guard_path)
      expect(flash[:alert]).to eq(I18n.t("auth.errors.reserved_role_required"))
      expect(assignment.reload).to be_persisted
      expect(target_user.reload.member?).to be(true)
    end

    it "returns translated JSON errors when the sole reserved assignment cannot be removed" do
      assignment = target_user.users_roles.find_by!(role: member_role)
      delete "#{guard_path}/#{assignment.id}", as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq(
        "ok" => false, "errors" => { "base" => [I18n.t("auth.errors.reserved_role_required")] }
      )
      expect(UsersRole.exists?(assignment.id)).to be(true)
    end

    it "removes a supplemental assignment and audits it while retaining the reserved role" do
      assignment = target_user.users_roles.create!(role: custom_role)

      expect {
        delete "#{guard_path}/#{assignment.id}"
      }.to change { Authentication::Event.where(event: "role_revoked", user_id: target_user.id).count }.by(1)

      expect(response).to redirect_to(guard_path)
      expect(flash[:notice]).to eq(I18n.t("admin_settings.flash.user_role_assignments.removed"))
      expect(UsersRole.exists?(assignment.id)).to be(false)
      expect(target_user.reload.member?).to be(true)
    end

    it "translates a model rejection after the controller check without recording a revocation" do
      assignment = target_user.users_roles.create!(role: custom_role)
      allow_any_instance_of(UsersRole).to receive(:destroy!).and_wrap_original do |method|
        record = method.receiver
        if record.id == assignment.id
          record.errors.add(:base, I18n.t("auth.errors.reserved_role_required"))
          raise ActiveRecord::RecordNotDestroyed.new(nil, record)
        end
        method.call
      end

      expect {
        delete "#{guard_path}/#{assignment.id}", as: :json
      }.not_to change { Authentication::Event.where(event: "role_revoked").count }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig("errors", "base")).to eq([I18n.t("auth.errors.reserved_role_required")])
      expect(UsersRole.exists?(assignment.id)).to be(true)
    end
  end

  # ==========================================================================
  # The fixed owner assignment cannot be removed by any actor.
  # ==========================================================================
  describe "DELETE destroy — owner-role protection" do
    let(:owner_user) { find_or_create_platform_owner }
    let(:platform_customer) { owner_user.customer }
    let(:owner_ur) { owner_user.users_roles.joins(:role).find_by!(roles: { key: "owner" }) }

    context "when the actor is a non-owner admin of the same (platform) customer" do
      let(:non_owner_admin) { create(:user, :admin, customer: platform_customer) }

      before do
        sign_out :user if respond_to?(:sign_out)
        sign_in non_owner_admin
      end

      it "refuses and redirects with an alert" do
        delete "/#{platform_customer.id}/admin/settings/modules/authentication/user_role_assignments/#{owner_ur.id}"

        expect(response).to redirect_to(
          admin_settings_modules_authentication_user_role_assignments_path(platform_customer.id)
        )
        follow_redirect!
        # The flash text is HTML-escaped on render (the message contains an
        # apostrophe), so assert against the escaped form.
        expect(response.body).to include(CGI.escapeHTML(I18n.t("auth.errors.owner_role_protected")))
      end

      it "does not destroy the owner's role row" do
        delete "/#{platform_customer.id}/admin/settings/modules/authentication/user_role_assignments/#{owner_ur.id}"

        expect(UsersRole.exists?(owner_ur.id)).to be true
        expect(owner_user.reload.owner?).to be true
      end

      it "does not record a role_revoked audit event" do
        expect {
          delete "/#{platform_customer.id}/admin/settings/modules/authentication/user_role_assignments/#{owner_ur.id}"
        }.not_to change { Authentication::Event.where(event: "role_revoked").count }
      end
    end

    context "when the actor is the owner themselves" do
      before do
        sign_out :user if respond_to?(:sign_out)
        sign_in owner_user
      end

      it "rejects the removal with the translated fixed-owner error" do
        delete "/#{platform_customer.id}/admin/settings/modules/authentication/user_role_assignments/#{owner_ur.id}"

        expect(UsersRole.exists?(owner_ur.id)).to be true
        expect(owner_user.reload.owner?).to be(true)
        expect(response).to redirect_to(
          admin_settings_modules_authentication_user_role_assignments_path(platform_customer.id)
        )
        expect(flash[:alert]).to eq(I18n.t("admin_settings.errors.validations.role_owner_reserved"))
      end

      it "does not record a role_revoked audit event" do
        expect {
          delete "/#{platform_customer.id}/admin/settings/modules/authentication/user_role_assignments/#{owner_ur.id}"
        }.not_to change {
          Authentication::Event.where(event: "role_revoked", user_id: owner_user.id).count
        }
      end
    end
  end
end
