# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::GalleryComponent, type: :component do
  let(:props) do
    { "heading" => "In this issue", "items" => Array.new(5) { |i| { "caption" => "Plate #{i + 1}", "image_url" => "https://images.unsplash.com/photo-1-#{i}" } } }
  end

  it "renders its content from props" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 42))

    expect(page).to have_css("figure", count: 5)
    expect(page).to have_css("figcaption", text: "Plate 5")
    expect(page).to have_css("figure.md\\:col-span-7", count: 2)
    expect(page).to have_css("figure.md\\:col-span-12", count: 1)
  end

  it "renders in a dark theme" do
    render_inline(described_class.new(props: props, theme: website_theme("appearance" => "dark"), customer_id: 42))

    expect(page).to have_css("section")
  end

  it "applies a style override to the caption" do
    render_inline(described_class.new(
      props: props.merge("styles" => { "items.caption" => { "color" => "#be123c" } }),
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='items.caption'][style*='#be123c']")
  end
end

