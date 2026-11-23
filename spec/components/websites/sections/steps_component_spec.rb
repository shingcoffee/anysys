# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::StepsComponent, type: :component do
  let(:props) do
    { "heading" => "How it works", "items" => [{ "title" => "Join", "body" => "Sign up." }, { "title" => "Book", "body" => "Pick a time." }] }
  end

  it "renders its content from props" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 42))

    expect(page).to have_css("ol > li", count: 2)
    expect(page).to have_css("h3", text: "Book")
    expect(page).not_to have_css("ol > div")
  end

  it "renders in a dark theme" do
    render_inline(described_class.new(props: props, theme: website_theme("appearance" => "dark"), customer_id: 42))

    expect(page).to have_css("section")
  end

  it "renders a style override on a restylable element" do
    render_inline(described_class.new(
      props: props.merge("styles" => { "heading" => { "color" => "#be123c" } }),
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='heading'][style*='#be123c']")
  end
end
