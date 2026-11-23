# frozen_string_literal: true

require "rails_helper"

# GET /:cid/page/:uuid renders when public is in the set, unless the viewer's
# audience has a counterpart in the same action (§3.2.6). POST requires the
# viewer's audience and otherwise applies the §3.1.5 refusal rules in order.
RSpec.describe "Public page visibility enforcement", type: :request do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }

  let!(:page_rec) do
    Current.set(customer: customer) do
      create(:page, customer: customer, launched: true, public_uuid: SecureRandom.uuid)
    end
  end
  let(:url) { "/#{customer.id}/page/#{page_rec.public_uuid}" }

  def sign_in_member(cust = customer)
    sign_in create(:user, :member, customer: cust)
  end

  def sign_in_admin(cust = customer)
    sign_in create(:user, :admin, customer: cust)
  end

  def create_launched_page(*traits, key: nil)
    attrs = { customer: customer, launched: true }
    attrs[:action_key] = key if key
    Current.set(customer: customer) { create(:page, *traits, **attrs) }
  end

  def submittable_page(*traits, key: nil)
    attrs = {
      customer: customer,
      entity: entity,
      launched: true,
      configuration: {
        metadata: { entity_id: entity.id, entity_name: entity.name },
        fields: []
      }.to_json
    }
    attrs[:action_key] = key if key
    Current.set(customer: customer) { create(:page, *traits, **attrs) }
  end

  # -----------------------------------------------------------------------
  # GET — public in the set (old public mapping: admin + member + public)
  # -----------------------------------------------------------------------
  context "when the page includes the public audience" do
    before { page_rec.update!(audience_member: true, audience_public: true) }

    it "renders 200 for an anonymous visitor" do
      get url
      expect(response).to have_http_status(:ok)
    end

    it "renders 200 for a signed-in member of the customer" do
      sign_in_member
      get url
      expect(response).to have_http_status(:ok)
    end

    it "renders 200 for a signed-in admin of the customer" do
      sign_in_admin
      get url
      expect(response).to have_http_status(:ok)
    end
  end

  context "when the page is public-only" do
    let!(:public_only) { create_launched_page(:public_only) }
    let(:public_only_url) { "/#{customer.id}/page/#{public_only.public_uuid}" }

    it "renders 200 for an anonymous visitor" do
      get public_only_url
      expect(response).to have_http_status(:ok)
    end

    it "renders 200 for a signed-in member when there is no counterpart" do
      sign_in_member
      get public_only_url
      expect(response).to have_http_status(:ok)
    end

    it "renders 200 for a signed-in admin when there is no counterpart" do
      sign_in_admin
      get public_only_url
      expect(response).to have_http_status(:ok)
    end
  end

  context "when the page is admin-only (default)" do
    it "returns 404 for an anonymous visitor (no sign-in leak)" do
      get url
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a signed-in member of the same customer" do
      sign_in_member
      get url
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a signed-in admin of the same customer" do
      sign_in_admin
      get url
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for the platform owner crossing into this tenant" do
      ensure_platform_customer
      sign_in find_or_create_platform_owner
      get url
      expect(response).to have_http_status(:not_found)
    end
  end

  context "when the page is member-level (admin + member)" do
    before { page_rec.update!(audience_member: true) }

    it "returns 404 for an anonymous visitor" do
      get url
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a signed-in member of the same customer" do
      sign_in_member
      get url
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a signed-in admin of the same customer" do
      sign_in_admin
      get url
      expect(response).to have_http_status(:not_found)
    end
  end

  context "when the page is member-only" do
    let!(:member_only) { create_launched_page(:member_only) }

    it "returns 404 at the public URL" do
      get "/#{customer.id}/page/#{member_only.public_uuid}"
      expect(response).to have_http_status(:not_found)
    end
  end

  # -----------------------------------------------------------------------
  # GET — counterpart redirect (§3.2.6)
  # -----------------------------------------------------------------------
  context "when the action has a counterpart for the viewer" do
    let!(:public_page) { create_launched_page(:public_only, key: "enroll") }
    let!(:member_page) { create_launched_page(:member_only, key: "enroll") }
    let!(:admin_page) { create_launched_page(key: "enroll") }
    let(:public_url) { "/#{customer.id}/page/#{public_page.public_uuid}" }

    it "redirects a signed-in member (303) to the member counterpart and keeps prefill" do
      sign_in_member
      get public_url, params: { prefill: { course: "99" } }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(
        "#{member_page_path(customer_id: customer.id, id: member_page.id)}?#{ { prefill: { "course" => "99" } }.to_query }"
      )
    end

    it "redirects a signed-in admin (303) to Create Entry and keeps prefill" do
      sign_in_admin
      get public_url, params: { prefill: { course: "99" } }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(
        "#{new_admin_entity_entry_path(customer.id, admin_page.entity)}?#{ { prefill: { "course" => "99" } }.to_query }"
      )
    end
  end

  context "when a shared public page shares its action with this tenant's public page" do
    let!(:shared_page) do
      create(:page, :shared, :public_only, launched: true, action_key: "enroll", public_uuid: SecureRandom.uuid)
    end
    let!(:tenant_page) { create_launched_page(:public_only, key: "enroll") }

    it "redirects (303) from the shared page to the tenant's page" do
      get "/#{customer.id}/page/#{shared_page.public_uuid}"

      expect(response).to have_http_status(:see_other)
      expect(response.location).to include(tenant_page.public_uuid)
      expect(response.location).to start_with("http://www.example.com/")
    end

    it "renders the tenant's page without a further redirect" do
      get "/#{customer.id}/page/#{tenant_page.public_uuid}"

      expect(response).to have_http_status(:ok)
    end
  end

  # -----------------------------------------------------------------------
  # POST — authorizes against the viewer's audience, then §3.1.5 refusals
  # -----------------------------------------------------------------------
  context "submit on an admin-only page" do
    it "redirects an anonymous POST to sign-in rather than processing" do
      post url
      expect(response).to redirect_to("/auth/sign_in")
    end

    it "stores the admin render path so sign-in does not return to a public 404" do
      post url
      expect(session["user_return_to"]).to eq(
        admin_maintenance_page_render_path(customer.id, page_rec)
      )
    end

    it "returns 404 for a member POSTing to an admin-only page (no counterpart, no public)" do
      sign_in_member
      post url
      expect(response).to have_http_status(:not_found)
    end

    it "accepts a POST from an admin (authorized to view the page)" do
      sign_in_admin
      post url
      expect(response).not_to have_http_status(:not_found)
    end
  end

  context "submit on a member-level page" do
    before { page_rec.update!(audience_member: true) }

    it "accepts a POST from a member of the same customer" do
      sign_in_member
      post url
      expect(response).not_to have_http_status(:not_found)
    end

    it "redirects an anonymous POST to sign-in" do
      post url
      expect(response).to redirect_to("/auth/sign_in")
    end

    it "stores the member page path so sign-in does not return to a public 404" do
      post url
      expect(session["user_return_to"]).to eq("/#{customer.id}/member/pages/#{page_rec.id}")
    end

    it "rejects a member of a different customer (cross-tenant isolation)" do
      sign_in_member(other_customer)
      post url
      expect(response).to have_http_status(:not_found)
                      .or have_http_status(:forbidden)
                      .or redirect_to("/#{other_customer.id}/member")
    end
  end

  context "POST refusal rules (§3.1.5) write nothing" do
    it "redirects a member to the counterpart with continue_here" do
      public_page = submittable_page(:public_only, key: "enroll")
      member_page = create_launched_page(:member_only, key: "enroll")
      sign_in_member

      expect {
        post "/#{customer.id}/page/#{public_page.public_uuid}"
      }.not_to change(EntityEntry, :count)

      expect(response).to redirect_to(member_page_path(customer_id: customer.id, id: member_page.id))
      expect(flash[:notice]).to eq(I18n.t("public_views.actions.continue_here"))
    end

    it "sends a member back to a public-only page with not_for_your_account when there is no counterpart" do
      page = submittable_page(:public_only)
      sign_in_member

      expect {
        post "/#{customer.id}/page/#{page.public_uuid}"
      }.not_to change(EntityEntry, :count)

      expect(response).to redirect_to("/#{customer.id}/page/#{page.public_uuid}")
      expect(flash[:alert]).to eq(I18n.t("public_views.actions.not_for_your_account"))
    end

    it "sends an admin back to a public-only page with not_for_your_account" do
      page = submittable_page(:public_only)
      sign_in_admin

      expect {
        post "/#{customer.id}/page/#{page.public_uuid}"
      }.not_to change(EntityEntry, :count)

      expect(response).to redirect_to("/#{customer.id}/page/#{page.public_uuid}")
      expect(flash[:alert]).to eq(I18n.t("public_views.actions.not_for_your_account"))
    end
  end

  context "foreign-tenant viewers are the public audience" do
    let!(:public_page) { create_launched_page(:for_member, :for_public) }
    let(:public_url) { "/#{customer.id}/page/#{public_page.public_uuid}" }

    it "renders GET for another tenant's admin only when public is in the set" do
      sign_in_admin(other_customer)
      get public_url
      expect(response).to have_http_status(:ok)

      public_page.update!(audience_public: false)
      get public_url
      expect(response).to have_http_status(:not_found)
    end

    it "renders GET for another tenant's member only when public is in the set" do
      sign_in_member(other_customer)
      get public_url
      expect(response).to have_http_status(:ok)

      public_page.update!(audience_public: false)
      get public_url
      expect(response).to have_http_status(:not_found)
    end

    it "refuses POST from another tenant's admin when public is not in the set" do
      page = submittable_page(:for_member)
      sign_in_admin(other_customer)

      expect {
        post "/#{customer.id}/page/#{page.public_uuid}"
      }.not_to change(EntityEntry, :count)
      expect(response).to have_http_status(:not_found)
    end
  end
end
