# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Settings::Modules::Authentication::ForgetPassword", type: :request do
  include_context "as admin"
  let(:guard_path) { admin_settings_modules_authentication_forget_password_path(customer.id) }

  it_behaves_like "an admin-guarded GET"

  let(:auth_module) { FeatureModules::Module.find_by!(key: "authentication") }

  let(:assignment) do
    FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: auth_module)
  end

  def sign_in_as_cross_tenant_admin
    sign_out admin
    sign_in create(:user, :admin, customer: create(:customer))
  end

  # ---------------------------------------------------------------------------
  # PATCH /:customer_id/admin/settings/modules/authentication/forget_password
  # ---------------------------------------------------------------------------
  describe "PATCH update" do
    context "enabling password reset" do
      before do
        assignment.update!(configuration: { "allow_password_reset" => false }.to_json)
      end

      it "persists allow_password_reset = true" do
        patch admin_settings_modules_authentication_forget_password_path(customer.id),
              params: { setting: { enabled: "1" } }

        config = JSON.parse(assignment.reload.configuration)
        expect(config["allow_password_reset"]).to be(true)
      end

      it "keeps sibling authentication keys on the same configuration blob" do
        assignment.update!(configuration: {
          "allow_password_reset" => false,
          "allow_registration" => true
        }.to_json)

        patch admin_settings_modules_authentication_forget_password_path(customer.id),
              params: { setting: { enabled: "1" } }

        config = JSON.parse(assignment.reload.configuration)
        expect(config["allow_password_reset"]).to be(true)
        expect(config["allow_registration"]).to be(true)
      end

      it "redirects back to the show page with a notice" do
        patch admin_settings_modules_authentication_forget_password_path(customer.id),
              params: { setting: { enabled: "1" } }
        expect(response).to redirect_to(
          admin_settings_modules_authentication_forget_password_path(customer.id)
        )
        follow_redirect!
        expect(response.body).to include("enabled")
      end
    end

    context "disabling password reset" do
      before do
        assignment.update!(configuration: { "allow_password_reset" => true }.to_json)
      end

      it "persists allow_password_reset = false" do
        patch admin_settings_modules_authentication_forget_password_path(customer.id),
              params: { setting: { enabled: "0" } }

        config = JSON.parse(assignment.reload.configuration)
        expect(config["allow_password_reset"]).to be(false)
      end

      it "redirects back to the show page with a notice" do
        patch admin_settings_modules_authentication_forget_password_path(customer.id),
              params: { setting: { enabled: "0" } }
        expect(response).to redirect_to(
          admin_settings_modules_authentication_forget_password_path(customer.id)
        )
        follow_redirect!
        expect(response.body).to include("disabled")
      end
    end

    context "with a missing or blank enabled setting" do
      before do
        assignment.update!(configuration: {
          "allow_password_reset" => true,
          "allow_registration" => true
        }.to_json)
      end

      [{}, { setting: {} }, { setting: { enabled: "" } }, { setting: { enabled: "   " } }].each do |payload|
        it "persists false consistently with the disabled notice for #{payload.inspect}" do
          patch guard_path, params: payload

          expect(response).to redirect_to(guard_path)
          expect(flash[:notice]).to eq(I18n.t("admin_settings.flash.forget_password.disabled"))
          config = JSON.parse(assignment.reload.configuration)
          expect(config["allow_password_reset"]).to be(false)
          expect(config["allow_registration"]).to be(true)
          expect(Authentication::Settings.for(customer.id).password_reset_enabled?).to be(false)
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Authorization
  # ---------------------------------------------------------------------------
  describe "authorization" do
    it_behaves_like "an admin-guarded request", :patch

    it "allows the platform owner to access another customer's settings" do
      sign_out admin
      sign_in find_or_create_platform_owner
      get admin_settings_modules_authentication_forget_password_path(customer.id)
      expect(response).to have_http_status(:ok)
    end

    # Cross-tenant isolation: admin of customer A cannot touch customer B's settings
    it "prevents a cross-tenant admin from reaching another customer's toggle" do
      sign_in_as_cross_tenant_admin
      get admin_settings_modules_authentication_forget_password_path(customer.id)
      expect([302, 403, 404]).to include(response.status)
      expect(response.status).not_to eq(200)
    end

    it "prevents a cross-tenant admin from updating another customer's toggle" do
      sign_in_as_cross_tenant_admin
      patch admin_settings_modules_authentication_forget_password_path(customer.id),
            params: { setting: { enabled: "1" } }
      expect([302, 403, 404]).to include(response.status)
      expect(response.status).not_to eq(200)
    end
  end
end
