# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Website shortcut identity at controller dispatch", type: :request do
  let_it_be(:customer) { create(:customer) }
  let!(:website_module) { enable_module!("website", customer, name: "Website") }
  let!(:website) { create(:website, :published, customer: customer, name: "Dispatch brand") }
  let!(:home) { create(:website_page, :home, :published, website: website, title: "Original dispatch home") }
  let!(:inner) { create(:website_page, :published, website: website, slug: "offer", title: "Original dispatch offer") }

  around do |example|
    config = Rails.application.config.x.page_shortcuts
    previous = config.default_customer_id
    config.default_customer_id = customer.id
    example.run
  ensure
    config.default_customer_id = previous
    Current.reset
  end

  def map_page(page, path:)
    PageShortcut.create!(customer_id: customer.id, path: path, target_type: "WebsitePage", target_id: page.id)
  end

  def change_before_dispatch(&change)
    changed = false
    allow_any_instance_of(Websites::PagesController).to receive(:public_site_available?).and_wrap_original do |original|
      unless changed
        changed = true
        change.call
      end
      original.call
    end
  end

  def expect_page_title(page)
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("title").text).to eq("#{page.title} · #{website.name}")
    expect(response.headers["Location"]).to be_nil
  end

  ["/offer", "/campaign/offer"].each do |path|
    it "keeps #{path} bound to the resolved ID when the slug is renamed and reused before dispatch" do
      map_page(inner, path: path) unless path == "/offer"
      replacement = nil
      change_before_dispatch do
        inner.update!(slug: "renamed-offer", title: "Renamed dispatch offer")
        replacement = create(:website_page, :published, website: website, slug: "offer", title: "Reused dispatch offer")
      end

      get path, params: { target_id: home.id, page_shortcut_target: { target_id: home.id } }
      expect_page_title(inner)
      target = request.env.fetch(PageShortcuts::RouteConstraint::MATCH_KEY).fetch(:target)
      expect(target).to have_attributes(target_id: inner.id, page_slug: "offer")

      get website_page_path(customer.id, "offer"), params: { target_id: inner.id }
      expect_page_title(replacement)
      expect(request.env[PageShortcuts::RouteConstraint::MATCH_KEY]).to be_nil
    end
  end

  ["/", "/campaign/welcome"].each do |path|
    it "keeps #{path} bound to the old home ID when the home flag changes before dispatch" do
      map_page(home, path: path) unless path == "/"
      change_before_dispatch do
        home.update!(home: false, slug: "former-home")
        inner.update!(home: true)
      end

      get path
      expect_page_title(home)
      expect(request.path_parameters).to include(controller: "websites/pages", action: "home")

      get website_home_path(customer.id), params: { target_id: home.id }
      expect_page_title(inner)
    end
  end

  it "renders the resolved inner-page ID even when it becomes home before show dispatch" do
    map_page(inner, path: "/campaign/offer")
    change_before_dispatch do
      home.update!(home: false, slug: "former-home")
      inner.update!(home: true)
    end

    get "/campaign/offer"
    expect_page_title(inner)
    expect(request.path_parameters).to include(controller: "websites/pages", action: "show")

    get website_page_path(customer.id, "offer")
    expect(response).to have_http_status(:not_found)
  end

  %i[home inner].each do |destination|
    it "rechecks publication of the resolved #{destination} page before rendering" do
      page = public_send(destination)
      map_page(page, path: "/campaign/hidden")
      change_before_dispatch { page.update!(published: false) }

      get "/campaign/hidden"
      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_empty
      expect(request.env.fetch(PageShortcuts::RouteConstraint::MATCH_KEY).fetch(:target).target_id).to eq(page.id)
    end
  end

  it "rechecks site publication after resolution" do
    change_before_dispatch { website.update!(published: false) }
    get "/offer"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to be_empty
  end

  it "rechecks module enablement after resolution" do
    change_before_dispatch do
      FeatureModules::CustomerAssignment.find_by!(customer_id: customer.id, feature_module: website_module)
                                       .update!(status: :suspended)
    end
    get "/offer"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to be_empty
  end

  %i[customer_id website_id].each do |attribute|
    it "rejects a resolved page moved to a different #{attribute} before dispatch" do
      foreign_customer = create(:customer)
      foreign_website = create(:website, :published, customer: foreign_customer)
      map_page(inner, path: "/campaign/offer")
      change_before_dispatch do
        inner.update_columns(attribute => attribute == :customer_id ? foreign_customer.id : foreign_website.id)
      end

      get "/campaign/offer"
      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_empty
    end
  end
end
