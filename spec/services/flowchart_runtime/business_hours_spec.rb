# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::BusinessHours do
  let(:schedule) { { "monday" => "09:00-17:00", "tuesday" => "09:00-17:00" } }

  describe ".open?" do
    it "reports open during a scheduled weekday window" do
      at = Time.utc(2026, 10, 19, 12, 0, 0) # Monday

      result = described_class.open?(schedule: schedule, at: at, timezone: "UTC")

      expect(result[:open]).to be(true)
      expect(result[:next_open_at]).to be_nil
    end

    it "reports closed on a holiday and returns the next open instant" do
      at = Time.utc(2026, 10, 19, 12, 0, 0)

      result = described_class.open?(
        schedule: schedule,
        at: at,
        timezone: "UTC",
        holidays: ["2026-10-19"]
      )

      expect(result[:open]).to be(false)
      expect(result[:next_open_at]).to eq(Time.utc(2026, 10, 20, 9, 0, 0))
    end

    it "returns the next weekday open when the current day has no hours" do
      at = Time.utc(2026, 10, 18, 12, 0, 0) # Sunday

      result = described_class.open?(schedule: schedule, at: at, timezone: "UTC")

      expect(result[:open]).to be(false)
      expect(result[:next_open_at]).to eq(Time.utc(2026, 10, 19, 9, 0, 0))
    end

    it "adds business minutes, wrapping into the next open window" do
      due = described_class.add_minutes(
        schedule: schedule,
        at: Time.utc(2026, 10, 19, 16, 30),
        timezone: "UTC",
        minutes: 60
      )

      expect(due).to eq(Time.utc(2026, 10, 20, 9, 30))
    end

    it "rejects an unknown timezone" do
      expect {
        described_class.open?(schedule: schedule, at: Time.utc(2026, 10, 19, 12), timezone: "Not/AZone")
      }.to raise_error(described_class::Error, /timezone/)
    end

    it "treats a lunch break as closed and returns the afternoon opening" do
      at = Time.utc(2026, 10, 19, 12, 30, 0)

      result = described_class.open?(
        schedule: { "monday" => "09:00-12:00,13:00-17:00" },
        at: at,
        timezone: "UTC"
      )

      expect(result[:open]).to be(false)
      expect(result[:next_open_at]).to eq(Time.utc(2026, 10, 19, 13, 0, 0))
      expect(result[:minutes_until_open]).to eq(30)
    end

    it "rejects overlapping windows" do
      expect(described_class.valid_windows?("09:00-12:00,11:00-17:00")).to be(false)
    end

    it "accepts a holiday hash and a string clock" do
      result = described_class.open?(
        schedule: schedule,
        at: "2026-10-19T12:00:00Z",
        timezone: "UTC",
        holidays: { "2026-10-19" => "Closed" }
      )

      expect(result[:open]).to be(false)
      expect(result[:next_open_at]).to eq(Time.utc(2026, 10, 20, 9, 0, 0))
    end
  end
end

