# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::Violation do
  it "defaults resolution by code namespace" do
    expect(described_class.new(code: "permission.denied").resolution).to eq("blocked")
    expect(described_class.new(code: "quota.exceeded").resolution).to eq("blocked")
    expect(described_class.new(code: "conflict.version_changed").resolution).to eq("refresh")
    expect(described_class.new(code: "schema.enum").resolution).to eq("fix_payload")
  end

  it "interpolates scalar details and joins arrays" do
    violation = described_class.new(code: "schema.enum", details: { allowed: %w[red blue] })

    expect(violation.message).to eq("Value must be one of: red, blue.")
  end

  it "appends suggestions only when there are candidates" do
    with = described_class.new(code: "schema.unknown_property", details: { "candidates" => %w[name label] })
    without = described_class.new(code: "schema.unknown_property", details: { "candidates" => [] })

    expect(with.message).to eq("Unknown property. Did you mean: name, label?")
    expect(without.message).to eq("Unknown property.")
    I18n.with_locale(:"zh-CN") do
      expect(with.message).to eq("未知属性。你是不是指：name, label？")
    end
  end

  it "falls back to the generic message for an unknown code" do
    expect(described_class.new(code: "no.such.code").message).to include("no.such.code")
  end

  it "merges JSON-safe details into as_json" do
    json = described_class.new(pointer: "/name", code: "schema.required", details: { property: "name" }).as_json

    expect(json).to include(
      "pointer" => "/name",
      "code" => "schema.required",
      "resolution" => "fix_payload",
      "property" => "name"
    )
    expect(json["message"]).to eq("Missing required property name.")
  end

  it "suggests case-insensitive exact matches first, then DidYouMean candidates" do
    expect(described_class.candidates("Name", %w[name title])).to eq(["name"])
    expect(described_class.candidates("colour", %w[color count])).to include("color")
  end
end
