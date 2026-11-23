# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::ShowcaseTilesComponent, type: :component do
  let(:props) do
    {
      "tiles" => [
        { "kicker" => "New", "title" => "Model Aero", "body" => "Long range.", "primary_label" => "Order", "primary_href" => "models",
          "secondary_label" => "Test drive", "secondary_href" => "visit", "image_url" => "https://images.unsplash.com/photo-1?w=1800", "tone" => "light", "size" => "full" },
        { "title" => "Studio Edition", "primary_label" => "Learn more", "primary_href" => "models", "tone" => "dark", "size" => "half" }
      ]
    }
  end

  it "renders each tile with its copy and pill links" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 12345678))

    expect(page).to have_css("article", count: 2)
    expect(page).to have_css("h2", text: "Model Aero")
    expect(page).to have_text("New")
    expect(page).to have_link("Order", href: "/12345678/models")
    expect(page).to have_link("Test drive", href: "/12345678/visit")
    expect(page).to have_css("img[src^='https://images.unsplash.com/photo-1']")
  end

  it "spans full tiles across both columns and keeps half tiles to one" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 42))

    full, half = page.all("article").to_a
    expect(full[:class]).to include("md:col-span-2", "bg-neutral-100")
    expect(half[:class]).not_to include("md:col-span-2")
    expect(half[:class]).to include("bg-neutral-950", "text-white")
  end

  it "renders a placeholder instead of an empty image and skips missing pills" do
    render_inline(described_class.new(props: { "tiles" => [{ "title" => "Energy", "tone" => "dark" }] }, theme: website_theme, customer_id: 42))

    expect(page).to have_css("h2", text: "Energy")
    expect(page).not_to have_css("img[src='']")
    expect(page).not_to have_css("a")
  end

  it "drops unsafe links and images and escapes authored markup" do
    tile = { "title" => "<script>alert(1)</script>", "primary_label" => "Order", "primary_href" => "javascript:alert(1)",
             "secondary_label" => "Visit", "secondary_href" => "http://evil.example", "image_url" => "javascript:alert(1)" }
    render_inline(described_class.new(props: { "tiles" => [tile] }, theme: website_theme, customer_id: 42))

    expect(page).to have_css("h2", text: "<script>alert(1)</script>")
    expect(page).not_to have_css("script")
    expect(page).not_to have_css("a")
    expect(page).not_to have_css("img[src^='javascript']")
  end

  it "renders a style override on a restylable element" do
    render_inline(described_class.new(
      props: props.merge("styles" => { "tiles.title" => { "color" => "#be123c" } }),
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='tiles.title'][style*='#be123c']")
  end
end
