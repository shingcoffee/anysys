# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Websites::Public::Pages", type: :request do
  let_it_be(:customer) { create(:customer) }
  let!(:website_module) { enable_module!("website", customer, name: "Website") }
  let(:home_path) { "/#{customer.id}/site" }

  def website_records_available?
    website = "Website".safe_constantize
    page = "WebsitePage".safe_constantize
    website&.table_exists? && page&.table_exists? &&
      FactoryBot.factories.registered?(:website) &&
      FactoryBot.factories.registered?(:website_page)
  end

  def create_published_site!(inner_slug: "about")
    skip "Website factory not available" unless website_records_available?

    Current.customer = customer
    site = create(:website, customer: customer, published: true, name: "Acme")
    home = create(
      :website_page,
      website: site,
      customer: customer,
      home: true,
      published: true,
      title: "Home",
      slug: ""
    )
    inner = create(
      :website_page,
      website: site,
      customer: customer,
      home: false,
      published: true,
      title: "About",
      slug: inner_slug
    )
    [site, home, inner]
  end

  it "returns 404 when the site is unpublished or missing" do
    get home_path
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include("Acme")
    expect(response.body).to be_empty
  end

  it "returns 404 for an inner slug when nothing is published" do
    get "#{home_path}/about"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to be_empty
  end

  it "returns 200 for a published home page when records exist" do
    create_published_site!
    get home_path
    expect(response).to have_http_status(:ok)
  end

  it "returns 200 for a published inner page when records exist" do
    create_published_site!
    get "#{home_path}/about"
    expect(response).to have_http_status(:ok)
  end

  it "renders the marketing layout rather than a form card" do
    create_published_site!
    get home_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Acme")
    expect(response.body).to include('data-controller="website-nav"')
    expect(response.body).to include("fonts.bunny.net")
    expect(response.body).to include("Inter")
    expect(response.body).not_to include("noindex")

    html = Nokogiri::HTML(response.body)
    expect(html.css("form")).to be_empty
    expect(html.css("a").map { |link| link["href"] }).to include("#{home_path}?locale=en", "#{home_path}?locale=zh-CN")
    expect(html.at("main")).to be_present
    expect(html.at("[data-controller='website-nav']")).to be_present
  end

  it "returns 404 for an unpublished inner page even when the site is published" do
    skip "Website factory not available" unless website_records_available?

    Current.customer = customer
    site = create(:website, customer: customer, published: true, name: "Hidden Inner")
    create(:website_page, :home, :published, website: site, customer: customer, title: "Home")
    create(:website_page, website: site, customer: customer, home: false, published: false, title: "Secret Draft", slug: "secret-draft")

    get "#{home_path}/secret-draft"
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include("Secret Draft")
    expect(response.body).not_to include("Hidden Inner")
    expect(response.body).to be_empty
  end

  it "returns 404 for an unpublished home even when the site is published" do
    skip "Website factory not available" unless website_records_available?

    Current.customer = customer
    site = create(:website, customer: customer, published: true, name: "Hidden Home")
    create(:website_page, website: site, customer: customer, home: true, published: false, title: "Hidden Home", slug: "")

    get home_path
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include("Hidden Home")
    expect(response.body).to be_empty
  end

  it "returns 404 when the Website module is disabled even if records are published" do
    create_published_site!
    FeatureModules::CustomerAssignment.find_by!(
      customer: customer, feature_module: FeatureModules::Module.find_by!(key: "website")
    ).update!(status: :suspended)

    get home_path
    expect(response).to have_http_status(:not_found)
    expect(response.body).to be_empty
  end

  it "does not resolve another tenant's published slug on this customer's public URL" do
    create_published_site!
    other = create(:customer)
    enable_module!("website", other, name: "Website")
    other_site = create(:website, :published, customer: other, name: "Foreign brand")
    other_page = create(:website_page, :published, website: other_site, slug: "foreign-only", title: "Foreign secret", sections: [
      { "id" => "foreign", "type" => "rich_text", "props" => { "body" => "Foreign content" } }
    ])
    before_foreign = [other_site.attributes.deep_dup, other_page.attributes.deep_dup]

    get "#{home_path}/foreign-only"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to be_empty
    get "/#{other.id}/site/foreign-only"
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at("main").text).to include("Foreign content")
    expect([other_site.reload.attributes, other_page.reload.attributes]).to eq(before_foreign)
  end

  it "allows signed-in foreign public readers while selecting content strictly from the URL tenant" do
    site, home, = create_published_site!
    home.update!(sections: [{ "id" => "public", "type" => "rich_text", "props" => { "body" => "URL tenant content" } }])
    actor_customer = create(:customer)
    actor = create(:user, :admin, customer: actor_customer)
    enable_module!("website", actor_customer)
    actor_site = create(:website, :published, customer: actor_customer, name: "Actor tenant brand")
    create(:website_page, :home, :published, website: actor_site, sections: [
      { "id" => "actor", "type" => "rich_text", "props" => { "body" => "Actor tenant content" } }
    ])
    before = [site.attributes.deep_dup, home.attributes.deep_dup]
    sign_in actor
    get home_path, params: { customer_id: actor_customer.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Acme", "URL tenant content")
    expect(response.body).not_to include("Actor tenant brand", "Actor tenant content")
    expect([site.reload.attributes, home.reload.attributes]).to eq(before)
    sign_out actor
    get home_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("URL tenant content")
  end

  it "does not route POST /site" do
    post home_path
    expect(response).to have_http_status(:not_found)
  rescue ActionController::RoutingError
    # Public POST is intentionally unrouted.
  end
end
