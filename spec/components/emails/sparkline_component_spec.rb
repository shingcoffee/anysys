# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SparklineComponent, type: :component do
  it "renders an svg polyline" do
    render_inline(described_class.new(values: [1, 2, 3]))
    expect(page).to have_css("svg polyline")
  end

  it "renders a gradient-filled polygon area" do
    render_inline(described_class.new(values: [1, 2, 3]))
    expect(page).to have_css("svg polygon")
    expect(rendered_content).to include("linearGradient")
  end

  it "does not render an svg when values are empty" do
    render_inline(described_class.new(values: []))
    expect(page).not_to have_css("svg")
  end

  it "shows a no-data message when values are empty" do
    render_inline(described_class.new(values: []))
    expect(page).to have_text(I18n.t("common.labels.no_data"))
  end

  it "uses the specified tone class on the svg element" do
    render_inline(described_class.new(values: [1, 2, 3], tone: "success"))
    expect(page).to have_css("svg.text-success")
  end

  it "maps legacy color names onto tones" do
    component = described_class.new(values: [1, 2, 3], color: "emerald")
    expect(component.tone).to eq("success")
  end

  it "falls back to accent for unknown colors" do
    component = described_class.new(values: [1, 2, 3], color: "turquoise")
    expect(component.tone).to eq("accent")
  end

  it "computes fill_points as a closed polygon string" do
    component = described_class.new(values: [1, 2, 3], width: 300, height: 40)
    fill = component.fill_points
    expect(fill).to start_with("0,40 ")
    expect(fill).to end_with(" 300,40")
  end
end
