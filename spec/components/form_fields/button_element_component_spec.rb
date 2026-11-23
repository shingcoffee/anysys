# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormFields::ButtonElementComponent, type: :component do
  def render_button(content_text: "Btn", **opts)
    render_inline(described_class.new(content_text: content_text, **opts))
  end

  it "renders the button text as a link" do
    render_button(content_text: "Click Me")
    expect(page).to have_css("a", text: "Click Me")
  end

  it "defaults to the indigo primary variant" do
    render_button
    expect(page).to have_css("a.bg-indigo-600")
  end

  it "renders the white secondary variant" do
    render_button(button_variant: "secondary")
    expect(page).to have_css("a.bg-white")
  end

  it "renders the outline variant with indigo text and current border" do
    render_button(button_variant: "outline")
    expect(page).to have_css("a.text-indigo-600")
    expect(page).to have_css("a.border-current")
  end

  it "defaults to md size (text-sm)" do
    render_button
    expect(page).to have_css("a.text-sm")
  end

  it "renders sm size as text-xs" do
    render_button(button_size: "sm")
    expect(page).to have_css("a.text-xs")
  end

  it "renders lg size as text-base" do
    render_button(button_size: "lg")
    expect(page).to have_css("a.text-base")
  end

  it "sets href from button_url" do
    render_button(content_text: "Go", button_url: "https://example.com")
    expect(page).to have_link("Go", href: "https://example.com")
  end

  it "defaults href to #" do
    render_button(content_text: "Go")
    expect(page).to have_link("Go", href: "#")
  end

  it "applies center alignment to the wrapper" do
    render_button(alignment: "center")
    expect(page).to have_css("div.text-center")
  end
end
