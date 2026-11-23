# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::TeamGridComponent, type: :component do
  it "renders the heading from props" do
    render_inline(described_class.new(
      props: {
        "heading" => "People",
        "people" => [{ "name" => "Ada Lovelace", "role" => "Fellow", "bio" => "Notes on engines." }]
      },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_text("People")
    expect(page).to have_text("Ada Lovelace")
  end

  it "renders a style override on a restylable element" do
    render_inline(described_class.new(
      props: {
        "heading" => "People",
        "people" => [{ "name" => "Ada Lovelace" }],
        "styles" => { "heading" => { "color" => "#be123c" } }
      },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='heading'][style*='#be123c']")
  end
end
