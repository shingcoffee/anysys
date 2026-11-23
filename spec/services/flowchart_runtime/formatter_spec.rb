# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Formatter do
  around { |example| I18n.with_locale(:en) { example.run } }

  def apply(value, **opts)
    described_class.apply(value, ctx: { locale: "en" }, **opts)
  end

  it "formats number, currency, percentage, delimited, human size and human number" do
    expect(apply(1234.5, format_type: "number", precision: 1)).to eq("1,234.5")
    expect(apply(12.5, format_type: "currency", currency_unit: "$")).to include("12.50")
    expect(apply(12.5, format_type: "percentage", precision: 0)).to include("13")
    expect(apply(1234, format_type: "delimited")).to eq("1,234")
    expect(apply(1024, format_type: "human_size")).to match(/KB/)
    expect(apply(1_500_000, format_type: "human_number")).to match(/Million|million/)
  end

  it "formats phone, date and datetime styles" do
    expect(apply("+14155552671", format_type: "phone", phone_style: "e164")).to eq("+14155552671")
    expect(apply(Date.new(2026, 1, 15), format_type: "date", date_style: "iso8601")).to eq("2026-01-15")
    expect(apply(Date.new(2026, 1, 15), format_type: "date", date_style: "custom", custom_format: "%d/%m/%Y"))
      .to eq("15/01/2026")
    stamp = Time.utc(2026, 1, 15, 12, 0, 0)
    expect(apply(stamp, format_type: "datetime", date_style: "iso8601", timezone: "UTC")).to include("2026-01-15")
  end

  it "returns the fallback when the source is nil or unparseable" do
    expect(apply(nil, fallback_value: "n/a")).to eq("n/a")
    expect(apply("nope", format_type: "date", fallback_value: "n/a")).to eq("n/a")
  end

  it "uses ctx locale when locale is blank" do
    text = described_class.apply(1_234, ctx: { locale: "en" }, format_type: "delimited", locale: "")
    expect(text).to eq("1,234")
  end

  it "raises Error for an unknown format type" do
    expect { apply(1, format_type: "widget") }.to raise_error(described_class::Error)
  end
end
