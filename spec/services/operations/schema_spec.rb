# frozen_string_literal: true

require "rails_helper"

RSpec.describe Operations::Schema do
  let_it_be(:customer) { create(:customer) }
  let(:context) { Operations::Context.new(customer: customer, channel: "assistant") }

  def schema_for(klass)
    described_class.new(klass, context: context)
  end

  def validate(klass, input)
    schema_for(klass).validate(input)
  end

  after { described_class.reset_cache! }

  describe "resolution" do
    it "sets $id and $schema and merges shared $defs" do
      document = schema_for(Operations::FakeEcho).document

      expect(document["$id"]).to eq("urn:anysys:operation:fake_echo:v1")
      expect(document["$schema"]).to eq("https://json-schema.org/draft/2020-12/schema")
      expect(document.dig("$defs", "label", "type")).to eq("string")
    end

    it "resolves vocabulary enums, nullable null, and maximum slots" do
      document = schema_for(Operations::FakeVocab).document

      expect(document.dig("properties", "color", "enum")).to include("red", "blue", "tenant-#{customer.id}")
      expect(document.dig("properties", "color", "x-enum-descriptions")).to include("red" => "The red option.")
      expect(document.dig("properties", "optional_color", "enum")).to include("red", nil)
      expect(document.dig("properties", "limit", "maximum")).to eq(5)
    end

    it "raises ArgumentError for an unknown vocabulary slot" do
      allow_any_instance_of(described_class).to receive(:load_json).and_return(
        "type" => "object",
        "properties" => { "color" => { "x-vocabulary" => "missing" } }
      )

      expect { schema_for(Operations::FakeVocab).document }.to raise_error(ArgumentError, /unknown vocabulary/)
    end

    it "resolves tenant-dependent slots per context" do
      first = schema_for(Operations::FakeVocab).document

      other = create(:customer)
      other_context = Operations::Context.new(customer: other, channel: "assistant")
      other_document = described_class.new(Operations::FakeVocab, context: other_context).document
      expect(other_document.dig("properties", "color", "enum")).to include("tenant-#{other.id}")
      expect(first.dig("properties", "color", "enum")).not_to include("tenant-#{other.id}")
    end

    it "picks up an edited schema file without a restart" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "edited.json")
        File.write(path, JSON.generate("type" => "object", "description" => "Before."))
        operation = Class.new(Operations::FakeEcho) { schema path }
        expect(described_class.new(operation, context: context).document["description"]).to eq("Before.")

        File.write(path, JSON.generate("type" => "object", "description" => "After."))
        later = Time.now + 5
        File.utime(later, later, path)
        expect(described_class.new(operation, context: context).document["description"]).to eq("After.")
      end
    end
  end

  describe "#validate" do
    it "inserts defaults on a copy and leaves the original untouched" do
      input = { "name" => "Alpha" }
      violations, normalized = validate(Operations::FakeEcho, input)

      expect(violations).to be_empty
      expect(normalized).to include("name" => "Alpha", "color" => "red", "count" => 1)
      expect(input).to eq("name" => "Alpha")
    end

    it "maps required, enum, type, and unknown properties with candidates" do
      violations, = validate(Operations::FakeEcho, { "color" => "green", "count" => "x", "hue" => 1 })
      by_code = violations.index_by(&:code)

      expect(by_code["schema.required"].pointer).to eq("/name")
      expect(by_code["schema.required"].details).to include("property" => "name")
      expect(by_code["schema.enum"].details["allowed"]).to include("red", "blue")
      expect(by_code["schema.type"].details["expected"]).to eq("integer")
      expect(by_code["schema.unknown_property"].pointer).to eq("/hue")
      expect(by_code["schema.unknown_property"].details["candidates"]).to be_an(Array)
    end

    it "maps pattern, format, length, items, bounds, and uniqueItems" do
      violations, = validate(Operations::FakeKeywords, {
        "token" => "AB",
        "host" => "not a host",
        "tags" => %w[a a a a],
        "size" => 1
      })
      codes = violations.map(&:code)

      expect(codes).to include(
        "schema.min_length", "schema.pattern", "schema.format",
        "schema.max_items", "schema.unique_items", "schema.minimum"
      )
    end

    it "reports the deepest anyOf error instead of the wrapper" do
      violations, = validate(Operations::FakeNested, { "payload" => { "kind" => "number", "n" => "nope" } })

      expect(violations.map(&:code)).not_to include("schema.invalid")
      expect(violations).to include(
        have_attributes(pointer: "/payload/n", code: "schema.type")
      )
    end

    it "reports the deepest if-then error instead of the wrapper" do
      violations, = validate(Operations::FakeNested, {
        "payload" => { "kind" => "number", "n" => 1 },
        "mode" => "numbered",
        "count" => "x"
      })

      expect(violations).to include(have_attributes(pointer: "/count", code: "schema.type"))
    end

    it "de-duplicates by pointer and code and caps at 25" do
      schema = { "type" => "object", "additionalProperties" => false, "properties" => {} }
      allow_any_instance_of(described_class).to receive(:document).and_return(schema)
      extras = (1..30).to_h { |i| ["k#{i}", i] }
      violations, = described_class.new(Operations::FakeEcho, context: context).validate(extras)

      expect(violations.size).to eq(25)
      expect(violations.map { |item| [item.pointer, item.code] }.uniq.size).to eq(25)
    end
  end
end
