# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormErrorsComponent, type: :component do
  let(:entity) { Entity.new(name: "").tap(&:valid?) }

  describe "#initialize" do
    it "sets the resource" do
      expect(described_class.new(resource: entity).resource).to eq(entity)
    end
  end

  describe "#render?" do
    it "returns true when resource has errors" do
      expect(described_class.new(resource: entity).render?).to be true
    end

    it "returns false when resource has no errors" do
      valid_entity = Entity.new(name: "Valid Entity").tap { |e| e.errors.clear }
      expect(described_class.new(resource: valid_entity).render?).to be false
    end

    it "returns false when resource is nil" do
      expect(described_class.new(resource: nil).render?).to be false
    end
  end

  describe "unit methods" do
    subject(:component) { described_class.new(resource: entity) }

    it "returns the number of errors from #error_count" do
      expect(component.error_count).to eq(entity.errors.count)
    end

    it "returns humanized model name in lowercase from #model_name" do
      expect(component.model_name).to eq("entity")
    end

    it "returns all full error messages from #error_messages" do
      expect(component.error_messages).to eq(entity.errors.full_messages)
    end

    it "returns properly pluralized header from #header_text" do
      entity.errors.add(:base, "Test error 1")
      entity.errors.add(:base, "Test error 2")
      aggregate_failures do
        expect(component.header_text).to include("errors")
        expect(component.header_text).to include("entity")
      end
    end
  end

  describe "rendering" do
    context "with errors" do
      before { render_inline(described_class.new(resource: entity)) }

      it "renders error container, icon, and error list" do
        aggregate_failures do
          expect(page).to have_css(".bg-red-50")
          expect(page).to have_css(".border-red-200")
          expect(page).to have_css("svg.text-red-500")
          expect(page).to have_css("ul.list-disc")
        end
      end

      it "renders each error message as a list item" do
        entity.errors.full_messages.each do |message|
          expect(page).to have_css("li", text: message)
        end
      end
    end

    context "without errors" do
      it "does not render when resource has no errors" do
        valid_entity = Entity.new(name: "Valid").tap { |e| e.errors.clear }
        render_inline(described_class.new(resource: valid_entity))
        expect(page).not_to have_css(".bg-red-50")
      end
    end
  end
end
