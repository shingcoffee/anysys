# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Currency do
  let(:ctx) { { customer_id: 49, errors: [] } }

  it "multiplies by a fixed rate and serializes a decimal string" do
    expect(described_class.convert(ctx, amount: 10, from: "USD", to: "EUR", rate_source: "fixed", fixed_rate: 0.5))
      .to eq("5.00")
  end

  it "returns the original amount when the rate is missing and on_missing_rate is identity" do
    expect(described_class.convert(ctx, amount: 10, from: "USD", to: "EUR", rate_source: "config",
                                        static_rates: { "GBP" => 0.5 }, on_missing_rate: "identity"))
      .to eq("10.00")
  end

  it "uses a ctx table target rate" do
    expect(described_class.convert(ctx, amount: 10, from: "USD", to: "EUR", rate_source: "ctx",
                                        rates: { "EUR" => "0.8" }))
      .to eq("8.00")
  end

  it "uses a cross rate when both currencies are in the table" do
    expect(described_class.convert(ctx, amount: 10, from: "USD", to: "EUR", rate_source: "ctx",
                                        rates: { "USD" => "1", "EUR" => "0.5" }))
      .to eq("5.00")
  end

  it "uses a pair key" do
    expect(described_class.convert(ctx, amount: 10, from: "USD", to: "EUR", rate_source: "config",
                                        static_rates: { "USD_EUR" => "0.25" }))
      .to eq("2.50")
  end

  it "returns the rounded amount when from and to are the same" do
    expect(described_class.convert(ctx, amount: "10.126", from: "USD", to: "USD", rate_source: "fixed",
                                        fixed_rate: 99))
      .to eq("10.13")
  end

  it "does not fetch an external URL" do
    expect(described_class::RATE_SOURCES).not_to include("external")
    expect { described_class.convert(ctx, amount: 10, from: "USD", to: "EUR", rate_source: "external") }
      .to raise_error(described_class::Error, /unsupported rate source/)
  end
end
