# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Page shortcut lifecycle integration", type: :request do
  let_it_be(:customer) { create(:customer) }

  around do |example|
    config = Rails.application.config.x.page_shortcuts
    previous = config.default_customer_id
    config.default_customer_id = customer.id
    example.run
  ensure
    config.default_customer_id = previous
  end

  after { Current.reset }

  def published_site
    enable_module!("website", customer, name: "Website")
    site = create(:website, :published, customer: customer)
    create(:website_page, :home, :published, website: site, title: "Lifecycle home")
    site
  end

  def public_form
    Current.set(customer: customer) do
      create(:page, :for_member, :for_public, customer: customer, launched: true, name: "Lifecycle public form")
    end
  end

  def save_shortcut(target, path:)
    result = PageShortcuts::Activities::Save.call(
      shortcut: PageShortcut.new, customer_id: customer.id,
      params: { path: path, target: "#{target.class.name}:#{target.id}" }
    )
    expect(result.success?).to be(true), result.errors.inspect
    result.model
  end

  def expect_missing(path, *hidden_content)
    get path
    expect(response).to have_http_status(:not_found)
    hidden_content.each { |text| expect(response.body).not_to include(text) }
    head path
    expect(response).to have_http_status(:not_found)
    expect(response.body).to be_empty
  end

  it "keeps a saved nested URL bound to record identity after a slug rename and reuse" do
    site = published_site
    target = create(:website_page, :published, website: site, slug: "old-offer", title: "Original offer")
    shortcut = save_shortcut(target, path: "/campaign/spring-offer")
    original = shortcut.attributes.slice("id", "customer_id", "path", "target_type", "target_id")

    result = Websites::Activities::SavePage.call(
      page: target, params: { slug: "new-offer", title: "Renamed offer" }, structure_editable: true
    )
    expect(result.success?).to be(true), result.errors.inspect
    target.reload
    replacement = create(:website_page, :published, website: site, slug: "old-offer", title: "Replacement offer")

    [shortcut.path, "/#{customer.id}#{shortcut.path}"].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("title").text).to include(target.title)
      expect(request.path_info).to eq(path)
      expect(request.params["page_slug"]).to eq("new-offer")
      expect(response.headers["Location"]).to be_nil
      head path
      expect(response).to have_http_status(:ok)
      expect(response.body).to be_empty
    end

    get "/old-offer"
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("title").text).to include(replacement.title)
    get website_page_path(customer.id, "new-offer")
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("title").text).to include(target.title)
    expect(shortcut.reload.attributes.slice(*original.keys)).to eq(original)
    expect(PageShortcuts::PublicPath.website_page(page: target)).to eq(shortcut.path)
  end

  {
    "unlaunched" => ->(page) { page.update!(launched: false) },
    "member-visible" => ->(page) { page.update!(visible_audiences: %w[admin member]) },
    "admin-visible" => ->(page) { page.update!(visible_audiences: %w[admin]) },
    "soft-deleted" => ->(page) { page.soft_delete },
    "destroyed" => ->(page) { page.destroy! }
  }.each do |state, make_unavailable|
    it "returns GET/HEAD 404 for an explicit root whose form is #{state}, without Home fallback" do
      site = published_site
      page = public_form
      shortcut = save_shortcut(page, path: "/")
      get "/"
      expect(response).to have_http_status(:ok)
      expect(request.path_parameters).to include(controller: "public_pages", action: "show")

      Current.set(customer: customer) { make_unavailable.call(page) }

      expect_missing("/", page.name, "Lifecycle home")
      expect_missing("/#{customer.id}/", page.name, "Lifecycle home")
      expect(PageShortcut.find(shortcut.id).target_id).to eq(page.id)
      get website_home_path(customer.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(site.home_page.title)
    end
  end

  {
    "unlaunched" => ->(page) { page.update!(launched: false) },
    "private" => ->(page) { page.update!(visible_audiences: %w[admin member]) },
    "destroyed" => ->(page) { page.destroy! }
  }.each do |state, make_unavailable|
    it "does not serve an automatic website collision when the saved form becomes #{state}" do
      site = published_site
      page = public_form
      shortcut = save_shortcut(page, path: "/spring-offer")
      # Persist historical/imported conflicting data; runtime must fail closed
      # even though management validation rejects creation of this collision.
      collision = create(:website_page, :published, website: site, slug: "spring-offer", title: "Unrelated spring offer")
      Current.set(customer: customer) { make_unavailable.call(page) }

      expect_missing(shortcut.path, page.name, collision.title)
      expect_missing("/#{customer.id}#{shortcut.path}", page.name, collision.title)
      get website_page_path(customer.id, collision.slug)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(collision.title)
      expect(PageShortcut.exists?(shortcut.id)).to be(true)
    end
  end

  {
    "unpublished" => ->(page) { page.update!(published: false) },
    "destroyed" => ->(page) { page.destroy! }
  }.each do |state, make_unavailable|
    it "does not replace a #{state} website target with a later website page using the alias slug" do
      site = published_site
      target = create(:website_page, :published, website: site, slug: "original", title: "Original website offer")
      shortcut = save_shortcut(target, path: "/offer")
      make_unavailable.call(target)
      replacement = create(:website_page, :published, website: site, slug: "offer", title: "Different website offer")

      expect_missing("/offer", target.title, replacement.title)
      get website_page_path(customer.id, replacement.slug)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(replacement.title)
      expect(PageShortcut.find(shortcut.id).target_id).to eq(target.id)
    end
  end

  it "allows an explicit website inner-page root and restores automatic home only when the mapping is removed" do
    site = published_site
    target = create(:website_page, :published, website: site, slug: "special", title: "Root website offer")
    shortcut = save_shortcut(target, path: "/")

    get "/"
    expect(response).to have_http_status(:ok)
    expect(request.path_parameters).to include(controller: "websites/pages", action: "show")
    expect(response.body).to include(target.title)
    head "/#{customer.id}/"
    expect(response).to have_http_status(:ok)
    expect(response.body).to be_empty

    target.update!(published: false)
    expect_missing("/", target.title, site.home_page.title)
    shortcut.destroy!
    get "/"
    expect(response).to have_http_status(:ok)
    expect(request.path_parameters).to include(controller: "websites/pages", action: "home")
    expect(response.body).to include(site.home_page.title)
  end
end
