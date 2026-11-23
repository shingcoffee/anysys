# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::ListingGridComponent, type: :component do
  let(:listings) do
    [
      { "title" => "Lakeside cabin", "meta" => "Banff, Canada\nWood stove", "price" => "$310 night", "rating" => "4.97", "badge" => "Guest favourite", "href" => "stays" },
      { "title" => "Red cottage", "price" => "$180 night" },
      { "title" => "Beach bungalow" },
      { "title" => "" }
    ]
  end

  it "renders each titled listing with its badge, meta, price and link" do
    render_inline(described_class.new(props: { "heading" => "Stays", "aspect" => "landscape", "listings" => listings }, theme: website_theme, customer_id: 12345678))

    expect(page).to have_css("h2", text: "Stays")
    expect(page).to have_css("h3", count: 3)
    expect(page).to have_link(href: "/12345678/stays", count: 1)
    expect(page).to have_css("article", count: 2)
    expect(page).to have_text("Guest favourite")
    expect(page).to have_text("$310 night")
    expect(rendered_content).to include("aspect-[4/3]")
  end

  it "announces the rating to screen readers" do
    render_inline(described_class.new(props: { "listings" => listings }, theme: website_theme, customer_id: 42))

    expect(page).to have_css(".sr-only", text: I18n.t("website.public.listings.rating", rating: "4.97"))
  end

  it "uses four columns for a multiple of four and three otherwise" do
    four = described_class.new(props: { "listings" => Array.new(4) { |i| { "title" => "Home #{i}" } } }, theme: website_theme, customer_id: 42)
    three = described_class.new(props: { "listings" => listings }, theme: website_theme, customer_id: 42)

    expect(four.grid_class).to include("lg:grid-cols-4")
    expect(three.grid_class).to include("lg:grid-cols-3")
  end

  it "falls back to square photos for an unknown aspect" do
    component = described_class.new(props: { "aspect" => "panorama", "listings" => listings }, theme: website_theme("appearance" => "dark"), customer_id: 42)

    expect(component.aspect_class).to eq("aspect-square")
  end

  it "drops unsafe links and images and escapes authored markup" do
    unsafe = [
      { "title" => "<script>alert(1)</script>", "href" => "javascript:alert(1)", "image_url" => "javascript:alert(1)" },
      { "title" => "Second", "href" => "http://evil.example" }
    ]
    render_inline(described_class.new(props: { "listings" => unsafe }, theme: website_theme, customer_id: 42))

    expect(page).to have_css("h3", text: "<script>alert(1)</script>")
    expect(page).not_to have_css("script")
    expect(page).not_to have_css("a")
    expect(page).not_to have_css("img[src^='javascript']")
  end

  it "applies a style override to the listing title" do
    render_inline(described_class.new(
      props: { "listings" => listings, "styles" => { "listings.title" => { "color" => "#be123c" } } },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='listings.title'][style*='#be123c']")
  end
end

