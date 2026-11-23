# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Settings::SectionComponent, type: :component do
  it "renders a named semantic section with an anchor, heading and description" do
    render_inline(described_class.new(id: "connection", title: "Connection", description: "Saved credentials")) { "Fields" }
    expect(page).to have_css("section#connection[aria-label='Connection'] h2", text: "Connection")
    expect(page).to have_text("Saved credentials")
    expect(page).to have_text("Fields")
  end

  it "supports untitled content without an empty heading or accessible name" do
    rendered = render_inline(described_class.new) { "Fields" }
    expect(rendered.css("h2, header, [aria-label]")).to be_empty
    expect(rendered.css("section").text).to include("Fields")
  end

  it "renders header actions and a footer bar only when the slots are given" do
    render_inline(described_class.new(title: "Invoices")) do |section|
      section.with_actions { "Filter" }
      section.with_footer { "Save" }
      "Rows"
    end
    expect(page).to have_css("header", text: "Filter")
    expect(page).to have_css("footer", text: "Save")
    expect(page).to have_text("Rows")

    render_inline(described_class.new(title: "Invoices")) { "Rows" }
    expect(page).not_to have_css("footer")
  end

  it "renders a header for actions even without a title" do
    render_inline(described_class.new) { |section| section.with_actions { "Filter" } }
    expect(page).to have_css("header", text: "Filter")
    expect(page).not_to have_css("h2")
  end
end
