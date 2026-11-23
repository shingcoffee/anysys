# frozen_string_literal: true

require "rails_helper"

# Admin::Maintenance::PagePreviewsController
#
# Serves the dedicated preview resource:
#   GET  /:cid/admin/maintenance/pages/:page_id/preview  (show)
#   POST /:cid/admin/maintenance/pages/:page_id/preview  (create)
#
# Both render the saved page content, or — when a `page[configuration]` blob is
# submitted — a preview built from that submitted configuration. Responds to
# HTML (preview layout) and JSON ({ content: ... }).

RSpec.describe "Admin::Maintenance::PagePreviews", type: :request do
  let(:customer)      { create(:customer) }
  let(:admin)         { create(:user, :admin, customer: customer) }
  let(:member)        { create(:user, :member, customer: customer) }
  let(:entity)        { create(:entity, customer: customer) }
  let!(:page_record)  { create(:page, customer: customer, entity: entity) }

  def preview_path(cust = customer, page = page_record)
    "/#{cust.id}/admin/maintenance/pages/#{page.id}/preview"
  end

  # ---------------------------------------------------------------------------
  # Authorization guards
  # ---------------------------------------------------------------------------

  describe "GET show — auth guards" do
    let(:guard_path) { preview_path }

    it_behaves_like "an admin-guarded GET"

    it "is rejected when embedding as anonymous" do
      get preview_path, params: { embed: 1 }
      expect(response).not_to have_http_status(:ok)
    end

    it "is forbidden when embedding as a member" do
      sign_in member
      get preview_path, params: { embed: 1 }
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "POST create — auth guards" do
    let(:guard_path) { preview_path }

    it_behaves_like "an admin-guarded request", :post
  end

  # ---------------------------------------------------------------------------
  # GET show — HTML
  # ---------------------------------------------------------------------------

  describe "GET show — HTML" do
    before { sign_in admin }

    it "renders the saved page content with the preview layout" do
      get preview_path
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
      expect(response.body).to include(I18n.t("public_views.layouts.preview.badge"))
      expect(response.body).to include(I18n.t("public_views.layouts.preview.back_to_editor"))
      expect(response.body).to include(page_record.name)
      expect(response.body).to include("py-8")

      get preview_path, params: { page: { configuration: page_record.configuration } }
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
    end

    it "omits preview chrome when embed=1" do
      get preview_path, params: { embed: 1 }
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")
      expect(response.body).to include(page_record.name)
      expect(response.body).not_to include(I18n.t("public_views.layouts.preview.badge"))
      expect(response.body).not_to include(I18n.t("public_views.layouts.preview.back_to_editor"))
      expect(response.body).to include("py-4")
      expect(response.body).not_to include("py-8")
    end
  end

  # ---------------------------------------------------------------------------
  # POST create — HTML
  # ---------------------------------------------------------------------------

  describe "POST create — HTML" do
    before { sign_in admin }

    it "renders HTML from submitted configuration or saved content" do
      post preview_path, params: { page: { configuration: page_record.configuration } }
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/html")

      post preview_path
      expect(response).to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------------
  # JSON — show and create return { content: ... }
  # ---------------------------------------------------------------------------

  describe "JSON responses" do
    before { sign_in admin }

    it "GET show returns content as JSON" do
      get preview_path, params: { format: :json }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key("content")
    end

    it "POST create returns content from the submitted configuration as JSON" do
      post preview_path,
           params: { page: { configuration: page_record.configuration } },
           as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key("content")
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant isolation
  # ---------------------------------------------------------------------------

  describe "cross-tenant isolation" do
    let(:other_customer) { create(:customer) }
    let!(:other_page)    { create(:page, customer: other_customer) }

    before { sign_in admin }

    it "returns 404 when previewing another tenant's page" do
      get preview_path(customer, other_page)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when embedding another tenant's page" do
      get preview_path(customer, other_page), params: { embed: 1 }
      expect(response).to have_http_status(:not_found)
    end
  end
end
