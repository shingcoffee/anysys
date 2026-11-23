# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::HeroSplitComponent, type: :component do
  it "renders the headline from props" do
    render_inline(described_class.new(
      props: { "headline" => "Infrastructure for ambitious teams.", "eyebrow" => "Platform" },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_text("Infrastructure for ambitious teams.")
    expect(page).to have_text("Platform")
    expect(rendered_content).to include("sm:text-site-5xl")
    expect(rendered_content).to include("lg:text-site-6xl")
  end

  it "renders style overrides on the headline and buttons" do
    render_inline(described_class.new(
      props: {
        "headline" => "Infrastructure for ambitious teams.", "primary_label" => "Start", "primary_href" => "about",
        "styles" => { "headline" => { "color" => "#be123c", "align" => "center" }, "buttons" => { "shape" => "square", "fill" => "#0f172a" } }
      },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='headline'][style*='#be123c'][style*='text-align: center']")
    expect(page).to have_css("[data-site-el='buttons'] [style*='background-color: #0f172a'][style*='border-radius: 0']", text: "Start")
  end
end
