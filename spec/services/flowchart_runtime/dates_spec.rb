# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Dates do
  around { |example| Time.use_zone("UTC") { example.run } }

  it "returns now, adds days, formats, and converts timezones" do
    travel_to Time.utc(2026, 4, 19, 12, 30) do
      expect(described_class.apply(nil, operation: "now", output_format: "iso8601"))
        .to eq("2026-04-19T12:30:00Z")
    end

    start = Time.utc(2026, 4, 19)
    expect(described_class.apply(start, operation: "add", amount: 2, unit: "days").to_date)
      .to eq(Date.new(2026, 4, 21))
    expect(described_class.apply(start, operation: "format", format_string: "%Y-%m-%d")).to eq("2026-04-19")
    converted = described_class.apply(
      "2026-04-19 12:00:00",
      operation: "convert_timezone",
      source_timezone: "UTC",
      target_timezone: "America/New_York",
      output_format: "iso8601"
    )
    expect(converted).to include("2026-04-19T08:00:00")
  end

  it "computes start_of, end_of, difference in hours, age, and compare" do
    stamp = Time.utc(2026, 4, 19, 15, 30)
    expect(described_class.apply(stamp, operation: "start_of", unit: "days")).to eq(stamp.beginning_of_day)
    expect(described_class.apply(stamp, operation: "end_of", unit: "days")).to eq(stamp.end_of_day)
    expect(described_class.apply(stamp, operation: "difference", end_value: stamp + 3.hours, unit: "hours")).to eq(3)
    travel_to Time.utc(2026, 4, 19) do
      expect(described_class.apply(Date.new(2000, 4, 19), operation: "age")).to eq(26)
    end
    expect(described_class.apply(stamp, operation: "compare", end_value: stamp + 1.day)).to eq(-1)
  end

  it "skips weekends when adding business days" do
    friday = Time.utc(2026, 4, 17, 12) # Friday
    expect(described_class.apply(friday, operation: "add", amount: 1, unit: "days", business_days: true).to_date)
      .to eq(Date.new(2026, 4, 20))
  end

  it "raises Error for an invalid timezone" do
    expect {
      described_class.apply("2026-01-01", operation: "convert_timezone", target_timezone: "Not/AZone")
    }.to raise_error(described_class::Error)
  end
end
