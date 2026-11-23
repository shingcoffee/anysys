# frozen_string_literal: true

require "rails_helper"

RSpec.describe CardComponent, type: :component do
  describe "#initialize" do
    it "sets default variant to default" do
      expect(described_class.new.variant).to eq(:default)
    end

    it "sets default padding to md" do
      expect(described_class.new.padding).to eq(:md)
    end

    it "accepts custom variant" do
      expect(described_class.new(variant: :bordered).variant).to eq(:bordered)
    end
  end

  describe "variant styling" do
    it "default and bordered variants include card class" do
      aggregate_failures do
        expect(described_class.new(variant: :default).variant_classes).to include("card")
        expect(described_class.new(variant: :bordered).variant_classes).to include("card")
      end
    end

    it "flat variant has subtle background" do
      expect(described_class.new(variant: :flat).variant_classes).to include("bg-canvas-elevated")
    end
  end

  describe "padding styling" do
    {
      none: "",
      sm:   "p-4",
      md:   "p-6",
      lg:   "p-8"
    }.each do |padding, expected|
      it "returns #{padding == :none ? 'no' : padding} padding" do
        result = described_class.new(padding: padding).padding_classes
        if padding == :none
          expect(result).to eq("")
        else
          expect(result).to include(expected)
        end
      end
    end
  end

  describe "rendering" do
    it "renders content from block" do
      render_inline(described_class.new) { "Card content" }
      expect(page).to have_text("Card content")
    end

    it "renders as div element with card class" do
      render_inline(described_class.new) { "Content" }
      expect(page).to have_css("div.card")
    end

    it "merges additional HTML attributes" do
      render_inline(described_class.new(id: "my-card")) { "Content" }
      expect(page).to have_css("#my-card")
    end
  end
end
