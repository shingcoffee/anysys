# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Admin::StatusBadgeComponent, type: :component do
  describe "#initialize" do
    it "accepts symbol states" do
      aggregate_failures do
        expect(described_class.new(state: :active).state).to eq(:active)
        expect(described_class.new(state: :needs_setup).state).to eq(:needs_setup)
        expect(described_class.new(state: :disabled).state).to eq(:disabled)
      end
    end

    it "coerces string state to symbol" do
      expect(described_class.new(state: "active").state).to eq(:active)
    end
  end

  describe "state mappings — badge_variant and label" do
    {
      active:      { variant: :success, label: "Active"      },
      needs_setup: { variant: :warning, label: "Needs setup" },
      disabled:    { variant: :default, label: "Disabled"    }
    }.each do |state, expected|
      it "#{state} maps to variant #{expected[:variant]} and label '#{expected[:label]}'" do
        component = described_class.new(state: state)
        aggregate_failures do
          expect(component.badge_variant).to eq(expected[:variant])
          expect(component.label).to eq(expected[:label])
        end
      end
    end
  end

  describe "rendering" do
    {
      active:      { css: ".badge-success", text: "Active"      },
      needs_setup: { css: ".badge-warning", text: "Needs setup" },
      disabled:    { css: ".badge-default", text: "Disabled"    }
    }.each do |state, expected|
      it "renders #{state} badge with correct styling and text" do
        render_inline(described_class.new(state: state))
        aggregate_failures do
          expect(page).to have_css(expected[:css])
          expect(page).to have_text(expected[:text])
        end
      end
    end

    it "renders a dot indicator and aria-label for accessibility" do
      render_inline(described_class.new(state: :active))
      aggregate_failures do
        expect(page).to have_css("span")
        expect(page).to have_css("[aria-label]")
      end
    end
  end
end
