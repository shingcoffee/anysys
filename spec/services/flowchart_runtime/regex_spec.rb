# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Regex do
  it "returns the first capture for match" do
    expect(described_class.apply("invoice 123", pattern: "(\\d+)", operation: "match", capture_group: 1))
      .to eq("123")
  end

  it "tests and replaces" do
    expect(described_class.apply("Ada", pattern: "ada", operation: "test", flags: "i")).to be(true)
    expect(described_class.apply("aa bb", pattern: "\\s+", operation: "replace", replacement: "-")).to eq("aa-bb")
  end

  it "compiles with a timeout option" do
    regex = described_class.compile("a+")
    expect(regex).to be_a(Regexp)
  end

  it "raises Error for an invalid pattern" do
    expect { described_class.compile("[") }.to raise_error(described_class::Error)
  end
end
