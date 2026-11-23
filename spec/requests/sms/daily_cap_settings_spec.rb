# frozen_string_literal: true

require "rails_helper"

# The SMS cap belongs to this customer's assignment; only the owner may change it.
RSpec.describe "SMS per-tenant daily-cap settings", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:sms_module) { ::FeatureModules::Module.find_by!(key: "sms") }
  let(:admin)      { create(:user, :admin, customer: customer) }
  let(:config_path) { "/#{customer.id}/admin/settings/modules/sms" }
  let(:guard_path) { config_path }

  it_behaves_like "an admin-guarded GET"
  it_behaves_like "an admin-guarded request", :patch

  before do
    ::FeatureModules::Sms::Registration.register!
    sms_module.update!(status: :active) # the platform owner activates SMS globally
    ensure_customer_feature_module(customer, sms_module, status: :active)
    sign_in admin
  end

  it "exposes a daily_send_cap field in the configuration schema" do
    expect(sms_module.configuration_schema_json).to have_key("daily_send_cap")
  end

  it "renders the daily cap read-only for tenant admins" do
    get config_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("settings_modules.configuration.fields.sms.daily_send_cap"))
    expect(response.body).not_to include('name="configuration[daily_send_cap]"')
  end

  it "ignores forged daily_send_cap updates from tenant admins" do
    cfm = ::FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: sms_module)
    cfm.merge_configuration!(daily_send_cap: 40)
    patch config_path, params: { configuration: { daily_send_cap: "250" } }
    expect(response).to have_http_status(:redirect)

    expect(cfm.reload.configuration_json["daily_send_cap"]).to eq(40)
    expect(::Sms::Activities::Send.daily_cap_for(customer)).to eq(40)
  end
end
