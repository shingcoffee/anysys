# frozen_string_literal: true

RSpec.shared_examples "covers all configured branches" do |action_name:, base_element: nil|
  it "generates non-stub code for every enum branch in configSchema (action: #{action_name})" do
    base = base_element || { "config" => {} }
    CodeGenerators::Shared::SchemaReader.each_enum_branch(action_name) do |field, value|
      config_key = described_class.generator_kind == :element_type ? "properties" : "config"
      element = base.deep_merge(config_key => { field => value })
      generator = described_class.new(element, {})
      body = generator.generate_body
      next if body.nil? # intentional-nil generators (start/subflow/fork/join)
      expect(body).not_to match(/\A\s*#.*\n\s*true\s*\z/), "#{action_name}.#{field}=#{value}: stub fall-through"
      expect { RubyVM::InstructionSequence.compile(generator.generate_step_method) }.not_to raise_error
    end
    # Does not fail if schema has no enum fields — legitimate for text-only generators.
  end
end
