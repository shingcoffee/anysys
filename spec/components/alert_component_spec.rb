# frozen_string_literal: true

require "rails_helper"

RSpec.describe AlertComponent, type: :component do
  describe "#initialize" do
    it "sets default type to success" do
      expect(described_class.new(message: "Test").type).to eq(:success)
    end

    it "accepts custom type" do
      expect(described_class.new(message: "Test", type: :error).type).to eq(:error)
    end

    it "converts string type to symbol" do
      expect(described_class.new(message: "Test", type: "warning").type).to eq(:warning)
    end
  end

  describe "#render?" do
    it "returns true when message is present" do
      expect(described_class.new(message: "Test message").render?).to be true
    end

    it "returns false when message is blank" do
      expect(described_class.new(message: "").render?).to be false
    end

    it "returns false when message is nil" do
      expect(described_class.new(message: nil).render?).to be false
    end
  end

  describe "type configurations" do
    {
      success: { bg: "bg-success-subtle", border: "border-success/20", text: "text-success" },
      error:   { bg: "bg-danger-subtle",  border: "border-danger/20",  text: "text-danger"  },
      warning: { bg: "bg-warning-subtle", border: "border-warning/20", text: "text-warning" },
      info:    { bg: "bg-info-subtle",    border: "border-info/20",    text: "text-info"    }
    }.each do |type, expected|
      describe "#{type} type" do
        subject(:component) { described_class.new(message: "#{type}!", type: type) }

        it "has correct styling" do
          aggregate_failures do
            expect(component.bg_class).to eq(expected[:bg])
            expect(component.border_class).to eq(expected[:border])
            expect(component.text_class).to eq(expected[:text])
            expect(component.icon_class).to eq(expected[:text])
          end
        end
      end
    end

    describe "unknown type" do
      subject(:component) { described_class.new(message: "Unknown!", type: :unknown) }

      it "falls back to info styling" do
        aggregate_failures do
          expect(component.bg_class).to eq("bg-info-subtle")
          expect(component.border_class).to eq("border-info/20")
        end
      end
    end
  end

  describe "rendering" do
    it "renders the message" do
      render_inline(described_class.new(message: "Test message"))
      expect(page).to have_text("Test message")
    end

    it "renders with correct background color" do
      render_inline(described_class.new(message: "Success", type: :success))
      expect(page).to have_css(".bg-success-subtle")
    end

    it "renders with correct border color" do
      render_inline(described_class.new(message: "Error", type: :error))
      expect(page).to have_css('[class*="border-danger"]')
    end

    it "renders SVG icon" do
      render_inline(described_class.new(message: "Test"))
      expect(page).to have_css("svg")
    end

    it "does not render when message is blank" do
      render_inline(described_class.new(message: ""))
      expect(page).not_to have_css(".mb-6")
    end
  end
end
