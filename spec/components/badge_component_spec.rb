# frozen_string_literal: true

require "rails_helper"

RSpec.describe BadgeComponent, type: :component do
  describe "#initialize" do
    it "sets default variant to default" do
      component = described_class.new
      expect(component.variant).to eq(:default)
    end

    it "sets default size to md" do
      component = described_class.new
      expect(component.size).to eq(:md)
    end

    it "accepts custom variant" do
      component = described_class.new(variant: :success)
      expect(component.variant).to eq(:success)
    end

    it "converts string variant to symbol" do
      component = described_class.new(variant: "danger")
      expect(component.variant).to eq(:danger)
    end
  end

  describe "variant styling" do
    {
      default: "badge-default",
      primary: "badge-accent",
      success: "badge-success",
      warning: "badge-warning",
      danger: "badge-danger",
      info: "bg-info-subtle",
      purple: "bg-purple-100"
    }.each do |variant, expected_class|
      describe "#{variant} variant" do
        let(:component) { described_class.new(variant: variant) }

        it "has correct styling" do
          expect(component.variant_classes).to include(expected_class)
        end
      end
    end
  end

  describe "size styling" do
    it "returns small size classes" do
      component = described_class.new(size: :sm)
      expect(component.size_classes).to include("px-2")
      expect(component.size_classes).to include("text-xs")
    end

    it "returns medium size classes" do
      component = described_class.new(size: :md)
      expect(component.size_classes).to include("px-2.5")
      expect(component.size_classes).to include("text-sm")
    end
  end

  describe "rendering" do
    it "renders content from block" do
      render_inline(described_class.new) { "Active" }
      expect(page).to have_text("Active")
    end

    it "renders with correct variant styling" do
      render_inline(described_class.new(variant: :success)) { "Success" }
      expect(page).to have_css(".badge-success")
    end

    it "renders as span element" do
      render_inline(described_class.new) { "Badge" }
      expect(page).to have_css("span")
    end

    it "includes badge base class" do
      render_inline(described_class.new) { "Badge" }
      expect(page).to have_css(".badge")
    end

    it "merges additional HTML attributes" do
      render_inline(described_class.new(data: { test: "value" })) { "Test" }
      expect(page).to have_css("[data-test='value']")
    end
  end
end
