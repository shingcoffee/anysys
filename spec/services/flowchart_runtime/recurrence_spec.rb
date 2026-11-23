# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Recurrence do
  around { |example| Time.use_zone("UTC") { example.run } }

  def next_at(**opts)
    described_class.next_occurrences(frequency: "monthly", **opts)
  end

  it "returns the next monthly occurrence after now" do
    travel_to Time.utc(2026, 1, 15, 12) do
      result = next_at
      expect(result[:error]).to be_nil
      expect(result[:value]).to eq(Time.utc(2026, 2, 15, 12))
    end
  end

  it "advances daily, weekly, yearly and cron series" do
    origin = Time.utc(2026, 1, 15, 12)
    after = origin
    expect(next_at(frequency: "daily", start_at: origin, from: after)[:value]).to eq(Time.utc(2026, 1, 16, 12))
    expect(next_at(frequency: "weekly", start_at: origin, from: after)[:value]).to eq(Time.utc(2026, 1, 22, 12))
    expect(next_at(frequency: "yearly", start_at: origin, from: after)[:value]).to eq(Time.utc(2027, 1, 15, 12))
    cron = next_at(frequency: "cron", cron_expression: "0 9 * * *", from: after, start_at: origin)
    expect(cron[:value]).to eq(Time.utc(2026, 1, 16, 9))
  end

  it "finds the next occurrence for an anchor far in the past" do
    origin = Time.utc(2019, 3, 4, 8)
    after = Time.utc(2026, 11, 16, 12)
    expect(next_at(frequency: "daily", start_at: origin, from: after)[:value]).to eq(Time.utc(2026, 11, 17, 8))
    expect(next_at(frequency: "weekly", start_at: origin, from: after, weekdays: %w[mon thu])[:value])
      .to eq(Time.utc(2026, 11, 19, 8))
    expect(next_at(frequency: "monthly", start_at: origin, from: after)[:value]).to eq(Time.utc(2026, 12, 4, 8))
    expect(next_at(frequency: "yearly", start_at: origin, from: after)[:value]).to eq(Time.utc(2027, 3, 4, 8))
  end

  it "keeps a business-day-adjusted list strictly increasing without duplicates" do
    origin = Time.utc(2026, 1, 9, 9)
    result = next_at(frequency: "daily", start_at: origin, from: origin - 1.minute, returns: "list", count: 4,
                     business_day_adjust: "next_business_day")
    expect(result[:value]).to eq([Time.utc(2026, 1, 9, 9), Time.utc(2026, 1, 12, 9), Time.utc(2026, 1, 13, 9),
                                  Time.utc(2026, 1, 14, 9)])
  end

  it "clamps or skips an impossible day of month" do
    origin = Time.utc(2026, 1, 31, 12)
    clamped = next_at(start_at: origin, from: origin, day_of_month: 31, month_end_policy: "clamp")
    expect(clamped[:value].to_date).to eq(Date.new(2026, 2, 28))
    skipped = next_at(start_at: origin, from: origin, day_of_month: 31, month_end_policy: "skip")
    expect(skipped[:value].to_date).to eq(Date.new(2026, 3, 31))
  end

  it "returns a list, applies time of day, and shifts weekends" do
    origin = Time.utc(2026, 1, 15, 12)
    listed = next_at(frequency: "daily", start_at: origin, from: origin, returns: "list", count: 3)
    expect(listed[:value].map { |time| time.to_date }).to eq([
      Date.new(2026, 1, 16), Date.new(2026, 1, 17), Date.new(2026, 1, 18)
    ])
    timed = next_at(frequency: "daily", start_at: origin, from: origin, time_of_day: "09:30")
    expect(timed[:value]).to eq(Time.utc(2026, 1, 16, 9, 30))
    weekend = Time.utc(2026, 1, 17, 12) # Saturday
    shifted = next_at(frequency: "daily", start_at: weekend - 1.day, from: weekend - 1.day,
                      business_day_adjust: "next_business_day")
    expect(shifted[:value].to_date).to eq(Date.new(2026, 1, 19))
  end

  it "returns invalid_anchor and no_occurrence" do
    expect(next_at(start_at: "not-a-time")[:error]).to eq(:invalid_anchor)
    origin = Time.utc(2026, 1, 15, 12)
    none = next_at(start_at: origin, from: origin, until_at: origin + 1.hour)
    expect(none[:error]).to eq(:no_occurrence)
  end
end
