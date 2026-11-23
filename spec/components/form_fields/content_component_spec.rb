# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormFields::ContentComponent, type: :component do
  it "renders its block content inside a wrapper div" do
    render_inline(described_class.new) { "<p>Terms and conditions</p>".html_safe }

    expect(rendered_content).to have_css("div p", text: "Terms and conditions")
  end

  it "applies the default (normal) field spacing when no theme is given" do
    render_inline(described_class.new) { "x" }

    expect(rendered_content).to have_css("div.space-y-5")
  end

  it "applies theme-resolved tight field spacing" do
    render_inline(described_class.new(theme: { "field_spacing" => "tight" })) { "x" }

    expect(rendered_content).to have_css("div.space-y-3")
  end

  it "applies theme-resolved relaxed field spacing" do
    render_inline(described_class.new(theme: { "field_spacing" => "relaxed" })) { "x" }

    expect(rendered_content).to have_css("div.space-y-8")
  end
end
