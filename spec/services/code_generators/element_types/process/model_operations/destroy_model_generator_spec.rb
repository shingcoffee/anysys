# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::DestroyModelGenerator do
  let(:element) { { "id" => "step_destroy", "type" => "process", "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, {}).generate_body
  end

  def errors(config)
    described_class.new({ "config" => config }, {}).validate_config(config)
  end

  def run_body(config, ctx)
    body = generate(config)
    runner = Class.new do
      class_eval <<~RUBY, __FILE__, __LINE__ + 1
        def run(ctx)
          #{body}
        end
      RUBY
    end
    runner.new.run(ctx)
  end

  it "has only :required errors for schema defaults" do
    defaults = described_class._config_schema.defaults
    unexpected = errors(defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        unless ctx[:model]
          return FlowchartRuntime::Step.fail(ctx, :record_missing, field: :modelVariable)
        end
        FlowchartRuntime::Step.attempt(
          ctx,
          :"destroy_model.failed",
          FlowchartRuntime::Entries::Error
        ) do
          FlowchartRuntime::Entries.destroy(ctx, ctx[:model])
        end
      end
    RUBY
  end

  it "emits a BodyLint-clean body for each mode" do
    %w[delete archive].each do |mode|
      config = described_class.sample_input.merge("mode" => mode, "archiveField" => "archived_at")
      next if errors(config).any?

      result = CodeGenerators::BodyLint.check(generate(config), outputs: [])
      expect(result.ok?).to be(true), "#{mode}: #{result.violations.inspect}\n#{generate(config)}"
    end
  end

  it "is version 5.2.0" do
    expect(described_class._metadata[:version]).to eq("5.2.0")
  end

  it "ignores a missing record when onMissing is ignore" do
    code = generate("mode" => "delete", "onMissing" => "ignore")
    expect(code).to include("return true unless ctx[:model]")
    expect(code).not_to include("record_missing")
  end

  it "archives through Entries.archive with an optional actor field" do
    expect(generate("mode" => "archive", "archiveField" => "archived_at"))
      .to include('FlowchartRuntime::Entries.archive(ctx, ctx[:model], field: "archived_at")')
    expect(generate("mode" => "archive", "archiveField" => "archived_at", "archivedByField" => "archived_by"))
      .to include('FlowchartRuntime::Entries.archive(ctx, ctx[:model], field: "archived_at", by_field: "archived_by")')
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other_customer) { create(:customer) }
    let(:schema) do
      [
        { "name" => "Email", "name_slug" => "email", "data_type" => "string" },
        { "name" => "Archived at", "name_slug" => "archived_at", "data_type" => "datetime" },
        { "name" => "Archived by", "name_slug" => "archived_by", "data_type" => "string" }
      ]
    end
    let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json) }

    it "deletes the tenant row and refuses a foreign row" do
      own = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "email" => "a@x.io" })
      foreign = create(:entity_entry, :with_data, entity: entity, customer: other_customer, entry_data: { "email" => "z@x.io" })
      ctx = {
        bound_entity: entity,
        customer_id: customer.id,
        model: FlowchartRuntime::Entries.find_by({ bound_entity: entity, customer_id: customer.id }, "id" => own.id),
        errors: []
      }

      expect(run_body({ "mode" => "delete" }, ctx)).to be(true)
      expect(EntityEntry.where(id: own.id)).to be_empty

      foreign_ctx = ctx.merge(model: foreign, errors: [])
      expect(run_body({ "mode" => "delete" }, foreign_ctx)).to be(false)
      expect(foreign_ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.destroy_model.failed", reason: "Error")])
      expect(EntityEntry.where(id: foreign.id)).to exist
    end

    it "archives a date-time field and optionally the actor" do
      own = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "email" => "a@x.io" })
      ctx = {
        bound_entity: entity,
        customer_id: customer.id,
        current_user_id: 88,
        model: FlowchartRuntime::Entries.find_by({ bound_entity: entity, customer_id: customer.id }, "id" => own.id),
        errors: []
      }
      config = { "mode" => "archive", "archiveField" => "archived_at", "archivedByField" => "archived_by" }

      expect(run_body(config, ctx)).to be(true)
      own.reload
      expect(own.archived_at).to be_present
      expect(own.archived_by).to eq(88)
      expect(EntityEntry.where(id: own.id)).to exist
    end

    it "fails when the model variable is nil and onMissing is fail" do
      ctx = { bound_entity: entity, customer_id: customer.id, model: nil, errors: [] }

      expect(run_body({ "mode" => "delete" }, ctx)).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.record_missing")])
      expect(ctx[:error_details].last["code"]).to eq("record_missing")
    end

    it "continues when the model variable is nil and onMissing is ignore" do
      own = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "email" => "a@x.io" })
      ctx = { bound_entity: entity, customer_id: customer.id, model: nil, errors: [] }

      expect(run_body({ "mode" => "delete", "onMissing" => "ignore" }, ctx)).to be(true)
      expect(EntityEntry.where(id: own.id)).to exist
      expect(ctx[:errors]).to eq([])
    end
  end
end
