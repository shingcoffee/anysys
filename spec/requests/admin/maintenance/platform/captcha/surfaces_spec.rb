# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::Captcha::Surfaces", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }
  let(:other_customer)     { create(:customer, name: "Other Corp") }
  let(:admin_user)         { create(:user, :admin, customer: other_customer) }

  let!(:captcha_module) { find_or_create_feature_module!("captcha", name: "Captcha") }

  def surfaces_path(cid = platform_customer.id)
    admin_maintenance_platform_module_settings_captcha_surfaces_path(cid)
  end

  def stub_update(success: true)
    allow(Captcha::Activities::UpdateUrlThrottle).to receive(:call)
      .and_return(instance_double("UpdateResult", success?: success))
  end

  let(:guard_path) { surfaces_path }

  it_behaves_like "a platform-owner-guarded request", :patch

  describe "regular admin (non-owner)" do
    before { sign_in admin_user }

    it "is denied on its own tenant path (platform gate)" do
      patch surfaces_path(other_customer.id),
            params: { surface_key: "authentication/sessions", preset: "5_per_1min" }
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  context "as platform owner" do
    before { sign_in platform_owner }

    it "sets a known surface throttle and redirects to captcha Resources" do
      stub_update
      patch surfaces_path, params: { surface_key: "authentication/sessions", preset: "5_per_1min" }

      expect(Captcha::Activities::UpdateUrlThrottle).to have_received(:call).with(
        hash_including(
          match_kind: "template",
          url_pattern: "/auth/sign_in",
          preset: "5_per_1min",
          surface_key: "authentication/sessions"
        )
      )
      expect(response).to redirect_to(
        admin_maintenance_platform_module_settings_captcha_pages_path(platform_customer.id)
      )
      expect(flash[:notice]).to eq(I18n.t("captcha.throttle.flash_updated"))
    end

    it "skips a known surface when skipped is true" do
      stub_update
      patch surfaces_path, params: {
        surface_key: "authentication/sessions",
        preset: "100_per_5min",
        skipped: true
      }

      expect(Captcha::Activities::UpdateUrlThrottle).to have_received(:call).with(
        hash_including(
          surface_key: "authentication/sessions",
          skipped: "true"
        )
      )
    end

    it "returns 404 for an unknown surface key and does not write" do
      stub_update
      patch surfaces_path, params: { surface_key: "unknown/surface", preset: "5_per_1min" }

      expect(response).to have_http_status(:not_found)
      expect(Captcha::Activities::UpdateUrlThrottle).not_to have_received(:call)
    end

    it "redirects with an alert when the activity fails" do
      stub_update(success: false)
      patch surfaces_path, params: { surface_key: "authentication/sessions", preset: "every_hit" }

      expect(response).to redirect_to(
        admin_maintenance_platform_module_settings_captcha_pages_path(platform_customer.id)
      )
      expect(flash[:alert]).to eq(I18n.t("captcha.throttle.flash_failed"))
    end
  end
end
