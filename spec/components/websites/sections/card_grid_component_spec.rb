# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::CardGridComponent, type: :component do
  it "renders the heading from props" do
    render_inline(described_class.new(
      props: {
        "heading" => "Services",
        "cards" => [{ "title" => "Workshops", "body" => "Hands-on days.", "href" => "about" }]
      },
      theme: website_theme,
      customer_id: 12345678
    ))

    expect(page).to have_text("Services")
    expect(page).to have_link("Workshops", href: "/12345678/about")
  end

  it "renders a style override on the card title" do
    render_inline(described_class.new(
      props: {
        "heading" => "Services",
        "cards" => [{ "title" => "Workshops", "body" => "Hands-on days.", "href" => "about" }],
        "styles" => { "cards.title" => { "color" => "#be123c" } }
      },
      theme: website_theme,
      customer_id: 12345678
    ))

    expect(page).to have_css("[data-site-el='cards.title'][style*='#be123c']")
  end
end
