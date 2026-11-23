# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Text do
  it "strips, splits, joins, and applies Base64 operations" do
    expect(described_class.apply("  hi  ", operation: "strip")).to eq("hi")
    expect(described_class.apply("a,b", operation: "split", delimiter: ",")).to eq(%w[a b])
    expect(described_class.apply(%w[a b], operation: "join", delimiter: "-")).to eq("a-b")
    encoded = described_class.apply("hello", operation: "base64_encode")
    expect(encoded).to eq("aGVsbG8=")
    expect(described_class.apply(encoded, operation: "base64_decode")).to eq("hello")
  end

  it "raises Error for an unknown operation" do
    expect { described_class.apply("x", operation: "nope") }.to raise_error(described_class::Error)
  end

  it "squishes, titleizes, parameterizes, and masks the middle" do
    expect(described_class.apply("  a   b  ", operation: "squish")).to eq("a b")
    expect(described_class.apply("hello world", operation: "titleize")).to eq("Hello World")
    expect(described_class.apply("Hello World", operation: "parameterize")).to eq("hello-world")
    expect(described_class.apply("123456", operation: "mask_middle", length: 1, pad_char: "*")).to eq("1****6")
  end
end
