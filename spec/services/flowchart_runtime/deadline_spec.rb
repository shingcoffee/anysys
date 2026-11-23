# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Deadline do
  describe ".check" do
    it "reports a future deadline as not breached" do
      result = described_class.check(
        deadline: Time.utc(2026, 10, 20, 12),
        reference: Time.utc(2026, 10, 19, 12)
      )

      expect(result[:breached]).to be(false)
      expect(result[:status][:passed]).to be(false)
      expect(result[:status][:remaining_seconds]).to eq(86_400.0)
    end

    it "reports a past deadline as breached" do
      result = described_class.check(
        deadline: Time.utc(2026, 10, 18, 12),
        reference: Time.utc(2026, 10, 19, 12)
      )

      expect(result[:breached]).to be(true)
      expect(result[:status][:passed]).to be(true)
      expect(result[:status][:overdue_seconds]).to eq(86_400.0)
    end

    it "honours a grace period" do
      result = described_class.check(
        deadline: Time.utc(2026, 10, 19, 11, 59),
        reference: Time.utc(2026, 10, 19, 12),
        grace_seconds: 120
      )

      expect(result[:breached]).to be(false)
    end

    it "marks at-risk when remaining time is within the warning window" do
      result = described_class.check(
        deadline: Time.utc(2026, 10, 19, 12, 2),
        reference: Time.utc(2026, 10, 19, 12),
        warning_seconds: 300
      )

      expect(result[:breached]).to be(false)
      expect(result[:at_risk]).to be(true)
    end

    it "is not at-risk when warning_seconds is zero" do
      result = described_class.check(
        deadline: Time.utc(2026, 10, 19, 12, 2),
        reference: Time.utc(2026, 10, 19, 12),
        warning_seconds: 0
      )

      expect(result[:at_risk]).to be(false)
    end

    it "parses an iso8601 string" do
      result = described_class.check(
        deadline: "2026-10-20T12:00:00Z",
        format: "iso8601",
        reference: Time.utc(2026, 10, 19, 12)
      )

      expect(result[:breached]).to be(false)
    end

    it "rejects an invalid deadline" do
      expect {
        described_class.check(deadline: "not-a-time", reference: Time.utc(2026, 10, 19))
      }.to raise_error(described_class::Error, /deadline/)
    end
  end
end
