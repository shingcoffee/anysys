# frozen_string_literal: true

require "rails_helper"

# End-to-end chrome coverage for the admin-topbar bell inbox
# (NotificationsButtonComponent on ShellComponent pages). Resolver and
# component specs already unit-test candidate windows and markup — this
# file asserts the HTML that reaches tenant-admin / owner / member pages.
RSpec.describe "Admin platform announcement bell inbox", type: :request do
  let(:tenant)        { create(:customer) }
  let(:tenant_admin)  { create(:user, :admin, customer: tenant) }
  let(:tenant_member) { create(:user, :member, customer: tenant) }

  def selected_rules_for(customer)
    {
      "type" => "group",
      "joins" => [],
      "conditions" => [
        { "field" => "id", "operator" => "equals", "value" => customer.id.to_s }
      ]
    }
  end

  def html
    Nokogiri::HTML(response.body)
  end

  def bell_panel
    html.at_css("#notifications-panel-body")
  end

  def banner_stack
    html.at_css("#platform-announcements")
  end

  def bell_text
    bell_panel&.text.to_s
  end

  def banner_text
    banner_stack&.text.to_s
  end

  def unread_badge
    html.at_css("[data-badge-count]")
  end

  def mark_read(announcement, customer: tenant)
    post admin_platform_announcement_reads_path(customer.id),
         params: { platform_announcement_id: announcement.id },
         headers: { "HTTP_REFERER" => admin_dashboard_path(customer.id) }
  end

  def dismiss(announcement, customer: tenant)
    post admin_platform_announcement_dismissals_path(customer.id),
         params: { platform_announcement_id: announcement.id },
         headers: { "HTTP_REFERER" => admin_dashboard_path(customer.id) }
  end

  def announcement_write_params(announcement, overrides = {})
    {
      platform_announcement: {
        title: announcement.title,
        body_en: announcement.body_en,
        body_zh: announcement.body_zh,
        severity: announcement.severity,
        status: announcement.status,
        audience: announcement.audience
      }.merge(overrides)
    }
  end

  describe "live targeted published notice" do
    let(:title)   { "QA-BELL-LIVE-TITLE" }
    let(:body_en) { "QA-BELL-LIVE-BODY-EN" }

    before do
      create(:platform_announcement, :published, :all_customers, title: title, body_en: body_en)
      sign_in tenant_admin
      get admin_dashboard_path(tenant.id)
    end

    it "renders title and body_en in the bell panel with an unread badge" do
      expect(response).to have_http_status(:ok)
      expect(bell_text).to include(title)
      expect(bell_text).to include(body_en)
      expect(unread_badge).to be_present
      expect(unread_badge["data-badge-count"]).to eq("1")
    end

    it "still shows the same live notice in the banner independently of the bell" do
      expect(banner_text).to include(title)
      expect(banner_text).to include(body_en)
    end
  end

  describe "visibility filters" do
    before { sign_in tenant_admin }

    it "does not list a draft in the bell" do
      create(:platform_announcement, :draft, :all_customers, title: "QA-BELL-DRAFT-TITLE", body_en: "QA-BELL-DRAFT-BODY")

      get admin_dashboard_path(tenant.id)

      expect(response).to have_http_status(:ok)
      expect(bell_text).not_to include("QA-BELL-DRAFT-TITLE")
      expect(bell_text).not_to include("QA-BELL-DRAFT-BODY")
      expect(unread_badge).to be_nil
    end

    it "does not list a published announcement whose starts_at is in the future" do
      create(
        :platform_announcement, :published, :all_customers,
        title: "QA-BELL-FUTURE-TITLE",
        body_en: "QA-BELL-FUTURE-BODY",
        starts_at: 1.hour.from_now
      )

      get admin_dashboard_path(tenant.id)

      expect(response).to have_http_status(:ok)
      expect(bell_text).not_to include("QA-BELL-FUTURE-TITLE")
      expect(unread_badge).to be_nil
    end

    it "does not list a selected-audience notice that does not match the tenant" do
      other = create(:customer)
      create(
        :platform_announcement, :published, :selected,
        title: "QA-BELL-UNMATCHED-TITLE",
        body_en: "QA-BELL-UNMATCHED-BODY",
        target_rules: selected_rules_for(other)
      )

      get admin_dashboard_path(tenant.id)

      expect(response).to have_http_status(:ok)
      expect(bell_text).not_to include("QA-BELL-UNMATCHED-TITLE")
      expect(unread_badge).to be_nil
    end
  end

  describe "member dashboard" do
    it "does not contain the announcement title — member chrome has no bell inbox" do
      create(:platform_announcement, :published, :all_customers, title: "QA-BELL-MEMBER-LEAK")
      enable_module!("authentication", tenant, name: "Authentication")
      sign_in tenant_member
      get member_dashboard_path(tenant.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("QA-BELL-MEMBER-LEAK")
      expect(html.at_css("#notifications-panel-body")).to be_nil
      expect(unread_badge).to be_nil
    end
  end

  describe "owner acting-as" do
    let(:platform_owner) { find_or_create_platform_owner }
    let(:platform_cid)   { ensure_platform_customer.id }
    let(:target)         { create(:customer) }
    let(:title)          { "QA-BELL-ACT-AS-TITLE" }

    before do
      create(
        :platform_announcement, :published, :selected,
        title: title,
        body_en: "QA-BELL-ACT-AS-BODY",
        target_rules: selected_rules_for(target)
      )
      sign_in platform_owner
    end

    it "does not show a C-targeted notice on the 81721200 dashboard without acting-as" do
      get admin_dashboard_path(platform_cid)

      expect(response).to have_http_status(:ok)
      expect(bell_text).not_to include(title)
    end

    it "shows a C-targeted notice on C's dashboard after the owner acts as C" do
      patch admin_maintenance_platform_customer_context_path(platform_cid),
            params: { customer_id: target.id }
      expect(response).to redirect_to(admin_dashboard_path(target.id))
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(bell_text).to include(title)
      expect(unread_badge).to be_present
    end
  end

  describe "banner dismiss vs bell mark-read" do
    let(:title)   { "QA-BELL-DISMISS-READ-TITLE" }
    let(:body_en) { "QA-BELL-DISMISS-READ-BODY" }

    before do
      @announcement = create(:platform_announcement, :published, :all_customers, title: title, body_en: body_en)
      sign_in tenant_admin
    end

    it "drops the banner body after dismiss but keeps the title in the bell" do
      dismiss(@announcement)
      get admin_dashboard_path(tenant.id)

      expect(response).to have_http_status(:ok)
      expect(banner_text).not_to include(body_en)
      expect(banner_text).not_to include(title)
      expect(bell_text).to include(title)
      expect(unread_badge).to be_present
    end

    it "clears the unread badge after mark-read but keeps the banner body" do
      mark_read(@announcement)
      get admin_dashboard_path(tenant.id)

      expect(response).to have_http_status(:ok)
      expect(unread_badge).to be_nil
      expect(bell_text).to include(title)
      expect(bell_panel.at_css("span.font-medium.text-text-secondary")&.text).to include(title)
      expect(banner_text).to include(body_en)
    end
  end

  describe "ended / unpublished / discarded history" do
    it "keeps an announcement that ended 1 hour ago in the bell, not the banner" do
      create(
        :platform_announcement, :published, :all_customers,
        title: "QA-BELL-ENDED-HOUR-TITLE",
        body_en: "QA-BELL-ENDED-HOUR-BODY",
        ends_at: 1.hour.ago
      )
      sign_in tenant_admin
      get admin_dashboard_path(tenant.id)

      expect(response).to have_http_status(:ok)
      expect(bell_text).to include("QA-BELL-ENDED-HOUR-TITLE")
      expect(banner_text).not_to include("QA-BELL-ENDED-HOUR-BODY")
      expect(banner_text).not_to include("QA-BELL-ENDED-HOUR-TITLE")
    end

    it "hides an announcement that ended 8 days ago from the bell" do
      create(
        :platform_announcement, :published, :all_customers,
        title: "QA-BELL-ENDED-8D-TITLE",
        body_en: "QA-BELL-ENDED-8D-BODY",
        ends_at: 8.days.ago
      )
      sign_in tenant_admin
      get admin_dashboard_path(tenant.id)

      expect(response).to have_http_status(:ok)
      expect(bell_text).not_to include("QA-BELL-ENDED-8D-TITLE")
    end

    it "keeps an unpublished-from-live notice in the tenant admin bell" do
      announcement = create(
        :platform_announcement, :published, :all_customers,
        title: "QA-BELL-UNPUBLISHED-TITLE",
        body_en: "QA-BELL-UNPUBLISHED-BODY"
      )
      owner = find_or_create_platform_owner
      sign_in owner
      patch admin_maintenance_platform_announcement_path(ensure_platform_customer.id, announcement),
            params: announcement_write_params(announcement, status: "draft")
      expect(announcement.reload.status).to eq("draft")
      expect(announcement.left_live_at).to be_present

      sign_out owner
      sign_in tenant_admin
      get admin_dashboard_path(tenant.id)

      expect(response).to have_http_status(:ok)
      expect(bell_text).to include("QA-BELL-UNPUBLISHED-TITLE")
      expect(banner_text).not_to include("QA-BELL-UNPUBLISHED-BODY")
    end

    it "keeps a discarded live notice in the tenant admin bell" do
      announcement = create(
        :platform_announcement, :published, :all_customers,
        title: "QA-BELL-DISCARDED-TITLE",
        body_en: "QA-BELL-DISCARDED-BODY"
      )
      owner = find_or_create_platform_owner
      sign_in owner
      expect {
        delete admin_maintenance_platform_announcement_path(ensure_platform_customer.id, announcement)
      }.not_to change(PlatformAnnouncement, :count)
      expect(announcement.reload.deleted_at).to be_present

      sign_out owner
      sign_in tenant_admin
      get admin_dashboard_path(tenant.id)

      expect(response).to have_http_status(:ok)
      expect(bell_text).to include("QA-BELL-DISCARDED-TITLE")
    end
  end

  describe "per-admin reads" do
    it "does not clear admin B's unread badge when admin A marks the same notice read" do
      announcement = create(
        :platform_announcement, :published, :all_customers,
        title: "QA-BELL-TWO-ADMINS-TITLE"
      )
      other_admin = create(:user, :admin, customer: tenant)

      sign_in tenant_admin
      mark_read(announcement)
      get admin_dashboard_path(tenant.id)
      expect(unread_badge).to be_nil

      sign_out tenant_admin
      sign_in other_admin
      get admin_dashboard_path(tenant.id)

      expect(response).to have_http_status(:ok)
      expect(bell_text).to include("QA-BELL-TWO-ADMINS-TITLE")
      expect(unread_badge).to be_present
      expect(unread_badge["data-badge-count"]).to eq("1")
    end
  end
end
