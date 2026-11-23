# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SMS campaign platform configuration HTTP", type: :request do
  let(:owner) { find_or_create_platform_owner }
  let(:base) { "/81721200/admin/maintenance/platform/module_settings/sms" }

  before { sign_in owner }

  it "saves template purpose/mirror through owner-only validation and redirects 303" do
    post "#{base}/templates", params: { sms_template: { key: "http_marketing", purpose: "marketing", body_template: "Hi {{name}}",
      variables_raw: "name", status: "active", provider_template_codes: { aliyun: "SMS_MARKETING" } } }
    expect(response).to have_http_status(:see_other), response.body
    expect(Sms::Template.find_by!(key: "http_marketing")).to have_attributes(purpose: "marketing", body_template: "Hi {{name}}")
    template = Sms::Template.find_by!(key: "http_marketing")
    patch "#{base}/templates/#{template.id}", params: { sms_template: { purpose: "transactional" } }
    expect(response).to have_http_status(:see_other)
    expect(template.reload).to have_attributes(purpose: "transactional", variables: ["name"], provider_template_codes: { "aliyun" => "SMS_MARKETING" })
    patch "#{base}/templates/#{template.id}", params: { sms_template: { purpose: "marketing", body_template: "{{unapproved}}", variables_raw: "name", provider_template_codes: { aliyun: "SMS_MARKETING" } } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(template.reload.body_template).to eq("Hi {{name}}")
  end

  it "persists the common finite account rate with vendor fields and rejects runtime clock injection" do
    credential = create(:sms_credential)
    patch "#{base}/credentials/#{credential.id}", params: { sms_credential: { sender_rate_per_second: "0.5", sign_name: "Updated", access_key_secret: "" } }
    expect(response).to have_http_status(:see_other)
    expect(credential.reload.config).to include("sender_rate_per_second" => 0.5, "sign_name" => "Updated")
    expect(credential.access_key_secret).to eq("AKSECRET_TEST")
    %w[0 -1 1.1 NaN Infinity invalid].each do |rate|
      patch "#{base}/credentials/#{credential.id}", params: { sms_credential: { sender_rate_per_second: rate } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(credential.reload.config["sender_rate_per_second"]).to eq(0.5)
    end
    patch "#{base}/credentials/#{credential.id}.json", params: { sms_credential: { sender_rate_per_second: 1, dispatch_next_at: Time.current.iso8601 } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(credential.reload.dispatch_next_at).to be_nil
  end

  it "denies tenant admins and owner requests at a non-platform customer URL" do
    tenant = create(:customer)
    sign_in create(:user, :admin, customer: tenant)
    post "#{base}/templates.json", params: { sms_template: { purpose: "marketing" } }, as: :json
    expect(response).to have_http_status(:forbidden)
    sign_in owner
    get "/#{tenant.id}/admin/maintenance/platform/module_settings/sms/templates.json"
    expect(response).to have_http_status(:not_found)
  end
end
