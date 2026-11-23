# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Code generator I/O and test pipeline" do
  let(:generator_class) { CodeGenerators::ElementTypes::Process::DataOperations::AssignValueGenerator }
  let(:assign_config) { { "resultVar" => "assigned", "valueType" => "string", "stringValue" => "hello" } }

  describe "CodeIntrospector integration with real generators" do
    it "derives output keys from ctx[:key] = assignments" do
      element = { "config" => assign_config, "properties" => assign_config }
      body = generator_class.new(element, {}).generate_body
      result = CodeGenerators::CodeIntrospector.analyze(body)
      expect(result[:outputs]).to include("assigned")
    end

    it "filters out internal keys prefixed with _" do
      loop_class = CodeGenerators::ElementTypes::Loop::LoopGenerator
      element = { "properties" => {} }
      body = loop_class.new(element, {}).generate_body
      result = CodeGenerators::CodeIntrospector.analyze(body)
      result[:outputs].each do |key|
        expect(key).not_to start_with("_")
      end
    end
  end

  describe "TestRunner integration" do
    it "runs assign_value generator with sample config" do
      result = CodeGenerators::TestRunner.run(generator_class, config: assign_config)
      expect(result[:code]).to include("(ctx, **)")
      expect(result[:body]).to include("ctx[:assigned]")
      expect(result[:outputs]).to include("assigned")
    end
  end

  describe "#generate_step_method" do
    it "returns a complete step method with (ctx, **) signature" do
      element = { "config" => assign_config }
      gen = generator_class.new(element, {})
      code = gen.generate_step_method
      expect(code).to include("def ")
      expect(code).to include("(ctx, **)")
      expect(code).to include("ctx[:assigned]")
      expect(code).to end_with("end")
    end

    it "uses element label for step name when available" do
      element = { "config" => { "resultVar" => "x", "valueType" => "string", "stringValue" => "ok" }, "label" => "Set Result" }
      gen = generator_class.new(element, {})
      code = gen.generate_step_method
      expect(code).to include("def set_result(ctx, **)")
    end

    it "falls back to generator_name when no label" do
      element = { "config" => { "resultVar" => "x", "valueType" => "string", "stringValue" => "ok" } }
      gen = generator_class.new(element, {})
      code = gen.generate_step_method
      expect(code).to include("def assign_value(ctx, **)")
    end
  end

  describe "MetadataDSL.bump_patch" do
    it "increments the patch version" do
      expect(CodeGenerators::MetadataDSL.bump_patch("1.0.0")).to eq("1.0.1")
      expect(CodeGenerators::MetadataDSL.bump_patch("2.3.5")).to eq("2.3.6")
    end

    it "handles nil/empty gracefully" do
      expect(CodeGenerators::MetadataDSL.bump_patch(nil)).to eq("1.0.1")
      expect(CodeGenerators::MetadataDSL.bump_patch("")).to eq("1.0.1")
    end
  end
end
