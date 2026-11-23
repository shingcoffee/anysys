# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ConditionOperators do
  it "classifies unary and binary operators" do
    expect(described_class.unary?("is_empty")).to be(true)
    expect(described_class.unary?("==")).to be(false)
    expect(described_class.known?("contains")).to be(true)
    expect(described_class.known?("")).to be(false)
    expect(described_class.known?("drop table")).to be(false)
  end

  it "covers every operator the condition builder compiles" do
    builder = Class.new { include CodeGenerators::Shared::ConditionBuilder }.new
    described_class::KEYS.each do |operator|
      row = { "leftOperand" => "ctx.a", "operator" => operator, "rightOperand" => "1" }
      expect(builder.send(:build_single_condition, row)).to be_a(String)
    end
  end

  it "exports translated labels in both locales" do
    en = described_class.export(locale: :en)
    zh = described_class.export(locale: :"zh-CN")

    expect(en.map { |op| op["value"] }).to eq(described_class::KEYS)
    expect(en.find { |op| op["value"] == "is_true" }).to eq("value" => "is_true", "label" => "is true", "unary" => true, "count" => false)
    expect(en.select { |op| op["count"] }.map { |op| op["value"] }).to eq(described_class::COUNT)
    expect(zh.find { |op| op["value"] == "==" }["label"]).to eq("等于")
    expect(zh.map { |op| op["label"] }).to all(match(/\p{Han}/))
  end
end
