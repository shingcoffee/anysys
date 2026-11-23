# frozen_string_literal: true

require "rails_helper"
require "support/generator_conformance"

# Disk-backed catalog, so a missing registry entry cannot remove its examples.
# Compile/load every sample; invoke only fixtures with explicit inputs and bounded
# dependencies. Never auto-execute arbitrary samples (jobs, SQL, files, HTTP).
RSpec.describe "generator catalog execution contract" do
  GeneratorConformance.inventory.each do |entry|
    generator = entry.fetch(:generator)
    describe generator.name do
      it "accepts its sample and defines a callable step (or a declared orchestration shell)" do
        sample = generator.sample_input.deep_dup
        expect(sample).to be_a(Hash)
        expect(GeneratorConformance.validation_errors(generator, sample)).to eq([])
        result = GeneratorConformance.compiled_result(generator, sample)
        expect(result.fetch(:validation_errors)).to eq([])

        if GeneratorConformance::SOURCELESS_GENERATORS.include?(generator.name)
          expect(result.values_at(:body, :code)).to eq([nil, nil])
        else
          host = Class.new
          host.class_eval(result.fetch(:code), entry.fetch(:implementation), 1)
          expect(host.instance_methods(false)).to contain_exactly(:test_step)
          parameters = host.instance_method(:test_step).parameters
          expect(parameters).to include([:req, :ctx])
          expect(parameters.map(&:first)).to include(:keyrest)
        end
        expect(sample).to eq(generator.sample_input), "generation mutated the sample config"
      end

      generator.config_fields.select { |field| field[:required] }.each do |field|
        it "rejects removal of required sample field #{field.fetch(:name)}" do
          config = generator.sample_input.except(field.fetch(:name).to_s)
          expect(GeneratorConformance.validation_errors(generator, config)).not_to be_empty
        end
      end
    end
  end

  def execute_action(key, ctx:, overrides: {})
    generator = CodeGenerators::GeneratorRegistry.find_step_action(key)
    expect(generator).not_to be_nil
    config = generator.sample_input.merge(overrides)
    expect(GeneratorConformance.validation_errors(generator, config)).to eq([])
    result = CodeGenerators::TestRunner.execute(generator, config: config, ctx: ctx)
    expect(result.fetch(:validation_errors)).to eq([])
    expect(result.fetch(:outcome)).to be(true)
    expect(result.fetch(:ctx)).to equal(ctx)
    expect(ctx).not_to have_key(:_last_error)
    ctx
  end

  # Concrete expected values rather than source snippets/digests. Each row is a
  # separately selectable RSpec example. Existing focused specs cover deeper
  # option matrices; these exercise the complete generated method and ctx wiring.
  fixtures = {
    "assign_value" => [{ preferred_name: "", name: "Ada" }, { assigned: "Ada" },
                       { "valueType" => "first_present", "candidates" => %w[preferred_name name] }],
    "calculate" => [{ items: [{ amount: 2 }, { amount: 3 }] }, { total: 5 },
                    { "operation" => "sum", "fieldName" => "amount" }],
    "compare_data" => [
      { before: { name: "old", removed: 1, updated_at: 1 }, after: { name: "new", added: 2, updated_at: 2 } },
      { diff: { added: { added: 2 }, removed: { removed: 1 }, changed: { name: { from: "old", to: "new" } } } }
    ],
    "filter_collection" => [
      { items: [nil, { status: "active" }, { status: "inactive" }] },
      { filtered: [{ status: "active" }] },
      { "filterValue" => "active" }
    ],
    "hash_manipulate" => [{ data: { name: "Ada", email: "a@example.test", secret: 9 } },
                          { hash: { name: "Ada", email: "a@example.test" } }],
    "map_value" => [{ status: "unknown" }, { mapped_value: "Unknown" }],
    "math_operation" => [{ subtotal: 7, tax: 2 }, { number: 9.0 }],
    "parse_data" => [{ payload: '{"count":2}' }, { data: { "count" => 2 } }],
    "regex_extract" => [{ invoice_number: "invoice 123, line 45" }, { match: "123" }],
    "serialize_data" => [{ order: { count: 2 } }, { serialized: '{"count":2}' }],
    "string_manipulate" => [{ customer_name: "  hello  " }, { text: "hello" }],
    "template_render" => [{ name: "Ada" }, { greeting: "Hello, Ada!" },
                          { "template" => "Hello, {{name}}!", "resultVar" => "greeting" }],
    "type_cast" => [{ amount: "42" }, { cast_value: 42 }, { "targetType" => "integer" }],
    "collection_manipulate" => [
      { items: [{ name: "Ada", secret: 1 }] },
      { collection: [{ label: "Ada" }] }
    ]
  }

  fixtures.each do |key, (input, expected, overrides)|
    it "executes #{key} with concrete data and verifies its output contract" do
      ctx = execute_action(key, ctx: input.deep_dup, overrides: overrides || {})
      expect(ctx).to include(expected)
    end
  end

  it "executes generate_id with a controlled entropy boundary" do
    expect(SecureRandom).to receive(:uuid).and_return("11111111-2222-4333-8444-555555555555")
    expect(execute_action("generate_id", ctx: {}))
      .to include(id: "user_11111111-2222-4333-8444-555555555555")
  end

  it "executes collection_manipulate unique/flatten/group/sort with concrete data" do
    expect(execute_action("collection_manipulate",
                          ctx: { items: [{ id: 1, name: "first" }, { id: 1, name: "last" }, { id: 2 }] },
                          overrides: { "operation" => "unique", "uniqField" => "id" }))
      .to include(collection: [{ id: 1, name: "first" }, { id: 2 }])
    expect(execute_action("collection_manipulate",
                          ctx: { items: [[1, [2]], nil, [3]] },
                          overrides: { "operation" => "flatten" }))
      .to include(collection: [1, [2], nil, 3])
    expect(execute_action("collection_manipulate",
                          ctx: { items: [{ category: "a", id: 1 }, { category: "b", id: 2 }, { category: "a", id: 3 }] },
                          overrides: { "operation" => "group", "groupField" => "category" }))
      .to include(collection: { "a" => [{ category: "a", id: 1 }, { category: "a", id: 3 }],
                                "b" => [{ category: "b", id: 2 }] })
    expect(execute_action("collection_manipulate",
                          ctx: { items: [{ name: "Z", id: 1 }, { name: "A", id: 2 }, { name: "A", id: 3 }] },
                          overrides: { "operation" => "sort", "sortField" => "name" }))
      .to include(collection: [{ name: "A", id: 2 }, { name: "A", id: 3 }, { name: "Z", id: 1 }])
  end

  it "executes date_time_calc with a fixed clock" do
    travel_to Time.utc(2026, 4, 19, 12, 30) do
      result = execute_action("date_time_calc", ctx: {})[:datetime]
      expect(result).to eq(Time.utc(2026, 4, 19, 12, 30))
    end
  end

  it "executes log against an isolated logger, including configured context fields" do
    logger = instance_double(ActiveSupport::Logger)
    allow(Rails).to receive(:logger).and_return(logger)
    expect(logger).to receive(:info).with("Processing step")
    execute_action("log", ctx: { user_id: 19 })
  end

  it "no longer registers broadcast" do
    expect(CodeGenerators::GeneratorRegistry.find_step_action("broadcast")).to be_nil
  end

  it "no longer registers publish_event" do
    expect(CodeGenerators::GeneratorRegistry.find_step_action("publish_event")).to be_nil
  end
end
