# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite::Presentation do
  let(:website) { Website.new(id: 71, customer_id: 81_721_200) }
  let(:site_page) { WebsitePage.new(id: 72, website_id: 71, customer_id: 81_721_200, slug: "platform") }

  def resolve(site: website, record: site_page)
    described_class.for(website: site, page: record)
  end

  it "accepts exactly the saved home predicate and the four named roles" do
    %w[platform pricing about contact].each do |slug|
      site_page.slug = slug
      expect(resolve.role).to eq(slug.to_sym)
    end
    site_page.assign_attributes(home: true, slug: "owner-chosen")
    expect(resolve.role).to eq(:home)
    site_page.home = false
    ["", "home", "extra", "Platform"].each do |slug|
      site_page.slug = slug
      expect(resolve).to be_nil
    end
  end

  it "requires both actual records and their customer and site identities" do
    expect(resolve(site: nil)).to be_nil
    expect(resolve(record: nil)).to be_nil
    expect(resolve(site: { id: 71, customer_id: 81_721_200 })).to be_nil
    site_page.website_id = 99
    expect(resolve).to be_nil
    site_page.website_id = nil
    expect(resolve).to be_nil
    site_page.website_id = 71
    site_page.customer_id = 42
    expect(resolve).to be_nil
    site_page.customer_id = 81_721_200
    website.customer_id = 42
    expect(resolve).to be_nil
  end

  it "validates readonly localization copies by saved identity even when not persisted" do
    site = website.dup.tap { |copy| copy.id = website.id; copy.readonly! }
    record = site_page.dup.tap { |copy| copy.id = site_page.id; copy.readonly! }
    expect(record).not_to be_persisted
    expect(resolve(site: site, record: record).role).to eq(:platform)
    record.website_id = 99
    expect(resolve(site: site, record: record)).to be_nil
    site.id = nil
    record.website_id = nil
    expect(resolve(site: site, record: record)).to be_nil
  end

  it "requires object association for genuinely unsaved records, never nil identity equality" do
    site = Website.new(customer_id: 81_721_200)
    record = WebsitePage.new(customer_id: 81_721_200, slug: "pricing")
    expect(resolve(site: site, record: record)).to be_nil
    record.website = site
    expect(resolve(site: site, record: record).role).to eq(:pricing)
    expect(resolve(site: site.dup, record: record)).to be_nil
  end

  it "gives only the page's source assistant role the assistant showcase" do
    expect(resolve.variant_for("feature_grid", id: "home_site_platform_assistant")).to eq(:assistant)
    expect(resolve.variant_for("feature_grid", id: "home_site_home_assistant")).to eq(:capabilities)
    expect(resolve.variant_for("feature_grid", id: "owner_assistant")).to eq(:capabilities)
    expect(resolve.variant_for("feature_grid")).to eq(:capabilities)
    expect(resolve.variant_for("steps", id: "home_site_platform_assistant")).to eq(:process)
    site_page.assign_attributes(home: true, slug: "")
    expect(resolve.variant_for("feature_grid", id: "home_site_home_assistant")).to eq(:assistant)
    site_page.assign_attributes(home: false, slug: "about")
    expect(resolve.variant_for("feature_grid", id: "home_site_about_principles")).to eq(:principles)
  end

  it "maps types and variants without reading copy, Current or mutating records" do
    site_page.sections = [{ "id" => "arbitrary", "type" => "hero_centered", "props" => { "headline" => "Literal" } }]
    before = [website.attributes.deep_dup, site_page.attributes.deep_dup]
    presentation = resolve
    expect(presentation.component_class("hero_centered")).to eq(Websites::HomeSite::HeroComponent)
    expect(presentation.component_class("quote")).to be_nil
    expect(presentation.variant_for("hero_centered")).to eq(:lead)
    expect(presentation.variant_for("steps")).to eq(:process)
    {
      "proof_strip" => [Websites::HomeSite::StatsComponent, :stats],
      "logo_cloud" => [Websites::HomeSite::MarqueeComponent, :marquee],
      "comparison_table" => [Websites::HomeSite::ComparisonComponent, :comparison]
    }.each do |type, (component, variant)|
      expect([presentation.component_class(type), presentation.variant_for(type)]).to eq([component, variant])
    end
    site_page.slug = "about"
    expect(resolve.variant_for("hero_centered")).to eq(:about)
    expect(resolve.variant_for("feature_grid")).to eq(:principles)
    expect(resolve.variant_for("rich_text")).to eq(:editorial)
    site_page.slug = "contact"
    expect(resolve.variant_for("hero_centered")).to eq(:contact)
    expect(resolve.variant_for("rich_text")).to eq(:contact_note)
    expect(resolve.variant_for("cta_band")).to eq(:contact_next_steps)
    site_page.slug = "pricing"
    expect(resolve.variant_for("hero_centered")).to eq(:pricing)
    expect(resolve.variant_for("feature_grid")).to eq(:foundation)
    site_page.slug = "platform"
    expect([website.attributes, site_page.attributes]).to eq(before)
  end

  it "filters navigation by publication, visibility and actual site identity while preserving order" do
    pages = ["pricing", "platform", "about", "contact"].map do |slug|
      WebsitePage.new(website_id: 71, customer_id: 81_721_200, slug: slug, published: true, nav_visible: true)
    end
    pages[2].published = false
    pages[3].nav_visible = false
    foreign = pages[0].dup.tap { |page| page.website_id = 99 }
    wrong_tenant = pages[0].dup.tap { |page| page.customer_id = 42 }
    expect(resolve.nav_pages([*pages, foreign, wrong_tenant])).to eq(pages.first(2))
  end
end
