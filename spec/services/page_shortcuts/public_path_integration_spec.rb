# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Page shortcut public link round trips" do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:dedicated_customer) { create(:customer) }
  let!(:hostname) { CustomDomainRecord.create!(hostname: "tenant.example.test", customer_id: dedicated_customer.id) }

  around do |example|
    config = Rails.application.config.x.page_shortcuts
    previous = config.default_customer_id
    config.default_customer_id = customer.id
    example.run
  ensure
    config.default_customer_id = previous
  end

  after { Current.reset }

  def resolve_link(link, host:)
    # Fragments stay in the generated href but never reach the HTTP request.
    uri = Addressable::URI.parse(link)
    uri.fragment = nil
    env = Rack::MockRequest.env_for("https://#{host}#{uri}")
    PageShortcuts::Resolver.resolve(ActionDispatch::Request.new(env))
  end

  def map_page(page, path:, tenant: customer)
    PageShortcut.create!(customer_id: tenant.id, path: path, target_type: page.class.name, target_id: page.id)
  end

  it "refreshes generated link prefixes and their resolved tenant after every hostname change" do
    shared = create(:page, :shared, launched: true, audience_member: true, audience_public: true)
    [customer, dedicated_customer].each { |tenant| map_page(shared, path: "/join", tenant: tenant) }
    host = "live.example.test"
    check_links = ->(selected) do
      [customer, dedicated_customer].each do |tenant|
        canonical = "/#{tenant.id}/page/#{shared.public_uuid}"
        link = Websites::Href.resolve(canonical, customer_id: selected.id, host: host)
        prefix = tenant.id == selected.id ? "" : "/#{tenant.id}"
        expect(link).to eq("#{prefix}/join")
        expect(resolve_link(link, host: host)).to have_attributes(customer_id: tenant.id, target_id: shared.id)
      end
    end

    check_links.call(customer)
    binding = CustomDomainRecord.create!(hostname: host, customer_id: dedicated_customer.id)
    check_links.call(dedicated_customer)
    binding.update!(hostname: "renamed.example.test", customer_id: customer.id)
    check_links.call(customer)
    host = binding.hostname
    check_links.call(customer)
    binding.update!(customer_id: dedicated_customer.id)
    check_links.call(dedicated_customer)
    binding.destroy!
    check_links.call(customer)
  end

  it "translates a renamed canonical website link to the original saved URL on either host, retaining query bytes and fragment" do
    enable_module!("website", customer, name: "Website")
    site = create(:website, :published, customer: customer)
    page = create(:website_page, :published, website: site, slug: "original-offer")
    mapping = map_page(page, path: "/campaign/evergreen")
    page.update!(slug: "renamed-offer")
    suffix = "?locale=zh-CN&tag=a&tag=b&return=%2Fauth%2Fsign_in#plans%20and%20prices"

    ["shared.example.test", "tenant.example.test"].each do |host|
      link = Websites::Href.resolve("/#{customer.id}/site/#{page.slug}#{suffix}", customer_id: dedicated_customer.id, host: host)
      prefix = host == "shared.example.test" ? "" : "/#{customer.id}"
      expect(link).to eq("#{prefix}#{mapping.path}#{suffix}")
      expect(resolve_link(link, host: host)).to have_attributes(customer_id: customer.id, target_type: "WebsitePage",
                                                              target_id: page.id, page_slug: "renamed-offer")
    end
  end

  it "translates shared Page UUID links using the URL tenant's actual shortcuts rather than Current.customer or the caller tenant" do
    page = Current.set(customer: nil, shared_resources_mode: true) do
      create(:page, :shared, launched: true, audience_member: true, audience_public: true)
    end
    map_page(page, path: "/shared/join")
    map_page(page, path: "/dedicated/join", tenant: dedicated_customer)
    Current.customer = dedicated_customer
    suffix = "?locale=en&tag=first&tag=second#registration"

    [
      [customer, "shared.example.test", "/shared/join"],
      [customer, "tenant.example.test", "/#{customer.id}/shared/join"],
      [dedicated_customer, "tenant.example.test", "/dedicated/join"],
      [dedicated_customer, "shared.example.test", "/#{dedicated_customer.id}/dedicated/join"]
    ].each do |tenant, host, path|
      link = Websites::Href.resolve("/#{tenant.id}/page/#{page.public_uuid}#{suffix}", customer_id: customer.id, host: host)
      expect(link).to eq("#{path}#{suffix}")
      expect(resolve_link(link, host: host)).to have_attributes(customer_id: tenant.id, target_type: "Page",
                                                              target_id: page.id, uuid: page.public_uuid)
    end
    expect(Current.customer).to eq(dedicated_customer)
  end

  it "stops advertising a removed preferred alias immediately and preserves the canonical UUID URL after all mappings are removed" do
    page = Current.set(customer: customer) { create(:page, customer: customer, launched: true, audience_member: true, audience_public: true) }
    preferred = map_page(page, path: "/a-registration")
    remaining = map_page(page, path: "/z-registration")
    canonical = "/#{customer.id}/page/#{page.public_uuid}"
    expect(Websites::Href.resolve(canonical, customer_id: customer.id)).to eq(preferred.path)

    preferred.destroy!
    link = Websites::Href.resolve(canonical, customer_id: customer.id)
    expect(link).to eq(remaining.path)
    expect(resolve_link(link, host: "shared.example.test").target_id).to eq(page.id)
    expect(resolve_link(preferred.path, host: "shared.example.test")).to be_nil

    remaining.destroy!
    expect(Websites::Href.resolve(canonical, customer_id: customer.id)).to eq(canonical)
    expect(Page.find(page.id).public_uuid).to eq(page.public_uuid)
  end

  it "retains canonical website addresses for reserved slugs unless a valid arbitrary shortcut is saved" do
    enable_module!("website", customer, name: "Website")
    site = create(:website, :published, customer: customer)
    page = create(:website_page, :published, website: site, slug: "oauth")
    canonical = "/#{customer.id}/site/oauth?locale=zh-CN#overview"
    expect(Websites::Href.resolve(canonical, customer_id: customer.id)).to eq(canonical)
    expect(resolve_link("/oauth", host: "shared.example.test")).to be_nil

    mapping = map_page(page, path: "/platform/overview")
    link = Websites::Href.resolve(canonical, customer_id: customer.id)
    expect(link).to eq("#{mapping.path}?locale=zh-CN#overview")
    expect(resolve_link(link, host: "shared.example.test")).to have_attributes(target_id: page.id, page_slug: "oauth")
  end

  it "keeps media, protected application, static and external destinations byte-identical alongside live aliases" do
    page = Current.set(customer: customer) { create(:page, customer: customer, launched: true, audience_member: true, audience_public: true) }
    map_page(page, path: "/campaign/join")
    destinations = [
      "/#{customer.id}/site/media/signed-token?download=1#image",
      "/#{customer.id}/admin/maintenance/pages?locale=zh-CN",
      "/#{customer.id}/member/profile", "/auth/sign_in?locale=en", "/oauth/authorize?client_id=app",
      "/captcha/challenge?return_to=%2Fcampaign%2Fjoin", "/up", "/assets/application.js",
      "/robots.txt", "/site-images/anysys/anysys-home-workspace-hero.svg",
      "https://external.example.test/#{customer.id}/page/#{page.public_uuid}?tag=a&tag=b#form"
    ]
    destinations.each do |destination|
      expect(Websites::Href.resolve(destination, customer_id: customer.id, host: "tenant.example.test")).to eq(destination)
    end
  end
end
