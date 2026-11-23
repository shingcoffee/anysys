# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::MetricsComponent, type: :component do
  let(:items) do
    [
      { "value" => "99.99%", "label" => "Historical uptime", "body" => "Across every region." },
      { "value" => "135+", "label" => "Currencies" },
      { "value" => "", "label" => "", "body" => "" }
    ]
  end

  it "renders the header and skips blank metrics" do
    render_inline(described_class.new(
      props: { "kicker" => "Scale", "heading" => "Global by default", "subhead" => "Numbers that hold.", "items" => items },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("h2", text: "Global by default")
    expect(page).to have_text("99.99%")
    expect(page).to have_text("Historical uptime")
    expect(page).to have_css("article", count: 2)
  end

  it "renders in a dark theme with accent-colored figures" do
    component = described_class.new(props: { "items" => items }, theme: website_theme("appearance" => "dark", "accent" => "violet"), customer_id: 42)
    render_inline(component)

    expect(page).to have_css("section")
    expect(component.value_class).to include("text-violet-300")
    expect(component.value_class).to include("tabular-nums")
  end

  it "sizes the grid to the number of metrics" do
    build = ->(count) { described_class.new(props: { "items" => Array.new(count) { |i| { "value" => "#{i}M" } } }, theme: website_theme, customer_id: 42) }

    expect(build.call(1).grid_class).to include("max-w-sm")
    expect(build.call(2).grid_class).to include("sm:grid-cols-2")
    expect(build.call(3).grid_class).to include("sm:grid-cols-3")
    expect(build.call(4).grid_class).to include("lg:grid-cols-4")
  end

  it "applies a style override to a restylable target" do
    render_inline(described_class.new(
      props: { "items" => items, "styles" => { "items.value" => { "color" => "#be123c" } } },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='items.value'][style*='#be123c']")
  end

  it "renders an empty section when there are no items" do
    render_inline(described_class.new(props: {}, theme: website_theme, customer_id: 42))

    expect(page).to have_css("section")
    expect(page).not_to have_css("article")
  end
end
