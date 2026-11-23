# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::SettingsSectionComponent, type: :component do
  it "renders a scrollspy card labelled by its heading" do
    render_inline(described_class.new(id: "website-settings-seo", heading: "Search appearance", description: "Helper copy")) do
      "<input id='body-field'>".html_safe
    end

    expect(page).to have_css("section#website-settings-seo.card[aria-labelledby='website-settings-seo-heading'][data-website-theme-picker-target='section']")
    expect(page).to have_css("h2#website-settings-seo-heading.section-header.scroll-mt-24", text: "Search appearance")
    expect(page).to have_css("header p", text: "Helper copy")
    expect(page).to have_css("header + div input#body-field")
  end

  it "merges extra data attributes, skips a blank description, and renders the aside slot" do
    render_inline(described_class.new(id: "starter", heading: "Starter", data: { skeleton_replace: "true" })) do |section|
      section.with_aside { "<span data-aside='true'>Extra</span>".html_safe }
      "Body"
    end

    expect(page).to have_css("section#starter[data-skeleton-replace='true'][data-website-theme-picker-target='section']")
    expect(page).not_to have_css("header p")
    expect(page).to have_css("header [data-aside='true']", text: "Extra")
  end
end
