# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivities::RecurrenceRule do
  describe ".parse" do
    it "returns nil for a blank rule" do
      expect(described_class.parse(nil)).to be_nil
      expect(described_class.parse("")).to be_nil
    end

    it "parses each supported FREQ" do
      %w[DAILY WEEKLY MONTHLY HOURLY].each do |freq|
        expect(described_class.parse("FREQ=#{freq}")).to eq("FREQ" => freq)
      end
    end

    it "parses INTERVAL, COUNT, and UNTIL alongside FREQ" do
      parts = described_class.parse("FREQ=WEEKLY;INTERVAL=2;COUNT=5;UNTIL=20261231")
      expect(parts).to eq("FREQ" => "WEEKLY", "INTERVAL" => "2", "COUNT" => "5", "UNTIL" => "20261231")
    end

    it "raises Invalid for an unsupported FREQ" do
      expect { described_class.parse("FREQ=YEARLY") }.to raise_error(described_class::Invalid)
    end

    it "raises Invalid when FREQ is missing" do
      expect { described_class.parse("INTERVAL=1") }.to raise_error(described_class::Invalid)
    end

    it "raises Invalid for an unsupported part (e.g. BYDAY)" do
      expect { described_class.parse("FREQ=WEEKLY;BYDAY=MO") }.to raise_error(described_class::Invalid)
    end

    it "raises Invalid for a non-positive INTERVAL" do
      expect { described_class.parse("FREQ=DAILY;INTERVAL=0") }.to raise_error(described_class::Invalid)
      expect { described_class.parse("FREQ=DAILY;INTERVAL=-1") }.to raise_error(described_class::Invalid)
    end

    it "raises Invalid for a non-positive COUNT" do
      expect { described_class.parse("FREQ=DAILY;COUNT=0") }.to raise_error(described_class::Invalid)
    end

    it "raises Invalid for an unparseable UNTIL" do
      expect { described_class.parse("FREQ=DAILY;UNTIL=not-a-date") }.to raise_error(described_class::Invalid)
    end
  end

  describe ".valid?" do
    it "is true for a well-formed rule" do
      expect(described_class.valid?("FREQ=DAILY;INTERVAL=1")).to be true
    end

    it "is false for a malformed rule" do
      expect(described_class.valid?("FREQ=YEARLY")).to be false
    end

    it "is true for a blank rule (nothing to validate)" do
      expect(described_class.valid?(nil)).to be true
    end
  end

  describe ".parse_until" do
    it "interprets a date-only UNTIL as end-of-day in the given zone" do
      until_at = described_class.parse_until("20261231", zone: "America/New_York")
      expect(until_at.zone).to eq("EST")
      expect(until_at).to eq(ActiveSupport::TimeZone["America/New_York"].parse("20261231").end_of_day)
    end

    it "parses a full UTC date-time UNTIL" do
      until_at = described_class.parse_until("20261231T093000Z", zone: "America/New_York")
      expect(until_at).to eq(Time.utc(2026, 12, 31, 9, 30, 0))
    end

    it "returns nil for a garbage UNTIL" do
      expect(described_class.parse_until("garbage")).to be_nil
    end
  end

  describe ".with_count" do
    it "rewrites only the COUNT part, preserving order and other parts" do
      rewritten = described_class.with_count("FREQ=WEEKLY;COUNT=5;INTERVAL=2", 4)
      expect(rewritten).to eq("FREQ=WEEKLY;COUNT=4;INTERVAL=2")
    end

    it "is a no-op when the rule has no COUNT" do
      rewritten = described_class.with_count("FREQ=DAILY;INTERVAL=1", 4)
      expect(rewritten).to eq("FREQ=DAILY;INTERVAL=1")
    end
  end
end
