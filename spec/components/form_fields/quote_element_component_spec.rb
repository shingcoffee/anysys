# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormFields::QuoteElementComponent, type: :component do
  it "renders quote text in a blockquote" do
    render_inline(described_class.new(content_text: "To be or not to be."))
    expect(page).to have_css("blockquote")
    expect(page).to have_text("To be or not to be.")
  end

  it "renders with left border styling" do
    render_inline(described_class.new(content_text: "Quote"))
    expect(page).to have_css(".border-l-2")
  end

  it "renders italic text" do
    render_inline(described_class.new(content_text: "Quote"))
    expect(page).to have_css("p.italic")
  end

  it "renders attribution when provided" do
    render_inline(described_class.new(content_text: "Quote", attribution: "Shakespeare"))
    expect(page).to have_css("cite", text: "Shakespeare")
  end

  it "does not render cite element without attribution" do
    render_inline(described_class.new(content_text: "Quote"))
    expect(page).not_to have_css("cite")
  end

  it "defaults attribution to empty string" do
    component = described_class.new(content_text: "Quote")
    expect(component.attribution).to eq("")
  end

  # Task C — d. components render without error given a non-default theme
  describe "theme propagation" do
    it "renders without error when theme is {} (default)" do
      expect { render_inline(described_class.new(content_text: "Quote", theme: {})) }.not_to raise_error
    end

    it "renders without error when given a rose theme hash" do
      expect {
        render_inline(described_class.new(content_text: "Quote", attribution: "Author",
                                          theme: { "accent_color" => "rose", "primary_color" => "rose" }))
      }.not_to raise_error
    end

    it "still renders blockquote and text with a custom theme" do
      render_inline(described_class.new(content_text: "Test quote",
                                        theme: { "accent_color" => "teal", "primary_color" => "teal" }))
      expect(page).to have_css("blockquote")
      expect(page).to have_text("Test quote")
    end
  end
end
