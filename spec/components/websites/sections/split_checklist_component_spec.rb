# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::SplitChecklistComponent, type: :component do
  let(:props) do
    {
      "kicker" => "Why us",
      "heading" => "Built for teams who send",
      "body" => "A marketing platform that stays out of the way.",
      "button_label" => "Start free",
      "button_href" => "about",
      "items" => [
        { "title" => "Audience first", "body" => "Segments that stay honest." },
        { "title" => "On-brand", "body" => "" },
        { "title" => "", "body" => "" }
      ]
    }
  end

  it "renders the pitch, button and checked items" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 12345678))

    expect(page).to have_css("h2", text: "Built for teams who send")
    expect(page).to have_text("Why us")
    expect(page).to have_link("Start free", href: "/12345678/about")
    expect(page).to have_css("li", count: 2)
    expect(page).to have_css("h3", text: "Audience first")
    expect(page).to have_css("svg[aria-hidden='true']", count: 2)
  end

  it "renders in a dark theme and keeps a button without a href as a span" do
    render_inline(described_class.new(props: props.merge("button_href" => ""), theme: website_theme("appearance" => "dark"), customer_id: 42))

    expect(page).to have_text("Start free")
    expect(page).not_to have_link("Start free")
    expect(page).to have_css("section")
  end

  it "renders the left column alone when the list is empty" do
    render_inline(described_class.new(props: { "heading" => "Just the pitch" }, theme: website_theme, customer_id: 42))

    expect(page).to have_css("h2", text: "Just the pitch")
    expect(page).not_to have_css("li")
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
