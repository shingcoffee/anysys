# frozen_string_literal: true

require "rails_helper"
require "support/generator_conformance"
require Rails.root.join("scripts/audit_generator_ui")

RSpec.describe "generator QA inventory" do
  SURVIVING_STEP_ACTIONS = %w[
    acquire_lock adjust_number aggregate_query ai_inference allocate_amount api_call
    assign_value audit_log authenticate authorize barcode_generate
    batch_operation build_contract build_installment_plan bulk_import
    business_hours_check cache_delete cache_fetch cache_read cache_write child_records
    calculate calculate_pricing clone_model collection_manipulate compare_data
    compress_files count_records create_notification currency_convert
    date_time_calc deadline_check decompress_files decrypt_data destroy_model
    download_file encrypt_data enqueue_job evaluate_rules fail_with_error
    filter_collection find_model format_value generate_document generate_file
    generate_id generate_token geolocation_lookup hand_off_to_module hash_data
    hash_manipulate i18n_translate idempotency_check invoke_service
    load_current_user log map_value mask_data math_operation new_model
    next_occurrence next_sequence_number parse_data query_models rate_limiter
    read_setting referenced_record refund_payment regex_extract register_member related_record
    release_lock request_payment sanitize_input save_model select_assignee
    send_chat_message send_email send_sms send_template_email send_webhook serialize_data
    set_record_fields set_submission_outcome skip_journey_steps string_manipulate template_render
    transition_state type_cast update_model upload_file upsert_model
    validate_contract validate_value verify_signature verify_token
  ].freeze

  let(:inventory) { GeneratorConformance.inventory }
  let(:registry) { CodeGenerators::GeneratorRegistry.instance }

  it "discovers 96 action implementations and five structural implementations independently of registration" do
    classes = inventory.map { |entry| entry.fetch(:generator) }
    expect(classes.size).to eq(101)
    expect(classes.uniq).to eq(classes)
    expect(classes).to all(be < CodeGenerators::BaseGenerator)
    expect(classes.count { |klass| klass.generator_kind == :step_action }).to eq(96)
    expect(classes.count { |klass| klass.generator_kind == :element_type }).to eq(5)
    expect(CodeGenerators::GeneratorRegistry.all).to match_array(classes)
  end

  it "registers exactly one name per class with no step-action aliases" do
    registrations = registry.step_action_generators.merge(registry.element_type_generators)
    expect(registry.step_action_generators.size).to eq(96)
    expect(registry.element_type_generators.size).to eq(5)
    expect(registrations.size).to eq(101)
    expect(registry.step_action_generators.keys).to match_array(SURVIVING_STEP_ACTIONS)
    aliases = registrations.group_by { |_key, klass| klass }.values
                           .select { |pairs| pairs.size > 1 }
    expect(aliases).to be_empty
    inventory.each do |entry|
      klass = entry.fetch(:generator)
      expect(klass.registered_names).to eq([klass.generator_name])
      expect(registrations.select { |_key, value| value == klass }.keys).to eq([klass.generator_name])
    end
  end

  it "declares a config schema for every step action" do
    registry.step_action_generators.each_value do |klass|
      expect(klass._config_schema).to be_present, klass.name
    end
  end

  GeneratorConformance.inventory.each do |entry|
    it "maps #{entry.fetch(:generator).name} to its dedicated #{entry.fetch(:spec)}" do
      path = Rails.root.join(entry.fetch(:spec))
      expect(path).to exist
      expect(GeneratorConformance.dedicated_spec_identities(path.read)).to include(entry.fetch(:generator).name)
    end
  end

  it "does not mistake comments, strings, or another class's describe for dedicated coverage" do
    source = <<~RUBY
      # RSpec.describe MissingGenerator do
      message = "RSpec.describe MissingGenerator do"
      RSpec.describe Other::Generator do
        it("works") { expect(true).to be(true) }
      end
    RUBY
    expect(GeneratorConformance.dedicated_spec_identities(source)).to eq(["Other::Generator"])
    expect { GeneratorConformance.dedicated_spec_identities("RSpec.describe(") }
      .to raise_error(GeneratorConformance::Error, /parse/)
  end

  it "maps every live catalog action once and identifies process as the seventh editor type" do
    schemas = GeneratorUiAudit.load_ui_schemas
    actions = GeneratorUiAudit.load_builder_action_keys
    expect(actions).to match_array(SURVIVING_STEP_ACTIONS)
    expect(actions.map { |key| registry.find_step_action(key) }).not_to include(nil)
    expect(actions.map { |key| registry.find_step_action(key) }).to match_array(registry.step_action_generators.values.uniq)
    expect(schemas.keys - actions).to match_array(%w[start end decision loop subflow process])
    expect(schemas.fetch("process")).to eq([])
    expect(registry.find_element_type("process")).to be_nil
  end

  it "reads element-type schemas from the Ruby generators rather than a JS mirror" do
    mirror = Rails.root.join("lib/code_generators/config_schemas.rb")
    expect(mirror).not_to exist
    schemas = GeneratorUiAudit.load_ui_schemas
    expect(schemas.keys).to include("start", "end", "process", "assign_value")
    expect(schemas.fetch("end").map { |field| field[:key].to_s }).to include("responseType")
    expect(defined?(CodeGenerators::CONFIG_SCHEMAS)).to be_nil
  end
end
