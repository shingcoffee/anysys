# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Serialize do
  it "serializes json yaml xml csv and toml" do
    data = { "count" => 2 }
    expect(described_class.apply(data, format: "json")).to eq('{"count":2}')
    expect(described_class.apply(data, format: "yaml")).to include("count: 2")
    expect(described_class.apply(data, format: "xml")).to include("<count")
    expect(described_class.apply([{ "count" => 2 }], format: "csv")).to include("count")
    expect(described_class.apply(data, format: "toml")).to include("count")
  end

  it "raises Error for msgpack which is no longer supported" do
    expect { described_class.apply({}, format: "msgpack") }.to raise_error(described_class::Error)
  end
end
