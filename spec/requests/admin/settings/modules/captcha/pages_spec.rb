# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Settings::Modules::Captcha", type: :request do
  include_context "as admin"

  let(:other_customer) { create(:customer) }
  let(:other_admin)    { create(:user, :admin, customer: other_customer) }
  let(:member_user)    { create(:user, :member, customer: customer) }

  def show_path(cid = customer.id)
    admin_settings_modules_captcha_path(cid)
  end

  def page_path(page, cid = customer.id)
    admin_settings_modules_captcha_page_path(cid, page)
  end

  def build_public_page(owner:, name: "Public page", traits: %i[for_member for_public])
    entity = create(:entity, :with_name_status_schema, customer: owner)
    page = build(:page, *traits, customer: owner, entity: entity, name: name)
    page.save!(validate: false)
    page
  end

  def stub_update(success: true)
    allow(Captcha::Activities::UpdateUrlThrottle).to receive(:call)
      .and_return(instance_double("UpdateResult", success?: success))
  end

  describe "GET /:cid/admin/settings/modules/captcha" do
    let(:guard_path) { show_path }

    it_behaves_like "an admin-guarded GET"
    it "renders StatusController for a same-tenant admin (not generic module_configs)" do
      get show_path
      expect(response).to have_http_status(:ok)
      expect(request.controller_class).to eq(Admin::Settings::Modules::Captcha::StatusController)
    end

    it "still renders when the captcha module is not enabled for the tenant" do
      fm = find_or_create_feature_module!("captcha", name: "Captcha")
      FeatureModules::CustomerAssignment.where(
        customer: customer,
        feature_module: fm
      ).delete_all

      get show_path
      expect(response).to have_http_status(:ok)
      expect(request.controller_class).to eq(Admin::Settings::Modules::Captcha::StatusController)
    end

    it "rejects a cross-tenant admin" do
      sign_out admin
      sign_in other_admin
      get show_path
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden).or have_http_status(:not_found)
      expect(response).not_to have_http_status(:ok)
    end

    it "renders Status with this tenant's public pages, including unpublished ones" do
      listed = build_public_page(owner: customer, name: "Event RSVP")
      build_public_page(owner: other_customer, name: "Foreign RSVP")
      shared = build(:page, :shared, :for_member, :for_public, name: "Shared public")
      shared.save!(validate: false)

      get show_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("settings_modules.captcha.page_limits"))
      expect(response.body).to include("Event RSVP")
      expect(response.body).to include("/#{customer.id}/page/#{listed.public_uuid}")
      expect(response.body).to include(I18n.t("captcha.customer_status.not_launched"))
      expect(response.body).not_to include("Foreign RSVP")
      expect(response.body).not_to include("Shared public")
      expect(response.body).to include(admin_settings_modules_captcha_page_path(customer.id, listed))
      expect(response.body).to include(Captcha::ThrottlePresets::PRESET_100_PER_5MIN)
    end

    it "renders the active provider name when one is configured" do
      create(:captcha_provider_settings, enabled: true)
      get show_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Aliyun Captcha")
    end
  end

  describe "PATCH /:cid/admin/settings/modules/captcha/pages/:id" do
    let!(:page) { build_public_page(owner: customer) }
    let(:guard_path) { page_path(page) }

    it_behaves_like "an admin-guarded request", :patch

    it "lets a same-tenant admin set a public page throttle" do
      stub_update
      patch page_path(page), params: { preset: "5_per_1min" }

      expect(Captcha::Activities::UpdateUrlThrottle).to have_received(:call).with(
        hash_including(
          match_kind: "exact",
          preset: "5_per_1min",
          page: page,
          customer_id: customer.id
        )
      )
      expect(response).to redirect_to(show_path)
      expect(flash[:notice]).to eq(I18n.t("captcha.throttle.flash_updated"))
    end

    it "writes a url throttle row for the concrete page path" do
      patch page_path(page), params: { preset: "20_per_1min" }

      expect(response).to redirect_to(show_path)
      row = Captcha::UrlThrottle.find_by!(page_id: page.id)
      expect(row.match_kind).to eq("exact")
      expect(row.url_pattern).to eq("/#{customer.id}/page/#{page.public_uuid}")
      expect(row.limit_count).to eq(20)
    end

    it "returns 404 for another tenant's page and does not write" do
      foreign = build_public_page(owner: other_customer, name: "Foreign")
      stub_update
      patch page_path(foreign), params: { preset: "every_hit" }

      expect(response).to have_http_status(:not_found)
      expect(Captcha::Activities::UpdateUrlThrottle).not_to have_received(:call)
    end

    it "lists and throttles a public-only page (no admin audience)" do
      listed = build_public_page(owner: customer, name: "Walk-in RSVP", traits: %i[public_only])
      stub_update
      get show_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Walk-in RSVP")
      expect(response.body).to include("/#{customer.id}/page/#{listed.public_uuid}")

      patch page_path(listed), params: { preset: "5_per_1min" }

      expect(Captcha::Activities::UpdateUrlThrottle).to have_received(:call).with(
        hash_including(page: listed, customer_id: customer.id)
      )
    end

    it "returns 404 for a shared page and does not write" do
      shared = build(:page, :shared, :for_member, :for_public, name: "Shared public")
      shared.save!(validate: false)
      stub_update
      patch page_path(shared), params: { preset: "every_hit" }

      expect(response).to have_http_status(:not_found)
      expect(Captcha::Activities::UpdateUrlThrottle).not_to have_received(:call)
    end

    it "returns 404 for a non-public page" do
      entity = create(:entity, :with_name_status_schema, customer: customer)
      private_page = build(:page, customer: customer, entity: entity)
      private_page.save!(validate: false)
      stub_update
      patch page_path(private_page), params: { preset: "every_hit" }

      expect(response).to have_http_status(:not_found)
      expect(Captcha::Activities::UpdateUrlThrottle).not_to have_received(:call)
    end

    it "does not update throttle settings for a member" do
      sign_out admin
      sign_in member_user
      stub_update
      patch page_path(page), params: { preset: "every_hit" }

      expect(Captcha::Activities::UpdateUrlThrottle).not_to have_received(:call)
    end

    it "does not update throttle settings for an anonymous request" do
      sign_out admin
      stub_update
      patch page_path(page), params: { preset: "every_hit" }

      expect(Captcha::Activities::UpdateUrlThrottle).not_to have_received(:call)
    end

    it "rejects a cross-tenant admin" do
      sign_out admin
      sign_in other_admin
      stub_update
      patch page_path(page), params: { preset: "every_hit" }

      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden).or have_http_status(:not_found)
      expect(response).not_to have_http_status(:ok)
    end
  end
end
