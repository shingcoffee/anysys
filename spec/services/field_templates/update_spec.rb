# frozen_string_literal: true

require "rails_helper"

RSpec.describe FieldTemplates::Update do
  let_it_be(:customer) { create(:customer) }
  let!(:template) do
    FieldTemplate.create!(name: "Original", configuration: "{}",
                          customer_id: customer.id, built_in: false)
  end

  let(:valid_params) { { name: "Renamed", configuration: '{"fields":[]}' } }

  def call(id:, customer_id:, params: valid_params)
    signal, (ctx, _) = described_class.call({ id: id, customer_id: customer_id, params: params })
    [signal, ctx]
  end

  describe "success path" do
    it "emits a :success signal" do
      signal, = call(id: template.id, customer_id: customer.id)
      expect(signal.to_h[:semantic]).to eq(:success)
    end

    it "updates the template name" do
      call(id: template.id, customer_id: customer.id)
      expect(template.reload.name).to eq("Renamed")
    end

    it "sets the model on ctx" do
      _, ctx = call(id: template.id, customer_id: customer.id)
      expect(ctx[:model]).to eq(template)
    end
  end

  describe "find_model failure" do
    it "fails when the id does not exist" do
      signal, = call(id: 0, customer_id: customer.id)
      expect(signal.to_h[:semantic]).to eq(:failure)
    end

    it "fails when id belongs to a different customer (cross-tenant isolation)" do
      other_customer = create(:customer)
      other_template = FieldTemplate.create!(name: "X", configuration: "{}",
                                             customer_id: other_customer.id,
                                             built_in: false)
      signal, = call(id: other_template.id, customer_id: customer.id)
      expect(signal.to_h[:semantic]).to eq(:failure)
    end
  end

  describe "check_not_built_in" do
    let!(:builtin) do
      FieldTemplate.create!(name: "Built-in", configuration: "{}",
                            customer_id: customer.id, built_in: true)
    end

    it "fails for a built-in template" do
      signal, = call(id: builtin.id, customer_id: customer.id)
      expect(signal.to_h[:semantic]).to eq(:failure)
    end

    it "does not modify the built-in template" do
      call(id: builtin.id, customer_id: customer.id)
      expect(builtin.reload.name).to eq("Built-in")
    end
  end

  describe "validation failure" do
    it "fails when name is blank" do
      signal, = call(id: template.id, customer_id: customer.id, params: valid_params.merge(name: ""))
      expect(signal.to_h[:semantic]).to eq(:failure)
    end

    it "fails when name exceeds 100 characters" do
      signal, = call(id: template.id, customer_id: customer.id, params: valid_params.merge(name: "x" * 101))
      expect(signal.to_h[:semantic]).to eq(:failure)
    end

    it "does not persist changes on validation failure" do
      call(id: template.id, customer_id: customer.id, params: valid_params.merge(name: ""))
      expect(template.reload.name).to eq("Original")
    end
  end
end
