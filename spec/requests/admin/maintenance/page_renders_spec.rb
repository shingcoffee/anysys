# frozen_string_literal: true

require "rails_helper"

# Auth matrix, audience/published gating, and cross-tenant isolation for
# GET /:cid/admin/maintenance/pages/:page_id/render
# (Admin::Maintenance::PageRendersController#show)
RSpec.describe "Admin::Maintenance::PageRenders", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  # A published admin-only page — the happy-path record.
  let!(:page_record) do
    Current.set(customer: customer) do
      create(:page,
             customer:   customer,
             launched:  true)
    end
  end

  def render_url(cid = customer.id, page_id = page_record.id)
    "/#{cid}/admin/maintenance/pages/#{page_id}/render"
  end

  let(:guard_path) { render_url }

  it_behaves_like "an admin-guarded GET"

  it "redirects anonymous visitors to the customer sign-in page" do
    get render_url
    expect(response).to redirect_to("/auth/sign_in")
  end

  # -------------------------------------------------------------------------
  # Happy path — admin, published page with the admin audience
  # -------------------------------------------------------------------------

  context "admin of the same customer, page published with the admin audience" do
    before { sign_in admin }

    it "renders the page name in the body" do
      get render_url
      expect(response.body).to include(CGI.escapeHTML(page_record.name))
    end
  end

  # -------------------------------------------------------------------------
  # Audience/published gating — must 404, not 200
  # -------------------------------------------------------------------------

  context "admin, page without the admin audience" do
    before do
      sign_in admin
      page_record.update!(visible_audiences: %w[member])
    end

    it "returns 404" do
      get render_url
      expect(response).to have_http_status(:not_found)
    end
  end

  context "admin, page is unpublished" do
    before do
      sign_in admin
      page_record.update!(launched: false)
    end

    it "returns 404" do
      get render_url
      expect(response).to have_http_status(:not_found)
    end
  end

  # -------------------------------------------------------------------------
  # Cross-tenant isolation — admin from another customer must not see the page
  # -------------------------------------------------------------------------

  context "admin of a different customer" do
    let(:other_customer) { create(:customer) }
    let(:other_admin)    { create(:user, :admin, customer: other_customer) }

    before { sign_in other_admin }

    it "is denied (not 200) — tenant guard prevents cross-customer access" do
      get render_url
      expect(response).not_to have_http_status(:ok)
    end
  end

  # -------------------------------------------------------------------------
  # Platform owner — cross-tenant read must succeed
  # -------------------------------------------------------------------------

  context "platform owner visiting another customer's page" do
    let(:owner) { find_or_create_platform_owner }

    before do
      ensure_platform_customer
      sign_in owner
    end

    it "returns 200 (cross-tenant access permitted for platform owner)" do
      get render_url
      expect(response).to have_http_status(:ok)
    end
  end

  # -------------------------------------------------------------------------
  # PageRendering form_action always targets public_page_submit_path
  # -------------------------------------------------------------------------

  context "page forms" do
    before { sign_in admin }

    let(:entity) { create(:entity, customer: customer) }

    let!(:page_with_form) do
      Current.set(customer: customer) do
        create(:page,
               customer:   customer,
               entity:     entity,
               launched:   true,
               configuration: {
                 pages:    [{ id: "p1", name: "P1", order: 1, fields: [] }],
                 metadata: { entity_id: entity.id, entity_name: entity.name }
               }.to_json)
      end
    end

    let!(:page_with_leftover_flowchart_id) do
      Current.set(customer: customer) do
        create(:page,
               customer:   customer,
               launched:   true,
               configuration: {
                 pages:    [{ id: "p1", name: "P1", order: 1, fields: [] }],
                 metadata: {},
                 form_settings: { flowchart_id: 999_999_999 }
               }.to_json)
      end
    end

    it "returns 200 for an entity form and for a page with a leftover flowchart id" do
      get "/#{customer.id}/admin/maintenance/pages/#{page_with_form.id}/render"
      expect(response).to have_http_status(:ok)

      get "/#{customer.id}/admin/maintenance/pages/#{page_with_leftover_flowchart_id.id}/render"
      expect(response).to have_http_status(:ok)
    end
  end

  context "admin audience required" do
    before { sign_in admin }

    it "returns 404 when admin is not in the set" do
      page_record.update!(audience_admin: false, audience_member: false, audience_public: true)

      get render_url

      expect(response).to have_http_status(:not_found)
    end
  end
end
