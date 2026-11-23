# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::PageSectionComponent, type: :component do
  def render_section(**opts, &block)
    block ||= proc { "x" }
    render_inline(described_class.new(**opts), &block)
  end

  it "wraps content in a site card" do
    render_section { "<p>body</p>".html_safe }
    expect(page).to have_css("section[data-member-card].rounded-2xl p", text: "body")
  end

  it "renders an optional title and description above the body" do
    render_section(title: "Refunds", description: "Money back")
    expect(page).to have_css("h2", text: "Refunds")
    expect(page).to have_text("Money back")
  end

  it "renders the title in the public site headline type" do
    render_section(title: "Refunds")
    expect(page.find("h2")[:class]).to include("font-site-heading", "text-site-2xl")
  end

  it "supports density: :flush for tables (no inner padding wrapper)" do
    render_section(density: :flush) { "<table></table>".html_safe }
    section = page.find("section[data-member-card]")
    expect(section[:class]).to include("p-0")
    expect(section[:class]).to include("overflow-hidden")
  end

  it "supports density: :compact" do
    render_section(density: :compact)
    expect(page).to have_css("section[data-member-card].p-5")
  end

  it "raises on unknown density" do
    expect { render_section(density: :wat) }.to raise_error(ArgumentError, /density/)
  end
end
