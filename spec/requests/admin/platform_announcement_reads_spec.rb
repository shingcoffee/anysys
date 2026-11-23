# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::PlatformAnnouncementReads", type: :request do
  let(:tenant)        { create(:customer) }
  let(:customer)      { tenant }
  let(:tenant_admin)  { create(:user, :admin, customer: tenant) }
  let(:admin)         { tenant_admin }
  let(:tenant_member) { create(:user, :member, customer: tenant) }
  let(:guard_path)    { admin_platform_announcement_reads_path(tenant.id) }

  it_behaves_like "an admin-guarded request", :post

  def mark_read(announcement, customer: tenant)
    post admin_platform_announcement_reads_path(customer.id),
         params: { platform_announcement_id: announcement.id },
         headers: { "HTTP_REFERER" => admin_dashboard_path(customer.id) }
  end

  def read_ids(user:, customer:)
    PlatformAnnouncementRead.announcement_ids_for(user_id: user.id, customer_id: customer.id)
  end

  describe "tenant admin" do
    before { sign_in tenant_admin }

    it "persists a targeted live read for the user and redirects" do
      announcement = create(:platform_announcement, :published, :all_customers)
      mark_read(announcement)

      expect(read_ids(user: tenant_admin, customer: tenant)).to include(announcement.id)
      expect(response).to redirect_to(admin_dashboard_path(tenant.id))
    end

    it "is idempotent when the same announcement is marked read twice" do
      announcement = create(:platform_announcement, :published, :all_customers)
      mark_read(announcement)
      mark_read(announcement)

      expect(PlatformAnnouncementRead.count).to eq(1)
      expect(response).to redirect_to(admin_dashboard_path(tenant.id))
    end

    it "responds with Turbo Streams replacing the trigger, badge, and panel body" do
      announcement = create(
        :platform_announcement, :published, :all_customers,
        title: "QA-READ-STREAM-TITLE"
      )
      post admin_platform_announcement_reads_path(tenant.id),
           params: { platform_announcement_id: announcement.id },
           headers: { "HTTP_REFERER" => admin_dashboard_path(tenant.id),
                      "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(target="notifications-trigger"))
      expect(response.body).to include(%(target="notifications-badge"))
      expect(response.body).to include(%(target="notifications-panel-body"))
      expect(response.body).to include(%(target="notifications-announcement-unread"))
      expect(response.body).not_to include(%(target="notifications-bell-inner"))
      expect(response.body).to include("turbo-stream")
      expect(response.body).to include("QA-READ-STREAM-TITLE")
      expect(response.body).to include("text-text-muted")
      expect(response.body).to include(%(aria-expanded="true"))
      expect(response.body).not_to include(%(data-controller="notifications-menu"))
      expect(response.body).not_to include("data-badge-count")

      stream = Nokogiri::HTML(response.body)
      expect(stream.at_css("[data-controller='notifications-menu']")).to be_nil
      expect(stream.at_css("[data-badge-count]")).to be_nil
      expect(stream.at_css("#notifications-trigger")["aria-expanded"]).to eq("true")
      expect(stream.at_css("#notifications-badge")).to be_present
      expect(stream.at_css("span.font-medium.text-text-secondary")&.text).to include("QA-READ-STREAM-TITLE")
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

      mark_read(draft)
      expect(read_ids(user: tenant_admin, customer: tenant)).not_to include(draft.id)
      expect(response).to have_http_status(:redirect)

      mark_read(untargeted)
      expect(read_ids(user: tenant_admin, customer: tenant)).not_to include(untargeted.id)
      expect(response).to redirect_to(admin_dashboard_path(tenant.id))
    end

    it "does not store an aged-out history id" do
      aged = create(:platform_announcement, :published, :all_customers, ends_at: 8.days.ago)
      mark_read(aged)

      expect(read_ids(user: tenant_admin, customer: tenant)).not_to include(aged.id)
      expect(PlatformAnnouncementRead.count).to eq(0)
      expect(response).to redirect_to(admin_dashboard_path(tenant.id))
    end

    it "does not create a PlatformAnnouncementDismissal when marking read" do
      announcement = create(:platform_announcement, :published, :all_customers)
      mark_read(announcement)

      expect(PlatformAnnouncementRead.count).to eq(1)
      expect(PlatformAnnouncementDismissal.count).to eq(0)
    end
  end

  describe "banner dismiss isolation" do
    before { sign_in tenant_admin }

    it "does not create a PlatformAnnouncementRead when the banner is dismissed" do
      announcement = create(:platform_announcement, :published, :all_customers)
      post admin_platform_announcement_dismissals_path(tenant.id),
           params: { platform_announcement_id: announcement.id },
           headers: { "HTTP_REFERER" => admin_dashboard_path(tenant.id) }

      expect(PlatformAnnouncementDismissal.count).to eq(1)
      expect(PlatformAnnouncementRead.count).to eq(0)
    end
  end

  describe "member" do
    before { sign_in tenant_member }

    it "is denied without recording a read" do
      announcement = create(:platform_announcement, :published, :all_customers)
      mark_read(announcement)
      expect(PlatformAnnouncementRead.count).to eq(0)
    end
  end

  describe "cross-tenant mark-read" do
    let(:other)       { create(:customer) }
    let(:other_admin) { create(:user, :admin, customer: other) }

    it "forbids admin of A from marking read on B's URL and writes nothing" do
      announcement = create(:platform_announcement, :published, :all_customers)

      sign_in tenant_admin
      mark_read(announcement, customer: other)

      expect(response).to have_http_status(:forbidden).or have_http_status(:redirect)
      expect(response).not_to have_http_status(:ok)
      expect(PlatformAnnouncementRead.count).to eq(0)
    end
  end

  describe "owner acting-as" do
    let(:platform_owner) { find_or_create_platform_owner }
    let(:platform_cid)   { ensure_platform_customer.id }

    it "stores the read against the acted-as tenant, not 81721200" do
      announcement = create(:platform_announcement, :published, :all_customers)
      sign_in platform_owner
      patch admin_maintenance_platform_customer_context_path(platform_cid),
            params: { customer_id: tenant.id }
      mark_read(announcement, customer: tenant)

      expect(read_ids(user: platform_owner, customer: tenant)).to include(announcement.id)
      expect(PlatformAnnouncementRead.announcement_ids_for(
        user_id: platform_owner.id, customer_id: platform_cid
      )).to eq([])
    end
  end
end
