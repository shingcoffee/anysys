# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::Contracts::Definition do
  let(:form) { described_class.new(OpenStruct.new) }

  it "normalizes declared JSON bodies without persisting or accepting identity fields" do
    expect(form.validate(definition: { "name" => "Not a definition field", "property_schema" => '[{"name_slug":"value","config":{"options":[]}}]' })).to be(true)
    expect(form.normalized_attributes).to eq(property_schema: [{ "name_slug" => "value", "config" => { "options" => [] } }])
  end

  it "accepts native bags and an explicitly cleared template reference" do
    expect(form.validate(definition: { "attribute_groups" => [], "default_properties" => {}, "referenced_template" => "" })).to be(true)
    expect(form.normalized_attributes).to eq(attribute_groups: [], default_properties: {}, referenced_template: nil)
  end

  it "rejects malformed nested structure and clears the entire normalized result" do
    expect(form.validate(definition: { "default_properties" => {}, "property_schema" => '[{"name_slug":"value","validators":1}]' })).to be(false)
    expect(form.normalized_attributes).to eq({})
    expect(form.errors.full_messages).to include(I18n.t("routes_audit.invalid_definition"))
  end

  it "rejects non-object snapshots rather than normalizing them to an empty body" do
    expect(form.validate(definition: [])).to be(false)
  end
end
