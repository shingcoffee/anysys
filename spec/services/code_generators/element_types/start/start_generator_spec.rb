# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Start::StartGenerator do
  let(:element) { { "properties" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates the sample step" do
    expect(generated_step).to be_nil
  end

  it "declares a config schema with no runtime fields" do
    expect(described_class._config_schema.fields).to be_empty
  end

  it "emits no runtime body for the manual entry point" do
    expect(described_class.new(element, context).generate_body).to be_nil
  end

  it "accepts an empty config" do
    expect(described_class.new(element, context).validate_config({})).to eq([])
  end

  it "reports undeclared trigger keys as field-addressed unknown_field errors" do
    %w[triggerType httpMethod httpPath triggerScope authRequired rateLimitPerMinute eventName eventFilter cronExpression].each do |field|
      errors = described_class.new(element, context).validate_config(field => "value")
      expect(errors).to include(have_attributes(field: field, code: :unknown_field)), field
      expect(errors.map(&:message).join).not_to include("Only manual Start")
    end
  end

  it "does not treat notes chrome as an unknown config key" do
    expect(described_class.new(element, context).validate_config("description" => "Entry")).to eq([])
  end

  it "does not treat I/O pin lists as unknown config keys" do
    expect(described_class.new(element, context).validate_config("inputs" => [], "outputs" => [])).to eq([])
  end
end
