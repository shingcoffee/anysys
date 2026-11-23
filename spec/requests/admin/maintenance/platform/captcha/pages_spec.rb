# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::Captcha::Pages", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }
  let(:other_customer)     { create(:customer, name: "Other Corp") }
  let(:admin_user)         { create(:user, :admin, customer: other_customer) }

  let!(:captcha_module) { find_or_create_feature_module!("captcha", name: "Captcha") }

  def pages_index_path(cid = platform_customer.id)
    admin_maintenance_platform_module_settings_captcha_pages_path(cid)
  end

  def page_path(page, cid = platform_customer.id)
    admin_maintenance_platform_module_settings_captcha_page_path(cid, page)
  end

  def build_shared_public_page(name: "Shared RSVP", traits: %i[for_member for_public])
    shared = build(:page, :shared, *traits, name: name)
    shared.save!(validate: false)
    shared
  end

  def stub_update(success: true)
    allow(Captcha::Activities::UpdateUrlThrottle).to receive(:call)
      .and_return(instance_double("UpdateResult", success?: success))
  end

  let(:guard_path) { pages_index_path }

  it_behaves_like "a platform-owner-guarded GET"

  describe "PATCH auth" do
    let(:guard_path) { page_path(build_shared_public_page) }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "regular admin (non-owner)" do
    before { sign_in admin_user }

    it "is denied on GET index of its own tenant path" do
      get pages_index_path(other_customer.id)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  context "as platform owner" do
    before { sign_in platform_owner }

    describe "GET #index" do
      it "lists a public-only shared page" do
        public_only = build_shared_public_page(name: "Walk-in Shared", traits: %i[public_only])
        get pages_index_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Walk-in Shared")
        expect(response.body).to include("/:customer_id/page/#{public_only.public_uuid}")
      end

      it "renders stacked protected and skip sections" do
        get pages_index_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-module-settings-shell="true"')
        expect(response.body).to include(I18n.t("maint_platform.module_settings.show.captcha.pages_title"))
        expect(response.body).to include(I18n.t("maint_platform.module_settings.show.captcha.skip_title"))
        expect(response.body).to include('data-controller="captcha-page-list"')
        expect(response.body).to match(/data-section-nav-tab="resources"[^>]*aria-current="page"/)
        expect(response.body).not_to include("Verifications")
        expect(response.body).not_to include('data-module-settings-pane="overview"')
        expect(response.body).not_to include('data-module-settings-section="availability"')
      end
    end

    it "sets a shared public page throttle and redirects to captcha Resources" do
      page_record = build_shared_public_page
      stub_update
      patch page_path(page_record), params: { preset: "5_per_1min" }

      expect(Captcha::Activities::UpdateUrlThrottle).to have_received(:call).with(
        hash_including(
          match_kind: "template",
          url_pattern: "/:customer_id/page/#{page_record.public_uuid}",
          preset: "5_per_1min",
          page: page_record
        )
      )
      expect(response).to redirect_to(pages_index_path)
      expect(flash[:notice]).to eq(I18n.t("captcha.throttle.flash_updated"))
    end

    it "writes a template throttle row for the shared page" do
      page_record = build_shared_public_page
      patch page_path(page_record), params: { preset: "every_hit" }

      expect(response).to redirect_to(pages_index_path)
      row = Captcha::UrlThrottle.find_by!(page_id: page_record.id)
      expect(row.match_kind).to eq("template")
      expect(row.url_pattern).to eq("/:customer_id/page/#{page_record.public_uuid}")
      expect(row.every_hit).to eq(true)
      expect(row.customer_id).to be_nil
      expect(row.skipped).to eq(false)
    end

    it "skips a shared public page" do
      page_record = build_shared_public_page
      patch page_path(page_record), params: { preset: "100_per_5min", skipped: true }

      row = Captcha::UrlThrottle.find_by!(page_id: page_record.id)
      expect(row.skipped).to eq(true)
      expect(row.limit_count).to eq(100)
    end

    it "returns 404 for a customer-owned page and does not write" do
      entity = create(:entity, :with_name_status_schema, customer: other_customer)
      owned = build(:page, :for_member, :for_public, customer: other_customer, entity: entity)
      owned.save!(validate: false)
      stub_update
      patch page_path(owned), params: { preset: "every_hit" }

      expect(response).to have_http_status(:not_found)
      expect(Captcha::Activities::UpdateUrlThrottle).not_to have_received(:call)
    end
  end
end
