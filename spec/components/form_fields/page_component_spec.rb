# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormFields::PageComponent, type: :component do
  let(:page) { create(:page, name: "Test Page", description: "Test description") }

  # Renders the component around the `page` fixture; yields "Content" as the body unless a block is given.
  def render_page(**opts)
    render_inline(described_class.new(page: page, **opts)) do
      block_given? ? yield : "Content"
    end
  end

  it "renders with content block" do
    render_page { "Test content" }

    expect(rendered_content).to have_text("Test content")
  end

  it "applies default wrapper classes with inline Tailwind" do
    render_page

    expect(rendered_content).to have_css("div.max-w-4xl")
    expect(rendered_content).to have_css("div.mx-auto")
    expect(rendered_content).to have_css("div.p-6")
    expect(rendered_content).to have_css("div.rounded-lg")
  end

  it "applies custom form width from theme" do
    render_page(theme: { "form_width" => "sm" })

    expect(rendered_content).to have_css("div.max-w-md")
  end

  it "applies form shadow from theme" do
    render_page(theme: { "form_shadow" => "lg" })

    expect(rendered_content).to have_css("div.shadow-lg")
  end

  it "applies form padding from theme" do
    render_page(theme: { "form_padding" => "spacious" })

    expect(rendered_content).to have_css("div.p-8")
  end

  it "applies form border from theme" do
    render_page(theme: { "form_border" => "visible" })

    expect(rendered_content).to have_css("div.border")
  end

  it "displays page title when show_title is true" do
    render_page(show_title: true)

    expect(rendered_content).to have_text("Test Page")
  end

  it "hides page title when show_title is false" do
    render_page(show_title: false)

    expect(rendered_content).not_to have_text("Test Page")
  end

  it "accepts custom css_class" do
    render_page(css_class: "custom-class")

    expect(rendered_content).to have_css("div.custom-class")
  end

  it "displays description when show_description is true" do
    render_page(show_title: true, show_description: true)

    expect(rendered_content).to have_text("Test description")
  end
end
