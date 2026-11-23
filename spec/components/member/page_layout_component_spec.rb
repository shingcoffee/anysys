# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::PageLayoutComponent, type: :component do
  # Renders the layout with a default "primary" slot; yields the component so
  # examples can attach hero/aside slots. Pass primary: to override the body text.
  def render_layout(primary: "primary")
    render_inline(described_class.new) do |c|
      c.with_primary { primary }
      yield c if block_given?
    end
  end

  it "renders the primary slot inside the layout wrapper" do
    render_layout(primary: "primary content")

    expect(page).to have_text("primary content")
    expect(page).to have_css("[data-component='member-page-layout']")
  end

  it "omits any hero markup when the hero slot is not provided" do
    render_layout

    expect(page).not_to have_text("hero")
    expect(page).not_to have_css("[data-test='hero-content']")
  end

  it "keeps primary at lg:col-span-8 even when aside is omitted" do
    render_layout

    expect(page).to have_css(".lg\\:col-span-8", text: "primary")
    expect(page).not_to have_css(".lg\\:col-span-12", text: "primary")
  end

  it "renders an invisible aside placeholder when no aside slot is given" do
    render_layout

    placeholder = page.find("div.hidden.lg\\:block.lg\\:col-span-4", visible: :all)
    expect(placeholder["aria-hidden"]).to eq("true")
    expect(placeholder.text).to eq("")
    expect(page).not_to have_css("aside")
  end

  it "renders the hero slot before the grid when given" do
    render_layout do |c|
      c.with_hero { '<div data-test="hero-content">hero</div>'.html_safe }
    end

    hero_index    = page.native.to_s.index("hero-content")
    primary_index = page.native.to_s.index("primary")
    expect(hero_index).to be < primary_index
  end

  it "renders the aside slot inside an <aside> with lg:col-span-4 when given" do
    render_layout do |c|
      c.with_aside { "aside content" }
    end

    expect(page).to have_css("aside.lg\\:col-span-4", text: "aside content")
    expect(page).not_to have_css("div.hidden.lg\\:block.lg\\:col-span-4", visible: :all)
  end

  it "keeps primary at lg:col-span-8 when aside is given" do
    render_layout do |c|
      c.with_aside { "aside" }
    end

    expect(page).to have_css(".lg\\:col-span-8", text: "primary")
  end

  it "uses a responsive grid: grid-cols-1 below lg, lg:grid-cols-12 above" do
    render_layout

    expect(page).to have_css(".grid.grid-cols-1.lg\\:grid-cols-12")
  end
end
