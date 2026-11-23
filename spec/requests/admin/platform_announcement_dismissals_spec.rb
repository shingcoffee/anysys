# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::PlatformAnnouncementDismissals", type: :request do
  let(:tenant)        { create(:customer) }
  let(:customer)      { tenant }
  let(:tenant_admin)  { create(:user, :admin, customer: tenant) }
  let(:admin)         { tenant_admin }
  let(:tenant_member) { create(:user, :member, customer: tenant) }
  let(:guard_path)    { admin_platform_announcement_dismissals_path(tenant.id) }

  it_behaves_like "an admin-guarded request", :post

  def dismiss(announcement, customer: tenant)
    post admin_platform_announcement_dismissals_path(customer.id),
         params: { platform_announcement_id: announcement.id },
         headers: { "HTTP_REFERER" => admin_dashboard_path(customer.id) }
  end

  def dismissed_ids(user:, customer:)
    PlatformAnnouncementDismissal.announcement_ids_for(user_id: user.id, customer_id: customer.id)
  end

  describe "tenant admin" do
    before { sign_in tenant_admin }

    it "persists a targeted live dismissal for the user and redirects" do
      announcement = create(:platform_announcement, :published, :all_customers)
      dismiss(announcement)

      expect(dismissed_ids(user: tenant_admin, customer: tenant)).to include(announcement.id)
      expect(response).to redirect_to(admin_dashboard_path(tenant.id))
    end

    it "is idempotent when the same announcement is dismissed twice" do
      announcement = create(:platform_announcement, :published, :all_customers)
      dismiss(announcement)
      dismiss(announcement)

      expect(PlatformAnnouncementDismissal.count).to eq(1)
      expect(response).to redirect_to(admin_dashboard_path(tenant.id))
    end

    it "survives a new session, unlike the previous session-only dismissal" do
      announcement = create(:platform_announcement, :published, :all_customers, body_en: "QA-PERSISTED-NOTICE")
      dismiss(announcement)

      sign_out tenant_admin
      sign_in tenant_admin
      get admin_dashboard_path(tenant.id)

      expect(response).to have_http_status(:ok)
      banner = Nokogiri::HTML(response.body).at_css("#platform-announcements")
      expect(banner&.text).not_to include("QA-PERSISTED-NOTICE")
    end

    it "does not leak one admin's dismissal to another admin of the same tenant" do
      announcement = create(:platform_announcement, :published, :all_customers, body_en: "QA-OTHER-ADMIN-NOTICE")
      dismiss(announcement)

      other_admin = create(:user, :admin, customer: tenant)
      sign_out tenant_admin
      sign_in other_admin
      get admin_dashboard_path(tenant.id)

      expect(response.body).to include("QA-OTHER-ADMIN-NOTICE")
    end

    it "responds with a Turbo Stream replacing the banner stack" do
      announcement = create(:platform_announcement, :published, :all_customers)
      post admin_platform_announcement_dismissals_path(tenant.id),
           params: { platform_announcement_id: announcement.id },
           headers: { "HTTP_REFERER" => admin_dashboard_path(tenant.id),
                      "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(target="#{Platform::AnnouncementBannerComponent::STACK_DOM_ID}"))
      expect(response.body).to include("turbo-stream")
    end

    it "does not store an untargeted or draft id and still redirects" do
      draft = create(:platform_announcement, :draft, :all_customers)
      other = create(:customer)
      untargeted = create(
        :platform_announcement, :published, :selected,
        target_rules: {
          "type" => "group",
          "joins" => [],
          "conditions" => [
            { "field" => "id", "operator" => "equals", "value" => other.id.to_s }
          ]
        }
      )

      dismiss(draft)
      expect(dismissed_ids(user: tenant_admin, customer: tenant)).not_to include(draft.id)
      expect(response).to have_http_status(:redirect)

      dismiss(untargeted)
      expect(dismissed_ids(user: tenant_admin, customer: tenant)).not_to include(untargeted.id)
      expect(response).to redirect_to(admin_dashboard_path(tenant.id))
    end
  end

  describe "member" do
    before { sign_in tenant_member }

    it "is denied without storing a dismissal" do
      announcement = create(:platform_announcement, :published, :all_customers)
      dismiss(announcement)
      expect(PlatformAnnouncementDismissal.count).to eq(0)
    end
  end

  describe "cross-tenant dismiss" do
    let(:other)       { create(:customer) }
    let(:other_admin) { create(:user, :admin, customer: other) }

    it "forbids admin of A from dismissing on B's URL and does not leak session state" do
      announcement = create(:platform_announcement, :published, :all_customers)

      sign_in tenant_admin
      dismiss(announcement, customer: other)

      expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
      expect(response).not_to have_http_status(:ok)
      expect(PlatformAnnouncementDismissal.count).to eq(0)

      sign_out tenant_admin
      sign_in other_admin
      get admin_dashboard_path(other.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(announcement.body_en)
    end
  end
end
