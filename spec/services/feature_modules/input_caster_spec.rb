# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeatureModules::InputCaster do
  def field(name, type, validates = {})
    FeatureModules::HandoffField.new(name: name, type: type, validates: validates)
  end

  let(:fields) do
    [
      field("amount_cents", "integer"),
      field("ratio",        "number"),
      field("flag",         "boolean"),
      field("currency",     "enum", { inclusion: { in: %w[CNY USD] } }),
      field("subject",      "string")
    ]
  end

  def cast(input)
    described_class.call(input: input, fields: fields)
  end

  it "coerces integer strings and passes through uncoercible values for the contract to reject" do
    expect(cast(amount_cents: "500")[:amount_cents]).to eq(500)
    expect(cast(amount_cents: 500)[:amount_cents]).to eq(500)
    expect(cast(amount_cents: " 42 ")[:amount_cents]).to eq(42)
    expect(cast(amount_cents: "5.5")[:amount_cents]).to eq("5.5")   # not an integer -> passthrough
    expect(cast(amount_cents: "abc")[:amount_cents]).to eq("abc")
  end

  it "coerces number strings" do
    expect(cast(ratio: "1.5")[:ratio]).to eq(1.5)
    expect(cast(ratio: "nope")[:ratio]).to eq("nope")
  end

  it "coerces boolean-ish strings" do
    expect(cast(flag: "true")[:flag]).to be(true)
    expect(cast(flag: "0")[:flag]).to be(false)
    expect(cast(flag: "maybe")[:flag]).to eq("maybe")
    expect(cast(flag: true)[:flag]).to be(true)
  end

  it "case-normalizes an enum to its canonical allowed value, else passes through" do
    expect(cast(currency: "cny")[:currency]).to eq("CNY")
    expect(cast(currency: "Usd")[:currency]).to eq("USD")
    expect(cast(currency: "eur")[:currency]).to eq("eur") # not allowed -> passthrough (contract rejects)
  end

  it "case-normalizes any field with an inclusion set, even one declared as a non-enum type" do
    tier = [field("tier", "string", { inclusion: { in: %w[GOLD SILVER] } })]
    expect(described_class.call(input: { tier: "gold" }, fields: tier)[:tier]).to eq("GOLD")
  end

  it "turns blank strings into nil so presence validation fires" do
    expect(cast(subject: "")[:subject]).to be_nil
    expect(cast(subject: "   ")[:subject]).to be_nil
    expect(cast(amount_cents: "")[:amount_cents]).to be_nil
  end

  it "passes values through unchanged for fields not in the contract" do
    out = cast(unknown: "x", subject: "hello")
    expect(out[:unknown]).to eq("x")
    expect(out[:subject]).to eq("hello")
  end

  it "handles nil/empty input and nil fields" do
    expect(described_class.call(input: nil, fields: fields)).to eq({})
    expect(described_class.call(input: { amount_cents: "5" }, fields: nil)).to eq(amount_cents: "5")
  end

  it "leaves untyped/datetime/hash fields untouched" do
    dt = [field("expires_at", "datetime"), field("metadata", "hash")]
    out = described_class.call(input: { expires_at: "2026-01-01", metadata: { a: 1 } }, fields: dt)
    expect(out[:expires_at]).to eq("2026-01-01")
    expect(out[:metadata]).to eq(a: 1)
  end
end
