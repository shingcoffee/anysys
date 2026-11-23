# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::Announcements", type: :request do
  let(:platform_owner) { find_or_create_platform_owner }
  let(:platform_cid)   { ensure_platform_customer.id }

  let(:other_customer) { create(:customer) }
  let(:tenant_admin)   { create(:user, :admin, customer: other_customer) }

  let(:valid_attrs) do
    {
      title: "Q3 downtime",
      body_en: "We will be down for maintenance.",
      body_zh: "系统将进行维护。",
      severity: "warning",
      status: "published",
      audience: "all"
    }
  end

  def announcement_params(overrides = {})
    { platform_announcement: valid_attrs.merge(overrides) }
  end

  let(:guard_path) { admin_maintenance_platform_announcements_path(platform_cid) }

  it_behaves_like "a platform-owner-guarded GET"
  it_behaves_like "a platform-owner-guarded request", :post

  describe "GET show — auth guards" do
    let(:announcement) { create(:platform_announcement) }
    let(:guard_path) { admin_maintenance_platform_announcement_path(platform_cid, announcement) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET new — auth guards" do
    let(:guard_path) { new_admin_maintenance_platform_announcement_path(platform_cid) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET edit — auth guards" do
    let(:announcement) { create(:platform_announcement) }
    let(:guard_path) { edit_admin_maintenance_platform_announcement_path(platform_cid, announcement) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "PATCH update — auth guards" do
    let(:announcement) { create(:platform_announcement) }
    let(:guard_path) { admin_maintenance_platform_announcement_path(platform_cid, announcement) }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "DELETE destroy — auth guards" do
    let(:announcement) { create(:platform_announcement) }
    let(:guard_path) { admin_maintenance_platform_announcement_path(platform_cid, announcement) }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  describe "POST audience_preview — auth guards" do
    let(:guard_path) { audience_preview_admin_maintenance_platform_announcements_path(platform_cid) }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "tenant admin" do
    before { sign_in tenant_admin }

    it "cannot create via POST to the platform-owner announcements path" do
      expect {
        post admin_maintenance_platform_announcements_path(platform_cid),
             params: announcement_params
      }.not_to change(PlatformAnnouncement, :count)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
      expect(response).not_to have_http_status(:ok)
    end

    it "cannot update via PATCH to the platform-owner announcements path" do
      announcement = create(:platform_announcement, title: "Keep original")
      patch admin_maintenance_platform_announcement_path(platform_cid, announcement),
            params: announcement_params(title: "Hijacked")
      expect(announcement.reload.title).to eq("Keep original")
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
      expect(response).not_to have_http_status(:ok)
    end

    it "cannot destroy via DELETE to the platform-owner announcements path" do
      announcement = create(:platform_announcement)
      expect {
        delete admin_maintenance_platform_announcement_path(platform_cid, announcement)
      }.not_to change(PlatformAnnouncement, :count)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "platform owner" do
    before { sign_in platform_owner }

    describe "GET index" do
      it "returns 200 and lists announcements" do
        create(:platform_announcement, title: "Listed notice")
        get admin_maintenance_platform_announcements_path(platform_cid)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Listed notice")
      end
    end

    describe "GET show" do
      it "returns 200" do
        announcement = create(:platform_announcement, :published, title: "Show notice")
        get admin_maintenance_platform_announcement_path(platform_cid, announcement)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Show notice")
      end

      it "lists customers that currently match selected target_rules" do
        matching = create(:customer, name: "Acme Match Co")
        create(:customer, name: "Other Tenant")
        announcement = create(
          :platform_announcement, :published, :selected,
          title: "Filtered notice",
          target_rules: {
            "type" => "group",
            "joins" => [],
            "conditions" => [
              { "field" => "id", "operator" => "equals", "value" => matching.id.to_s }
            ]
          }
        )
        get admin_maintenance_platform_announcement_path(platform_cid, announcement)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Acme Match Co")
        expect(response.body).not_to include("Other Tenant")
      end
    end

    describe "GET new" do
      it "returns 200 and renders the form with the customer condition builder" do
        get new_admin_maintenance_platform_announcement_path(platform_cid)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("maint_platform.announcements.form.create"))
        expect(response.body).to include('name="platform_announcement[target_rules_json]"')
        expect(response.body).to include('data-controller="segment-builder"')
      end
    end

    describe "GET edit" do
      it "returns 200 and renders the form" do
        announcement = create(:platform_announcement, title: "Editable")
        get edit_admin_maintenance_platform_announcement_path(platform_cid, announcement)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("maint_platform.announcements.form.update"))
        expect(response.body).to include("Editable")
      end
    end

    describe "POST create" do
      it "creates a published all-audience announcement and redirects to index" do
        expect {
          post admin_maintenance_platform_announcements_path(platform_cid),
               params: announcement_params
        }.to change(PlatformAnnouncement, :count).by(1)

        created = PlatformAnnouncement.order(:id).last
        expect(created.status).to eq("published")
        expect(created.audience).to eq("all")
        expect(created.target_rules).to eq({})
        expect(response).to redirect_to(admin_maintenance_platform_announcements_path(platform_cid))
        follow_redirect!
        expect(response.body).to include(I18n.t("maint_platform.flash.announcements.created"))
      end

      it "creates a selected announcement from target_rules_json" do
        rules = {
          "type" => "group",
          "joins" => [],
          "conditions" => [
            { "field" => "id", "operator" => "equals", "value" => other_customer.id.to_s }
          ]
        }
        expect {
          post admin_maintenance_platform_announcements_path(platform_cid),
               params: announcement_params(
                 audience: "selected",
                 target_rules_json: rules.to_json
               )
        }.to change(PlatformAnnouncement, :count).by(1)

        created = PlatformAnnouncement.order(:id).last
        expect(created.audience).to eq("selected")
        expect(created.target_rules).to eq(rules)
        expect(response).to redirect_to(admin_maintenance_platform_announcements_path(platform_cid))
      end

      it "re-renders new with 422 when validation fails" do
        expect {
          post admin_maintenance_platform_announcements_path(platform_cid),
               params: announcement_params(title: "", body_en: "")
        }.not_to change(PlatformAnnouncement, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "PATCH update" do
      it "updates the announcement and redirects to show" do
        announcement = create(:platform_announcement, :published, :all_customers, title: "Before")
        patch admin_maintenance_platform_announcement_path(platform_cid, announcement),
              params: announcement_params(title: "After")
        expect(announcement.reload.title).to eq("After")
        expect(response).to redirect_to(
          admin_maintenance_platform_announcement_path(platform_cid, announcement)
        )
        follow_redirect!
        expect(response.body).to include(I18n.t("maint_platform.flash.announcements.updated"))
      end

      it "re-renders edit with 422 when validation fails" do
        announcement = create(:platform_announcement, title: "Keep me")
        patch admin_maintenance_platform_announcement_path(platform_cid, announcement),
              params: announcement_params(title: "")
        expect(announcement.reload.title).to eq("Keep me")
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "DELETE destroy" do
      it "hard-deletes a never-live draft and redirects to index" do
        announcement = create(:platform_announcement)
        expect {
          delete admin_maintenance_platform_announcement_path(platform_cid, announcement)
        }.to change(PlatformAnnouncement, :count).by(-1)
        expect(response).to redirect_to(admin_maintenance_platform_announcements_path(platform_cid))
        follow_redirect!
        expect(response.body).to include(I18n.t("maint_platform.flash.announcements.deleted"))
      end

      it "discards a published live row so the tenant admin still sees it in the bell for 7 days" do
        announcement = create(
          :platform_announcement, :published, :all_customers,
          title: "QA-DESTROY-LIVE-BELL-TITLE",
          body_en: "QA-DESTROY-LIVE-BELL-BODY"
        )

        expect {
          delete admin_maintenance_platform_announcement_path(platform_cid, announcement)
        }.not_to change(PlatformAnnouncement, :count)

        announcement.reload
        expect(announcement.deleted_at).to be_present
        expect(announcement.left_live_at).to be_present
        expect(response).to redirect_to(admin_maintenance_platform_announcements_path(platform_cid))

        sign_out platform_owner
        sign_in tenant_admin
        get admin_dashboard_path(other_customer.id)

        expect(response).to have_http_status(:ok)
        panel = Nokogiri::HTML(response.body).at_css("#notifications-panel-body")
        expect(panel&.text).to include("QA-DESTROY-LIVE-BELL-TITLE")
      end
    end
  end

  describe "POST audience_preview" do
    let!(:acme)  { create(:customer, name: "Acme Industries") }
    let!(:globex) { create(:customer, name: "Globex") }

    def id_rules(id)
      {
        "type" => "group", "joins" => [],
        "conditions" => [ { "field" => "id", "operator" => "equals", "value" => id.to_s } ]
      }
    end

    def preview(body)
      post audience_preview_admin_maintenance_platform_announcements_path(platform_cid),
           params: body, as: :json
    end

    it "sizes the audience for the platform owner" do
      sign_in platform_owner
      preview(target_rules_json: id_rules(acme.id).to_json)

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body
      expect(payload["count"]).to eq(1)
      expect(payload["sample"].map { |c| c["name"] }).to eq([ "Acme Industries" ])
    end

    it "reports zero for conditions nothing matches" do
      sign_in platform_owner
      preview(target_rules_json: id_rules(-1).to_json)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["count"]).to eq(0)
    end

    it "treats empty conditions as nobody, never everybody" do
      sign_in platform_owner
      preview(target_rules_json: "{}")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["count"]).to eq(0)
    end

    it "rejects malformed JSON with a translated error" do
      sign_in platform_owner
      preview(target_rules_json: "{not json")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"])
        .to eq(I18n.t("maint_platform.announcements.form.errors.target_rules_invalid"))
    end

    it "caps the returned sample" do
      sign_in platform_owner
      preview(target_rules_json: {
        "type" => "group", "joins" => [],
        "conditions" => [ { "field" => "id", "operator" => "is_present", "value" => "" } ]
      }.to_json)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["sample"].size)
        .to be <= Admin::Maintenance::Platform::AnnouncementsController::PREVIEW_SAMPLE_LIMIT
    end

    it "is denied to a tenant admin" do
      sign_in tenant_admin
      post audience_preview_admin_maintenance_platform_announcements_path(other_customer.id),
           params: { target_rules_json: "{}" }, as: :json

      expect(response).not_to have_http_status(:ok)
    end

    it "is denied to an anonymous visitor" do
      preview(target_rules_json: "{}")
      expect(response).not_to have_http_status(:ok)
    end
  end
end
