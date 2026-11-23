# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::Captcha::Settings", type: :request do
  include_context "as platform owner"

  let(:other_customer)    { create(:customer) }
  let(:non_owner)         { create(:user, :admin, customer: other_customer) }
  let(:same_tenant_admin) { create(:user, :admin, customer: customer) }

  def settings_path(cid = customer.id, provider: nil)
    path = "/#{cid}/admin/maintenance/platform/module_settings/captcha/settings"
    provider ? "#{path}?provider=#{provider}" : path
  end

  def test_connection_path(cid = customer.id, provider: "aliyun")
    "/#{cid}/admin/maintenance/platform/module_settings/captcha/settings/test_connection?provider=#{provider}"
  end

  def aliyun_params(overrides = {})
    {
      access_key_id: "AK", access_key_secret: "S2", scene_id: "scn", prefix: "captcha-test-identity",
      endpoint: "captcha.cn-shanghai.aliyuncs.com", region: "cn-shanghai", fail_policy: "open"
    }.merge(overrides)
  end

  before { Captcha::Providers::Aliyun }

  let(:guard_path) { settings_path }

  it_behaves_like "a platform-owner-guarded GET"

  describe "PATCH update — auth guards" do
    let(:guard_path) { settings_path }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "POST test_connection — auth guards" do
    let(:guard_path) { test_connection_path }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "GET show" do
    it "is forbidden for a non-owner admin of another customer" do
      sign_in non_owner
      get settings_path(other_customer.id)
      expect(response.status).to be_in([302, 403, 404])
    end

    it "is forbidden for a same-tenant admin who is not the owner" do
      sign_in same_tenant_admin
      get settings_path
      expect(response.status).to be_in([302, 403, 404])
    end

    it "defaults to the active provider when no ?provider= param is given" do
      Captcha::ProviderSettings.for_provider("turnstile").tap { |s|
        s.update!(access_key_id: "SK", access_key_secret: "SS")
        s.activate!
      }
      get settings_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("turnstile")
    end

    it "falls back to the registry default when no provider is active" do
      get settings_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(Captcha::Providers.default_key.to_s)
    end

    it "honors an explicit ?provider= param" do
      get settings_path(provider: "turnstile")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("turnstile")
    end
  end

  describe "PATCH update" do
    it "rotates credentials on a non-blank secret submission" do
      patch settings_path, params: { captcha_provider_settings: aliyun_params(enabled: "1") }
      expect(response).to have_http_status(:redirect)
      expect(Captcha::ProviderSettings.active.config_value(:prefix)).to eq("captcha-test-identity")
      expect(Captcha::ProviderSettings.active.access_key_secret).to eq("S2")
    end

    it "preserves the secret on blank submission" do
      settings = Captcha::ProviderSettings.for_provider("aliyun")
      settings.update!(access_key_id: "AK", access_key_secret: "OLD")
      settings.write_config(scene_id: "scn", prefix: "captcha-test-identity")
      settings.save!
      settings.activate!
      patch settings_path, params: {
        captcha_provider_settings: aliyun_params(access_key_id: "AK2", access_key_secret: "")
      }
      expect(response).to have_http_status(:redirect)
      expect(Captcha::ProviderSettings.active.access_key_secret).to eq("OLD")
    end

    it "re-renders with a 422 when validation fails" do
      patch settings_path, params: {
        captcha_provider_settings: aliyun_params(access_key_id: "")
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "is forbidden for a non-owner" do
      sign_in non_owner
      patch settings_path(other_customer.id), params: { captcha_provider_settings: aliyun_params }
      expect(response.status).to be_in([302, 403, 404])
    end

    it "switches the live vendor from active_assignee without credential fields" do
      Captcha::ProviderSettings.for_provider("aliyun").activate!
      patch settings_path, params: {
        section: "active",
        captcha_provider_settings: { active_assignee: "turnstile" }
      }
      expect(response).to have_http_status(:redirect)
      expect(Captcha::ProviderSettings.find_by!(provider: "turnstile").enabled).to eq(true)
      expect(Captcha::ProviderSettings.find_by!(provider: "aliyun").enabled).to eq(false)
    end
  end

  describe "POST test_connection" do
    it "redirects with a notice on success" do
      settings = Captcha::ProviderSettings.for_provider("aliyun")
      settings.update!(access_key_id: "AK", access_key_secret: "S")
      settings.write_config(scene_id: "scn", prefix: "captcha-test-identity")
      settings.save!
      allow(Captcha::Activities::TestConnection).to receive(:call)
        .and_return(Captcha::Activities::TestConnection::Result.new(status: "ok"))

      post test_connection_path
      expect(response).to redirect_to(%r{/module_settings/captcha/settings\?provider=aliyun})
      expect(flash[:notice]).to be_present
    end

    it "redirects with an alert when the probe fails" do
      Captcha::ProviderSettings.for_provider("aliyun")
      allow(Captcha::Activities::TestConnection).to receive(:call)
        .and_return(Captcha::Activities::TestConnection::Result.new(status: "unreachable"))

      post test_connection_path
      expect(flash[:alert]).to be_present
    end

    it "is forbidden for a non-owner" do
      sign_in non_owner
      post "/#{other_customer.id}/admin/maintenance/platform/module_settings/captcha/settings/test_connection?provider=aliyun"
      expect(response.status).to be_in([302, 403, 404])
    end
  end
end
