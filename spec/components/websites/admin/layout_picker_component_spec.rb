# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::LayoutPickerComponent, type: :component do
  let(:website) { build_stubbed(:website, skeleton_key: "cinematic", default_layout_key: "saas_home") }
  let(:layouts) do
    [
      build_stubbed(:website_layout, key: "presence_home", sections: [ { "type" => "hero_split", "props" => {} }, { "type" => "cta_band", "props" => {} } ]),
      build_stubbed(:website_layout, key: "saas_home"),
      build_stubbed(:website_layout, key: "cinematic_home"),
      build_stubbed(:website_layout, key: "article")
    ]
  end

  def render_picker(website: self.website, layouts: self.layouts, selected_key: nil)
    component_class = described_class
    render_in_view_context do
      form_with(url: "/pages", scope: :website_page) do |form|
        render component_class.new(form: form, layouts: layouts, selected_key: selected_key, website: website)
      end
    end
  end

  def families
    page.all("section[data-website-layout-picker-target='group']", visible: :all).map { |group| group["data-layout-family"] }
  end

  it "groups layouts by starter with the site's own starter first and standalone pages last" do
    render_picker

    expect(families).to eq(%w[cinematic presence saas_landing standalone])
    expect(page).to have_css("[data-layout-family='standalone'] h3", text: I18n.t("website.admin.pages.new.filters.general"), visible: :all)
    expect(page).to have_css("[data-layout-family='presence'] h3", text: I18n.t("website.skeletons.presence.name"), visible: :all)
  end

  it "opens on the suggested filter: the site's starter plus its default layout" do
    render_picker

    expect(page).to have_css("button[data-filter='suggested'][aria-pressed='true']", text: I18n.t("website.admin.pages.new.filters.suggested"))
    expect(page).to have_css("button[data-filter='all'][aria-pressed='false']", text: "4")
    expect(page).to have_css("label[data-layout-key='cinematic_home'][data-layout-suggested='true']:not(.hidden)")
    expect(page).to have_css("label[data-layout-key='saas_home'][data-layout-suggested='true']:not(.hidden)")
    expect(page).to have_css("label.hidden[data-layout-key='presence_home'][data-layout-suggested='false']", visible: :all)
    expect(page).to have_css("section.hidden[data-layout-family='presence']", visible: :all)
    expect(page).to have_css("[data-website-layout-picker-target='count']", text: I18n.t("website.admin.pages.new.layout_count", count: 2))
  end

  it "offers category chips in catalog order with counts and a general bucket" do
    render_picker

    chips = page.all("button[data-website-layout-picker-target='filter']").map { |chip| chip["data-filter"] }
    expect(chips).to eq(%w[suggested all business product general])
    expect(page).to have_css("button[data-filter='product']", text: "2")
    expect(page).to have_css("label[data-layout-key='article'][data-layout-category='general']", visible: :all)
  end

  it "badges the site default and carries card data for search and the summary" do
    render_picker

    card = page.find("label[data-layout-key='presence_home']", visible: :all)
    expect(card["data-layout-count"]).to eq(I18n.t("website.admin.pages.new.section_count", count: 2))
    expect(card["data-layout-sections"]).to eq([ I18n.t("website.sections.hero_split.name"), I18n.t("website.sections.cta_band.name") ].join(" · "))
    expect(card["data-layout-search"]).to eq(card["data-layout-search"].downcase)
    expect(card["data-layout-search"]).to include(I18n.t("website.sections.hero_split.name").downcase)
    expect(page).to have_css("label[data-layout-key='saas_home']", text: I18n.t("website.admin.pages.new.site_default"))
    expect(page).not_to have_css("label[data-layout-key='cinematic_home']", text: I18n.t("website.admin.pages.new.site_default"))
  end

  it "keeps each card an accessible radio with a described-by line and a decorative thumbnail" do
    render_picker(selected_key: "article")

    expect(page).to have_css("input[type='radio'][name='website_page[layout_key]'][value='article'][checked][aria-describedby='website-layout-article-description']", visible: :all)
    expect(page).to have_css("#website-layout-article-description", visible: :all)
    expect(page).to have_css("label[data-layout-key='article'] [data-catalog-thumbnail][aria-hidden='true']", visible: :all)
    expect(page).to have_css("input#website-layout-search[data-action*='keydown.esc->website-layout-picker#clearSearch']")
    expect(page).to have_css("[data-website-layout-picker-target='empty'].hidden button[data-action='click->website-layout-picker#reset']", visible: :all)
  end

  it "falls back to the first suggested layout so the checked card starts visible" do
    component = described_class.new(form: nil, layouts: layouts, selected_key: "missing", website: build_stubbed(:website, skeleton_key: "cinematic"))

    expect(component.selected_layout.key).to eq("cinematic_home")
    expect(component.initial_filter).to eq(described_class::SUGGESTED)
  end

  it "selects the first layout when nothing is suggested" do
    component = described_class.new(form: nil, layouts: layouts, selected_key: "missing")

    expect(component.selected_layout.key).to eq("presence_home")
    expect(component.initial_filter).to eq(described_class::ALL)
  end

  it "opens on all layouts when the explicit choice is not suggested" do
    render_picker(selected_key: "presence_home")

    expect(page).to have_css("button[data-filter='all'][aria-pressed='true']")
    expect(page).to have_css("label[data-layout-key='presence_home']:not(.hidden) input[checked]", visible: :all)
    expect(page).not_to have_css("label.hidden[data-website-layout-picker-target='card']", visible: :all)
  end

  it "shows everything when there is no site context to suggest from" do
    render_picker(website: nil)

    expect(page).not_to have_css("button[data-filter='suggested']")
    expect(page).to have_css("button[data-filter='all'][aria-pressed='true']")
    expect(page).not_to have_css("label.hidden[data-website-layout-picker-target='card']", visible: :all)
    expect(families.first).to eq("presence")
  end
end
