# frozen_string_literal: true

require "rails_helper"

RSpec.describe TierBadgeComponent, type: :component do
  describe "#initialize" do
    it "accepts tier as symbol" do
      expect(described_class.new(tier: :premium).tier).to eq(:premium)
    end

    it "converts string tier to symbol" do
      expect(described_class.new(tier: "enterprise").tier).to eq(:enterprise)
    end
  end

  describe "tier styling" do
    {
      basic:      %w[bg-gray-100 text-gray-800],
      standard:   %w[bg-blue-100 text-blue-800],
      premium:    %w[bg-purple-100 text-purple-800],
      enterprise: %w[bg-amber-100 text-amber-800]
    }.each do |tier, expected_classes|
      it "#{tier} tier has correct styling" do
        classes = described_class.new(tier: tier).tier_classes
        expected_classes.each { |css_class| expect(classes).to include(css_class) }
      end
    end

    it "falls back to basic styling for unknown tier" do
      expect(described_class.new(tier: :unknown).tier_classes).to include("bg-gray-100")
    end
  end

  describe "rendering" do
    subject(:rendered) { render_inline(described_class.new(tier: :enterprise)) }

    it "renders the tier name, pill shape, capitalize, and correct variant styling" do
      aggregate_failures do
        expect(rendered).to have_text("Enterprise")
        expect(rendered).to have_css("span")
        expect(rendered).to have_css(".rounded-full")
        expect(rendered).to have_css(".capitalize")
        expect(rendered).to have_css(".bg-amber-100")
        expect(rendered).to have_css(".text-amber-800")
      end
    end
  end
end
