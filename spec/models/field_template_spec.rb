# frozen_string_literal: true

require "rails_helper"

RSpec.describe FieldTemplate, type: :model do
  # Positional hash (not keyword params) so callers can override any attribute,
  # including clearing one to nil to exercise a presence validation.
  def build_template(overrides = {})
    described_class.new({ customer_id: 1, name: "Test", configuration: { "field_type" => "text" } }.merge(overrides))
  end

  it "is invalid without a customer_id" do
    template = build_template(customer_id: nil)
    expect(template).not_to be_valid
    expect(template.errors[:customer_id]).to include("can't be blank")
  end

  it "is invalid without a name" do
    template = build_template(name: nil)
    expect(template).not_to be_valid
    expect(template.errors[:name]).to include("can't be blank")
  end

  it "is invalid without a configuration" do
    template = build_template(configuration: nil)
    expect(template).not_to be_valid
    expect(template.errors[:configuration]).to include("can't be blank")
  end

  it "is valid with customer_id, name, and configuration" do
    expect(build_template(name: "US Phone", configuration: { "field_type" => "tel" })).to be_valid
  end

  it "rejects a name longer than 100 characters" do
    template = build_template(name: "x" * 101)
    expect(template).not_to be_valid
    expect(template.errors[:name]).to include("is too long (maximum is 100 characters)")
  end

  it "rejects a category longer than 50 characters" do
    template = build_template(category: "x" * 51)
    expect(template).not_to be_valid
    expect(template.errors[:category]).to include("is too long (maximum is 50 characters)")
  end

  it "allows a blank category" do
    expect(build_template(category: "")).to be_valid
  end

  describe "scopes" do
    before do
      described_class.create!(customer_id: 1, name: "A", configuration: { "type" => "text" })
      described_class.create!(customer_id: 2, name: "B", configuration: { "type" => "text" })
      described_class.create!(customer_id: 1, name: "C", configuration: { "type" => "text" }, built_in: true)
    end

    it "scopes by customer" do
      expect(described_class.for_customer(1).count).to eq(2)
      expect(described_class.for_customer(2).count).to eq(1)
    end

    it "scopes custom templates" do
      expect(described_class.custom.count).to eq(2)
    end

    it "scopes built_in templates" do
      expect(described_class.built_in.count).to eq(1)
    end
  end

  it "defaults built_in to false" do
    template = described_class.create!(customer_id: 1, name: "Test", configuration: { "type" => "text" })
    expect(template.built_in).to be false
  end
end
