# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::CountableItem, type: :model do
  let(:registry_keys) { %w[page entity member] }

  # Seed rows so scope/validation/usage examples have data to work with.
  before { Billing::Countable::CatalogSync.call }

  describe "scopes" do
    describe ".enabled" do
      it "returns only enabled rows" do
        described_class.find_by!(key: "page").update!(enabled: true)
        described_class.find_by!(key: "entity").update!(enabled: false)

        enabled_keys = described_class.enabled.pluck(:key)
        expect(enabled_keys).to include("page")
        expect(enabled_keys).not_to include("entity")
      end
    end

    describe ".ordered" do
      it "sorts by position ascending, then key ascending" do
        described_class.find_by!(key: "entity").update!(position: 99)
        result = described_class.ordered.pluck(:key)
        expect(result.last).to eq("entity")
      end
    end
  end

  describe "validations" do
    it "requires key" do
      item = described_class.new(label: "Test", key: nil)
      expect(item).not_to be_valid
      expect(item.errors[:key]).to be_present
    end

    it "enforces key uniqueness" do
      dup = described_class.new(key: "page", label: "Duplicate")
      expect(dup).not_to be_valid
      expect(dup.errors[:key]).to be_present
    end

    it "requires label" do
      item = described_class.new(key: "custom_key", label: nil)
      expect(item).not_to be_valid
      expect(item.errors[:label]).to be_present
    end

    it "validates period is 'total' or 'monthly'" do
      item = described_class.find_by!(key: "page")
      item.period = "weekly"
      expect(item).not_to be_valid
      expect(item.errors[:period]).to be_present

      item.period = "total"
      expect(item).to be_valid

      item.period = "monthly"
      expect(item).to be_valid
    end
  end

  describe "#usage_for" do
    let_it_be(:customer) { create(:customer) }

    it "reflects actual entity count for the customer" do
      item = described_class.find_by!(key: "entity")
      baseline = item.usage_for(customer)

      create(:entity, customer: customer)

      expect(item.usage_for(customer)).to eq(baseline + 1)
    end

    it "returns nil for an unsupported meter rather than fictitious zero usage" do
      item = described_class.new(key: "nonexistent", label: "Ghost")
      expect(item.usage_for(customer)).to be_nil
    end
  end
end
