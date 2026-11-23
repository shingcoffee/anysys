# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::CollectionRailComponent, type: :component do
  let(:items) do
    [
      { "title" => "Cabins", "meta" => "128 stays", "image_url" => "https://images.unsplash.com/photo-rail-1", "href" => "about" },
      { "title" => "Jazz after dark", "meta" => "Playlist" },
      { "title" => "", "meta" => "", "image_url" => "" }
    ]
  end

  it "renders a snap rail of titled cards and links when href resolves" do
    render_inline(described_class.new(
      props: { "kicker" => "Browse", "heading" => "Categories", "subhead" => "Pick a mood.", "aspect" => "landscape", "items" => items },
      theme: website_theme,
      customer_id: 12345678
    ))

    expect(page).to have_css("h2", text: "Categories")
    expect(page).to have_link("Cabins", href: "/12345678/about")
    expect(page).to have_text("128 stays")
    expect(page).to have_css("article", text: "Jazz after dark")
    expect(page).to have_css("h3", count: 2)
    expect(rendered_content).to include("aspect-[4/3]")
    expect(rendered_content).to include("snap-x")
  end

  it "defaults a blank aspect to portrait and honors square" do
    blank = described_class.new(props: { "items" => items }, theme: website_theme("appearance" => "dark"), customer_id: 42)
    square = described_class.new(props: { "aspect" => "square", "items" => items }, theme: website_theme, customer_id: 42)
    unknown = described_class.new(props: { "aspect" => "panorama", "items" => items }, theme: website_theme, customer_id: 42)

    expect(blank.aspect_class).to eq("aspect-[4/5]")
    expect(square.aspect_class).to eq("aspect-square")
    expect(unknown.aspect_class).to eq("aspect-[4/5]")
  end

  it "renders an empty section when every card is blank" do
    render_inline(described_class.new(props: { "heading" => "Empty shelf", "items" => [{ "title" => "" }] }, theme: website_theme, customer_id: 42))

    expect(page).to have_css("h2", text: "Empty shelf")
    expect(page).not_to have_css("h3")
    expect(page).not_to have_css("a")
  end

  it "drops unsafe links and images and escapes authored markup" do
    unsafe = [{ "title" => "<script>alert(1)</script>", "href" => "javascript:alert(1)", "image_url" => "javascript:alert(1)" }]
    render_inline(described_class.new(props: { "items" => unsafe }, theme: website_theme, customer_id: 42))

    expect(page).to have_css("h3", text: "<script>alert(1)</script>")
    expect(page).not_to have_css("script")
    expect(page).not_to have_css("a")
    expect(page).not_to have_css("img[src^='javascript']")
  end

  it "renders a style override on the item title" do
    render_inline(described_class.new(
      props: { "heading" => "Categories", "items" => items, "styles" => { "items.title" => { "color" => "#be123c" } } },
      theme: website_theme,
      customer_id: 12345678
    ))

    expect(page).to have_css("[data-site-el='items.title'][style*='#be123c']")
  end
end
