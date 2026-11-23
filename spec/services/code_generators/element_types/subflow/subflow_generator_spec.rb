# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Subflow::SubflowGenerator do
  let(:element) { { "properties" => { "flowchartId" => "1" } } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  it "generates the sample step" do
    expect(generated_step).to be_nil
  end

  it "declares a config schema with a flowcharts reference" do
    field = described_class._config_schema.fields.find { |item| item.name == "flowchartId" }
    expect(field.role).to eq(:reference)
    expect(field.options[:source]).to eq(:flowcharts)
    expect(field.options[:required]).to eq(true)
  end

  it "leaves synchronous Subprocess declaration to ActivityGenerator" do
    expect(described_class.new(element, context).generate_body).to be_nil
  end

  it "requires flowchartId with a translated message" do
    errors = described_class.new(element, context).validate_config({})
    expect(errors).to include(have_attributes(field: "flowchartId", code: :required))
    expect(errors.map(&:message)).to include(
      I18n.t("flowchart_elements.shared.errors.required", field: "flowchartId")
    )
    expect(errors.map(&:message).join).not_to include("No flowchartId specified")
  end

  describe "#variable_mapping" do
    def mapping_for(rows)
      described_class.new({ "properties" => { "flowchartId" => "1", "inputVariables" => rows } }, context)
        .variable_mapping
    end

    it "emits one Trailblazer Inject per named input" do
      expect(mapping_for([
        { "key" => "order", "value" => "ctx[:model]" },
        { "key" => "total", "value" => "ctx[:amount] * 2" }
      ])).to eq([
        "Inject(:order, override: true) => ->(ctx, **) { ctx[:model] }",
        "Inject(:total, override: true) => ->(ctx, **) { (ctx[:amount] * 2) }"
      ])
    end

    it "is empty when no inputs are named" do
      expect(described_class.new(element, context).variable_mapping).to eq([])
    end

    it "drops rows whose expression would break out of the lambda" do
      expect(mapping_for([{ "key" => "order", "value" => "1 }; Kernel.raise('pwn'); ->(ctx, **) { 2" }])).to eq([])
    end
  end

  it "rejects an input variable named twice" do
    errors = described_class.new(element, context).validate_config(
      "flowchartId" => "1",
      "inputVariables" => [{ "key" => "order", "value" => "ctx[:model]" }, { "key" => "order", "value" => "1" }]
    )

    expect(errors).to include(have_attributes(field: "inputVariables", code: :duplicate_input))
    expect(errors.map(&:message)).to include("inputVariables names order more than once")
  end

  it "rejects an input variable that shadows a seeded run key" do
    errors = described_class.new(element, context).validate_config(
      "flowchartId" => "1", "inputVariables" => [{ "key" => "customer_id", "value" => "1" }]
    )

    expect(errors).to include(have_attributes(field: "inputVariables", code: :reserved_name))
  end

  it "reports removed mapping keys as unknown fields" do
    %w[subflowId varMappings inputMapping outputMapping runMode].each do |field|
      errors = described_class.new(element, context).validate_config("flowchartId" => "1", field => "x")
      expect(errors).to include(have_attributes(field: field, code: :unknown_field)), field
    end
  end
end
