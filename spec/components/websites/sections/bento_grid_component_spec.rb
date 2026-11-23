# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::BentoGridComponent, type: :component do
  it "renders the heading from props" do
    render_inline(described_class.new(
      props: {
        "heading" => "What we ship",
        "cells" => [{ "span" => "hero", "title" => "Studio", "body" => "Quiet rooms." }]
      },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_text("What we ship")
    expect(page).to have_text("Studio")
  end

  it "renders a style override on the cell title" do
    render_inline(described_class.new(
      props: {
        "heading" => "What we ship",
        "cells" => [{ "span" => "hero", "title" => "Studio", "body" => "Quiet rooms." }],
        "styles" => { "cells.title" => { "color" => "#be123c" } }
      },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='cells.title'][style*='#be123c']")
  end
end
