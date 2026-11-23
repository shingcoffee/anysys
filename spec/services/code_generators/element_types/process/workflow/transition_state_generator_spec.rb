# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Workflow::TransitionStateGenerator do
  let(:element) { { "config" => {} } }
  let(:context) { {} }

  it_behaves_like "a code generator"

  def generate(config = described_class.sample_input)
    described_class.new({ "config" => config }, context).generate_body
  end

  def errors(config, ctx = context)
    described_class.new({ "config" => config }, ctx).validate_config(config)
  end

  def execute(config, ctx)
    CodeGenerators::TestRunner.execute(described_class, config: config, ctx: ctx)
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

  let(:map) do
    [{ "key" => "draft", "value" => "submitted" }, { "key" => "submitted", "value" => "approved, rejected" }]
  end

  it "has only :required errors for schema defaults" do
    unexpected = errors(described_class._config_schema.defaults).reject { |error| error.code == :required }
    expect(unexpected).to eq([])
  end

  it "accepts sample_input and compiles" do
    sample = described_class.sample_input
    expect(errors(sample)).to eq([])
    expect { RubyVM::InstructionSequence.compile("def test_step(ctx, **)\n#{generate(sample)}\nend") }.not_to raise_error
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        FlowchartRuntime::Step.attempt(
          ctx,
          :"transition_state.failed",
          FlowchartRuntime::StateMachine::Error
        ) do
          result = FlowchartRuntime::StateMachine.transition(
            ctx,
            current: FlowchartRuntime::StateMachine.read_field(ctx[:model], "status"),
            target: "approved",
            transitions: {"draft" => "submitted", "submitted" => "approved, rejected"},
            record: ctx[:model],
            state_field: "status"
          )
          next false unless result
          ctx[:state] = result[:state]
          ctx[:previous_state] = result[:previous_state]
          ctx[:transitioned] = result[:transitioned]
          result
        end
      end
    RUBY
  end

  it "generates a variable-source step" do
    expect(generated_step(described_class.sample_input.merge("stateSource" => "variable", "stateVariable" => "status"))).to include("current: ctx[:status]", "variable: :status")
    expect(generated_step(described_class.sample_input.merge("stateSource" => "variable", "stateVariable" => "status"))).not_to include("record:")
  end

  it "rejects an empty transitions list in variable mode" do
    variable = described_class.sample_input.merge("stateSource" => "variable", "stateVariable" => "status")
    expect(errors(variable.merge("transitions" => [])).map(&:field)).to include("transitions")
    expect(errors(variable.except("transitions")).map(&:field)).to include("transitions")
  end

  it "lets a record step leave the map empty to follow its state field's lifecycle" do
    expect(errors(described_class.sample_input.merge("transitions" => [])).map(&:field)).not_to include("transitions")
    expect(errors(described_class.sample_input.except("transitions")).map(&:field)).not_to include("transitions")
  end

  it "requires the map in record mode when the page's entity declares no lifecycle on the field" do
    customer = create(:customer)
    plain = create(:entity, customer: customer, property_schema: [
      { "name" => "Status", "name_slug" => "status", "html_type" => "select",
        "config" => { "source" => "manual", "options" => [{ "label" => "Draft", "value" => "draft", "default" => true }] } }
    ].to_json)
    with_lifecycle = create(:entity, customer: customer, property_schema: [
      { "name" => "Status", "name_slug" => "status", "html_type" => "select",
        "config" => { "source" => "manual", "options" => [{ "label" => "Draft", "value" => "draft", "default" => true },
                                                          { "label" => "Submitted", "value" => "submitted" }] },
        "lifecycle" => { "transitions" => [{ "from" => "draft", "to" => "submitted", "by" => ["member"] }] } }
    ].to_json)
    config = described_class.sample_input.merge("stateField" => "status", "transitions" => [])

    expect(errors(config, { bound_entity: plain }).map(&:field)).to include("transitions")
    expect(errors(config, { bound_entity: with_lifecycle }).map(&:field)).not_to include("transitions")
    expect(errors(config.merge("modelVariable" => "order"), { bound_entity: plain }).map(&:field)).not_to include("transitions")
  end

  it "requires stateField in record mode and stateVariable in variable mode" do
    record = described_class.sample_input.except("stateField")
    expect(errors(record).map(&:field)).to include("stateField")
    variable = described_class.sample_input.merge("stateSource" => "variable").except("stateVariable")
    expect(errors(variable).map(&:field)).to include("stateVariable")
  end

  it "rejects a nested stateVariable path because the new state could not be written back" do
    config = described_class.sample_input.merge("stateSource" => "variable", "stateVariable" => "order.status")
    expect(errors(config).map(&:code)).to include(:plain_variable)
    expect(errors(config.merge("stateVariable" => "status")).map(&:code)).not_to include(:plain_variable)
  end

  it "rejects an unknown attribute when a bound entity is present" do
    customer = create(:customer)
    entity = create(:entity, :with_name_status_schema, customer: customer)
    problems = errors(described_class.sample_input.merge("stateField" => "not_a_field"), { bound_entity: entity })
    expect(problems.map(&:code)).to include(:unknown_attribute)

    other_record = described_class.sample_input.merge("stateField" => "not_a_field", "modelVariable" => "order")
    expect(errors(other_record, { bound_entity: entity }).map(&:code)).not_to include(:unknown_attribute)
  end

  described_class::STATE_SOURCES.each do |source|
    it "emits a BodyLint-clean body for stateSource #{source}" do
      config = described_class.sample_input.merge("stateSource" => source)
      next if errors(config).any?

      src = generate(config)
      result = CodeGenerators::BodyLint.check(src, outputs: %w[state previous_state transitioned])
      expect(result.ok?).to be_truthy, "#{result.violations.inspect}\n#{src}"
      expect(src).to include("FlowchartRuntime::StateMachine.transition")
    end
  end

  it "emits a distinct body for every stateSource, targetSource, and onInvalid" do
    sources = described_class::STATE_SOURCES.map { |value| generate(described_class.sample_input.merge("stateSource" => value)) }
    expect(sources.uniq.size).to eq(described_class::STATE_SOURCES.size)
    targets = described_class::TARGET_SOURCES.map { |value| generate(described_class.sample_input.merge("targetSource" => value)) }
    expect(targets.uniq.size).to eq(described_class::TARGET_SOURCES.size)
    invalids = described_class::ON_INVALID.map { |value| generate(described_class.sample_input.merge("onInvalid" => value)) }
    expect(invalids.uniq.size).to eq(described_class::ON_INVALID.size)
  end

  it "does not emit a hidden variable-mode field while in record mode" do
    base = generate(described_class.sample_input)
    leaked = generate(described_class.sample_input.merge("stateVariable" => "other_status"))
    expect(leaked).to eq(base)
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }
    let(:schema) do
      [
        { "name" => "Status", "name_slug" => "status", "data_type" => "string" },
        { "name" => "Changed", "name_slug" => "status_changed_at", "data_type" => "datetime" }
      ]
    end
    let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json) }
    let(:record_config) do
      described_class.sample_input.merge(
        "stateField" => "status",
        "targetState" => "submitted",
        "transitions" => map
      )
    end

    def loaded_entry(customer:, data:)
      entry = create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: data)
      model = FlowchartRuntime::Entries.find_by({ bound_entity: entity, customer_id: customer.id }, "id" => entry.id)
      [entry, model]
    end

    it "transitions a tenant record without saving" do
      own, model = loaded_entry(customer: customer, data: { "status" => "draft" })
      _foreign, = loaded_entry(customer: other, data: { "status" => "draft" })
      ctx = { bound_entity: entity, customer_id: customer.id, model: model, errors: [] }

      expect(run_body(record_config, ctx)).to be_truthy
      expect(ctx[:state]).to eq("submitted")
      expect(ctx[:previous_state]).to eq("draft")
      expect(ctx[:transitioned]).to be_truthy
      expect(model.status).to eq("submitted")
      expect(own.reload.data_json["status"]).to eq("draft")
    end

    described_class::ON_INVALID.each do |mode|
      it "handles onInvalid #{mode} for a blocked transition" do
        _own, model = loaded_entry(customer: customer, data: { "status" => "draft" })
        ctx = { bound_entity: entity, customer_id: customer.id, model: model, errors: [] }
        config = record_config.merge("targetState" => "approved", "onInvalid" => mode)
        result = execute(config, ctx)

        if mode == "fail"
          expect(result[:outcome]).to eq(false)
          expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.transition_state.invalid_transition",
                                             from: "draft", to: "approved")])
          expect(model.status).to eq("draft")
        else
          expect(result[:outcome]).to be_truthy
          expect(ctx[:transitioned]).to be(false)
          expect(ctx[:state]).to eq("draft")
          expect(ctx[:errors]).to eq([])
        end
      end
    end

    described_class::STATE_SOURCES.each do |source|
      it "moves state from stateSource #{source}" do
        if source == "record"
          _own, model = loaded_entry(customer: customer, data: { "status" => "draft" })
          ctx = { bound_entity: entity, customer_id: customer.id, model: model, errors: [] }
          config = record_config.merge("stateSource" => source)
        else
          ctx = { status: "draft", errors: [] }
          config = record_config.merge("stateSource" => source, "stateVariable" => "status")
        end
        execute(config, ctx)
        expect(ctx[:state]).to eq("submitted")
        expect(ctx[:transitioned]).to be_truthy
        expect(ctx[:status]).to eq("submitted") if source == "variable"
      end
    end

    described_class::TARGET_SOURCES.each do |source|
      it "reads the target from targetSource #{source}" do
        ctx = { status: "draft", next_status: "submitted", errors: [] }
        config = described_class.sample_input.merge(
          "stateSource" => "variable",
          "stateVariable" => "status",
          "targetSource" => source,
          "targetState" => "submitted",
          "targetVariable" => "next_status",
          "transitions" => map
        )
        execute(config, ctx)
        expect(ctx[:state]).to eq("submitted")
      end
    end

    it "no-ops when allowSameState is true" do
      ctx = { status: "draft", errors: [] }
      config = described_class.sample_input.merge(
        "stateSource" => "variable", "stateVariable" => "status",
        "targetState" => "draft", "allowSameState" => true, "transitions" => map
      )
      execute(config, ctx)
      expect(ctx[:transitioned]).to be(false)
      expect(ctx[:state]).to eq("draft")
    end

    it "fails when the guard expression is false" do
      ctx = { status: "draft", allowed: false, errors: [] }
      config = described_class.sample_input.merge(
        "stateSource" => "variable", "stateVariable" => "status",
        "targetState" => "submitted", "transitions" => map,
        "guardExpression" => "ctx[:allowed]"
      )
      result = execute(config, ctx)
      expect(result[:outcome]).to eq(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.transition_state.guard_failed",
                                         from: "draft", to: "submitted")])
    end

    it "stamps timestampField when the record transitions" do
      _own, model = loaded_entry(customer: customer, data: { "status" => "draft" })
      ctx = { bound_entity: entity, customer_id: customer.id, model: model, errors: [] }
      stamp = Time.zone.local(2026, 3, 1, 9)
      travel_to stamp do
        execute(record_config.merge("timestampField" => "status_changed_at"), ctx)
      end
      expect(model.status_changed_at).to eq(stamp.utc.iso8601(3))
    end

    context "when the record step has no map and the state field declares a lifecycle" do
      let(:schema) do
        [{ "name" => "Status", "name_slug" => "status", "html_type" => "select",
           "config" => { "source" => "manual", "options" => [
             { "label" => "Draft", "value" => "draft", "default" => true },
             { "label" => "Submitted", "value" => "submitted" }, { "label" => "Approved", "value" => "approved" }
           ] },
           "lifecycle" => { "transitions" => [{ "from" => "draft", "to" => "submitted", "by" => ["member"] },
                                              { "from" => "submitted", "to" => "approved", "by" => ["admin"] }] } }]
      end
      let(:lifecycle_config) { record_config.merge("transitions" => []) }

      it "follows the lifecycle, whoever runs it" do
        _own, model = loaded_entry(customer: customer, data: { "status" => "draft" })
        ctx = { bound_entity: entity, customer_id: customer.id, model: model, audience: "admin", errors: [] }

        expect(run_body(lifecycle_config, ctx)).to be_truthy
        expect(ctx).to include(state: "submitted", previous_state: "draft", transitioned: true)
      end

      it "refuses a change the lifecycle does not list" do
        _own, model = loaded_entry(customer: customer, data: { "status" => "draft" })
        ctx = { bound_entity: entity, customer_id: customer.id, model: model, errors: [] }

        expect(run_body(lifecycle_config.merge("targetState" => "approved"), ctx)).to be(false)
        expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.transition_state.invalid_transition",
                                           from: "draft", to: "approved")])
        expect(model.status).to eq("draft")
      end
    end

    it "fails with transition_state.failed when the record lacks the state field at run time" do
      _own, model = loaded_entry(customer: customer, data: { "status" => "draft" })
      ctx = { bound_entity: entity, customer_id: customer.id, model: model, errors: [] }

      config = record_config.merge("stateField" => "phase", "initialState" => "draft")
      expect(run_body(config, ctx)).to be(false)
      expect(ctx[:error_details].last["code"]).to eq("transition_state.failed")
      expect(ctx[:error_details].last.dig("details", :reason)).to eq("Error")
    end
  end
end
