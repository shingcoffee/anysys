# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeGenerators::ElementTypes::Process::Validation::BuildContractGenerator do
  let(:context) { {} }
  let(:base)    { {} }
  let(:element) { { "config" => base } }

  it_behaves_like "a code generator"

  def body(overrides = {})
    described_class.new({ "config" => base.merge(overrides) }, context).generate_body
  end

  def errors_for(config)
    described_class.new({ "config" => config }, context).validate_config(config)
  end

  describe "schema" do
    it "has only :required errors for schema defaults" do
      schema = described_class._config_schema
      unexpected = errors_for(schema.defaults).reject { |error| error.code == :required }
      expect(unexpected).to eq([])
    end
  end

  it "generates the sample step" do
    expect(generated_step).to eq(<<~RUBY.chomp)
      def test_step(ctx, **)
        unless ctx[:model]
          return FlowchartRuntime::Step.fail(ctx, :record_missing, field: :modelVariable)
        end
        form = EntityEntryContract.build_for(
          ctx[:bound_entity],
          audience: ctx[:audience],
          writable_slugs: ctx[:writable_slugs]
        )
        ctx[:contract] = form.new(ctx[:model])
        true
      end
    RUBY
  end

  describe "#generate_body" do
    it "honours configured contractClass" do
      expect(body("contractClass" => "OrderContract")).to include("form = OrderContract.build_for(")
    end

    it "ignores a leftover resultVar and still writes ctx[:contract]" do
      expect(body("resultVar" => "my_contract")).to include("ctx[:contract] = form.new")
      expect(body("resultVar" => "my_contract")).not_to include("ctx[:my_contract]")
    end

    it "honours configured modelVariable" do
      expect(body("modelVariable" => "record")).to include("form.new(ctx[:record])")
    end
  end

  describe "#validate_config" do
    it "rejects malformed contractClass names" do
      codes = errors_for("contractClass" => "not a class").map(&:code)
      expect(codes).to include(:invalid_class_name)
    end

    it "accepts namespaced class names" do
      expect(errors_for("contractClass" => "Shop::OrderContract")).to eq([])
    end

    it "accepts blank contractClass (default applies)" do
      expect(errors_for({})).to eq([])
    end
  end

  describe "#dependencies" do
    it "depends on :new_model (contract wraps a model)" do
      expect(described_class.new(element, context).dependencies).to eq([:new_model])
    end
  end

  describe "behaviour" do
    it "wraps a tenant's entry and does not touch another tenant's row" do
      customer_a = create(:customer)
      customer_b = create(:customer)
      entity_a = create(:entity, :with_name_status_schema, customer: customer_a)
      entity_b = create(:entity, :with_name_status_schema, customer: customer_b)
      entry_a = create(:entity_entry, :with_data, entity: entity_a, customer: customer_a, entry_data: { "name" => "Ada" })
      entry_b = create(:entity_entry, :with_data, entity: entity_b, customer: customer_b, entry_data: { "name" => "Bo" })

      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: described_class.sample_input,
        ctx: {
          bound_entity: entity_a,
          audience: "admin",
          model: entry_a,
          customer_id: customer_a.id,
          params: {}
        }
      )

      expect(result[:outcome]).to eq(true)
      contract = result[:ctx][:contract]
      expect(contract.model).to eq(entry_a)
      expect(contract.model.customer_id).to eq(customer_a.id)
      expect(entry_b.reload.data).to include("Bo")
    end

    it "fails with record_missing when the model variable is empty" do
      customer = create(:customer)
      entity = create(:entity, :with_name_status_schema, customer: customer)
      result = CodeGenerators::TestRunner.execute(
        described_class,
        config: described_class.sample_input,
        ctx: { bound_entity: entity, audience: "admin", model: nil, customer_id: customer.id, errors: [] }
      )

      expect(result[:outcome]).to eq(false)
      expect(result[:ctx][:errors]).to eq([I18n.t("flowchart_runtime.errors.record_missing")])
    end
  end
end
