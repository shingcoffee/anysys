# frozen_string_literal: true

require "rails_helper"

# GET /:customer_id/actions/:action_key — public URL category, redirect-only.
# Pages::ActionsController has no auth guard; each target surface enforces its own.
RSpec.describe "Pages::Actions", type: :request do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:action_key) { "enroll" }

  def action_url(cid = customer.id, key = action_key, prefill: nil)
    path = "/#{cid}/actions/#{key}"
    return path if prefill.blank?

    "#{path}?#{ { prefill: prefill }.to_query }"
  end

  def create_action_page(*traits, cid: customer, key: action_key)
    Current.set(customer: cid) do
      create(:page, *traits, :launched, customer: cid, action_key: key)
    end
  end

  def redirect_location
    URI.parse(response.location)
  end

  def redirect_query
    Rack::Utils.parse_nested_query(redirect_location.query.to_s)
  end

  def expect_public_surface(page, cid: customer, prefill: {}, with_continuation: false)
    expect(response).to have_http_status(:see_other)
    expect(redirect_location.path).to eq("/#{cid.id}/page/#{page.public_uuid}")
    query = redirect_query
    expect(query["prefill"] || {}).to include(prefill.stringify_keys) if prefill.present?
    if with_continuation
      payload = Pages::Continuation.verify(query["continuation"])
      expect(payload).to eq(action_key: action_key, prefill: prefill.stringify_keys)
    else
      expect(query).not_to have_key("continuation")
    end
  end

  it "exposes page_action_path(customer_id:, action_key:)" do
    expect(page_action_path(customer_id: customer.id, action_key: action_key))
      .to eq("/#{customer.id}/actions/#{action_key}")
  end

  describe "routing" do
    it "does not serve an action key that fails the format constraint" do
      get "/#{customer.id}/actions/Enroll"
      expect(response).to have_http_status(:not_found)
    end
  end

  context "when each audience has a live page" do
    let!(:public_page) { create_action_page(:public_only) }
    let!(:member_page) { create_action_page(:member_only) }
    let!(:admin_page) { create_action_page }

    it "sends an anonymous viewer to the public page surface with a continuation" do
      get action_url

      expect_public_surface(public_page, with_continuation: true)
    end

    it "sends a same-tenant member to the member page surface" do
      sign_in create(:user, :member, customer: customer)
      get action_url

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(member_page_path(customer_id: customer.id, id: member_page.id))
    end

    it "sends a same-tenant admin to Create Entry for the bound entity" do
      sign_in create(:user, :admin, customer: customer)
      get action_url

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(new_admin_entity_entry_path(customer.id, admin_page.entity))
    end

    it "treats another tenant's admin as public and sends them to the public page" do
      sign_in create(:user, :admin, customer: other_customer)
      get action_url

      expect_public_surface(public_page, with_continuation: true)
    end

    it "treats another tenant's member as public and sends them to the public page" do
      sign_in create(:user, :member, customer: other_customer)
      get action_url

      expect_public_surface(public_page, with_continuation: true)
    end

    it "passes sanitized prefill through to the target surface and into the continuation" do
      get action_url(prefill: { "course" => "12" })

      expect_public_surface(public_page, prefill: { "course" => "12" }, with_continuation: true)
    end

    it "drops prefill keys and values that exceed the limits" do
      keys = (1..11).to_h { |n| [ "field_#{n}", n.to_s ] }
      get action_url(prefill: keys.merge("course-id" => "1", "toolong" => "x" * 201))

      expect(response).to have_http_status(:see_other)
      query = URI.parse(response.location).query.to_s
      prefill_keys = CGI.parse(query).keys.grep(/\Aprefill/)
      expect(prefill_keys.size).to be <= 10
      expect(query).not_to include("course-id")
      expect(query).not_to include("toolong")
    end
  end

  context "when only a public page exists" do
    let!(:public_page) { create_action_page(:public_only) }

    it "does not append a continuation" do
      get action_url(prefill: { "course" => "12" })

      expect_public_surface(public_page, prefill: { "course" => "12" }, with_continuation: false)
    end
  end

  context "when only a member page exists" do
    let!(:member_page) { create_action_page(:member_only) }

    it "stores the member page path with prefill and redirects an anonymous viewer to sign-in" do
      get action_url(prefill: { "course" => "99" })

      expect(response).to redirect_to("/auth/sign_in")
      expect(session["user_return_to"]).to eq(
        "#{member_page_path(customer_id: customer.id, id: member_page.id)}?#{ { prefill: { "course" => "99" } }.to_query }"
      )
    end

    it "returns 404 for a same-tenant admin (no page for that audience)" do
      sign_in create(:user, :admin, customer: customer)
      get action_url

      expect(response).to have_http_status(:not_found)
    end
  end

  it "returns 404 for an unknown action key" do
    get "/#{customer.id}/actions/no_such_action"

    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 for an action key that only exists on another tenant" do
    Current.set(customer: other_customer) do
      create(:page, :public_only, :launched, customer: other_customer, action_key: action_key)
    end

    get action_url

    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 when the viewer has no page and is already signed in" do
    create_action_page
    sign_in create(:user, :member, customer: customer)
    get action_url

    expect(response).to have_http_status(:not_found)
  end
end
