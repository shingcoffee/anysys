# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::TestimonialsComponent, type: :component do
  let(:props) do
    { "heading" => "What members say", "items" => [{ "quote" => "Seen by ten.", "name" => "Rachel Kim", "role" => "Member" }] }
  end

  it "renders its content from props" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 42))

    expect(page).to have_css("blockquote, figure", text: "Seen by ten.")
    expect(page).to have_text("Rachel Kim")
    expect(page).to have_text("RK")
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
