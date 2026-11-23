# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::QuoteComponent, type: :component do
  it "renders the quote from props" do
    render_inline(described_class.new(
      props: { "quote" => "They rebuilt how we show up in public.", "attribution" => "Director", "role" => "Programs" },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_text("They rebuilt how we show up in public.")
    expect(page).to have_text("Director")
  end

  it "applies a style override to a restylable target" do
    render_inline(described_class.new(
      props: { "quote" => "They rebuilt how we show up in public.", "styles" => { "quote" => { "color" => "#be123c" } } },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='quote'][style*='#be123c']")
  end
end
