# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::AlternatingFeaturesComponent, type: :component do
  it "renders the heading from props" do
    render_inline(described_class.new(
      props: {
        "heading" => "How it works",
        "items" => [{ "title" => "Capture", "body" => "Start with presence." }]
      },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_text("How it works")
    expect(page).to have_text("Capture")
  end

  it "renders a style override on the item title" do
    render_inline(described_class.new(
      props: {
        "heading" => "How it works",
        "items" => [{ "title" => "Capture", "body" => "Start with presence." }],
        "styles" => { "items.title" => { "color" => "#be123c" } }
      },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='items.title'][style*='#be123c']")
  end
end
