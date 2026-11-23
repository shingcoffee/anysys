# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormFields::CodeBlockElementComponent, type: :component do
  def render_code_block(content_text: "code", **opts)
    render_inline(described_class.new(content_text: content_text, **opts))
  end

  it "renders code in a pre/code block" do
    render_code_block(content_text: "puts 'hello'")
    expect(page).to have_css("pre code", text: "puts 'hello'")
  end

  it "renders with a dark background" do
    render_code_block
    expect(page).to have_css("pre.bg-gray-800")
  end

  it "renders the language label when provided" do
    render_code_block(code_language: "Ruby")
    expect(page).to have_css("div.bg-gray-700", text: "Ruby")
  end

  it "does not render the language label when empty" do
    render_code_block
    expect(page).not_to have_css("div.bg-gray-700")
  end

  it "uses a monospace font" do
    render_code_block
    expect(page).to have_css("pre.font-mono")
  end

  it "defaults code_language to empty string" do
    component = described_class.new(content_text: "code")
    expect(component.code_language).to eq("")
  end
end
