# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Owner-managed customer module limits", type: :request do
  let(:customer) { create(:customer) }
  let(:owner) { find_or_create_platform_owner }
  let(:admin) { create(:user, :admin, customer: customer) }

  def path(tenant, module_key)
    "/#{tenant.id}/admin/maintenance/modules/#{module_key}/owner_configuration"
  end

  def assignment(tenant, key)
    feature = enable_module!(key, tenant)
    FeatureModules::CustomerAssignment.find_by!(customer: tenant, feature_module: feature)
  end

  it "lets the platform owner edit each active customer's email, SMS and recording limits" do
    sign_in owner
    { "email" => ["daily_send_cap", "250"], "sms" => ["daily_send_cap", "45"],
      "ai_assistant" => ["max_duration_seconds", "90"] }.each do |key, (field, value)|
      record = assignment(customer, key)
      get admin_maintenance_modules_path(customer.id)
      page = Capybara.string(response.body)
      expect(page).to have_css("form[action='#{path(customer, key)}'] input[name='configuration[#{field}]']")

      patch path(customer, key), params: { configuration: { field => value } }
      expect(response).to redirect_to(admin_maintenance_modules_path(customer.id))
      expect(record.reload.configuration_json[field]).to eq(value)
    end
  end

  it "shows limits only for enabled modules and only to the platform owner" do
    assignment(customer, "email")
    sign_in admin
    get admin_maintenance_modules_path(customer.id)
    expect(response.body).not_to include("owner_configuration")
    patch path(customer, "email"), params: { configuration: { daily_send_cap: "1" } }
    expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
    expect(assignment(customer, "email").reload.configuration_json).not_to have_key("daily_send_cap")

    sign_in owner
    get admin_maintenance_modules_path(customer.id)
    expect(response.body).to include(path(customer, "email"))
    expect(response.body).not_to include(path(customer, "sms"))
  end

  it "keeps Email read-only in Settings for tenants and the owner, including forged PATCH requests" do
    record = assignment(customer, "email")
    record.merge_configuration!(daily_send_cap: "80")
    [admin, owner].each do |actor|
      sign_in actor
      get "/#{customer.id}/admin/settings/modules/emails/daily_cap"
      settings = Capybara.string(response.body).find("[data-settings-page]")
      expect(settings).to have_text(I18n.t("settings_modules.configuration.fields.email.daily_send_cap"))
      expect(settings).to have_text("80")
      expect(settings).not_to have_field("configuration[daily_send_cap]")

      patch "/#{customer.id}/admin/settings/modules/emails", params: { configuration: { daily_send_cap: "999" } }
      expect(record.reload.configuration_json["daily_send_cap"]).to eq("80")
    end
  end

  it "rejects bad values and unrelated keys without overwriting existing configuration" do
    record = assignment(customer, "ai_assistant")
    record.merge_configuration!(language: "zh-CN", max_duration_seconds: "60")
    sign_in owner

    ["0", "-1", "1.5", "invalid", "2147483648"].each do |value|
      patch path(customer, "ai_assistant"), params: { configuration: { max_duration_seconds: value, language: "en" } }
      expect(flash[:alert]).to eq(I18n.t("maint_core.flash.module_owner_configurations.invalid"))
      expect(record.reload.configuration_json).to include("language" => "zh-CN", "max_duration_seconds" => "60")
    end

    patch path(customer, "ai_assistant"), params: { configuration: { language: "en" } }
    expect(flash[:alert]).to eq(I18n.t("maint_core.flash.module_owner_configurations.invalid"))
    expect(record.reload.configuration_json["language"]).to eq("zh-CN")
  end

  it "does not edit an unassigned or suspended module" do
    sign_in owner
    record = assignment(customer, "sms")
    record.destroy!
    patch path(customer, "sms"), params: { configuration: { daily_send_cap: "0" } }
    expect(response).to have_http_status(:not_found)

    record = assignment(customer, "sms")
    record.update!(status: :suspended)
    sign_in owner
    patch path(customer, "sms"), params: { configuration: { daily_send_cap: "2" } }
    expect(response).to have_http_status(:not_found)
  end

  it "cannot be used by another tenant's admin or a member" do
    record = assignment(customer, "email")
    [create(:user, :admin, customer: create(:customer)), create(:user, :member, customer: customer)].each do |actor|
      sign_in actor
      patch path(customer, "email"), params: { configuration: { daily_send_cap: "10" } }
      expect(response).not_to have_http_status(:ok)
      expect(record.reload.configuration_json).not_to have_key("daily_send_cap")
    end
  end
end
