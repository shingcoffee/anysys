# frozen_string_literal: true

require "rails_helper"

# Per-tenant Settings / AI Assistant — generic Admin::ModuleConfigsController
# surface (language editable, max_duration_seconds visible but owner-managed).
RSpec.describe "AI Assistant per-tenant settings", type: :request do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  let(:ai_assistant_module) { ::FeatureModules::Module.find_by!(key: "ai_assistant") }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:member) { create(:user, :member, customer: customer) }
  let(:other_admin) { create(:user, :admin, customer: other_customer) }
  let(:config_path) { "/#{customer.id}/admin/settings/modules/ai_assistant" }

  def assignment_for(tenant)
    ::FeatureModules::CustomerAssignment.find_by(customer: tenant, feature_module: ai_assistant_module)
  end

  before do
    ::FeatureModules::AiAssistant::Registration.register!
    ai_assistant_module.update!(status: :active)
  end

  describe "GET show when the module is enabled for the tenant" do
    before do
      ensure_customer_feature_module(customer, ai_assistant_module, status: :active)
      sign_in admin
    end

    it "renders language and max_duration_seconds with I18n labels (not humanize fallback)" do
      get config_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("admin_misc.module_config.fields.ai_assistant.language"))
      expect(response.body).to include(I18n.t("admin_misc.module_config.fields.ai_assistant.max_duration_seconds"))
      expect(response.body).to include('name="configuration[language]"')
      expect(response.body).not_to include('name="configuration[max_duration_seconds]"')
    end

    it "localizes language options instead of humanizing locale codes" do
      get config_path
      expect(response.body).to include("Simplified Chinese")
      expect(response.body).not_to include("Zh cn")
    end

    it "localizes language options in zh-CN" do
      get config_path, params: { locale: "zh-CN" }
      expect(response.body).to include("简体中文")
      expect(response.body).not_to include("Zh cn")
    end
  end

  describe "PATCH update when the module is enabled for the tenant" do
    before do
      ensure_customer_feature_module(customer, ai_assistant_module, status: :active)
      sign_in admin
    end

    it "persists language but ignores a forged recording limit" do
      patch config_path, params: {
        configuration: { language: "zh-CN", max_duration_seconds: "90" }
      }

      expect(response).to have_http_status(:redirect)

      cfm = assignment_for(customer)
      expect(cfm.configuration_json["language"]).to eq("zh-CN")
      expect(cfm.configuration_json).not_to have_key("max_duration_seconds")
    end
  end

  describe "authorization" do
    before { ensure_customer_feature_module(customer, ai_assistant_module, status: :active) }
    let(:guard_path) { config_path }

    it_behaves_like "an admin-guarded GET"
    it_behaves_like "an admin-guarded request", :patch

    it "forbids a member PATCH without changing config" do
      sign_in member
      patch config_path, as: :json, params: {
        configuration: { language: "en", max_duration_seconds: "45" }
      }
      expect(response).to have_http_status(:forbidden)
      expect(assignment_for(customer).configuration_json["language"]).not_to eq("en")
    end

    it "blocks an admin of customer A from PATCHing customer B" do
      sign_in other_admin

      patch config_path, params: {
        configuration: { language: "en", max_duration_seconds: "45" }
      }

      expect(response).not_to have_http_status(:ok)
      expect([ 302, 403, 404 ]).to include(response.status)
      expect(assignment_for(customer).configuration_json["language"]).not_to eq("en")
      expect(assignment_for(customer).configuration_json["max_duration_seconds"]).not_to eq("45")
    end
  end

  describe "when the module is not enabled for the tenant" do
    it "returns 404 on show (ModuleConfigsController head :not_found)" do
      ::FeatureModules::CustomerAssignment
        .where(customer: customer, feature_module: ai_assistant_module)
        .delete_all

      sign_in admin
      get config_path

      expect(response).to have_http_status(:not_found)
    end
  end
end
