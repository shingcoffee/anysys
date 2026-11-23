# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::HeroCardComponent, type: :component do
  def render_hero(greeting: "Hi", name: "Lin", subhead: "x", **opts)
    render_inline(described_class.new(greeting: greeting, name: name, subhead: subhead, **opts))
  end

  it "renders the greeting, name, and subhead" do
    render_hero(greeting: "Good morning", subhead: "Your membership is active.")

    expect(page).to have_css("[data-member-hero]")
    expect(page).to have_text("Good morning, Lin")
    expect(page).to have_text("Your membership is active.")
  end

  it "renders the title in the public site headline type" do
    render_hero
    expect(page.find("h1")[:class]).to include("font-site-heading", "text-site-4xl")
  end

  it "renders an optional status badge" do
    render_hero(status: { label: "Active", tone: :success })

    expect(page).to have_text("Active")
  end
end
