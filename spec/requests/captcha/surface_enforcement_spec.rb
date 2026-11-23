# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Captcha platform surface throttle", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }

  let!(:captcha_module) { find_or_create_feature_module!("captcha", name: "Captcha") }
  let!(:provider) do
    Captcha::Providers::Aliyun
    create(:captcha_provider_settings, enabled: true)
  end

  def surfaces_path
    admin_maintenance_platform_module_settings_captcha_surfaces_path(platform_customer.id)
  end

  it "lets the owner set every-hit on sign-in, after which GET /auth/sign_in is challenged" do
    sign_in platform_owner
    patch surfaces_path, params: { surface_key: "authentication/sessions", preset: "every_hit" }
    expect(response).to have_http_status(:redirect)
    sign_out platform_owner

    get "/auth/sign_in"
    expect(response).to have_http_status(:redirect)
    expect(response.location).to include("/captcha/challenge")
  end

  it "lets the owner skip sign-in so GET /auth/sign_in is not challenged" do
    sign_in platform_owner
    patch surfaces_path, params: { surface_key: "authentication/sessions", preset: "every_hit", skipped: true }
    expect(response).to have_http_status(:redirect)
    sign_out platform_owner

    get "/auth/sign_in"
    expect(response).to have_http_status(:ok)
    expect(response.location.to_s).not_to include("/captcha/challenge")
  end
end
