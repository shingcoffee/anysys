# frozen_string_literal: true

RSpec.shared_examples "a code generator" do
  let(:generator) { described_class.new(element, context) }

  it "implements #generate_body returning String or nil" do
    expect(generator).to respond_to(:generate_body)
    result = generator.generate_body
    expect(result).to be_a(String).or be_nil
  end

  it "implements #generate_step_method wrapping body with def step(ctx, **)...end" do
    expect(generator).to respond_to(:generate_step_method)
    result = generator.generate_step_method
    if result
      expect(result).to include("(ctx, **)")
      expect(result).to match(/\Adef /)
      expect(result.strip).to end_with("end")
    end
  end

  it "implements #validate_config returning Array" do
    expect(generator).to respond_to(:validate_config)
    result = generator.validate_config(element.fetch("config", element.fetch("properties", {})))
    expect(result).to be_an(Array)
  end

  it "implements #dependencies returning Array" do
    expect(generator).to respond_to(:dependencies)
    expect(generator.dependencies).to be_an(Array)
  end

  it "implements .sample_input returning Hash" do
    expect(described_class.sample_input).to be_a(Hash)
  end

  it "declares metadata with description, category (Symbol), and version (semver)" do
    metadata = described_class._metadata
    expect(metadata).to be_a(Hash)
    expect(metadata[:description]).to be_a(String)
    expect(metadata[:category]).to be_a(Symbol)
    expect(metadata[:version]).to match(/\A\d+\.\d+\.\d+\z/)
  end

  it "has a generator_name derived from class name" do
    expect(described_class.generator_name).to be_a(String)
    expect(described_class.generator_name).not_to be_empty
  end

  it "has a generator_kind of :element_type or :step_action" do
    expect(described_class.generator_kind).to be_in([:element_type, :step_action])
  end

  it "TestRunner.run succeeds with sample_input" do
    result = CodeGenerators::TestRunner.run(described_class, config: described_class.sample_input)
    expect(result).to be_a(Hash)
    expect(result.keys).to contain_exactly(:code, :body, :inputs, :outputs, :validation_errors)
    expect(result[:inputs]).to be_an(Array)
    expect(result[:outputs]).to be_an(Array)
    expect(result[:validation_errors]).to be_an(Array)
  end
end
