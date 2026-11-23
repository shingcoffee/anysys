# frozen_string_literal: true
require "rails_helper"

RSpec.describe Billing::Activities::UpdateSettings do
  it "preserves invalid raw text without mutating the persisted policy" do
    settings = Billing::Settings.current
    result = described_class.call(settings: settings, params: { dunning_schedule: "1,soon,7", tax_rate_bps: "bad" })
    expect(result.status).to eq(:invalid)
    expect(result.form.dunning_schedule).to eq("1,soon,7")
    expect(settings.reload.dunning_schedule).to eq([1, 3, 7])
    expect(settings.tax_rate_bps).to eq(0)
  end

  it "persists explicitly empty retries" do
    settings = Billing::Settings.current
    result = described_class.call(settings: settings, params: { dunning_schedule: "" })
    expect(result.status).to eq(:saved)
    expect(settings.reload.dunning_offsets).to eq([])
  end
end
