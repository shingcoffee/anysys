# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::FeatureTabsComponent, type: :component do
  let(:tabs) do
    [
      { "label" => "Cycles", "title" => "Plan in cycles", "body" => "Ship on a cadence.", "image_url" => "https://images.unsplash.com/photo-tab-1" },
      { "label" => "Issues", "title" => "Track every issue", "body" => "One inbox.", "image_url" => "https://images.unsplash.com/photo-tab-2" },
      { "title" => "Untitled view", "body" => "Falls back to the title." },
      { "label" => "", "title" => "", "body" => "skipped" }
    ]
  end

  it "renders a tablist with the first panel visible without JavaScript" do
    render_inline(described_class.new(
      props: { "kicker" => "Product", "heading" => "A workspace that moves", "subhead" => "Switch the tour.", "tabs" => tabs },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("h2", text: "A workspace that moves")
    expect(page).to have_css("[data-controller='website-feature-tabs']")
    expect(page).to have_css("[role='tablist'][aria-label='#{I18n.t("website.public.feature_tabs.tablist")}']")
    expect(page).to have_css("[role='tab']", count: 3)
    expect(page).to have_css("[role='tab'][aria-selected='true']", text: "Cycles")
    expect(page).to have_css("[role='tab'][aria-selected='false']", count: 2)
    expect(page).to have_css("[role='tabpanel']", count: 3, visible: :all)
    expect(page).to have_css("[role='tabpanel']:not([hidden])", text: "Plan in cycles")
    expect(page).to have_css("[role='tabpanel'][hidden]", count: 2, visible: :hidden)
    expect(page).to have_css("img[src='https://images.unsplash.com/photo-tab-1'][loading='eager']")
    expect(page).to have_text("Untitled view")
  end

  it "uses the title as the tab label when label is blank and skips empty tabs" do
    component = described_class.new(props: { "tabs" => tabs }, theme: website_theme("appearance" => "dark"), customer_id: 42)

    expect(component.tabs.size).to eq(3)
    expect(component.tab_label(component.tabs.last)).to eq("Untitled view")
  end

  it "hides the tablist when only one tab is present but still shows the panel" do
    render_inline(described_class.new(
      props: { "tabs" => [{ "label" => "Only", "title" => "One feature", "body" => "Just this." }] },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-controller='website-feature-tabs']")
    expect(page).not_to have_css("[role='tablist']")
    expect(page).to have_css("h3", text: "One feature")
    expect(page).not_to have_css("[hidden]")
  end

  it "renders an empty section without a tablist when there are no tabs" do
    render_inline(described_class.new(props: {}, theme: website_theme, customer_id: 42))

    expect(page).to have_css("section")
    expect(page).not_to have_css("[data-controller]")
    expect(page).not_to have_css("[role='tablist']")
  end

  it "applies a style override to the tab title" do
    render_inline(described_class.new(
      props: {
        "tabs" => [{ "label" => "Cycles", "title" => "Plan in cycles", "body" => "Ship on a cadence." }],
        "styles" => { "tabs.title" => { "color" => "#be123c" } }
      },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='tabs.title'][style*='#be123c']")
  end
end

