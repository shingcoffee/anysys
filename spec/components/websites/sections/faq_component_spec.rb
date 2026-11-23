# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::FaqComponent, type: :component do
  it "renders the heading from props using details/summary" do
    render_inline(described_class.new(
      props: {
        "heading" => "Frequently asked questions",
        "items" => [{ "question" => "What is included?", "answer" => "The published pages." }]
      },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_text("Frequently asked questions")
    expect(page).to have_css("details")
    expect(page).to have_css("summary", text: "What is included?")
    expect(page).to have_text("The published pages.")
    expect(page).not_to have_css("[data-controller]")
  end

  it "applies a style override to the question" do
    render_inline(described_class.new(
      props: {
        "heading" => "Frequently asked questions",
        "items" => [{ "question" => "What is included?", "answer" => "The published pages." }],
        "styles" => { "items.question" => { "color" => "#be123c" } }
      },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='items.question'][style*='#be123c']")
  end
end

