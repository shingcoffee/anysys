# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::TemplateTokens::Operation::Create do
  it "returns contract errors on the unsaved model used by the form" do
    result = described_class.call(customer: create(:customer), params: { label: "", entity_id: "", attribute_slug: "" })

    expect(result.success?).to be(false)
    expect(result.model).not_to be_persisted
    expect(result.errors).to eq(result.model.errors)
    expect(result.model.errors.attribute_names).to include(:label, :entity_id, :attribute_slug)
  end
end
