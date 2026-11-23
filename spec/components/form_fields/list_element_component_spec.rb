# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormFields::ListElementComponent, type: :component do
  it "renders bullet list by default" do
    render_inline(described_class.new(content_text: "Item 1\nItem 2\nItem 3"))
    expect(page).to have_css("ul.list-disc")
    expect(page).to have_css("li", count: 3)
  end

  it "renders numbered list" do
    render_inline(described_class.new(content_text: "First\nSecond", list_style: "numbered"))
    expect(page).to have_css("ol.list-decimal")
  end

  it "renders unstyled list" do
    render_inline(described_class.new(content_text: "A\nB", list_style: "none"))
    expect(page).to have_css("ul")
    expect(page).not_to have_css("ul.list-disc")
    expect(page).not_to have_css("ol")
  end

  it "splits content on newlines" do
    render_inline(described_class.new(content_text: "Apple\nBanana\nCherry"))
    expect(page).to have_css("li", text: "Apple")
    expect(page).to have_css("li", text: "Banana")
    expect(page).to have_css("li", text: "Cherry")
  end

  it "strips whitespace from items" do
    render_inline(described_class.new(content_text: "  A  \n  B  "))
    expect(page).to have_css("li", text: "A")
    expect(page).to have_css("li", text: "B")
  end

  it "ignores blank lines" do
    render_inline(described_class.new(content_text: "A\n\nB\n\n"))
    expect(page).to have_css("li", count: 2)
  end

  it "defaults to bullet for invalid list_style" do
    component = described_class.new(content_text: "A", list_style: "invalid")
    expect(component.list_style).to eq("bullet")
  end
end
