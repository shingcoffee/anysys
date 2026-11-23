# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::SkeletonsGalleryComponent, type: :component do
  def render_gallery(**opts)
    render_inline(described_class.new(default_key: "presence", **opts))
  end

  it "renders a responsive catalog of the skeletons with the default badge" do
    render_gallery

    expect(page).to have_css("[data-skeletons-gallery='true']")
    expect(page).to have_css("h2", text: I18n.t("website.platform.skeletons.heading"))
    expect(page).to have_text(I18n.t("website.platform.skeletons.description"))
    expect(page).to have_css("[class*='grid-cols-1'][class*='sm:grid-cols-2'][class*='xl:grid-cols-3']")
    expect(page).to have_css("article[data-skeleton-key]", count: Websites::Skeletons.keys.size)

    Websites::Skeletons.keys.each do |key|
      expect(page).to have_css("article[data-skeleton-key='#{key}']")
      expect(page).to have_text(I18n.t("website.skeletons.#{key}.name"))
    end

    presence = page.find("article[data-skeleton-key='presence']")
    expect(presence).to have_text(I18n.t("website.platform.skeletons.default_badge"))
    expect(presence).to have_text(I18n.t("website.platform.skeletons.pages.home"))
    expect(presence).to have_text(I18n.t("website.platform.skeletons.pages.about"))
  end

  it "collapses page-role chips beyond the chip limit into a single overflow chip" do
    render_gallery

    presence = page.find("article[data-skeleton-key='presence']")
    roles = Websites::Skeletons.pages_for("presence").filter_map { |item| item.stringify_keys["role"].presence }
    extra = roles.size - Websites::Admin::SkeletonsGalleryComponent::CHIP_LIMIT

    expect(extra).to be_positive
    expect(presence).to have_text(I18n.t("website.platform.catalog.chips.more", count: extra))
    roles.drop(Websites::Admin::SkeletonsGalleryComponent::CHIP_LIMIT).each do |role|
      expect(presence).to have_no_text(I18n.t("website.platform.skeletons.pages.#{role}"), exact: true)
    end
  end

  it "shows category chips and inspired-by credit" do
    render_gallery

    presence = page.find("article[data-skeleton-key='presence']")
    expect(presence).to have_text(I18n.t("website.skeletons.categories.business"))
    expect(presence).to have_text(
      I18n.t("website.skeletons.inspired_by_format", brand: I18n.t("website.skeletons.presence.inspired_by"))
    )
    expect(page).to have_css("article[data-skeleton-key='presence'][data-category='business']")
    expect(page).to have_css("article[data-skeleton-key='campus'][data-category='education']")
  end

  it "filters skeletons by category" do
    render_gallery(category: "education")

    expect(page).to have_css("article[data-skeleton-key='campus']")
    expect(page).not_to have_css("article[data-skeleton-key='presence']")
  end

  it "groups skeletons by category when showing the full catalog" do
    render_gallery

    expect(page).to have_css("[data-skeleton-category='business']")
    expect(page).to have_css("[data-skeleton-category='education']")
    expect(page).to have_css("[data-skeleton-category='wellness']")
    expect(page).to have_text(I18n.t("website.skeletons.categories.business"))
    expect(page).to have_text(I18n.t("website.skeletons.categories.wellness"))
  end

  it "renders category filter chips when a customer id is present" do
    render_gallery(customer_id: 81_721_200)

    expect(page).to have_css("[data-catalog-filter='true']")
    expect(page).to have_link(I18n.t("website.platform.catalog.filter.all"))
    expect(page).to have_link(I18n.t("website.skeletons.categories.product"))
  end

  it "wraps the mini preview in a pointer-events-none scaled frame" do
    render_gallery

    expect(page).to have_css("[data-catalog-thumbnail='true'] .pointer-events-none.select-none.origin-top-left")
    expect(page).to have_css("[class*='scale-[0.4]']")
  end

  it "falls back to a static type list when no kit components exist" do
    allow(Websites::SectionKit).to receive(:component_class).and_return(nil)
    render_gallery

    presence = page.find("article[data-skeleton-key='presence']")
    expect(presence).to have_text(I18n.t("website.sections.hero_split.name"))
    expect(presence).to have_text(I18n.t("website.sections.proof_strip.name"))
    expect(presence).to have_text(I18n.t("website.sections.card_grid.name"))
    expect(presence).not_to have_css("main")
  end

  it "renders Home sections through PageComponent when a kit component exists" do
    render_gallery

    cinematic = page.find("article[data-skeleton-key='cinematic']")
    expect(cinematic).to have_css("main")
    expect(cinematic).to have_css(".pointer-events-none")
    expect(cinematic).to have_css("[class*='bg-neutral-950']")
  end

  it "does not wrap catalog cards as edit links" do
    render_gallery

    expect(page).not_to have_css("a > article[data-skeleton-key]")
    expect(page).not_to have_css("article[data-skeleton-key] > a")
  end

  it "omits unknown keys and moves the default badge" do
    render_inline(described_class.new(skeletons: %w[cinematic missing presence], default_key: "cinematic"))

    expect(page).to have_css("article[data-skeleton-key]", count: 2)
    expect(page).not_to have_css("article[data-skeleton-key='missing']")
    expect(page.find("article[data-skeleton-key='cinematic']")).to have_text(I18n.t("website.platform.skeletons.default_badge"))
    expect(page.find("article[data-skeleton-key='presence']")).not_to have_text(I18n.t("website.platform.skeletons.default_badge"))
  end

  it "does not show an inspired-by credit when the key has none" do
    allow(I18n).to receive(:exists?).and_call_original
    allow(I18n).to receive(:exists?).with("website.skeletons.presence.inspired_by").and_return(false)
    render_gallery(skeletons: %w[presence])

    presence = page.find("article[data-skeleton-key='presence']")
    expect(presence).not_to have_text(I18n.t("website.skeletons.inspired_by_format", brand: "Pentagram"))
  end
end
