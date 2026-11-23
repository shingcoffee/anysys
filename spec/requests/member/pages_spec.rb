# frozen_string_literal: true

require "rails_helper"

# Auth matrix, audience-set/launched gating, cross-tenant isolation, and
# route precedence for GET /:cid/member/pages/:id
# (Member::PagesController#show)
RSpec.describe "Member::Pages", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:member)   { create(:user, :member, customer: customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  # A published page visible to the member audience — the happy-path record.
  let!(:page_record) do
    Current.set(customer: customer) do
      create(:page, :for_member,
             customer:   customer,
             launched:  true)
    end
  end

  def show_url(cid = customer.id, page_id = page_record.id)
    "/#{cid}/member/pages/#{page_id}"
  end

  # -------------------------------------------------------------------------
  # Authentication gate
  # -------------------------------------------------------------------------

  context "anonymous visitor" do
    it "redirects to the customer sign-in page" do
      get show_url
      expect(response).to redirect_to("/auth/sign_in")
    end
  end

  # -------------------------------------------------------------------------
  # Happy path — member, published + visible_to member
  # -------------------------------------------------------------------------

  context "member of the same customer, page published and visible to member" do
    before { sign_in member }

    it "renders the page name in the body" do
      get show_url
      expect(response.body).to include(CGI.escapeHTML(page_record.name))
    end

    # -----------------------------------------------------------------------
    # Member chrome assertions (Task 4 — visual refresh)
    # -----------------------------------------------------------------------

    it "renders the page in the site card chrome" do
      get show_url
      expect(response.body).to include("data-member-card")
    end

    it "does NOT use generic admin card class" do
      get show_url
      expect(response.body).not_to match(/class="card /)
    end

    it "does NOT use admin border-border-subtle token" do
      get show_url
      expect(response.body).not_to include("border-border-subtle")
    end

    it "does NOT use page_chrome header color output" do
      get show_url
      # page_chrome_header_color returns CSS classes like 'text-red-600' or similar theme tokens;
      # the member view must not call this helper at all — check for its known output patterns.
      # The helper always returns a text-* color class tied to the per-page public theme.
      # We assert the generic fallback and section-header class are absent.
      expect(response.body).not_to include("section-header")
    end
  end

  # -------------------------------------------------------------------------
  # Blank-content empty state (Task 4 — visual refresh)
  # The factory-created page has no fields, so generate_content returns "".
  # The member view must render EmptyStateComponent copy in this case.
  # -------------------------------------------------------------------------

  context "member, page published with no content (factory default: empty fields)" do
    before { sign_in member }

    it "shows the member empty-state headline" do
      get show_url
      expect(response.body).to include("No content yet")
    end

    it "shows the descriptive empty-state body copy" do
      get show_url
      expect(response.body).to include("This page has no content to render yet")
    end
  end

  # -------------------------------------------------------------------------
  # Content-present branch (visual refresh + form-width fix)
  # A page WITH fields makes generate_content return non-blank HTML. The view
  # renders @content verbatim (the page-builder PageComponent brings its own
  # card + form-width centering) inside a form-width container — it must NOT
  # double-wrap the form in a full-width member card, which produced large
  # empty side margins. This guards the @content.present? branch.
  # -------------------------------------------------------------------------

  context "member, page published WITH renderable content" do
    let(:entity) do
      Current.set(customer: customer) do
        create(:entity, customer: customer, property_schema: [
          { "name" => "Full Name", "name_slug" => "full_name", "type" => "String", "html_type" => "text" }
        ].to_json)
      end
    end

    let!(:content_page) do
      Current.set(customer: customer) do
        create(:page, :for_member,
               customer:   customer,
               entity:     entity,
               launched:   true,
               configuration: {
                 pages: [{
                   id: "page_1", name: "Page 1", order: 1,
                   fields: [{
                     id: "field_name", field_type: "text_input",
                     property_slug: "full_name", property_type: "string",
                     label: "Full Name", required: false, width: "full", order: 0
                   }]
                 }],
                 metadata: { entity_id: entity.id, entity_name: entity.name }
               }.to_json)
      end
    end

    before { sign_in member }

    it "renders the member page header above the content" do
      get show_url(customer.id, content_page.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-member-title")
      expect(response.body).to include(CGI.escapeHTML(content_page.name))
    end

    it "does NOT double-wrap the self-contained form in a full-width member card" do
      get show_url(customer.id, content_page.id)
      # The page-builder PageComponent supplies its own card + form-width
      # centering; the member view must not add a second site card around it.
      expect(response.body).not_to include("data-member-card")
    end

    it "renders the configured field content (not the empty state)" do
      get show_url(customer.id, content_page.id)
      expect(response.body).to include("Full Name")
      expect(response.body).not_to include("This page has no content to render yet")
    end
  end

  # -------------------------------------------------------------------------
  # Admin preview (same-tenant admin GET opt-in)
  # -------------------------------------------------------------------------

  describe "admin preview" do
    it "allows a same-tenant admin to open the member render" do
      sign_in admin
      get show_url
      expect(response).to have_http_status(:ok)
    end

    it "still 404s the admin preview when the page is admin-only" do
      page_record.update!(audience_member: false, audience_public: false)
      sign_in admin
      get show_url
      expect(response).to have_http_status(:not_found)
    end

    it "refuses an admin POST through the member preview of a member-only page" do
      page_record.update!(audience_admin: false, audience_member: true, audience_public: false)
      sign_in admin
      get show_url
      expect(response).to have_http_status(:ok)

      post "/#{customer.id}/page/#{page_record.public_uuid}"
      expect(response).to have_http_status(:not_found)
    end

    it "rejects an admin from another tenant (cross-tenant isolation)" do
      other_customer = create(:customer)
      other_customer_admin = create(:user, :admin, customer: other_customer)
      sign_in other_customer_admin
      get show_url
      expect(response).to redirect_to("/#{other_customer_admin.customer_id}/admin/assistant")
    end

    it "allows an admin HEAD request via the preview opt-in" do
      sign_in admin
      head show_url
      expect(response).to have_http_status(:ok)
    end
  end

  # -------------------------------------------------------------------------
  # Audience-set / launched gating — must 404, not 200
  # -------------------------------------------------------------------------

  context "member, page is unpublished" do
    before do
      sign_in member
      page_record.update!(launched: false)
    end

    it "returns 404" do
      get show_url
      expect(response).to have_http_status(:not_found)
    end
  end

  context "member, page published but admin-only (member not in the set)" do
    before do
      sign_in member
      page_record.update!(audience_member: false, audience_public: false)
    end

    it "returns 404 (admin-only page is not visible_to?(:member))" do
      get show_url
      expect(response).to have_http_status(:not_found)
    end
  end

  # -------------------------------------------------------------------------
  # Cross-tenant isolation — member from another customer must not see the page
  # -------------------------------------------------------------------------

  context "member of a different customer" do
    let(:other_customer) { create(:customer) }
    let(:other_member)   { create(:user, :member, customer: other_customer) }

    before { sign_in other_member }

    it "is denied — cross-tenant isolation (redirect or non-200)" do
      get show_url
      # TenantContext intercepts cross-tenant signed-in users; the response
      # is either a redirect from the tenant guard or a non-200 from the
      # audience gate — either is correct tenant isolation.
      expect(response).not_to have_http_status(:ok)
    end
  end

  # -------------------------------------------------------------------------
  # Route precedence — /member/pages/:id must resolve to Member::PagesController
  # (not the :key catch-all surfaces route that follows it in routes.rb)
  # -------------------------------------------------------------------------

  context "route precedence over surfaces catch-all" do
    before { sign_in member }

    it "returns 404 (page lookup) for a non-existent page id, not a surfaces lookup" do
      get "/#{customer.id}/member/pages/0"
      expect(response).to have_http_status(:not_found)
    end

    it "serves an existing page at /member/pages/:id (would 404 under the surfaces catch-all)" do
      # If the surfaces catch-all matched first, key 'pages' would miss the
      # surface registry and 404; a 200 proves Member::PagesController won.
      get show_url
      expect(response).to have_http_status(:ok)
    end
  end

  context "member, page is public-only" do
    before do
      sign_in member
      page_record.update!(audience_admin: false, audience_member: false, audience_public: true)
    end

    it "returns 404 because member is not in the set" do
      get show_url
      expect(response).to have_http_status(:not_found)
    end
  end
end
