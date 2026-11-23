# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::LocationsComponent, type: :component do
  let(:places) do
    [
      { "name" => "Hayes Valley", "address" => "315 Linden Street\nSan Francisco, CA", "hours" => "Daily 7:00–17:00", "phone" => "+1 415 555 0161",
        "button_label" => "Get directions", "button_href" => "https://example.com/map" },
      { "name" => "Mint Plaza", "button_label" => "Menu", "button_href" => "menu" },
      { "name" => "" }
    ]
  end

  it "renders a card per named place with labelled detail rows" do
    render_inline(described_class.new(props: { "heading" => "Cafés", "places" => places }, theme: website_theme, customer_id: 12345678))

    expect(page).to have_css("h2", text: "Cafés")
    expect(page).to have_css("article", count: 2)
    card = page.find("article", text: "Hayes Valley")
    expect(card).to have_css("dt .sr-only", text: I18n.t("website.public.contact.address"))
    expect(card).to have_css("dt .sr-only", text: I18n.t("website.public.contact.hours"))
    expect(card).to have_text("315 Linden Street")
    expect(card).to have_link("+1 415 555 0161", href: "tel:+14155550161")
    expect(card).to have_link("Get directions", href: "https://example.com/map")
  end

  it "resolves internal button links and skips empty detail lists" do
    render_inline(described_class.new(props: { "places" => places }, theme: website_theme("appearance" => "dark"), customer_id: 12345678))

    card = page.find("article", text: "Mint Plaza")
    expect(card).to have_link("Menu", href: "/12345678/menu")
    expect(card).not_to have_css("dl")
  end

  it "sizes the grid to the number of places" do
    build = ->(count) { described_class.new(props: { "places" => Array.new(count) { |i| { "name" => "Store #{i}" } } }, theme: website_theme, customer_id: 42) }

    expect(build.call(1).grid_class).to include("max-w-xl")
    expect(build.call(4).grid_class).to eq("sm:grid-cols-2")
    expect(build.call(3).grid_class).to include("lg:grid-cols-3")
  end

  it "applies a style override to a restylable target" do
    render_inline(described_class.new(
      props: { "places" => [{ "name" => "Hayes Valley" }], "styles" => { "places.name" => { "color" => "#be123c" } } },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='places.name'][style*='#be123c']")
  end

  it "drops unsafe links and images and escapes authored markup" do
    unsafe = [
      { "name" => "<script>alert(1)</script>", "button_label" => "Directions", "button_href" => "javascript:alert(1)", "image_url" => "javascript:alert(1)" },
      { "name" => "Annex", "button_label" => "Menu", "button_href" => "http://evil.example" }
    ]
    render_inline(described_class.new(props: { "places" => unsafe }, theme: website_theme, customer_id: 42))

    expect(page).to have_css("h3", text: "<script>alert(1)</script>")
    expect(page).to have_text("Directions")
    expect(page).not_to have_css("script")
    expect(page).not_to have_css("a")
    expect(page).not_to have_css("img[src^='javascript']")
  end
end
