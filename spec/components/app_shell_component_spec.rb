# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppShellComponent, type: :component do
  it "renders the brand lockup linking to root and the content slot" do
    render_inline(described_class.new) { "<p>Hello world</p>".html_safe }

    expect(page).to have_css("[data-shell='app']")
    expect(page).to have_link(href: "/")
    expect(page).to have_css("svg[aria-label='Sapphire']")
    expect(page).to have_text("Hello world")
  end

  it "carries no dashboard navigation (the old Flowcharts / Code Generators links are gone)" do
    render_inline(described_class.new) { "" }

    expect(page).not_to have_text("Flowcharts")
    expect(page).not_to have_text("Code Generators")
  end

  it "honours an explicit home_path override for the brand link" do
    render_inline(described_class.new(home_path: "/12345678/admin")) { "" }

    expect(page).to have_link(href: "/12345678/admin")
  end
end
