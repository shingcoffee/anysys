# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::LayoutsGalleryComponent, type: :component do
  let(:customer_id) { 81_721_200 }
  let(:layouts) do
    [
      build_layout("presence_home", "Presence home", [ { "type" => "hero_split" }, { "type" => "proof_strip" } ]),
      build_layout("saas_home", "Product home", [ { "type" => "hero_split" }, { "type" => "faq" } ]),
      build_layout("article", "Article", [ { "type" => "rich_text" } ])
    ]
  end

  def build_layout(key, name, sections)
    instance_double(
      WebsiteLayout,
      key: key,
      display_name: name,
      display_description: "#{name} description",
      sections: sections,
      theme_preset_key: Websites::ThemePairing.for_layout(key)
    )
  end

  def render_gallery(family: nil, items: layouts)
    render_inline(described_class.new(layouts: items, customer_id: customer_id, family: family))
  end

  it "renders a responsive catalog with new-layout action" do
    render_gallery

    expect(page).to have_css("[data-layouts-gallery='true']")
    expect(page).to have_css("h2", text: I18n.t("website.platform.layouts.heading"))
    expect(page).to have_link(I18n.t("website.platform.layouts.new"))
    expect(page).to have_css("[class*='grid-cols-1'][class*='sm:grid-cols-2'][class*='xl:grid-cols-3']")
    expect(page).to have_css("article[data-layout-key='presence_home']")
    expect(page).to have_css("article[data-layout-key='saas_home']")
    expect(page).to have_css("article[data-layout-key='article']")
  end

  it "groups layouts by family and labels standalone keys" do
    render_gallery

    expect(page).to have_css("[data-layout-family='presence']")
    expect(page).to have_css("[data-layout-family='saas_landing']")
    expect(page).to have_css("[data-layout-family='standalone']")
    expect(page).to have_text(I18n.t("website.skeletons.presence.name"))
    expect(page).to have_text(I18n.t("website.platform.catalog.families.standalone"))
  end

  it "filters by family and shows section chips" do
    render_gallery(family: "standalone")

    expect(page).to have_css("article[data-layout-key='article']")
    expect(page).not_to have_css("article[data-layout-key='presence_home']")
    expect(page).to have_text(I18n.t("website.sections.rich_text.name"))
    expect(page).to have_text(I18n.t("website.platform.catalog.chips.sections", count: 1))
  end

  it "renders family filter chips" do
    render_gallery

    expect(page).to have_css("[data-catalog-filter='true']")
    expect(page).to have_link(I18n.t("website.platform.catalog.filter.all"))
    expect(page).to have_css("[data-filter-id='standalone']")
    expect(page).to have_css("[data-filter-id='all']", text: "3")
    expect(page).to have_css("[data-filter-id='standalone']", text: "1")
  end

  it "shows an empty state when a family has no layouts" do
    render_gallery(family: "campus")

    expect(page).to have_text(I18n.t("website.platform.catalog.empty.layouts_title"))
    expect(page).not_to have_css("article[data-layout-key]")
  end

  it "wraps the mini preview in a scaled frame" do
    render_gallery

    expect(page).to have_css("[data-catalog-thumbnail='true'] .pointer-events-none.select-none.origin-top-left")
    expect(page).to have_css("article[data-layout-key='presence_home'][data-family='presence']")
  end
end
