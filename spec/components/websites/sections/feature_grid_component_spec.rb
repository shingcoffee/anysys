# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::FeatureGridComponent, type: :component do
  let(:props) do
    { "heading" => "Everything included", "items" => [{ "title" => "Preview", "body" => "Live URLs." }, { "title" => "Deploy", "body" => "On push." }] }
  end

  it "renders its content from props" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 42))

    expect(page).to have_css("h2", text: "Everything included")
    expect(page).to have_css("h3", text: "Deploy")
    expect(page).to have_text("02")
  end

  it "renders style overrides on list items and their fields" do
    styles = { "items" => { "background" => "#0f172a" }, "items.title" => { "color" => "#be123c", "size" => "xl" } }
    render_inline(described_class.new(props: props.merge("styles" => styles), theme: website_theme, customer_id: 42))

    expect(page).to have_css("article[data-site-el='items'][style*='background-color: #0f172a']", count: 2)
    expect(page).to have_css("[data-site-el='items.title'][style*='#be123c']", count: 2)
    expect(page).to have_css("[data-site-el='items.body']:not([style])", count: 2)
  end

  it "renders in a dark theme" do
    render_inline(described_class.new(props: props, theme: website_theme("appearance" => "dark"), customer_id: 42))

    expect(page).to have_css("section")
  end
end
