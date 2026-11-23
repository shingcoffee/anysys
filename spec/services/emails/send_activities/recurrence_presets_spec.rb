# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivities::RecurrencePresets do
  describe ".rrule_for" do
    it "maps presets to RRULE values" do
      expect(described_class.rrule_for("none")).to be_nil
      expect(described_class.rrule_for("daily")).to eq("FREQ=DAILY;INTERVAL=1")
      expect(described_class.rrule_for("weekly")).to eq("FREQ=WEEKLY;INTERVAL=1")
      expect(described_class.rrule_for("monthly")).to eq("FREQ=MONTHLY;INTERVAL=1")
    end
  end

  describe ".preset_for" do
    it "maps RRULE values back to presets" do
      expect(described_class.preset_for("FREQ=WEEKLY;INTERVAL=1")).to eq("weekly")
      expect(described_class.preset_for(nil)).to eq("none")
    end
  end
end
