# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::TimelineComponent, type: :component do
  let(:props) do
    {
      "kicker" => "Since 2008",
      "heading" => "Fifteen years",
      "items" => [
        { "date" => "2008", "title" => "A birthday becomes a well", "body" => "The first project opens." },
        { "date" => "Sep 24, 2026", "title" => "Cycles, redesigned" },
        { "date" => "", "title" => "", "body" => "" }
      ]
    }
  end

  it "renders dated milestones as an ordered list and skips blank items" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 42))

    expect(page).to have_css("h2", text: "Fifteen years")
    expect(page).to have_css("ol > li", count: 2)
    expect(page).to have_css("li", text: "A birthday becomes a well")
    expect(page).to have_text("The first project opens.")
  end

  it "sets a year as a large numeral and a longer date as small caps" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 42))

    year = page.find("li", text: "2008").find("p", text: "2008")
    changelog = page.find("li", text: "Sep 24, 2026").find("p", text: "Sep 24, 2026")
    expect(year[:class]).to include("text-site-3xl")
    expect(changelog[:class]).to include("uppercase")
  end

  it "renders in a dark theme" do
    render_inline(described_class.new(props: props, theme: website_theme("appearance" => "dark"), customer_id: 42))

    expect(rendered_content).to include("bg-white/15")
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
