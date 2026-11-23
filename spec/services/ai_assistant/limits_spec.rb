# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Limits do
  describe "throttled windows" do
    it "throttles a burst tighter and shorter than the sustained window" do
      expect(described_class::BURST.limit).to be < described_class::SUSTAINED.limit
      expect(described_class::BURST.period).to be < described_class::SUSTAINED.period
    end

    it "orders the windows tightest first so a breach reports the right message" do
      expect(described_class::WINDOWS).to eq([described_class::BURST, described_class::SUSTAINED])
    end

    it "names an error message for every window" do
      described_class::WINDOWS.each do |window|
        expect(I18n.exists?("ai_assistant.errors.#{window.message_key}")).to be(true)
        expect(I18n.exists?("ai_assistant.errors.#{window.message_key}", :"zh-CN")).to be(true)
      end
    end

    it "gives every window a distinct name so their counters cannot collide" do
      names = described_class::WINDOWS.map(&:name)

      expect(names.uniq).to eq(names)
    end
  end

  describe "conversation rounds" do
    it "counts down from the cap" do
      expect(described_class.turns_remaining(0)).to eq(described_class::MAX_TURNS)
      expect(described_class.turns_remaining(1)).to eq(described_class::MAX_TURNS - 1)
    end

    it "never reports a negative remainder" do
      expect(described_class.turns_remaining(described_class::MAX_TURNS + 5)).to eq(0)
    end

    it "is exhausted at and beyond the cap" do
      expect(described_class).not_to be_turns_exhausted(described_class::MAX_TURNS - 1)
      expect(described_class).to be_turns_exhausted(described_class::MAX_TURNS)
      expect(described_class).to be_turns_exhausted(described_class::MAX_TURNS + 1)
    end

    it "warns only inside the warning threshold, and not once exhausted" do
      warning_starts_at = described_class::MAX_TURNS - described_class::TURNS_WARNING_THRESHOLD

      expect(described_class).not_to be_turns_warning(warning_starts_at - 1)
      expect(described_class).to be_turns_warning(warning_starts_at)
      expect(described_class).to be_turns_warning(described_class::MAX_TURNS - 1)
      expect(described_class).not_to be_turns_warning(described_class::MAX_TURNS)
    end
  end
end
