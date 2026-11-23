# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormFields::ColumnsElementComponent, type: :component do
  describe "rendering" do
    it "renders with default 50-50 layout" do
      render_inline(described_class.new) { "Column content" }

      expect(rendered_content).to have_css("div.grid.grid-cols-2.gap-6")
      expect(rendered_content).to have_text("Column content")
    end

    it "renders 33-33-33 layout" do
      render_inline(described_class.new(column_layout: "33-33-33")) { "Content" }

      expect(rendered_content).to have_css("div.grid.grid-cols-3.gap-6")
    end

    it "renders 25-25-25-25 layout" do
      render_inline(described_class.new(column_layout: "25-25-25-25")) { "Content" }

      expect(rendered_content).to have_css("div.grid.grid-cols-4.gap-6")
    end

    it "renders 66-33 layout with custom grid style" do
      render_inline(described_class.new(column_layout: "66-33")) { "Content" }

      expect(rendered_content).to have_css("div.grid.gap-6[style*='grid-template-columns: 2fr 1fr']")
    end

    it "renders 33-66 layout with custom grid style" do
      render_inline(described_class.new(column_layout: "33-66")) { "Content" }

      expect(rendered_content).to have_css("div.grid.gap-6[style*='grid-template-columns: 1fr 2fr']")
    end

    it "falls back to 50-50 for unknown layout" do
      render_inline(described_class.new(column_layout: "unknown")) { "Content" }

      expect(rendered_content).to have_css("div.grid.grid-cols-2.gap-6")
    end
  end

  describe "#grid_classes" do
    it "returns correct class for each layout" do
      layouts = {
        "50-50" => "grid grid-cols-2 gap-6",
        "33-33-33" => "grid grid-cols-3 gap-6",
        "25-25-25-25" => "grid grid-cols-4 gap-6",
        "66-33" => "grid gap-6",
        "33-66" => "grid gap-6"
      }

      layouts.each do |layout, expected|
        component = described_class.new(column_layout: layout)
        expect(component.grid_classes).to eq(expected)
      end
    end
  end

  describe "#grid_style" do
    it "returns nil for equal-width layouts" do
      %w[50-50 33-33-33 25-25-25-25].each do |layout|
        component = described_class.new(column_layout: layout)
        expect(component.grid_style).to be_nil
      end
    end

    it "returns custom grid-template-columns for asymmetric layouts" do
      expect(described_class.new(column_layout: "66-33").grid_style).to eq("grid-template-columns: 2fr 1fr")
      expect(described_class.new(column_layout: "33-66").grid_style).to eq("grid-template-columns: 1fr 2fr")
    end
  end

  describe "#column_count" do
    it "returns the number of columns" do
      component = described_class.new(columns: [{}, {}, {}])
      expect(component.column_count).to eq(3)
    end

    it "returns 0 for empty columns" do
      component = described_class.new(columns: [])
      expect(component.column_count).to eq(0)
    end
  end
end
