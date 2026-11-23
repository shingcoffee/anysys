# frozen_string_literal: true

require "rails_helper"

RSpec.describe ButtonComponent, type: :component do
  describe "#initialize" do
    it "sets default variant to primary" do
      expect(described_class.new.variant).to eq(:primary)
    end

    it "sets default size to md" do
      expect(described_class.new.size).to eq(:md)
    end

    it "sets default tag to button" do
      expect(described_class.new.tag).to eq(:button)
    end

    it "accepts custom variant" do
      expect(described_class.new(variant: :danger).variant).to eq(:danger)
    end

    it "converts string variant to symbol" do
      expect(described_class.new(variant: "secondary").variant).to eq(:secondary)
    end
  end

  describe "variant styling" do
    { primary: "btn-primary", secondary: "btn-secondary", danger: "btn-danger", ghost: "btn-ghost" }.each do |variant, css_class|
      it "#{variant} variant includes #{css_class}" do
        expect(described_class.new(variant: variant).variant_classes).to include(css_class)
      end
    end
  end

  describe "size styling" do
    it "returns small size classes" do
      component = described_class.new(size: :sm)
      aggregate_failures do
        expect(component.size_classes).to include("px-3")
        expect(component.size_classes).to include("text-[13px]")
      end
    end

    it "returns medium size classes" do
      component = described_class.new(size: :md)
      aggregate_failures do
        expect(component.size_classes).to include("px-4")
        expect(component.size_classes).to include("text-sm")
      end
    end

    it "returns large size classes" do
      component = described_class.new(size: :lg)
      aggregate_failures do
        expect(component.size_classes).to include("px-5")
        expect(component.size_classes).to include("text-sm")
      end
    end
  end

  describe "rendering" do
    it "renders as button by default" do
      render_inline(described_class.new) { "Click me" }
      expect(page).to have_button("Click me")
    end

    it "renders as link when tag is :a" do
      render_inline(described_class.new(tag: :a, href: "/test")) { "Go" }
      expect(page).to have_link("Go", href: "/test")
    end

    it "renders with primary styling" do
      render_inline(described_class.new(variant: :primary)) { "Save" }
      expect(page).to have_css(".btn-primary")
    end

    it "renders content from block" do
      render_inline(described_class.new) { "Submit" }
      expect(page).to have_text("Submit")
    end

    it "applies disabled attribute" do
      render_inline(described_class.new(disabled: true)) { "Disabled" }
      expect(page).to have_css("button[disabled]")
    end

    it "merges additional HTML attributes" do
      render_inline(described_class.new(data: { action: "click->test#run" })) { "Test" }
      expect(page).to have_css("[data-action='click->test#run']")
    end

    it "renders full width when specified" do
      render_inline(described_class.new(full_width: true)) { "Wide" }
      expect(page).to have_css(".w-full")
    end
  end
end
