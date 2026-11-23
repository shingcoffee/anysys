# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::TemplateTokens::Operation::BulkCreate do
  let(:customer) { create(:customer) }
  let(:entity) { create(:entity, :with_name_status_schema, customer: customer) }
  let(:fields) { [{ "selected" => "1", "attribute_slug" => "name", "label" => "Member name" }] }

  it "accepts an array of field hashes with string keys" do
    result = described_class.call(customer: customer, params: { entity_id: entity.id, fields: fields })

    expect(result.success?).to be(true)
    expect(result.model).to be_persisted
    expect(result.model.customer_id).to eq(customer.id)
    expect(result.model.attribute_slug).to eq("name")
  end

  it "accepts indexed hashes from Rails nested form parameters" do
    result = described_class.call(customer: customer, params: { entity_id: entity.id, fields: { "0" => fields.first } })
    expect(result.success?).to be(true)
  end

  ["bad", 123, [nil], ["bad"], [{ selected: ["1"] }], [{ selected: "1", label: {} }]].each do |shape|
    it "returns a controlled validation result for fields shape #{shape.inspect}" do
      expect {
        result = described_class.call(customer: customer, params: { entity_id: entity.id, fields: shape })
        expect(result.success?).to be(false)
        expect(result.model.errors[:base]).to include(I18n.t("settings_modules.email.bulk_errors.invalid_selection"))
      }.not_to change(Emails::TemplateToken, :count)
    end
  end

  it "does not persist any token if one selected field is invalid" do
    invalid = fields + [{ selected: "1", attribute_slug: "status", label: "" }]
    expect {
      result = described_class.call(customer: customer, params: { entity_id: entity.id, fields: invalid })
      expect(result.success?).to be(false)
      expect(result.model.errors[:label]).to be_present
    }.not_to change(Emails::TemplateToken, :count)
  end

  it "rejects a foreign tenant's entity" do
    foreign = create(:entity, :with_name_status_schema)
    result = described_class.call(customer: customer, params: { entity_id: foreign.id, fields: fields })
    expect(result.success?).to be(false)
    expect(result.model.errors[:base]).to include(I18n.t("settings_modules.email.bulk_errors.choose_valid_record"))
  end
end
