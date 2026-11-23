# frozen_string_literal: true

require "rails_helper"

# End-to-end chrome coverage for Platform::AnnouncementBannerComponent on
# ShellComponent pages. Component/resolver specs already unit-test render?
# and live windows — this file asserts the HTML actually reaches admin
# (and not member) dashboards, plus session dismiss + act-as preview.
RSpec.describe "Admin platform announcement banners", type: :request do
  include_context "admin records"
  let(:member) { create(:user, :member, customer: customer) }

  describe "banner on admin vs member dashboard" do
    let(:body_en) { "QA-ADMIN-DASH-BANNER-EN" }

    before do
      create(:platform_announcement, :published, :all_customers, body_en: body_en, body_zh: "QA-ADMIN-DASH-BANNER-ZH")
    end

    it "shows the English body to a tenant admin on the admin dashboard" do
      sign_in admin
      get admin_dashboard_path(customer.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(body_en)
    end

    it "does not show the banner on the member dashboard" do
      enable_module!("authentication", customer, name: "Authentication")
      sign_in member
      get member_dashboard_path(customer.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(body_en)
    end
  end

  describe "selected isolation" do
    let(:customer_a) { create(:customer) }
    let(:customer_b) { create(:customer) }
    let(:admin_a)    { create(:user, :admin, customer: customer_a) }
    let(:admin_b)    { create(:user, :admin, customer: customer_b) }
    let(:body_en)    { "QA-SELECTED-A-ONLY-BANNER" }

    before do
      create(
        :platform_announcement, :published, :selected,
        body_en: body_en,
        target_rules: {
          "type" => "group",
          "joins" => [],
          "conditions" => [
            { "field" => "id", "operator" => "equals", "value" => customer_a.id.to_s }
          ]
        }
      )
    end

    it "shows the banner to the targeted tenant admin and hides it from the other tenant" do
      sign_in admin_a
      get admin_dashboard_path(customer_a.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(body_en)

      sign_out admin_a
      sign_in admin_b
      get admin_dashboard_path(customer_b.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(body_en)
    end
  end

  describe "schedule window" do
    before { sign_in admin }

    it "does not show a published announcement whose starts_at is in the future" do
      create(
        :platform_announcement, :published, :all_customers,
        body_en: "QA-FUTURE-START-BANNER",
        starts_at: 1.hour.from_now
      )

      get admin_dashboard_path(customer.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("QA-FUTURE-START-BANNER")
    end

    it "does not show a published announcement whose ends_at is in the past" do
      create(
        :platform_announcement, :published, :all_customers,
        body_en: "QA-PAST-END-BANNER",
        ends_at: 1.hour.ago
      )

      get admin_dashboard_path(customer.id)
      expect(response).to have_http_status(:ok)
      banner = Nokogiri::HTML(response.body).at_css("#platform-announcements")
      expect(banner&.text).not_to include("QA-PAST-END-BANNER")
    end
  end

  describe "dismiss then remaining stack" do
    it "stacks both live notices, then keeps the other after one is dismissed" do
      older = create(:platform_announcement, :published, :all_customers, body_en: "QA-OLDER-NOTICE")
      newer = create(:platform_announcement, :published, :all_customers, body_en: "QA-NEWER-NOTICE")
      older.update_column(:created_at, 2.days.ago)
      newer.update_column(:created_at, 1.day.ago)

      sign_in admin
      get admin_dashboard_path(customer.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("QA-NEWER-NOTICE")
      expect(response.body).to include("QA-OLDER-NOTICE")

      post admin_platform_announcement_dismissals_path(customer.id),
           params: { platform_announcement_id: newer.id },
           headers: { "HTTP_REFERER" => admin_dashboard_path(customer.id) }
      expect(response).to redirect_to(admin_dashboard_path(customer.id))
      follow_redirect!

      expect(response).to have_http_status(:ok)
      banner = Nokogiri::HTML(response.body).at_css("#platform-announcements")
      expect(banner&.text).not_to include("QA-NEWER-NOTICE")
      expect(banner&.text).to include("QA-OLDER-NOTICE")
    end
  end

  describe "owner acting-as preview" do
    let(:platform_owner) { find_or_create_platform_owner }
    let(:platform_cid)   { ensure_platform_customer.id }
    let(:target)         { create(:customer) }
    let(:body_en)        { "QA-ACT-AS-TARGETED-BANNER" }

    before do
      create(
        :platform_announcement, :published, :selected,
        body_en: body_en,
        target_rules: {
          "type" => "group",
          "joins" => [],
          "conditions" => [
            { "field" => "id", "operator" => "equals", "value" => target.id.to_s }
          ]
        }
      )
      sign_in platform_owner
    end

    it "does not show a C-targeted banner on platform admin pages without acting-as" do
      get admin_dashboard_path(platform_cid)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(body_en)
    end

    it "shows a C-targeted banner on C's admin dashboard after acting as C" do
      patch admin_maintenance_platform_customer_context_path(platform_cid),
            params: { customer_id: target.id }
      expect(response).to redirect_to(admin_dashboard_path(target.id))
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(body_en)
    end
  end

  describe "all includes later customer" do
    it "shows a previously published all-audience banner to an admin of a later-created customer" do
      create(:platform_announcement, :published, :all_customers, body_en: "QA-LATER-CUSTOMER-BANNER")
      later = create(:customer)
      later_admin = create(:user, :admin, customer: later)

      sign_in later_admin
      get admin_dashboard_path(later.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("QA-LATER-CUSTOMER-BANNER")
    end
  end

  describe "zh-CN body" do
    it "renders body_zh on the admin dashboard when the locale is zh-CN" do
      create(
        :platform_announcement, :published, :all_customers,
        body_en: "QA-LOCALE-EN-BODY",
        body_zh: "QA-LOCALE-ZH-BODY"
      )
      sign_in admin

      I18n.with_locale(:"zh-CN") do
        get admin_dashboard_path(customer.id), params: { locale: "zh-CN" }
      end

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("QA-LOCALE-ZH-BODY")
      expect(response.body).not_to include("QA-LOCALE-EN-BODY")
    end
  end
end
