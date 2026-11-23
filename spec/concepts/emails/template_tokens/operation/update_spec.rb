# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::TemplateTokens::Operation::Update do
  let(:customer) { create(:customer) }
  let(:token) { create(:email_template_token, customer: customer) }

  it "returns contract validation errors on the model consumed by the editor" do
    result = described_class.call(token: token, params: { label: "", entity_id: token.entity_id, attribute_slug: "name" })

    expect(result.success?).to be(false)
    expect(result.model.errors[:label]).to be_present
    expect(result.errors).to eq(result.model.errors)
    expect(token.reload.label).to eq("Custom field")
  end

  it "rejects a nonexistent entity without raising a foreign-key exception or changing storage" do
    original = token.entity_id
    result = described_class.call(token: token, params: { label: "Changed", entity_id: Entity.maximum(:id).to_i + 1, attribute_slug: "name" })

    expect(result.success?).to be(false)
    expect(result.errors[:entity_id]).to be_present
    expect(token.reload.entity_id).to eq(original)
  end

  it "rejects another customer's entity" do
    foreign = create(:entity, :with_name_status_schema)
    result = described_class.call(token: token, params: { label: "Changed", entity_id: foreign.id, attribute_slug: "name" })

    expect(result.success?).to be(false)
    expect(result.errors[:entity_id]).to be_present
  end

  it "returns a visible error for platform-token mutation" do
    platform = Emails::TemplateToken.platform.first!
    result = described_class.call(token: platform, params: { label: "Changed" })
    expect(result.success?).to be(false)
    expect(result.errors[:base]).to include(I18n.t("email.template_tokens.errors.platform_readonly"))
  end
end
