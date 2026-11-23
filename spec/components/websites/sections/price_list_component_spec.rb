# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::PriceListComponent, type: :component do
  let(:props) do
    { "heading" => "Menu", "items" => [{ "title" => "Beetroot", "price" => "$18", "body" => "Rose and smoked cream." }] }
  end

  it "renders its content from props" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 42))

    expect(page).to have_css("h3", text: "Beetroot")
    expect(page).to have_text("$18")
    expect(page).not_to have_css("div > dt")
  end

  it "applies a style override to a restylable target" do
    render_inline(described_class.new(
      props: props.merge("styles" => { "items.title" => { "color" => "#be123c" } }),
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='items.title'][style*='#be123c']")
  end

  it "renders in a dark theme" do
    render_inline(described_class.new(props: props, theme: website_theme("appearance" => "dark"), customer_id: 42))

    expect(page).to have_css("section")
  end
end
