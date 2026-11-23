# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::FilePayload do
  it "wraps bytes into the canonical filename/content/content_type hash" do
    payload = described_class.wrap("a,b\n", filename: "orders.csv", content_type: "text/csv")
    expect(payload).to eq(
      "filename" => "orders.csv",
      "content" => "a,b\n",
      "content_type" => "text/csv"
    )
  end

  it "strips directory components from the filename" do
    payload = described_class.wrap("x", filename: "../secret.txt")
    expect(payload["filename"]).to eq("secret.txt")
  end

  it "extracts bytes from a payload hash or a raw string" do
    expect(described_class.bytes("raw")).to eq("raw")
    expect(described_class.bytes({ "content" => "from-hash", "filename" => "a.txt" })).to eq("from-hash")
  end
end
