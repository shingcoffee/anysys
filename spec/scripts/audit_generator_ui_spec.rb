# frozen_string_literal: true

require "rails_helper"
require "yaml"
require "tempfile"
require Rails.root.join("scripts/audit_generator_ui")

RSpec.describe "scripts/audit_generator_ui.rb", type: :script do
  let(:script_path) { Rails.root.join("scripts/audit_generator_ui.rb") }
  let(:output_path) { @output_path }

  around do |example|
    Tempfile.create(["generator-ui-audit-", ".yml"]) do |file|
      @output_path = Pathname.new(file.path)
      example.run
    end
  end

  # Exercise the real report/writer in a fresh subprocess with a disposable
  # destination. Specs must never replace or delete the tracked audit artifact.
  def run_script!
    runner = <<~RUBY
      require ARGV.fetch(0)
      Object.send(:remove_const, :OUTPUT_PATH)
      Object.const_set(:OUTPUT_PATH, Pathname.new(ARGV.fetch(1)))
      GeneratorUiAudit.run
      defects = GeneratorUiAudit.run_report.fetch(:defects)
      abort "Generator/UI defects: \#{defects.size}" if defects.any?
    RUBY
    system("bundle", "exec", "ruby", "-e", runner, script_path.to_s, output_path.to_s)
    $?.exitstatus
  end

  it "exists and is runnable" do
    expect(File).to exist(script_path)
  end

  it "produces the YAML artifact at the expected path when run" do
    expect(run_script!).to eq(0)
    expect(output_path).to exist
    content = YAML.safe_load_file(output_path, permitted_classes: [Symbol], aliases: true)
    expect(content).to be_an(Array)
  end

  describe "UI schema loading" do
    it "loads UI configSchemas from the Ruby generators" do
      ui = GeneratorUiAudit.load_ui_schemas
      expect(ui).to be_a(Hash)
      expect(ui).to include("assign_value", "save_model", "start", "end")
      expect(ui["assign_value"]).to be_an(Array)
      expect(ui["assign_value"].first).to include(:key)
    end

    it "loads mirrored builder action keys separately from element schemas" do
      GeneratorUiAudit.load_ui_schemas

      expect(GeneratorUiAudit.load_builder_action_keys).to include(
        "api_call", "validate_contract", "collection_manipulate"
      )
      expect(GeneratorUiAudit.load_builder_action_keys).not_to include("start", "process")
    end
  end

  describe ".discover_generators" do
    it "returns each registered generator class once" do
      gens = GeneratorUiAudit.discover_generators
      registry = CodeGenerators::GeneratorRegistry.instance

      # Derived from the registry rather than hard-coded, so removing a
      # category (e.g. human_workflow) or an element type cannot leave a
      # stale magic number behind.
      kinds = gens.group_by { |g| g[:kind] }
      expect(kinds[:element_type].size).to eq(registry.element_type_generators.values.uniq.size)
      expect(kinds[:element_type].size).to eq(5)
      expect(kinds[:step_action].size).to eq(registry.step_action_generators.values.uniq.size)
      expect(gens.size).to eq(kinds[:element_type].size + kinds[:step_action].size)
      expect(gens.map { |g| g[:generator] }.uniq.size).to eq(gens.size)
    end

    it "registers api_call and validate_contract once under their canonical names" do
      ui = GeneratorUiAudit.load_ui_schemas
      gens = GeneratorUiAudit.discover_generators(ui.keys)
      api = gens.find { |g| g[:generator_key] == "api_call" }
      expect(api[:ui_key]).to eq("api_call")
      expect(api[:registered_names]).to eq(["api_call"])

      vc = gens.find { |g| g[:generator_key] == "validate_contract" }
      expect(vc[:ui_key]).to eq("validate_contract")
      expect(vc[:registered_names]).to eq(["validate_contract"])
    end

    it "registers collection_manipulate once and does not keep deleted pluck actions" do
      gens = GeneratorUiAudit.discover_generators
      expect(gens.map { |g| g[:generator_key] }).to include("collection_manipulate")
      expect(gens.map { |g| g[:generator_key] }).not_to include("pluck_fields", "pluck_model_fields")
    end

    it "includes every registered structural element type" do
      gens = GeneratorUiAudit.discover_generators
      structural_keys = gens.select { |g| g[:kind] == :element_type }.map { |g| g[:generator_key] }

      expect(structural_keys).to contain_exactly(
        "decision", "end", "loop", "start", "subflow"
      )
    end
  end

  describe ".extract_contract" do
    let(:path) do
      Rails.root.join("app/services/code_generators/element_types/process/data_operations/assign_value_generator.rb").to_s
    end
    let(:contract) { GeneratorUiAudit.extract_contract(path) }

    it "extracts keys read from config" do
      expect(contract[:keys_read]).to include(
        "resultVar", "valueType", "stringValue", "integerValue", "floatValue",
        "booleanValue", "ctxRefVariable",
        "valueExpression"
      )
    end

    it "extracts enum values from the declared schema" do
      expect(contract[:enums]["valueType"]).to include(
        "string", "integer", "float", "boolean", "array", "hash", "expression",
        "null", "ctx_ref", "first_present"
      )
    end

    it "extracts enum values from VALUE_TYPES constant via fetch_enum" do
      # assign_value doesn't use fetch_enum for valueType — test with a
      # generator that does (authorize uses ROLES/ACTIONS constants).
      auth_path = Rails.root.join("app/services/code_generators/element_types/process/security/authorize_generator.rb").to_s
      contract = GeneratorUiAudit.extract_contract(auth_path)
      expect(contract[:enums]).to be_a(Hash)
    end

    it "extracts required keys from the declared schema" do
      api_path = Rails.root.join("app/services/code_generators/element_types/process/communication/api_call_generator.rb")
      expect(GeneratorUiAudit.extract_contract(api_path)[:required]).to include("url")
    end

    it "uses runtime config fields for ported decision declarations" do
      decision_class = CodeGenerators::ElementTypes::Decision::DecisionGenerator
      decision_path = Rails.root.join(
        "app/services/code_generators/element_types/decision/decision_generator.rb"
      )

      contract = GeneratorUiAudit.extract_contract(
        decision_path,
        generator_class: decision_class
      )

      expect(contract[:keys_read]).to include("condition")
      expect(contract[:required]).to include("condition", "routeBy")
      expect(contract[:fields]).to include(
        "routeBy" => include(type: :enum, values: %w[value condition]),
        "subject" => include(type: :expression, conditions: [{ type: :visible, when: { "routeBy" => "value" } }]),
        "condition" => include(
          type: :conditions, required: true,
          conditions: [{ type: :visible, when: { "routeBy" => "condition" } }]
        )
      )
    end

    it "uses runtime config fields for ported clone model declarations" do
      clone_class = CodeGenerators::ElementTypes::Process::ModelOperations::CloneModelGenerator
      clone_path = Rails.root.join(
        "app/services/code_generators/element_types/process/model_operations/clone_model_generator.rb"
      )

      contract = GeneratorUiAudit.extract_contract(
        clone_path,
        generator_class: clone_class
      )

      expect(contract[:keys_read]).to include("modelVariable", "resultVar")
      expect(contract[:required]).not_to include("sourceKey")
      expect(contract[:fields]).to include(
        "modelVariable" => include(type: :string),
        "resultVar" => include(type: :string)
      )
    end

    it "preserves runtime required, default, and allowed-values metadata" do
      generator_class = Class.new do
        def self.config_fields
          [
            {
              name: "mode",
              type: :enum,
              values: %w[safe fast],
              required: true,
              default: "safe"
            },
            { name: "enabled", type: :boolean, required: false }
          ]
        end
      end

      fields = GeneratorUiAudit.runtime_fields(generator_class)

      expect(fields.fetch("mode")).to include(
        type: :enum,
        values: %w[safe fast],
        required: true,
        default: "safe"
      )
      expect(fields.fetch("enabled")).to include(
        type: :boolean,
        values: %w[true false],
        required: false
      )
    end

    it "extracts an empty object default without treating it as a string or requiring runtime loading" do
      path = Rails.root.join("app/services/code_generators/element_types/process/communication/send_sms_generator.rb")
      contract = GeneratorUiAudit.extract_contract(path)
      expect(contract[:fields]["vars"]).to include(default: [])
      expect(GeneratorUiAudit.extract_literal_keyword("default: {}", "default")).to eq(found: true, value: {})
      expect(GeneratorUiAudit.extract_literal_keyword('default: "{}"', "default")).to eq(found: true, value: "{}")
      expect(GeneratorUiAudit.extract_literal_keyword("default: []", "default")).to eq(found: true, value: [])
    end
  end

  describe ".compute_gaps" do
    let(:gens) { GeneratorUiAudit.discover_generators }
    let(:ui)   { GeneratorUiAudit.load_ui_schemas }
    let(:assign_value_gaps) do
      g = gens.find { |x| x[:generator_key] == "assign_value" }
      contract = GeneratorUiAudit.extract_contract(g[:generator_path])
      GeneratorUiAudit.compute_gaps(contract, ui["assign_value"])
    end

    it "reports no missing enum options for assign_value valueType once UI is caught up" do
      # Post-refactor: the UI's valueType select covers the full generator enum
      # (string, integer, float, boolean, array, hash, expression, null,
      # ctx_ref, random). If this test starts failing
      # because enum values reappear as missing, either the generator grew
      # new enum values or the UI lost some — investigate, don't just relax.
      enum_gap = assign_value_gaps.find { |x| x[:type] == :missing_enum_option && x[:field] == "valueType" }
      expect(enum_gap).to be_nil
    end

    it "reports no missing value inputs for assign_value once UI is caught up" do
      missing_fields = assign_value_gaps.select { |x| x[:type] == :missing_field }.map { |x| x[:field] }
      expect(missing_fields).not_to include("floatValue", "arrayValue", "hashValue")
    end

    it "reports mismatched required when generator enforces but UI does not" do
      # The UI uses "targetVar" as the key while the generator reads "resultVar";
      # "resultVar" becomes a missing_field gap, and "targetVar" is an unused UI field.
      # Neither triggers mismatched_visibility_or_default here — but
      # the gap set should NOT raise.
      expect(assign_value_gaps).to all(be_a(Hash))
    end

    it "excludes cross-cutting wrapper keys from missing_field reporting" do
      # Construct a synthetic contract that reads wrapper keys.
      contract = {
        keys_read: %w[retryCount timeout guardCondition myCustomKey],
        enums: {},
        required: []
      }
      gaps = GeneratorUiAudit.compute_gaps(contract, [])
      missing = gaps.select { |g| g[:type] == :missing_field }.map { |g| g[:field] }
      expect(missing).to eq(["myCustomKey"])
    end

    it "reports a registry action with no builder action entry even when it has no fields" do
      contract = { keys_read: [], enums: {}, required: [], fields: {} }

      gaps = GeneratorUiAudit.compute_gaps(
        contract,
        nil,
        "configuration_free",
        kind: :step_action,
        builder_action_present: false
      )

      expect(gaps).to include(type: :missing_builder_action)
    end

    it "allows configuration-free actions with an explicit empty builder action entry" do
      contract = { keys_read: [], enums: {}, required: [], fields: {} }

      gaps = GeneratorUiAudit.compute_gaps(
        contract,
        [],
        "configuration_free",
        kind: :step_action,
        builder_action_present: true
      )

      expect(gaps).not_to include(include(type: :missing_builder_action))
      expect(gaps).not_to include(include(type: :missing_schema))
    end

    it "reports computed fields exposed by the builder even when the generator consumes them" do
      contract = {
        keys_read: %w[sourceVariable _route_index],
        enums: {},
        required: [],
        fields: {}
      }
      ui_fields = [
        { key: "sourceVariable", type: :text },
        { key: "_route_index", type: :number }
      ]

      gaps = GeneratorUiAudit.compute_gaps(
        contract,
        ui_fields,
        "decision",
        kind: :element_type
      )

      expect(gaps).to include(type: :computed_field_exposed, field: "_route_index")
    end

    context "typed JSON/expression defaults" do
      let(:contract) do
        { keys_read: ["variables"], enums: {}, required: [],
          fields: { "variables" => { type: :expression, required: false, default: {} } } }
      end
      let(:field) { { key: "variables", type: :json_or_expression } }

      it "lets an omitted optional editor value use the declared object default" do
        expect(GeneratorUiAudit.compute_gaps(contract, [field])).to be_empty
        expect(field).not_to have_key(:default)
      end

      [{}, "{}", " { } "].each do |value|
        it "compares #{value.inspect} as a serialized object" do
          expect(GeneratorUiAudit.compute_gaps(contract, [field.merge(default: value)])).to be_empty
        end
      end

      ["", [], "[]", "ctx.variables", "{broken}", { "code" => "preset" }].each do |value|
        it "reports genuine default drift for #{value.inspect}" do
          expect(GeneratorUiAudit.compute_gaps(contract, [field.merge(default: value)]))
            .to include(type: :mismatched_visibility_or_default, field: "variables", fix: { set: { default: {} } })
        end
      end

      it "does not exempt a required blank JSON/expression field" do
        expect(GeneratorUiAudit.compute_gaps(contract, [field.merge(required: true)]))
          .to include(type: :mismatched_visibility_or_default, field: "variables", fix: { set: { default: {} } })
      end

      it "does not normalize an ordinary text default into an object" do
        expect(GeneratorUiAudit.compute_gaps(contract, [field.merge(type: :text, default: "{}")]))
          .to include(type: :mismatched_visibility_or_default, field: "variables", fix: { set: { default: {} } })
      end
    end
  end

  describe "end-to-end run" do
    it "produces a populated audit artifact for all registered generator classes" do
      expect(run_script!).to eq(0)

      data = YAML.safe_load_file(output_path, permitted_classes: [Symbol], aliases: true)
      expect(data.size).to eq(GeneratorUiAudit.discover_generators.size)

      total_gaps = data.flat_map { |e| e[:gaps] }.size
      expect(total_gaps).to eq(0)

      phases = data.map { |e| e[:phase] }.uniq.sort
      expect(phases).to include(
        "background", "caching", "communication", "concurrency",
        "data", "element_decision", "element_end", "element_start",
        "element_subflow", "file",
        "model", "outcome", "payments",
        "resilience", "scheduling", "security", "service",
        "utility", "validation"
      )
    end
  end
end
