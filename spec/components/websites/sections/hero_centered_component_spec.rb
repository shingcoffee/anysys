# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::HeroCenteredComponent, type: :component do
  let(:props) do
    { "eyebrow" => "Introducing v3", "headline" => "Ship faster", "subhead" => "Preview every change.", "primary_label" => "Start", "primary_href" => "about", "secondary_label" => "Docs", "secondary_href" => "https://example.com/docs" }
  end

  it "renders its content from props" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 12345678))

    expect(page).to have_css("h1", text: "Ship faster")
    expect(page).to have_text("Introducing v3")
    expect(page).to have_link("Start", href: "/12345678/about")
    expect(page).to have_link("Docs", href: "https://example.com/docs")
  end

  it "renders in a dark theme" do
    render_inline(described_class.new(props: props, theme: website_theme("appearance" => "dark"), customer_id: 12345678))

    expect(page).to have_css("section")
  end

  [nil, "", "image"].each do |mode|
    it "retains the image frame for media_mode #{mode.inspect}" do
      render_inline(described_class.new(props: props.merge("media_mode" => mode, "image_url" => "https://example.com/product.jpg"), theme: website_theme))

      expect(page).to have_css("img[src='https://example.com/product.jpg'][alt='Ship faster'][loading='eager']")
      expect(page.find("section")[:class]).to include("pt-20 md:pt-32")
    end
  end

  it "retains the placeholder frame when the default image is absent" do
    render_inline(described_class.new(props: props, theme: website_theme))

    expect(page).to have_css("[class*='aspect-']")
  end

  it "makes a compact text-only hero without image or placeholder when media is off" do
    render_inline(described_class.new(props: props.merge("media_mode" => "none", "image_url" => "https://example.com/hidden.jpg"), theme: website_theme, customer_id: 12345678))

    expect(page).to have_css("h1", text: "Ship faster", count: 1)
    expect(page).to have_link("Start", href: "/12345678/about")
    expect(page).not_to have_css("img, svg, [class*='aspect-']")
    expect(page.find("section")[:class]).to include("pt-14 pb-8 md:pt-20 md:pb-10")
    expect(page.find("h1")[:class]).to include("max-w-4xl", "lg:text-site-6xl")
  end

  it "applies a style override to the headline" do
    render_inline(described_class.new(
      props: props.merge("styles" => { "headline" => { "color" => "#be123c" } }),
      theme: website_theme,
      customer_id: 12345678
    ))

    expect(page).to have_css("[data-site-el='headline'][style*='#be123c']")
  end
end

