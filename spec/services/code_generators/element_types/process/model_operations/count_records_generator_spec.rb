# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::CountRecordsGenerator do
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
        ctx[:count] = FlowchartRuntime::Entries.tally(ctx)
      end
    RUBY
  end

  it "generates the exists variant" do
    expect(generated_step(described_class.sample_input.merge("resultAs" => "exists", "resultVar" => "exists"))).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:exists] = FlowchartRuntime::Entries.tally(ctx, result_as: "exists")
      end
    RUBY
  end

  it "generates the absent variant" do
    expect(generated_step(described_class.sample_input.merge("resultAs" => "absent", "resultVar" => "exists"))).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        ctx[:exists] = FlowchartRuntime::Entries.tally(ctx, result_as: "absent")
      end
    RUBY
  end

  it "emits another entity and own record scope" do
    code = generated_step(described_class.sample_input.merge("entity" => "Booking", "recordScope" => "own"))
    expect(code).to include('entity: "Booking"', 'record_scope: "own"')
    expect(code).to include("FlowchartRuntime::Step.attempt")
  end

  it "fails the step when onZero is fail" do
    expect(generated_step(described_class.sample_input.merge("onZero" => "fail"))).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        count = FlowchartRuntime::Entries.tally(ctx)
        ctx[:count] = count
        return FlowchartRuntime::Step.fail(ctx, :"count_records.zero") unless count != 0
        count
      end
    RUBY
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other) { create(:customer) }
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { "name" => "Email", "name_slug" => "email", "type" => "Types::String" }
      ].to_json)
    end

    before do
      create(:entity_entry, :with_data, entity: entity, customer: customer, entry_data: { "email" => "a@x.io" })
      create(:entity_entry, :with_data, entity: entity, customer: other, entry_data: { "email" => "b@x.io" })
    end

    it "counts, detects existence, and ignores the other tenant" do
      ctx = { bound_entity: entity, customer_id: customer.id }
      counted = CodeGenerators::TestRunner.execute(described_class, config: { "resultAs" => "count", "resultVar" => "count" }, ctx: ctx)
      expect(counted[:outcome]).to eq(1)
      expect(ctx[:count]).to eq(1)

      exists = CodeGenerators::TestRunner.execute(described_class, config: { "resultAs" => "exists", "resultVar" => "exists" }, ctx: ctx.dup)
      expect(exists[:outcome]).to be(true)

      foreign = { bound_entity: entity, customer_id: other.id }
      absent = CodeGenerators::TestRunner.execute(described_class, config: { "resultAs" => "absent", "resultVar" => "exists" }, ctx: foreign)
      expect(absent[:outcome]).to eq(!EntityEntry.where(customer_id: other.id, entity_id: entity.id).exists?)
    end

    it "fails with a translated message when onZero is fail and the tenant count is 0" do
      EntityEntry.where(customer_id: customer.id, entity_id: entity.id).delete_all
      ctx = { bound_entity: entity, customer_id: customer.id, errors: [] }
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: { "resultAs" => "count", "onZero" => "fail", "resultVar" => "count" },
        ctx: ctx
      )
      expect(result[:outcome]).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.count_records.zero")])
    end

    it "counts another reachable entity's tenant rows only" do
      bookings = create(:entity, customer: customer, name: "Booking", property_schema: [
        { "name" => "Email", "name_slug" => "email", "type" => "Types::String" }
      ].to_json)
      create(:entity_entry, :with_data, entity: bookings, customer: customer, entry_data: { "email" => "a@x.io" })
      create(:entity_entry, :with_data, entity: bookings, customer: customer, entry_data: { "email" => "b@x.io" })
      create(:entity_entry, :with_data, entity: bookings, customer: other, entry_data: { "email" => "c@x.io" })
      ctx = { bound_entity: entity, customer_id: customer.id }

      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: { "entity" => "Booking", "resultAs" => "count", "resultVar" => "count" },
        ctx: ctx
      )
      expect(result[:outcome]).to eq(2)
      expect(ctx[:count]).to eq(2)
    end
  end
end
