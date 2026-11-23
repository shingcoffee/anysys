# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::ModuleSubTogglesController", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let!(:email_module) { enable_module!("email", customer, name: "Email") }
  let!(:assignment) do
    FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: email_module)
  end

  let(:guard_path) { admin_maintenance_module_sub_toggle_path(customer, email_module) }

  it_behaves_like "an admin-guarded request", :patch

  describe "PATCH /:cid/admin/maintenance/modules/:module_id/sub_toggle" do
    before { sign_in admin }
    it "rejects unknown configuration keys" do
      patch admin_maintenance_module_sub_toggle_path(customer, email_module),
            params: { key: "evil_key", enabled: "1" }

      expect(response).to redirect_to(admin_maintenance_modules_path(customer))
      expect(flash[:alert]).to eq(I18n.t("maint_core.flash.module_sub_toggles.invalid_key"))
    end

    it "rejects campaigns_enabled now that the sub-feature gate is removed" do
      patch admin_maintenance_module_sub_toggle_path(customer, email_module),
            params: { key: "campaigns_enabled", enabled: "1" }

      expect(response).to redirect_to(admin_maintenance_modules_path(customer))
      expect(flash[:alert]).to eq(I18n.t("maint_core.flash.module_sub_toggles.invalid_key"))
      expect(assignment.reload.configuration_json["campaigns_enabled"]).to be_nil
    end

    it "does not overwrite a numeric daily_send_cap with a boolean" do
      assignment.merge_configuration!("daily_send_cap" => 500)

      patch admin_maintenance_module_sub_toggle_path(customer, email_module),
            params: { key: "daily_send_cap", enabled: "1" }

      expect(response).to redirect_to(admin_maintenance_modules_path(customer))
      expect(flash[:alert]).to eq(I18n.t("maint_core.flash.module_sub_toggles.invalid_key"))
      expect(assignment.reload.configuration_json["daily_send_cap"]).to eq(500)
    end

    it "toggles a boolean schema key" do
      auth_module = enable_module!("authentication", customer, name: "User Authentication")
      auth_assignment = FeatureModules::CustomerAssignment.find_by!(
        customer: customer, feature_module: auth_module
      )
      auth_assignment.merge_configuration!("mfa_enabled" => false)

      patch admin_maintenance_module_sub_toggle_path(customer, auth_module),
            params: { key: "mfa_enabled", enabled: "1" }

      expect(response).to redirect_to(admin_maintenance_modules_path(customer))
      expect(flash[:notice]).to eq(I18n.t("maint_core.flash.module_sub_toggles.updated"))
      expect(auth_assignment.reload.configuration_json["mfa_enabled"]).to be(true)
    end
  end
end
