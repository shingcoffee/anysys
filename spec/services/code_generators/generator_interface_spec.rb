# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::GeneratorInterface do
  let(:test_class) do
    Class.new do
      include CodeGenerators::GeneratorInterface

      def self.name
        "CodeGenerators::ElementTypes::Process::Test::TestGenerator"
      end

      generator_metadata do
        description "Test generator"
        category :test
        version "1.0.0"
      end

      def generate_body
        'ctx[:result] = ctx[:input_value].to_s'
      end

      def validate_config(config)
        []
      end
    end
  end

  describe "class-level DSL" do
    it "stores metadata" do
      expect(test_class._metadata[:description]).to eq("Test generator")
      expect(test_class._metadata[:category]).to eq(:test)
      expect(test_class._metadata[:version]).to eq("1.0.0")
    end

    it "derives generator_name from class name" do
      expect(test_class.generator_name).to eq("test")
    end

    it "uses an explicitly declared metadata name" do
      named_class = Class.new do
        include CodeGenerators::GeneratorInterface

        def self.name
          "CodeGenerators::ElementTypes::Process::Test::QueryModelsGenerator"
        end

        generator_metadata do
          name "query_models"
        end
      end

      expect(named_class.generator_name).to eq("query_models")
      expect(named_class.registered_names).to eq(["query_models"])
    end

    it "derives generator_kind from namespace" do
      expect(test_class.generator_kind).to eq(:step_action)
    end

    it "defaults registered_names to [generator_name]" do
      expect(test_class.registered_names).to eq(["test"])
    end

    it "returns sample_input as empty hash by default" do
      expect(test_class.sample_input).to eq({})
    end
  end

  describe "instance methods" do
    let(:element) { { "label" => "My Step" } }
    let(:instance) { test_class.new(element, {}) }

    it "#generate_body returns the code body" do
      expect(instance.generate_body).to eq('ctx[:result] = ctx[:input_value].to_s')
    end

    it "#generate_step_method wraps body with def step(ctx, **)" do
      result = instance.generate_step_method
      expect(result).to include("def my_step(ctx, **)")
      expect(result).to include('ctx[:result] = ctx[:input_value].to_s')
    end

    it "#generate_step_method uses generator_name when no label" do
      instance = test_class.new({}, {})
      result = instance.generate_step_method
      expect(result).to include("def test(ctx, **)")
    end

    it "#generate_step_method sanitizes labels with leading digits" do
      instance = test_class.new({ "label" => "123 start" }, {})
      result = instance.generate_step_method
      expect(result).to include("def step_123_start(ctx, **)")
    end
  end

  describe "interface enforcement" do
    let(:bare_class) do
      Class.new do
        include CodeGenerators::GeneratorInterface
        def self.name = "CodeGenerators::ElementTypes::Process::Test::BareGenerator"
      end
    end

    it "raises InterfaceError for unimplemented #generate_body" do
      instance = bare_class.new({}, {})
      expect { instance.generate_body }.to raise_error(CodeGenerators::GeneratorInterface::InterfaceError)
    end

    it "raises InterfaceError for unimplemented #validate_config" do
      instance = bare_class.new({}, {})
      expect { instance.validate_config({}) }.to raise_error(CodeGenerators::GeneratorInterface::InterfaceError)
    end

    it "provides default #dependencies as empty array" do
      instance = bare_class.new({}, {})
      expect(instance.dependencies).to eq([])
    end
  end
end
