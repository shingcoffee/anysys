# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("scripts/audit_generator_ui")
require Rails.root.join("scripts/audit_step_action_config")

RSpec.describe "flowchart generator contract parity" do
  it "preserves category identity when flattening an injected contract defect" do
    allow(GeneratorUiAudit).to receive(:load_ui_schemas).and_return({})
    allow(GeneratorUiAudit).to receive(:load_builder_action_keys).and_return([])
    allow(GeneratorUiAudit).to receive(:build_report).and_return([
      { ui_key: "broken_action", phase: "data", gaps: [{ type: :missing_field, field: "input" }] }
    ])

    defects = GeneratorUiAudit.run_report.fetch(:defects)
    expect(defects.select { |defect| defect[:phase] == "data" }).to contain_exactly(
      type: :missing_field, field: "input", ui_key: "broken_action", phase: "data"
    )
  end

  it "reads element and action schemas from Ruby generators rather than an empty catalog" do
    expect(GeneratorUiAudit.load_ui_schemas.keys).to include("assign_value", "start")
    expect(GeneratorUiAudit.load_builder_action_keys).to include("api_call", "validate_contract")
    expect(GeneratorUiAudit.load_builder_action_keys).not_to include("start")
  end

  STRUCTURAL_KEYS = %w[
    decision end fork join loop parallel_for_each saga signal_wait start subflow
    timer transaction
  ].freeze

  it "represents every registry generator once while accounting for every registered name" do
    report = GeneratorUiAudit.run_report
    entries = report.fetch(:entries)
    registry = CodeGenerators::GeneratorRegistry.instance
    registered_names = entries.flat_map { |entry| entry.fetch(:registered_names) }
    registered_classes = entries.map { |entry| entry.fetch(:generator) }
    registry_names = registry.element_type_generators.keys + registry.step_action_generators.keys

    expect(registered_classes).to eq(registered_classes.uniq)
    expect(registered_names.sort).to eq(registry_names.sort)
    expect(report.fetch(:defects)).to all(include(:type, :ui_key, :phase))
  end

  it "registers each step action once under its canonical name" do
    entries = GeneratorUiAudit.run_report.fetch(:entries)
    api_call = entries.select do |entry|
      entry.fetch(:registered_names).include?("api_call")
    end

    expect(api_call.one?).to be(true)
    expect(api_call.first).to include(
      generator_key: "api_call",
      ui_key: "api_call",
      registered_names: ["api_call"]
    )
  end

  it "reports builder actions that have no registry registration" do
    registry = instance_double(
      CodeGenerators::GeneratorRegistry,
      step_action_generators: {
        "api_call" => Object,
        "validate_contract" => Object
      },
      element_type_generators: { "start" => Object }
    )

    expect(
      GeneratorUiAudit.missing_registration_defects(
        %w[api_call validate_contract orphan_action],
        registry: registry
      )
    ).to contain_exactly(
      type: :missing_registration,
      ui_key: "orphan_action",
      phase: "unregistered"
    )
  end

  it "registers collection pluck as collection_manipulate and query values as query_models" do
    registry = CodeGenerators::GeneratorRegistry.instance

    expect(registry.find_step_action("collection_manipulate")).to eq(
      CodeGenerators::ElementTypes::Process::DataOperations::CollectionManipulateGenerator
    )
    expect(registry.find_step_action("query_models")).to eq(
      CodeGenerators::ElementTypes::Process::ModelOperations::QueryModelsGenerator
    )
    expect(registry.find_step_action("pluck_fields")).to be_nil
    expect(registry.find_step_action("pluck_model_fields")).to be_nil
  end

  it "has registry coverage for every mirrored builder action" do
    expect(GeneratorUiAudit.run_report.fetch(:defects)).not_to include(
      include(type: :missing_registration)
    )
  end

  it "reports a registry action omitted from the builder action catalog" do
    ui = GeneratorUiAudit.load_ui_schemas
    builder_action_keys = GeneratorUiAudit.load_builder_action_keys - ["validate_contract"]
    validate = GeneratorUiAudit.build_report(
      ui,
      builder_action_keys: builder_action_keys
    ).find { |entry| entry[:generator_key] == "validate_contract" }

    expect(validate.fetch(:gaps)).to include(type: :missing_builder_action)
  end

  it "has no structural element defects" do
    types = CodeGenerators::GeneratorRegistry.element_type_generators.keys
    defects = GeneratorUiAudit.run_report.fetch(:defects).select do |defect|
      types.include?(defect.fetch(:ui_key))
    end

    expect(defects).to be_empty
  end

  it "keeps optional send_sms variables declared as a mapping with an empty default" do
    report = GeneratorUiAudit.run_report
    send_sms = report.fetch(:entries).find { |entry| entry[:generator_key] == "send_sms" }
    ui_field = GeneratorUiAudit.load_ui_schemas.fetch("send_sms").find { |field| field[:key] == "vars" }

    expect(ui_field).to include(type: :key_value_list, role: :mapping)
    expect(send_sms.fetch(:gaps)).to be_empty
  end

  %w[
    model validation data caching communication file background service
    security concurrency resilience scheduling utility payments outcome
  ].each do |phase|
    it "has no #{phase} action defects" do
      report = GeneratorUiAudit.run_report
      expect(report.fetch(:entries).select { |entry| entry.fetch(:phase) == phase }).not_to be_empty
      defects = report.fetch(:defects).select do |defect|
        defect.fetch(:phase) == phase
      end
      expect(defects).to be_empty
    end
  end

  it "reports structural UI fields that are neither consumed nor classified presentation state" do
    contract = { keys_read: ["condition"], enums: {}, required: [] }
    ui_fields = [
      { key: "label", type: :text },
      { key: "description", type: :textarea },
      { key: "condition", type: :condition },
      { key: "orphanedControl", type: :text }
    ]

    gaps = GeneratorUiAudit.compute_gaps(contract, ui_fields, "decision", kind: :element_type)

    expect(gaps).to include(type: :extra_ui_field, field: "orphanedControl")
    expect(gaps).not_to include(include(type: :extra_ui_field, field: "label"))
    expect(gaps).not_to include(include(type: :extra_ui_field, field: "description"))
  end

  it "serializes repository-relative generator paths" do
    paths = GeneratorUiAudit.run_report.fetch(:entries).map { |entry| entry.fetch(:generator_path) }

    expect(paths).to all(start_with("app/services/code_generators/"))
    expect(paths).not_to include(a_string_starting_with(Rails.root.to_s))
  end

  it "returns structured step-action configuration defects" do
    expect(StepActionConfigAudit.run_report).to all(
      include(:ui_key, :phase, :defects)
    )
  end
end
