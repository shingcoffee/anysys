# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::NewPageComponent, type: :component do
  let(:website) { build_stubbed(:website, skeleton_key: "presence", default_layout_key: "presence_home") }
  let(:record) { build_stubbed(:website_page, website: website, title: "", slug: "") }
  let(:layouts) do
    [
      build_stubbed(:website_layout, key: "presence_home", sections: [ { "type" => "hero_split", "props" => {} } ]),
      build_stubbed(:website_layout, key: "article")
    ]
  end

  def render_new_page(layouts: self.layouts)
    composer = Websites::Admin::ComposerComponent.new(page: record, identity_only: true, layouts: layouts, method: :post)
    component_class = described_class
    render_in_view_context do
      form_with(url: "/pages", scope: composer.form_scope) do |form|
        render component_class.new(composer: composer, form: form)
      end
    end
  end

  it "pairs the layout gallery with a sticky details card and mounts the picker controller" do
    render_new_page

    shell = page.find("[data-new-page-shell][data-controller='website-layout-picker']")
    expect(shell["data-action"]).to eq("change->website-layout-picker#select")
    expect(shell["data-website-layout-picker-filter-value"]).to eq("suggested")
    expect(JSON.parse(shell["data-website-layout-picker-count-formats-value"])).to eq(
      "one" => I18n.t("website.admin.pages.new.layout_count_template.one"),
      "other" => I18n.t("website.admin.pages.new.layout_count_template.other")
    )
    expect(page).to have_css("section[aria-labelledby='website-new-page-layout-heading'] h2", text: I18n.t("website.admin.pages.new.choose_heading"))
    expect(page).to have_css("aside.lg\\:sticky[aria-labelledby='website-page-identity-heading'] h2", text: I18n.t("website.admin.pages.new.details_heading"))
    expect(page).to have_field("website_page[title]")
    expect(page).to have_button(I18n.t("website.admin.pages.new.submit"), type: "submit")
  end

  it "summarizes the selected layout for the details card" do
    render_new_page

    expect(page).to have_css("[data-layout-summary] [data-website-layout-picker-target='summaryName']", text: layouts.first.display_name)
    expect(page).to have_css("[data-website-layout-picker-target='summarySections']", text: I18n.t("website.sections.hero_split.name"))
    expect(page).to have_css("[data-website-layout-picker-target='summaryCount']", text: I18n.t("website.admin.pages.new.section_count", count: 1))
  end

  it "falls back to a single narrow details card when no layouts are available" do
    render_new_page(layouts: [])

    expect(page).to have_css("[data-new-page-shell].max-w-xl")
    expect(page).not_to have_css("[data-controller='website-layout-picker']")
    expect(page).not_to have_css("#website-new-page-layout-heading")
    expect(page).not_to have_css("[data-layout-summary]")
    expect(page).to have_button(I18n.t("website.admin.pages.new.submit"))
  end

  it "renders the Chinese copy without missing translations" do
    I18n.with_locale(:"zh-CN") do
      render_new_page

      expect(page).to have_css("h2", text: I18n.t("website.admin.pages.new.choose_heading"))
      expect(page).not_to have_css(".translation_missing", visible: :all)
    end
  end
end
