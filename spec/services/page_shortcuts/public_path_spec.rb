# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageShortcuts::PublicPath do
  let_it_be(:customer) { create(:customer, id: 81721200) }
  let_it_be(:other_customer) { create(:customer, id: 12345678) }
  let(:website) { create(:website, :published, customer: customer) }
  let(:home) { create(:website_page, :published, :home, website: website) }
  let(:pricing) { create(:website_page, :published, website: website, slug: "pricing") }
  let(:page) { create(:page, customer: customer, launched: true, audience_member: true, audience_public: true) }

  before do
    enable_module!("website", customer, name: "Website")
    enable_module!("website", other_customer, name: "Website")
    CustomDomainRecord.create!(hostname: "other.example.com", customer_id: other_customer.id)
  end

  after { Current.reset }

  def shortcut(target, path:, customer_id: customer.id)
    PageShortcut.create!(customer_id: customer_id, path: path, target: target)
  end

  it "generates unmounted default-customer and dedicated-host clean URLs, with tenant prefixes otherwise" do
    home
    expect(described_class.website_home(customer_id: customer.id)).to eq("/")
    expect(described_class.website_page(page: pricing)).to eq("/pricing")
    expect(described_class.website_slug(slug: "pricing", customer_id: customer.id)).to eq("/pricing")
    expect(described_class.website_home(customer_id: other_customer.id)).to eq("/12345678/")
    expect(described_class.website_slug(slug: "pricing", customer_id: other_customer.id)).to eq("/12345678/pricing")
    expect(described_class.website_home(customer_id: other_customer.id, host: "other.example.com")).to eq("/")
    expect(described_class.website_slug(slug: "pricing", customer_id: other_customer.id, host: "other.example.com")).to eq("/pricing")
    expect(described_class.website_page(page: pricing, host: "other.example.com")).to eq("/81721200/pricing")
  end

  it "prefers lexically first eligible explicit aliases for website pages, including home and root" do
    shortcut(pricing, path: "/z-plans")
    shortcut(pricing, path: "/a-plans")
    shortcut(home, path: "/welcome")
    expect(described_class.website_page(page: pricing)).to eq("/a-plans")
    expect(described_class.website_slug(slug: "pricing", customer_id: customer.id)).to eq("/a-plans")
    expect(described_class.website_home(customer_id: customer.id)).to eq("/welcome")
    shortcut(pricing, path: "/")
    expect(described_class.website_page(page: pricing)).to eq("/")
  end

  it "keeps website home links canonical when root is explicitly assigned to a different page" do
    home
    shortcut(page, path: "/")
    expect(described_class.website_home(customer_id: customer.id)).to eq("/81721200/site")
    expect(described_class.public_page(page: page, customer_id: customer.id)).to eq("/")
  end

  it "falls back to canonical legacy site paths for reserved slugs and stale conflicts" do
    reserved = create(:website_page, :published, website: website, slug: "auth")
    expect(described_class.website_page(page: reserved)).to eq("/81721200/site/auth")
    expect(described_class.website_slug(slug: "auth", customer_id: customer.id)).to eq("/81721200/site/auth")
    shortcut(page, path: "/pricing")
    expect(described_class.website_page(page: pricing)).to eq("/81721200/site/pricing")
    expect(described_class.website_slug(slug: "pricing", customer_id: customer.id)).to eq("/81721200/site/pricing")
  end

  it "selects Page shortcuts deterministically, scoped to tenant and host, and otherwise returns the canonical UUID path" do
    shared = create(:page, :shared, launched: true, audience_member: true, audience_public: true)
    expect(described_class.public_page(page: page, customer_id: customer.id)).to eq("/81721200/page/#{page.public_uuid}")
    shortcut(shared, path: "/z-join")
    shortcut(shared, path: "/a-join")
    other = shortcut(shared, path: "/signup-form", customer_id: other_customer.id)
    Current.customer = other_customer
    expect(described_class.public_page(page: shared, customer_id: customer.id)).to eq("/a-join")
    expect(described_class.public_page(page: shared, customer_id: other_customer.id)).to eq("/12345678/signup-form")
    expect(described_class.public_page(page: shared, customer_id: other_customer.id, host: "other.example.com")).to eq("/signup-form")
    expect(described_class.shortcut(shortcut: other)).to eq("/12345678/signup-form")
    expect(described_class.public_page(page: page, customer_id: other_customer.id)).to be_nil
  end

  it "does not prefer aliases for unavailable targets or aliases blocked by unpublished automatic slugs" do
    shortcut(page, path: "/pricing")
    pricing.update!(published: false)
    canonical = "/81721200/page/#{page.public_uuid}"
    expect(described_class.public_page(page: page, customer_id: customer.id)).to eq(canonical)
    mapping = shortcut(page, path: "/join")
    expect(described_class.public_page(page: page, customer_id: customer.id)).to eq("/join")
    page.update!(launched: false)
    expect(described_class.public_page(page: page, customer_id: customer.id)).to eq(canonical)
    expect(described_class.shortcut(shortcut: mapping)).to eq("/join")
  end

  it "rejects malformed slugs, malformed shortcut paths and invalid customer IDs" do
    ["../auth", "https://external.test", "/pricing", "pricing?x=1"].each do |slug|
      expect(described_class.website_slug(slug: slug, customer_id: customer.id)).to be_nil
    end
    expect(described_class.website_home(customer_id: "81721200junk")).to be_nil
    expect(described_class.shortcut(shortcut: build(:page_shortcut, customer: customer, target: page, path: "/assets"))).to be_nil
  end
end
