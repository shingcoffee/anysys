# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::AggregateQueryGenerator do
  let(:context) { {} }
  let(:element) { { "config" => {} } }

  it_behaves_like "a code generator"

  def errors(config)
    described_class.new(element, context).validate_config(config)
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.respond_to?(:code) && error.code == :required }
    expect(unexpected).to eq([])
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:aggregates] = FlowchartRuntime::Entries.aggregate(ctx, function: "sum", field: "amount")
      end
    RUBY
  end

  %w[sum average minimum maximum count].each do |function|
    it "generates the #{function} variant" do
      code = generated_step(described_class.sample_input.merge("aggregateFunction" => function))
      expect(code).to include("function: #{function.inspect}")
      expect(CodeGenerators::BodyLint.check(code, outputs: %w[aggregates]).ok?).to be(true)
    end
  end

  it "emits round_to and omits default kwargs" do
    expect(generated_step(described_class.sample_input.merge(
      "aggregateFunction" => "average",
      "roundTo" => 1
    ))).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:aggregates] = FlowchartRuntime::Entries.aggregate(
          ctx,
          function: "average",
          field: "amount",
          round_to: 1
        )
      end
    RUBY
  end

  it "emits another entity and own record scope" do
    code = generated_step(described_class.sample_input.merge("entity" => "Invoice", "recordScope" => "own"))
    expect(code).to include('entity: "Invoice"', 'record_scope: "own"')
    expect(code).to include("FlowchartRuntime::Step.attempt")
  end

  it "rejects having without groupByFields" do
    cfg = described_class.sample_input.merge("having" => "COUNT(*) > 1")
    expect(errors(cfg).map(&:code)).to include(:having_needs_group)
  end

  it "rejects a scalar format with two aggregations" do
    cfg = described_class.sample_input.merge(
      "resultFormat" => "scalar",
      "aggregations" => [{ "key" => "amount", "value" => "sum" }, { "key" => "amount", "value" => "count" }]
    )
    expect(errors(cfg).map(&:code)).to include(:scalar_needs_single_aggregation)
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { "name_slug" => "category", "type" => "String" },
        { "name_slug" => "amount", "type" => "Integer" }
      ].to_json)
    end

    it "aggregates only this tenant's rows" do
      [["a", 3], ["a", 4], ["b", 9]].each do |category, amount|
        create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "category" => category, "amount" => amount })
      end
      create(:entity_entry, :with_data, entity: entity, customer: other, entry_data: { "category" => "a", "amount" => 100 })
      ctx = { bound_entity: entity, customer_id: customer.id }

      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: {
          "aggregateFunction" => "sum",
          "aggregateField" => "amount",
          "groupByFields" => %w[category],
          "resultVar" => "aggregates"
        },
        ctx: ctx
      )
      expect(result[:outcome]).to eq("a" => 7, "b" => 9)
      expect(ctx[:aggregates]).to eq("a" => 7, "b" => 9)
    end

    it "rounds a tenant average when roundTo is set" do
      [[3], [4]].each do |(amount)|
        create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "amount" => amount })
      end
      create(:entity_entry, :with_data, entity: entity, customer: other, entry_data: { "amount" => 100 })
      ctx = { bound_entity: entity, customer_id: customer.id }
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: {
          "aggregateFunction" => "average",
          "aggregateField" => "amount",
          "roundTo" => 1,
          "resultVar" => "aggregates"
        },
        ctx: ctx
      )
      expect(result[:outcome]).to eq(3.5)
      expect(ctx[:aggregates]).to eq(3.5)
    end
  end
end
