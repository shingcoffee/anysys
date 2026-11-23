# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityEntry, "calculated fields" do
  let_it_be(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, customer: customer, property_schema: [
      { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
      { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number",
        "readonly" => true, "storage" => "computed", "formula" => "price * 2" }
    ].to_json)
  end

  describe "validate_data_keys" do
    it "allows data with only data field keys" do
      entry = described_class.new(entity: entity, customer: customer, data: { "price" => "100" }.to_json)
      expect(entry).to be_valid
    end

    it "rejects truly invalid keys" do
      entry = described_class.new(entity: entity, customer: customer, data: { "price" => "100", "bogus" => "x" }.to_json)
      expect(entry).not_to be_valid
    end
  end

  describe ".build_for" do
    it "creates getter but no setter for calculated fields" do
      model_class = described_class.build_for(entity)
      instance = model_class.new(customer: customer)
      expect(instance).to respond_to(:price=)
      expect(instance).not_to respond_to(:total=)
      expect(instance).to respond_to(:total)
    end
  end
end
