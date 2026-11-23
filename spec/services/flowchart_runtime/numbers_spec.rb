# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Numbers do
  it "adds, divides, and applies unary ops with BigDecimal" do
    expect(described_class.apply(7, operation: "add", other: 2)).to eq(BigDecimal("9"))
    expect(described_class.apply(-4, operation: "abs")).to eq(BigDecimal("4"))
    expect(described_class.apply(9, operation: "sqrt")).to eq(BigDecimal("3"))
  end

  it "adds decimal amounts without binary float error" do
    expect(described_class.apply("0.1", operation: "add", other: "0.2")).to eq(BigDecimal("0.3"))
  end

  it "honors divide-by-zero policies" do
    expect(described_class.apply(1, operation: "divide", other: 0, divide_by_zero: "nil")).to be_nil
    expect(described_class.apply(1, operation: "divide", other: 0, divide_by_zero: "zero")).to eq(0)
    expect { described_class.apply(1, operation: "divide", other: 0, divide_by_zero: "raise") }
      .to raise_error(described_class::Error)
  end

  it "computes percent, clamps, and rounds" do
    expect(described_class.apply(25, operation: "percent", other: 200)).to eq(BigDecimal("12.5"))
    expect(described_class.apply(15, operation: "clamp", min_value: 0, max_value: 10)).to eq(BigDecimal("10"))
    expect(described_class.apply(5, operation: "divide", other: 2, precision: 0, rounding_mode: "floor")).to eq(2)
  end
end
