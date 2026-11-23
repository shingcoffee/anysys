# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::Contracts::Settings do
  let(:settings) { Billing::Settings.new(collection_mode: "gateway", tax_rate_bps: 0, grace_period_days: 7, trial_ending_notice_days: 3, dunning_schedule: [1, 3, 7]) }

  it "does not require a nonexistent global provider selection" do
    expect(described_class.new(settings).valid?).to be(true)
  end

  it "accepts no retries explicitly" do
    form = described_class.new(settings)
    expect(form.validate(dunning_schedule: "")).to be(true)
    expect(form.parsed_dunning_schedule).to eq([])
  end

  ["1,no,7", "1,,7", "1,3,", "3,1", "1,1", [1, "3"], [0, 1], [1, -1], nil].each do |value|
    it "rejects malformed or unordered offsets #{value.inspect} while retaining submitted input" do
      form = described_class.new(settings)
      expect(form.validate(dunning_schedule: value)).to be(false)
      expect(form.dunning_schedule).to eq(value)
      expect(settings.dunning_schedule).to eq([1, 3, 7])
    end
  end

  it "rejects tax above 10000 bps" do
    expect(described_class.new(settings).validate(tax_rate_bps: 10_001)).to be(false)
  end
end
