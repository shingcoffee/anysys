# frozen_string_literal: true

require "rails_helper"

RSpec.describe FieldTemplates::Create do
  let_it_be(:customer) { create(:customer) }

  let(:valid_params) do
    {
      name:          "My Template",
      configuration: { "fields" => [] }.to_json,
      customer_id:   customer.id
    }
  end

  def call(params)
    signal, (ctx, _) = described_class.call({ params: params })
    [signal, ctx]
  end

  describe "success path" do
    it "emits a :success signal" do
      signal, = call(valid_params)
      expect(signal.to_h[:semantic]).to eq(:success)
    end

    it "persists a new FieldTemplate record" do
      expect { call(valid_params) }.to change(FieldTemplate, :count).by(1)
    end

    it "sets a persisted model on ctx" do
      _, ctx = call(valid_params)
      expect(ctx[:model]).to be_a(FieldTemplate)
      expect(ctx[:model]).to be_persisted
    end

    it "stores the supplied name" do
      call(valid_params)
      expect(FieldTemplate.last.name).to eq("My Template")
    end
  end

  describe "validation failure" do
    it "emits a :failure signal when name is blank" do
      signal, = call(valid_params.merge(name: ""))
      expect(signal.to_h[:semantic]).to eq(:failure)
    end

    it "emits a :failure signal when configuration is missing" do
      signal, = call(valid_params.merge(configuration: nil))
      expect(signal.to_h[:semantic]).to eq(:failure)
    end

    it "does not persist the record on validation failure" do
      expect { call(valid_params.merge(name: "")) }.not_to change(FieldTemplate, :count)
    end

    it "populates contract errors on failure" do
      _, ctx = call(valid_params.merge(name: ""))
      expect(ctx[:contract].errors[:name]).to be_present
    end

    it "fails for a duplicate name within the same customer" do
      FieldTemplate.create!(name: "My Template", configuration: "{}",
                            customer_id: customer.id, built_in: false)
      signal, ctx = call(valid_params)
      expect(signal.to_h[:semantic]).to eq(:failure)
      expect(ctx[:contract].errors[:name]).to include("already exists")
    end
  end
end
