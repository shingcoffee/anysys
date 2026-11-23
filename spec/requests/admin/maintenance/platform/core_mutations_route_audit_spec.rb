# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Core platform mutation audit", type: :request do
  include_context "as platform owner"
  let!(:feature_module) { create(:feature_module, :inactive) }
  let(:module_path) { admin_maintenance_platform_module_setting_path(customer.id, feature_module) }

  it "prevalidates sensitive token input before changing availability or deprovisioning" do
    feature_module.update!(status: :active)
    expect(FeatureModules::Module::NullRegistration).not_to receive(:deprovision!)

    patch module_path, params: {
      status_active: "0", token_model: "Authentication::User", token_attribute: "otp_secret", token_enabled: "1"
    }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(feature_module.reload).to be_active
  end

  it "rejects malformed declared defaults before any other mutation" do
    feature_module.update!(configuration_schema: { "limit" => { "type" => "integer", "default" => 2 } }.to_json)

    patch module_path, params: { status_active: "1", config_defaults: { limit: [] } }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(feature_module.reload).to be_inactive
    expect(feature_module.configuration_schema_json.fetch("limit").fetch("default")).to eq(2)
  end

  it "rolls back an earlier mutation when a later database mutation fails" do
    allow(ModuleModelDiscovery).to receive(:call).with(feature_module.key).and_return([{ name: "Payments::Order" }])
    allow_any_instance_of(FeatureModules::Module).to receive(:set_extendable_model!).and_raise(StandardError, "simulated write failure")

    patch module_path, params: { status_active: "1", extendable_model: "Payments::Order", extendable: "1" }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(feature_module.reload).to be_inactive
    expect(feature_module.extendable_models_json).to be_empty
  end

  it "activates a required assignment only after its provisioning hook succeeds" do
    target = create(:customer)
    observed = nil
    allow(FeatureModules::Module::NullRegistration).to receive(:provision!).and_wrap_original do |method, provisioned|
      if provisioned.id == target.id
        observed = FeatureModules::CustomerAssignment.find_by(customer: target, feature_module: feature_module)&.active?
      end
      method.call(provisioned)
    end

    patch module_path, params: { status_active: "1", required: "1" }, as: :json

    expect(response).to have_http_status(:ok)
    expect(observed).not_to be(true)
    expect(FeatureModules::CustomerAssignment.find_by!(customer: target, feature_module: feature_module)).to be_active
  end

  it "rolls back required rollout and leaves a failed suspended assignment retryable" do
    target = create(:customer)
    assignment = create(:customer_feature_module, :suspended, customer: target, feature_module: feature_module)
    allow(FeatureModules::Module::NullRegistration).to receive(:provision!) do |provisioned|
      raise StandardError, "provisioning failed" if provisioned.id == target.id
    end

    patch module_path, params: { status_active: "1", required: "1" }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(feature_module.reload).to be_inactive
    expect(feature_module.required?).to be(false)
    expect(assignment.reload).to be_suspended
    expect(FeatureModules::CustomerAssignment.where(feature_module: feature_module).count).to eq(1)

    allow(FeatureModules::Module::NullRegistration).to receive(:provision!).and_return(nil)
    patch module_path, params: { status_active: "1", required: "1" }, as: :json
    expect(response).to have_http_status(:ok)
    expect(assignment.reload).to be_active
  end

  it "returns 404 for an unknown module on HTML update" do
    patch "/81721200/admin/maintenance/platform/module_settings/unknown_audit_module", params: { status_active: "1" }
    expect(response).to have_http_status(:not_found)
  end

  it "preserves industry mappings when a malformed container or item is submitted" do
    key = PageLayoutTemplates.keys.first
    IndustryTemplateMapping.find_or_create_by!(industry: "technology", template_key: key)
    baseline = IndustryTemplateMapping.for_industry("technology").order(:id).pluck(:id)
    path = admin_maintenance_platform_industry_template_path(customer.id, "technology")

    [{ injected: key }, [key, { injected: key }], [key, 123]].each do |invalid|
      patch path, params: { template_keys: invalid }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(IndustryTemplateMapping.for_industry("technology").order(:id).pluck(:id)).to eq(baseline)
    end
  end

  it "reports purge failure without claiming any customers were deleted" do
    target = create(:customer)
    target.soft_delete
    result = Customers::Purge::Result.new(ok: false, customer_ids: [], counts: {}, dependencies: {}, error_code: :foreign_dependency)
    allow(Customers::Purge).to receive(:call).and_return(result)

    delete empty_trash_admin_maintenance_platform_customers_path(customer.id)

    expect(response).to have_http_status(:redirect)
    expect(flash[:notice]).to be_nil
    expect(flash[:alert]).to eq(I18n.t("routes_audit.customer_purge_failed"))
    expect(Customer.only_deleted.exists?(target.id)).to be(true)
  end
end
