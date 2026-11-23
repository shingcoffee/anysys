# frozen_string_literal: true

require "rails_helper"

RSpec.describe FieldTemplates::Delete do
  let_it_be(:customer) { create(:customer) }
  let!(:template) do
    FieldTemplate.create!(name: "To Delete", configuration: "{}",
                          customer_id: customer.id, built_in: false)
  end

  def call(id:, customer_id:)
    signal, (ctx, _) = described_class.call({ id: id, customer_id: customer_id })
    [signal, ctx]
  end

  describe "success path" do
    it "emits a :success signal" do
      signal, = call(id: template.id, customer_id: customer.id)
      expect(signal.to_h[:semantic]).to eq(:success)
    end

    it "destroys the template" do
      expect { call(id: template.id, customer_id: customer.id) }
        .to change(FieldTemplate, :count).by(-1)
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

    it "does not destroy any record when find_model fails" do
      count_before = FieldTemplate.count
      call(id: 0, customer_id: customer.id)
      expect(FieldTemplate.count).to eq(count_before)
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

    it "does not destroy the built-in template" do
      call(id: builtin.id, customer_id: customer.id)
      expect(FieldTemplate.exists?(builtin.id)).to be true
    end
  end
end
