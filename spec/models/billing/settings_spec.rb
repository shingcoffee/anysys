# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Settings, type: :model do
  describe ".current" do
    it "creates a row with sensible defaults on first access" do
      settings = described_class.current
      expect(settings.collection_mode).to eq("manual")
      expect(settings.tax_rate_bps).to eq(0)
      expect(settings.grace_period_days).to eq(7)
      expect(settings.trial_ending_notice_days).to eq(3)
    end

    it "returns the same row on repeated calls" do
      first  = described_class.current
      second = described_class.current
      expect(second.id).to eq(first.id)
    end

    it "never creates more than one row regardless of concurrent calls (Fix 8)" do
      # Simulate a race by calling current multiple times concurrently via threads.
      # Each call should find_or_create_by!(singleton_guard: 0). The unique index
      # ensures only one row ever exists.
      threads = 5.times.map do
        Thread.new { described_class.current rescue nil }
      end
      threads.each(&:join)

      expect(described_class.count).to eq(1)
    end

    it "uses singleton_guard=0 as the uniqueness key" do
      settings = described_class.current
      expect(settings.singleton_guard).to eq(0)
    end
  end

  describe "predicates" do
    it "#manual? is true when collection_mode is manual" do
      settings = described_class.new(collection_mode: "manual")
      expect(settings.manual?).to be true
      expect(settings.gateway?).to be false
    end

    it "#gateway? is true when collection_mode is gateway" do
      settings = described_class.new(collection_mode: "gateway")
      expect(settings.gateway?).to be true
      expect(settings.manual?).to be false
    end
  end

  describe "#dunning_offsets" do
    it "returns the stored array" do
      settings = described_class.new(dunning_schedule: [1, 5, 10])
      expect(settings.dunning_offsets).to eq([1, 5, 10])
    end

    it "does not silently manufacture retry offsets for nil" do
      settings = described_class.new(dunning_schedule: nil)
      expect(settings.dunning_offsets).to eq([])
    end

    it "preserves an explicitly empty retry schedule" do
      settings = described_class.new(dunning_schedule: [])
      expect(settings.dunning_offsets).to eq([])
    end
  end

  describe "validations" do
    def build_settings(**overrides)
      described_class.new({ collection_mode: "manual", tax_rate_bps: 0,
                            grace_period_days: 7, trial_ending_notice_days: 3 }.merge(overrides))
    end

    it "validates collection_mode inclusion" do
      expect(build_settings(collection_mode: "cheque")).not_to be_valid
    end

    it "requires non-negative tax_rate_bps" do
      expect(build_settings(tax_rate_bps: -1)).not_to be_valid
    end
  end
end
