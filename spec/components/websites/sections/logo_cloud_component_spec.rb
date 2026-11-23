# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::LogoCloudComponent, type: :component do
  let(:props) do
    { "heading" => "Trusted by", "items" => [{ "name" => "Northwind" }, { "name" => "Halcyon", "image_url" => "https://example.com/halcyon.svg" }] }
  end

  it "renders its content from props" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 42))

    expect(page).to have_text("Trusted by")
    expect(page).to have_css("li span", text: "Northwind")
    expect(page).to have_css("img[alt='Halcyon'][src='https://example.com/halcyon.svg']")
  end

  it "applies a style override to a restylable target" do
    render_inline(described_class.new(
      props: props.merge("styles" => { "heading" => { "color" => "#be123c" } }),
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='heading'][style*='#be123c']")
  end

  it "renders in a dark theme" do
    render_inline(described_class.new(props: props, theme: website_theme("appearance" => "dark"), customer_id: 42))

    expect(page).to have_css("section")
  end
end
