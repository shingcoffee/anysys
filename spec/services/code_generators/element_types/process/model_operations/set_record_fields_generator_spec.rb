# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::SetRecordFieldsGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config, ctx = context)
    described_class.new({ "config" => config }, ctx).validate_config(config)
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
        FlowchartRuntime::Step.attempt(
          ctx,
          :"set_record_fields.failed",
          FlowchartRuntime::Entries::Error
        ) do
          record = ctx[:model]
          return FlowchartRuntime::Step.fail(ctx, :"set_record_fields.missing_record") unless record
          FlowchartRuntime::Entries.assign(record, {"email" => ctx[:params][:email]}, strict: true)
        end
      end
    RUBY
  end

  it "emits only_blank and skip_nil variants" do
    blank = generate(described_class.sample_input.merge("writeMode" => "only_blank", "skipNilValues" => true))
    expect(blank).to include('write_mode: "only_blank"')
    expect(blank).to include("skip_nil: true")
    expect(CodeGenerators::BodyLint.check(blank, outputs: []).ok?).to be(true)
  end

  it "rejects an unknown attribute at generation when the bound entity is present" do
    customer = create(:customer)
    entity = create(:entity, customer: customer, property_schema: [
      { "name" => "Email", "name_slug" => "email", "data_type" => "string" }
    ].to_json)
    config = { "assignments" => [{ "key" => "not_a_field", "value" => "1" }] }
    problems = errors(config, { bound_entity: entity })

    expect(problems.map(&:code)).to include(:unknown_attribute)
    expect(problems.map(&:message).join).to include("not_a_field")
    expect(errors(config.merge("modelVariable" => "cart"), { bound_entity: entity }).map(&:code)).not_to include(:unknown_attribute)
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }
    let(:schema) do
      [
        { "name" => "Email", "name_slug" => "email", "data_type" => "string" },
        { "name" => "Status", "name_slug" => "status", "data_type" => "string" }
      ]
    end
    let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json) }

    it "writes JSON attributes on the tenant entry and leaves the other tenant untouched" do
      own = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "email" => "a@x.io", "status" => "open" })
      foreign = create(:entity_entry, :with_data, entity: entity, customer: other, entry_data: { "email" => "b@x.io", "status" => "open" })
      model = FlowchartRuntime::Entries.find_by({ bound_entity: entity, customer_id: customer.id }, "id" => own.id)
      ctx = {
        bound_entity: entity,
        customer_id: customer.id,
        model: model,
        params: { "email" => "n@x.io" }
      }
      config = {
        "modelVariable" => "model",
        "assignments" => [
          { "key" => "email", "value" => "ctx[:params][\"email\"]" },
          { "key" => "status", "value" => '"closed"' }
        ]
      }

      expect(run_body(config, ctx)).to eq(model)
      expect(model.email).to eq("n@x.io")
      expect(model.status).to eq("closed")
      expect(own.reload.data_json["email"]).to eq("a@x.io")
      expect(foreign.reload.data_json["email"]).to eq("b@x.io")
    end

    it "only_blank fills empty fields and skipNilValues leaves a nil assignment untouched" do
      own = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "email" => "a@x.io" })
      model = FlowchartRuntime::Entries.find_by({ bound_entity: entity, customer_id: customer.id }, "id" => own.id)
      filled = { bound_entity: entity, customer_id: customer.id, model: model }
      expect(run_body({
        "modelVariable" => "model",
        "writeMode" => "only_blank",
        "assignments" => [
          { "key" => "email", "value" => '"n@x.io"' },
          { "key" => "status", "value" => '"open"' }
        ]
      }, filled)).to eq(model)
      expect(model.email).to eq("a@x.io")
      expect(model.status).to eq("open")

      skipped = { bound_entity: entity, customer_id: customer.id, model: model }
      expect(run_body({
        "modelVariable" => "model",
        "skipNilValues" => true,
        "assignments" => [{ "key" => "email", "value" => "nil" }]
      }, skipped)).to eq(model)
      expect(model.email).to eq("a@x.io")
    end

    it "fails when the record path is nil" do
      ctx = { bound_entity: entity, customer_id: customer.id, model: nil, errors: [] }
      expect(run_body(described_class.sample_input, ctx)).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.set_record_fields.missing_record")])
    end
  end
end
