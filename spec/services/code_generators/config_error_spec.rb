# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ConfigError do
  it "exposes field, code, and message" do
    error = described_class.new(field: "sourceVariable", code: :required, message: "sourceVariable is required")
    expect(error.field).to eq("sourceVariable")
    expect(error.code).to eq(:required)
    expect(error.message).to eq("sourceVariable is required")
  end

  it "stringifies as the message" do
    error = described_class.new(field: "x", code: :required, message: "x is required")
    expect(error.to_s).to eq("x is required")
    expect("#{error}").to eq("x is required")
  end
end
