# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::ProductSpotlightComponent, type: :component do
  let(:props) do
    {
      "kicker" => "iPhone 16 Pro",
      "headline" => "Titanium. So strong. So light. So Pro.",
      "subhead" => "A18 Pro chip. Camera Control.",
      "primary_label" => "Learn more",
      "primary_href" => "about",
      "secondary_label" => "Buy",
      "secondary_href" => "https://example.com/buy",
      "image_url" => "https://images.unsplash.com/photo-1",
      "specs" => [
        { "value" => "A18 Pro", "label" => "Chip" },
        { "value" => "48MP", "label" => "Camera" },
        { "value" => "", "label" => "" }
      ]
    }
  end

  it "renders the reveal, Apple-style links and populated specs" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 12345678))

    expect(page).to have_css("h2", text: "Titanium. So strong. So light. So Pro.")
    expect(page).to have_text("iPhone 16 Pro")
    expect(page).to have_link("Learn more", href: "/12345678/about")
    expect(page).to have_link("Buy", href: "https://example.com/buy")
    expect(page).to have_css("img[src='https://images.unsplash.com/photo-1'][alt='Titanium. So strong. So light. So Pro.']")
    expect(page).to have_css("dt", text: "A18 Pro")
    expect(page).to have_css("dd", text: "Chip")
    expect(page).to have_css("dt", count: 2)
  end

  it "applies a style override to a restylable target" do
    render_inline(described_class.new(
      props: props.merge("styles" => { "headline" => { "color" => "#be123c" } }),
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='headline'][style*='#be123c']")
  end

  it "renders in a dark theme and keeps labels without hrefs as text" do
    render_inline(described_class.new(
      props: props.merge("primary_href" => "", "secondary_label" => ""),
      theme: website_theme("appearance" => "dark"),
      customer_id: 42
    ))

    expect(page).to have_text("Learn more")
    expect(page).not_to have_link("Learn more")
    expect(page).to have_css("section")
  end

  it "lays four specs out as a 2×2 grid that becomes one row on wider screens" do
    specs = %w[A B C D].map { |value| { "value" => value, "label" => value } }
    render_inline(described_class.new(props: { "specs" => specs }, theme: website_theme, customer_id: 42))

    expect(page).to have_css("dl.grid-cols-2.sm\\:grid-cols-4")
    cells = page.all("dl > div").map { |cell| cell[:class].split }
    expect(cells.map { |c| c.include?("border-l") }).to eq([false, true, false, true])
    expect(cells.map { |c| c.include?("sm:border-l") }).to eq([false, false, true, false])
  end

  it "wraps five or more specs into three columns with row-aware dividers" do
    specs = %w[A B C D E].map { |value| { "value" => value, "label" => value } }
    render_inline(described_class.new(props: { "specs" => specs }, theme: website_theme("appearance" => "dark"), customer_id: 42))

    expect(page).to have_css("dl.grid-cols-2.sm\\:grid-cols-3")
    cells = page.all("dl > div").map { |cell| cell[:class].split }
    expect(cells[3]).to include("border-l", "sm:border-l-0", "border-white/[0.12]")
    expect(cells[2]).to include("sm:border-l")
  end

  it "renders an empty section without a spec row" do
    render_inline(described_class.new(props: {}, theme: website_theme, customer_id: 42))

    expect(page).to have_css("section")
    expect(page).not_to have_css("dl")
    expect(page).not_to have_css("a")
  end
end
