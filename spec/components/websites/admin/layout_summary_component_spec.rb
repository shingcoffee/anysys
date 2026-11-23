# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::LayoutSummaryComponent, type: :component do
  let(:layout) do
    build_stubbed(:website_layout, key: "custom_summary", name: "Summary layout", description: "Hero and a quote",
                                   sections: [ { "type" => "hero_split" }, { "type" => "not_a_section" }, { "type" => "quote" } ])
  end

  it "lists the known section types with a count and the layout copy" do
    render_inline(described_class.new(layout: layout))

    expect(page).to have_css("[data-website-layout-picker-target='summaryName']", text: "Summary layout")
    expect(page).to have_css("[data-website-layout-picker-target='summaryDescription']:not(.hidden)", text: "Hero and a quote")
    expect(page).to have_css("[data-website-layout-picker-target='summaryCount']", text: I18n.t("website.admin.pages.new.section_count", count: 2))
    expect(page).to have_css("[data-website-layout-picker-target='summarySections']",
                             text: "#{I18n.t("website.sections.hero_split.name")} · #{I18n.t("website.sections.quote.name")}")
  end

  it "keeps blank copy targets in the DOM but hidden so the picker can fill them" do
    layout.description = ""
    layout.sections = []
    render_inline(described_class.new(layout: layout))

    expect(page).to have_css("[data-website-layout-picker-target='summaryDescription'].hidden", visible: :all)
    expect(page).to have_css("[data-website-layout-picker-target='summarySections'].hidden", visible: :all)
    expect(page).to have_css("[data-website-layout-picker-target='summaryCount']", text: I18n.t("website.admin.pages.new.section_count", count: 0))
  end

  it "renders nothing without a layout" do
    render_inline(described_class.new(layout: nil))

    expect(page).not_to have_css("[data-layout-summary]")
  end
end
