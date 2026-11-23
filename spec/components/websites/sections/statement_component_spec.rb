# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::StatementComponent, type: :component do
  let(:props) do
    { "kicker" => "Our reason", "headline" => "We build what lasts.", "body" => "First paragraph.\n\nSecond paragraph." }
  end

  it "renders its content from props" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 42))

    expect(page).to have_css("h2", text: "We build what lasts.")
    expect(page).to have_css("p", text: "First paragraph.")
    expect(page).to have_css("p", text: "Second paragraph.")
  end

  it "renders in a dark theme" do
    render_inline(described_class.new(props: props, theme: website_theme("appearance" => "dark"), customer_id: 42))

    expect(page).to have_css("section")
  end

  it "renders a style override on a restylable element" do
    render_inline(described_class.new(
      props: props.merge("styles" => { "headline" => { "color" => "#be123c" } }),
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='headline'][style*='#be123c']")
  end
end
