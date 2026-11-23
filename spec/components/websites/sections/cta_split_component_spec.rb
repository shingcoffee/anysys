# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::CtaSplitComponent, type: :component do
  let(:props) do
    {
      "kicker" => "Hosting",
      "headline" => "Become a host",
      "body" => "Share your space. Earn on your terms.",
      "primary_label" => "Get started",
      "primary_href" => "about",
      "secondary_label" => "Learn more",
      "secondary_href" => "https://example.com/host",
      "image_url" => "https://images.unsplash.com/photo-split"
    }
  end

  it "renders the split panel with both buttons and the photograph" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 12345678))

    expect(page).to have_css("h2", text: "Become a host")
    expect(page).to have_text("Hosting")
    expect(page).to have_link("Get started", href: "/12345678/about")
    expect(page).to have_link("Learn more", href: "https://example.com/host")
    expect(page).to have_css("img[src='https://images.unsplash.com/photo-split'][alt='Become a host']")
    expect(rendered_content).to include("md:order-last")
  end

  it "places the photograph on the left when image_side is left" do
    component = described_class.new(props: props.merge("image_side" => "left"), theme: website_theme("appearance" => "dark"), customer_id: 42)
    render_inline(component)

    expect(component.image_left?).to be(true)
    expect(component.image_order_class).to eq("order-first")
    expect(page).to have_css("section")
  end

  it "defaults a blank image_side to the right" do
    component = described_class.new(props: {}, theme: website_theme, customer_id: 42)
    render_inline(component)

    expect(component.image_left?).to be(false)
    expect(page).to have_css("section")
    expect(page).not_to have_css("a")
  end

  it "applies a style override to the headline" do
    render_inline(described_class.new(
      props: props.merge("styles" => { "headline" => { "color" => "#be123c" } }),
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='headline'][style*='#be123c']")
  end
end

