# frozen_string_literal: true

require "rails_helper"

RSpec.describe "step-action catalog" do
  def step_generators
    CodeGenerators::GeneratorRegistry.step_action_generators.values.uniq
  end

  it "has only :required errors for schema defaults on every step action" do
    step_generators.each do |generator|
      schema = generator._config_schema
      errors = generator.new({ "config" => schema.defaults }, {}).validate_config(schema.defaults)
      unexpected = errors.reject { |error| error.respond_to?(:code) && error.code == :required }
      expect(unexpected).to eq([]), "#{generator.generator_name} defaults produced #{unexpected.inspect}"
    end
  end

  it "accepts sample_input and compiles generate_body for every step action" do
    step_generators.each do |generator|
      sample = generator.sample_input
      instance = generator.new({ "config" => sample, "label" => "test_step" }, {})
      expect(instance.validate_config(sample)).to eq([]), generator.generator_name
      body = instance.generate_body
      expect(body).to be_a(String)
      expect { RubyVM::InstructionSequence.compile("def test_step(ctx, **)\n#{body}\nend") }
        .not_to raise_error
    end
  end

  it "lints the sample body of every step action, including enum variants" do
    step_generators.each do |generator|
      schema = generator._config_schema
      output_fields = schema.fields.select { |field| field.role == :output }.map(&:name)
      configs = [generator.sample_input]
      schema.fields.select { |field| field.role == :enum }.each do |field|
        Array(field.options[:values]).each do |value|
          configs << generator.sample_input.merge(field.name => value)
        end
      end
      configs.uniq.each do |config|
        instance = generator.new({ "config" => config }, {})
        next if instance.validate_config(config).any?

        outputs = output_fields.filter_map { |name| instance.value(name).presence&.to_s }
        result = CodeGenerators::BodyLint.check(instance.generate_body, outputs: outputs)
        body = instance.generate_body
        expect(result.ok?).to be(true), "#{generator.generator_name}: #{result.violations.inspect}\n#{body}"
      end
    end
  end

  it "lints the Wave 1 fixture generator" do
    sample = Phase3FixtureGenerator.sample_input
    gen = Phase3FixtureGenerator.new({ "config" => sample }, {})
    expect(gen.validate_config(sample)).to eq([])
    result = CodeGenerators::BodyLint.check(gen.generate_body, outputs: %w[total])
    expect(result.ok?).to be(true)
    expect { RubyVM::InstructionSequence.compile(gen.generate_step_method) }.not_to raise_error
  end
end
