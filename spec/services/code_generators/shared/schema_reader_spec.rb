# spec/services/code_generators/shared/schema_reader_spec.rb
require "rails_helper"

RSpec.describe CodeGenerators::Shared::SchemaReader do
  describe ".read" do
    it "returns declared schema fields for a ported step action" do
      fields = described_class.read("api_call")
      expect(fields).to be_a(Array)
      keys = fields.map { |field| field[:key].to_s }
      expect(keys).to include("httpMethod", "url", "resultVar")
      http = fields.find { |field| field[:key].to_s == "httpMethod" }
      expect(http[:type]).to eq(:select)
      expect(http[:role]).to eq(:enum)
    end

    it "returns [] for unknown action" do
      expect(described_class.read("unknown")).to eq([])
    end

    it "exposes declared fields for query_models" do
      keys = described_class.read("query_models").map { |field| field[:key].to_s }
      expect(keys).to include("select", "returns", "resultVar")
    end

    it "returns ported element-type fields from the Ruby schema" do
      keys = described_class.read("end").map { |field| field[:key].to_s }
      expect(keys).to include("responseType", "returnValue")
      expect(keys).not_to include("httpStatus", "responseBody", "label")
    end

    it "returns an empty schema for process (steps are not element config)" do
      expect(described_class.read("process")).to eq([])
    end
  end

  describe ".each_enum_branch" do
    it "yields each [key, option_value] for declared enum fields" do
      yielded = []
      described_class.each_enum_branch("api_call") { |k, v| yielded << [k, v] }
      methods = yielded.select { |key, _| key == "httpMethod" }.map(&:last)
      expect(methods).to include("GET", "POST")
    end

    it "yields nothing for an action with no enum fields" do
      yielded = []
      described_class.each_enum_branch("build_contract") { |k, v| yielded << [k, v] }
      expect(yielded).to eq([])
    end
  end
end
