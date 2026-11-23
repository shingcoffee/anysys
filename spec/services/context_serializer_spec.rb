# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContextSerializer do
  let(:customer) { create(:customer) }

  describe ".serialize" do
    it "passes through scalar values unchanged" do
      expect(described_class.serialize(42)).to eq(42)
      expect(described_class.serialize("hello")).to eq("hello")
      expect(described_class.serialize(3.14)).to eq(3.14)
      expect(described_class.serialize(nil)).to be_nil
      expect(described_class.serialize(true)).to be(true)
    end

    it "converts a Symbol to its string representation" do
      expect(described_class.serialize(:my_key)).to eq("my_key")
    end

    it "recursively serializes Hash values" do
      input  = { a: :symbol_val, b: 1 }
      result = described_class.serialize(input)
      expect(result[:a]).to eq("symbol_val")
      expect(result[:b]).to eq(1)
    end

    it "recursively serializes Array elements" do
      result = described_class.serialize([:foo, 42, :bar])
      expect(result).to eq(["foo", 42, "bar"])
    end

    it "serializes an ActiveRecord record" do
      result = described_class.serialize(customer)
      expect(result[:_type]).to eq("Customer")
      expect(result[:id]).to eq(customer.id)
      expect(result[:attributes]).to be_a(Hash)
      expect(result[:attributes]).to have_key("name")
    end

    it "excludes sensitive AR columns (activity, configuration, property_schema, data)" do
      result = described_class.serialize(customer)
      %w[activity configuration property_schema data].each do |col|
        expect(result[:attributes]).not_to have_key(col)
      end
    end

    it "serializes a Class" do
      result = described_class.serialize(String)
      expect(result).to eq({ _type: "Class", name: "String" })
    end

    it "serializes a Proc" do
      p = proc { 42 }
      result = described_class.serialize(p)
      expect(result[:_type]).to eq("Proc")
      expect(result[:source]).to be_a(String)
    end

    it "serializes a Method" do
      m = 42.method(:to_s)
      result = described_class.serialize(m)
      expect(result[:_type]).to eq("Method")
      expect(result[:source]).to be_a(String)
    end

    it "serializes a nested Hash-within-Array structure" do
      result = described_class.serialize([{ key: :val }])
      expect(result).to eq([{ key: "val" }])
    end

    it "serializes an ActionDispatch::Request" do
      request = ActionDispatch::Request.new(
        "REQUEST_METHOD" => "GET",
        "PATH_INFO"      => "/some/path",
        "SERVER_NAME"    => "localhost",
        "SERVER_PORT"    => "80"
      )
      result = described_class.serialize(request)
      expect(result[:_type]).to eq("Request")
      expect(result[:method]).to eq("GET")
      expect(result[:path]).to eq("/some/path")
    end
  end
end
