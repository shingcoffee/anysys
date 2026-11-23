# frozen_string_literal: true

require "rails_helper"

RSpec.describe FieldTemplates::Contract do
  let(:customer)  { create(:customer) }
  let(:template)  { FieldTemplate.new(customer_id: customer.id) }
  let(:form)      { described_class.new(template) }

  let(:valid_attrs) do
    { name: "Address Block", configuration: { "fields" => [] }.to_json, customer_id: customer.id }
  end

  describe "valid attributes" do
    it "is valid with name, configuration and customer_id" do
      expect(form.validate(valid_attrs)).to be true
      expect(form.errors).to be_empty
    end
  end

  describe "name" do
    it "is invalid when blank" do
      form.validate(valid_attrs.merge(name: ""))
      expect(form.errors[:name]).to be_present
    end

    it "is invalid when over 100 characters" do
      form.validate(valid_attrs.merge(name: "x" * 101))
      expect(form.errors[:name]).to be_present
    end

    it "is valid at exactly 100 characters" do
      form.validate(valid_attrs.merge(name: "a" * 100))
      expect(form.errors[:name]).to be_empty
    end

    it "rejects a duplicate name within the same customer" do
      FieldTemplate.create!(name: "Address Block", configuration: "{}",
                            customer_id: customer.id, built_in: false)
      form.validate(valid_attrs)
      expect(form.errors[:name]).to include("already exists")
    end

    it "allows the same name for a different customer" do
      other_customer = create(:customer)
      FieldTemplate.create!(name: "Address Block", configuration: "{}",
                            customer_id: other_customer.id, built_in: false)
      form.validate(valid_attrs)
      expect(form.errors[:name]).to be_empty
    end

    it "allows an existing record to keep its own name on update" do
      existing = FieldTemplate.create!(name: "Address Block", configuration: "{}",
                                       customer_id: customer.id, built_in: false)
      update_form = described_class.new(existing)
      update_form.validate(valid_attrs)
      expect(update_form.errors[:name]).to be_empty
    end
  end

  describe "configuration" do
    it "is invalid when blank" do
      form.validate(valid_attrs.merge(configuration: ""))
      expect(form.errors[:configuration]).to be_present
    end

    it "is invalid when nil" do
      form.validate(valid_attrs.merge(configuration: nil))
      expect(form.errors[:configuration]).to be_present
    end
  end

  describe "category" do
    it "is valid when blank" do
      form.validate(valid_attrs.merge(category: ""))
      expect(form.errors[:category]).to be_empty
    end

    it "is invalid when over 50 characters" do
      form.validate(valid_attrs.merge(category: "x" * 51))
      expect(form.errors[:category]).to be_present
    end

    it "is valid at exactly 50 characters" do
      form.validate(valid_attrs.merge(category: "b" * 50))
      expect(form.errors[:category]).to be_empty
    end
  end
end
