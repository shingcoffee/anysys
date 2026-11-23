# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormFields::CardElementComponent, type: :component do
  def render_card(title: "Card", **opts)
    render_inline(described_class.new(title: title, **opts))
  end

  it "renders the title in an h4" do
    render_card(title: "Feature")
    expect(page).to have_css("h4", text: "Feature")
  end

  it "renders the body text in a paragraph" do
    render_card(content_text: "Description here")
    expect(page).to have_css("p", text: "Description here")
  end

  it "does not render a body paragraph when content is empty" do
    render_card(content_text: "")
    expect(page).not_to have_css("p")
  end

  it "renders inside a bordered rounded container" do
    render_card
    expect(page).to have_css("div.border.border-gray-100.rounded-xl")
  end

  it "defaults content_text to an empty string" do
    component = described_class.new(title: "Card")
    expect(component.content_text).to eq("")
  end

  # Task C — d. card renders without error given various theme values
  describe "theme propagation" do
    it "renders without error when theme is {} (default)" do
      expect { render_card(theme: {}) }.not_to raise_error
    end

    it "renders without error when given a non-default theme hash" do
      expect {
        render_card(content_text: "Content",
                    theme: { "accent_color" => "rose", "primary_color" => "rose" })
      }.not_to raise_error
    end

    it "still renders title and content with a custom theme" do
      render_card(title: "Themed Card", content_text: "Body text",
                  theme: { "primary_color" => "teal" })
      expect(page).to have_css("h4", text: "Themed Card")
      expect(page).to have_css("p", text: "Body text")
    end
  end
end
