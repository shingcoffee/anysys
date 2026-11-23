# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::ModelOperations::NewModelGenerator do
  let(:element) { { "id" => "step_new_model", "type" => "process", "config" => {} } }
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
        ctx[:model] = FlowchartRuntime::Entries.scope(ctx).new(customer_id: ctx[:customer_id])
      end
    RUBY
  end

  it "scopes the new record through Entries" do
    expect(generate).to include("ctx[:model] = FlowchartRuntime::Entries.scope(ctx).new(customer_id: ctx[:customer_id])")
    expect(generate).not_to include("EntityEntry.build_for")
  end

  it "uses the configured resultVar" do
    expect(generate("resultVar" => "record")).to include("ctx[:record] = FlowchartRuntime::Entries.scope(ctx).new")
  end

  it "is version 5.2.0" do
    expect(described_class._metadata[:version]).to eq("5.2.0")
  end

  it "does not assign fields when assignments is empty" do
    expect(generate).not_to include("Entries.assign")
  end

  it "assigns mapped expressions onto the new record" do
    code = generate("assignments" => [{ "key" => "email", "value" => "ctx[:params][:email]" }])
    expect(code).to include("ctx[:model] = FlowchartRuntime::Entries.scope(ctx).new(customer_id: ctx[:customer_id])")
    expect(code).to include('FlowchartRuntime::Entries.assign(ctx[:model], {"email" => ctx[:params][:email]}, strict: true)')
  end

  describe "behaviour" do
    let(:customer) { create(:customer) }
    let(:other_customer) { create(:customer) }
    let(:schema) { [{ "name" => "Email", "name_slug" => "email", "data_type" => "string" }] }
    let(:entity) { create(:entity, customer: customer, property_schema: schema.to_json) }

    it "builds an unsaved tenant-scoped entry and never a foreign row" do
      ctx = { bound_entity: entity, customer_id: customer.id }
      expect(run_body({}, ctx)).to be_a(EntityEntry)
      expect(ctx[:model]).not_to be_persisted
      expect(ctx[:model].customer_id).to eq(customer.id)
      expect(ctx[:model].entity_id).to eq(entity.id)
      expect(EntityEntry.where(customer_id: other_customer.id).count).to eq(0)
    end

    it "pre-fills assignments on this tenant's new record only" do
      ctx = { bound_entity: entity, customer_id: customer.id, params: { email: "a@x.io" } }
      config = { "assignments" => [{ "key" => "email", "value" => "ctx[:params][:email]" }] }

      expect(run_body(config, ctx)).to be_a(EntityEntry)
      expect(ctx[:model]).not_to be_persisted
      expect(ctx[:model].email).to eq("a@x.io")
      expect(ctx[:model].customer_id).to eq(customer.id)
      expect(EntityEntry.where(customer_id: other_customer.id).count).to eq(0)
    end
  end
end
