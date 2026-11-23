# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::Shared::RubyLiteral do
  describe ".emit" do
    it "emits scalars the way Ruby would write them" do
      expect(described_class.emit("a \"quoted\" value")).to eq('"a \"quoted\" value"')
      expect(described_class.emit(:status)).to eq(":status")
      expect(described_class.emit(42)).to eq("42")
      expect(described_class.emit(1.5)).to eq("1.5")
      expect(described_class.emit(nil)).to eq("nil")
      expect(described_class.emit(true)).to eq("true")
      expect(described_class.emit(BigDecimal("12.50"))).to eq("12.5")
    end

    it "uses symbol-key shorthand only for plain symbol keys" do
      expect(described_class.emit({ status: "paid", "total-due": 1 })).to eq('{status: "paid", :"total-due" => 1}')
      expect(described_class.emit({ "status" => "paid" })).to eq('{"status" => "paid"}')
      expect(described_class.emit({ 1 => :one })).to eq("{1 => :one}")
      expect(described_class.emit({})).to eq("{}")
    end

    it "nests arrays and hashes" do
      expect(described_class.emit([1, ["a"], { "k" => [nil] }])).to eq('[1, ["a"], {"k" => [nil]}]')
      expect(described_class.emit([])).to eq("[]")
    end

    it "round-trips through eval" do
      value = { "conditions" => [{ "field" => "x) || system('id'", "value" => [1, 2.5, nil] }], mode: :all }
      expect(eval(described_class.emit(value))).to eq(value) # rubocop:disable Security/Eval
    end
  end
end
