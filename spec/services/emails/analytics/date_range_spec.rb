# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::Analytics::DateRange do
  describe ".clamp" do
    it "leaves a short in-range window unchanged" do
      travel_to Time.zone.local(2023, 10, 15, 12, 0, 0) do
        since = 5.days.ago.beginning_of_day
        until_date = Time.current.end_of_day

        clamped_since, clamped_until = described_class.clamp(since, until_date)

        expect(clamped_since).to eq(since)
        expect(clamped_until).to eq(until_date)
      end
    end

    it "caps a millennia-wide since/until pair so daily series cannot allocate every calendar day" do
      travel_to Time.zone.local(2023, 10, 15, 12, 0, 0) do
        clamped_since, clamped_until = described_class.clamp(Date.new(1, 1, 1), Date.new(9999, 12, 31))

        expect(clamped_until.to_date).to eq(Date.current)
        expect((clamped_until.to_date - clamped_since.to_date).to_i).to eq(described_class::MAX_SPAN_DAYS)
      end
    end

    it "swaps an inverted window before capping" do
      travel_to Time.zone.local(2023, 10, 15, 12, 0, 0) do
        clamped_since, clamped_until = described_class.clamp(
          Time.zone.local(2023, 10, 14).beginning_of_day,
          Time.zone.local(2023, 10, 10).end_of_day
        )

        expect(clamped_since.to_date).to eq(Date.new(2023, 10, 10))
        expect(clamped_until.to_date).to eq(Date.new(2023, 10, 14))
      end
    end
  end
end
