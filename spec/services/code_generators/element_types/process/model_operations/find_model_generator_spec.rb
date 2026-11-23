# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::FindModelGenerator do
  let(:element) { { "config" => {} } }
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
        ctx[:model] = FlowchartRuntime::Entries.find_by(
          ctx,
          "id" => FlowchartRuntime::Step.dig(ctx[:params], :id)
        )
        return FlowchartRuntime::Step.fail(ctx, :record_not_found, field: :idSource) unless ctx[:model]
        true
      end
    RUBY
  end

  it "is version 5.3.0 and accepts current_person as a findBy value" do
    expect(described_class._metadata[:version]).to eq("5.3.0")
    expect(errors("findBy" => "current_person", "resultVar" => "model")).to eq([])
  end

  it "emits a BodyLint-clean body for each findBy variant" do
    %w[id attribute current_person].each do |find_by|
      config = described_class.sample_input.merge("findBy" => find_by)
      next if errors(config).any?

      result = CodeGenerators::BodyLint.check(generate(config), outputs: %w[model])
      expect(result.ok?).to be(true), "#{find_by}: #{result.violations.inspect}\n#{generate(config)}"
    end
  end

  it "looks up by id through Entries.find_by and fails with record_not_found" do
    code = generate("findBy" => "id", "idSource" => "params.id", "resultVar" => "model")
    expect(code).to include('FlowchartRuntime::Entries.find_by(ctx, "id" => FlowchartRuntime::Step.dig(ctx[:params], :id))')
    expect(code).to include("return FlowchartRuntime::Step.fail(ctx, :record_not_found, field: :idSource) unless ctx[:model]")
    expect(code).not_to include("ctx[:_last_error]")
    expect(code).not_to include("I18n.t")
  end

  it "looks up by attribute through Entries.find_by" do
    code = generate("findBy" => "attribute", "findField" => "email", "findValue" => "params.email", "resultVar" => "student")
    expect(code).to include('FlowchartRuntime::Entries.find_by(ctx, "email" => FlowchartRuntime::Step.dig(ctx[:params], :email))')
    expect(code).to include("return FlowchartRuntime::Step.fail(ctx, :record_not_found, field: :findValue) unless ctx[:student]")
  end

  it "looks up the signed-in member's record through Entries.find_current_person" do
    code = generate("findBy" => "current_person", "resultVar" => "model")
    expect(code).to include("FlowchartRuntime::Entries.find_current_person(ctx)")
    expect(code).to include("return FlowchartRuntime::Step.fail(ctx, :record_not_found) unless ctx[:model]")
    expect(code).not_to include("ctx[:params]")
    expect(code).not_to include("idSource")
  end

  it "emits distinct onNotFound branches" do
    fail_code = generate("findBy" => "id", "idSource" => "params.id", "onNotFound" => "fail")
    nil_code = generate("findBy" => "id", "idSource" => "params.id", "onNotFound" => "nil")
    new_code = generate("findBy" => "id", "idSource" => "params.id", "onNotFound" => "new")
    expect(fail_code).to include("return FlowchartRuntime::Step.fail(ctx, :record_not_found, field: :idSource) unless ctx[:model]")
    expect(nil_code).not_to include("Step.fail")
    expect(nil_code).not_to include("Entries.scope(ctx).new")
    expect(new_code).to include("FlowchartRuntime::Entries.scope(ctx).new(customer_id: ctx[:customer_id])")
    expect(new_code).not_to include("Step.fail")
  end

  it "pre-fills the lookup attribute when onNotFound is new and findBy is attribute" do
    code = generate("findBy" => "attribute", "findField" => "email", "findValue" => "params.email",
                    "onNotFound" => "new")
    expect(code).to include('FlowchartRuntime::Entries.assign(ctx[:model], { "email" => FlowchartRuntime::Step.dig(ctx[:params], :email) }, strict: true)')
  end

  it "uses a custom localized message when notFoundMessage is set" do
    code = generate("findBy" => "id", "idSource" => "params.id", "onNotFound" => "fail",
                    "notFoundMessage" => { "en" => "Missing student", "zh-CN" => "未找到学生。" })
    expect(code).to include("FlowchartRuntime::Step.fail_message(ctx,")
    expect(code).to include("Missing student")
    expect(code).to include("code: :record_not_found, field: :idSource")
    expect(code).not_to include("Step.fail(ctx, :record_not_found")
  end

  it "records foundVar before applying onNotFound" do
    code = generate("findBy" => "id", "idSource" => "params.id", "foundVar" => "was_found")
    expect(code).to include("ctx[:was_found] = !ctx[:model].nil?")
  end

  it "passes a FOR UPDATE lock through Entries.find_by and find_current_person" do
    by_id = generate("findBy" => "id", "idSource" => "params.id", "lock" => true)
    expect(by_id).to include('FlowchartRuntime::Entries.find_by(ctx, { "id" => FlowchartRuntime::Step.dig(ctx[:params], :id) }, true)')

    by_person = generate("findBy" => "current_person", "lock" => true)
    expect(by_person).to include("FlowchartRuntime::Entries.find_current_person(ctx, lock: true)")
  end

  it "does not emit a lock argument by default" do
    expect(generate("findBy" => "id", "idSource" => "params.id")).not_to include(", true)")
  end

  it "does not leak notFoundMessage when onNotFound is not fail" do
    code = generate("findBy" => "id", "idSource" => "params.id", "onNotFound" => "nil",
                    "notFoundMessage" => { "en" => "hidden" })
    expect(code).not_to include("hidden")
    expect(code).not_to include("fail_message")
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other_customer) { create(:customer) }
    let(:schema) { [{ "name" => "Email", "name_slug" => "email", "data_type" => "string" }] }
    let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json) }

    def entry_for(customer:, data:)
      create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: data)
    end

    it "loads the tenant row by id and fails with a translated message for another tenant" do
      own = entry_for(customer: customer, data: { "email" => "a@x.io" })
      foreign = create(:entity_entry, customer: other_customer, entity: entity)
      ctx = { bound_entity: entity, customer_id: customer.id, params: { "id" => foreign.id }, errors: [] }

      expect(run_body({ "findBy" => "id", "idSource" => "params.id" }, ctx)).to be(false)
      expect(ctx[:model]).to be_nil
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.record_not_found")])
      expect(ctx[:error_details].last["code"]).to eq("record_not_found")

      own_ctx = { bound_entity: entity, customer_id: customer.id, params: { "id" => own.id }, errors: [] }
      expect(run_body({ "findBy" => "id", "idSource" => "params.id" }, own_ctx)).to be(true)
      expect(own_ctx[:model].id).to eq(own.id)
    end

    it "loads the tenant row by attribute and never returns another tenant's row" do
      own = entry_for(customer: customer, data: { "email" => "a@x.io" })
      entry_for(customer: other_customer, data: { "email" => "a@x.io" })
      ctx = { bound_entity: entity, customer_id: customer.id, params: { "email" => "a@x.io" }, errors: [] }
      config = { "findBy" => "attribute", "findField" => "email", "findValue" => "params.email" }

      expect(run_body(config, ctx)).to be(true)
      expect(ctx[:model].id).to eq(own.id)

      missing = { bound_entity: entity, customer_id: customer.id, params: { "email" => "missing@x.io" }, errors: [] }
      expect(run_body(config, missing)).to be(false)
      expect(missing[:errors]).to eq([I18n.t("flowchart_runtime.errors.record_not_found")])
    end

    describe "findBy current_person" do
      let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
      let(:member) { create(:user, :member, customer: customer) }
      let(:person_entity) do
        enable_module!("authentication", customer).set_extendable_model!(person_model, true)
        create(:entity, customer: customer, name: "Student", extended_model: person_model,
               property_schema: schema.to_json)
      end
      let(:own) { create(:entity_entry, entity: person_entity, customer: customer, user: member) }
      let(:config) { { "findBy" => "current_person", "resultVar" => "model" } }

      it "loads the member's linked entry and ignores a forged params id" do
        other = create(:entity_entry, entity: person_entity, customer: customer)
        ctx = {
          bound_entity: person_entity,
          customer_id: customer.id,
          current_person_ids: { person_entity.id.to_s => own.id },
          params: { "id" => other.id },
          errors: []
        }

        expect(run_body(config, ctx)).to be(true)
        expect(ctx[:model].id).to eq(own.id)
      end

      it "fails with record_not_found for anonymous, unlinked, and non-person entities" do
        anonymous = { bound_entity: person_entity, customer_id: customer.id, errors: [] }
        expect(run_body(config, anonymous)).to be(false)
        expect(anonymous[:errors]).to eq([I18n.t("flowchart_runtime.errors.record_not_found")])

        unlinked = {
          bound_entity: person_entity,
          customer_id: customer.id,
          current_person_ids: {},
          errors: []
        }
        expect(run_body(config, unlinked)).to be(false)
        expect(unlinked[:errors]).to eq([I18n.t("flowchart_runtime.errors.record_not_found")])

        not_person = {
          bound_entity: entity,
          customer_id: customer.id,
          current_person_ids: { entity.id.to_s => entry_for(customer: customer, data: {}).id },
          errors: []
        }
        expect(run_body(config, not_person)).to be(false)
        expect(not_person[:errors]).to eq([I18n.t("flowchart_runtime.errors.record_not_found")])
      end

      it "never loads another tenant's entry from the trusted map" do
        foreign = create(:entity_entry, entity: person_entity, customer: other_customer)
        ctx = {
          bound_entity: person_entity,
          customer_id: customer.id,
          current_person_ids: { person_entity.id.to_s => foreign.id },
          errors: []
        }

        expect(run_body(config, ctx)).to be(false)
        expect(ctx[:model]).to be_nil
        expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.record_not_found")])
      end
    end

    it "returns nil and continues when onNotFound is nil" do
      entry_for(customer: other_customer, data: { "email" => "a@x.io" })
      ctx = { bound_entity: entity, customer_id: customer.id, params: { "email" => "a@x.io" }, errors: [] }
      config = { "findBy" => "attribute", "findField" => "email", "findValue" => "params.email",
                 "onNotFound" => "nil", "foundVar" => "was_found" }

      expect(run_body(config, ctx)).to be(true)
      expect(ctx[:model]).to be_nil
      expect(ctx[:was_found]).to be(false)
      expect(ctx[:errors]).to eq([])
    end

    it "builds an unsaved tenant record pre-filled with the lookup attribute when onNotFound is new" do
      entry_for(customer: other_customer, data: { "email" => "a@x.io" })
      ctx = { bound_entity: entity, customer_id: customer.id, params: { "email" => "a@x.io" }, errors: [] }
      config = { "findBy" => "attribute", "findField" => "email", "findValue" => "params.email",
                 "onNotFound" => "new", "foundVar" => "was_found" }

      expect(run_body(config, ctx)).to be(true)
      expect(ctx[:was_found]).to be(false)
      expect(ctx[:model]).not_to be_persisted
      expect(ctx[:model].customer_id).to eq(customer.id)
      expect(ctx[:model].entity_id).to eq(entity.id)
      expect(ctx[:model].email).to eq("a@x.io")
      expect(EntityEntry.where(customer_id: other_customer.id).count).to eq(1)
    end

    it "fails with a custom localized message" do
      ctx = { bound_entity: entity, customer_id: customer.id, params: { "id" => 0 }, errors: [] }
      config = {
        "findBy" => "id",
        "idSource" => "params.id",
        "notFoundMessage" => { "en" => "Missing student", "zh-CN" => "未找到学生。" }
      }

      expect(run_body(config, ctx)).to be(false)
      expect(ctx[:errors]).to eq(["Missing student"])
      expect(ctx[:error_details].last["code"]).to eq("record_not_found")
    end
  end
end
