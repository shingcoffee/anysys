# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::Audience::SaveList do
  let(:customer) { create(:customer) }
  let(:list) { create(:email_list, :dynamic, customer: customer) }

  it "returns visible contract errors without changing a persisted audience" do
    original = list.segment_rules
    invalid = { "conditions" => [{ "field" => "first_name", "operator" => "unknown", "value" => "Ada" }] }

    expect(described_class.call(list: list, attributes: { name: "Rejected", segment_rules: invalid })).to be(false)
    expect(list.errors[:segment_rules]).to include(I18n.t("admin_modules.errors.lists.segment_malformed"))
    persisted = Emails::Audience::List.find(list.id)
    expect(persisted.segment_rules).to eq(original)
    expect(persisted.name).not_to eq("Rejected")
  end

  it "preserves omitted rules during metadata-only updates" do
    original = list.segment_rules
    expect(described_class.call(list: list, attributes: { name: "Renamed" })).to be(true)
    expect(list.reload.segment_rules).to eq(original)
  end

  it "allows an explicit empty audience definition" do
    own = create(:user, customer: customer)
    foreign = create(:user)
    expect(described_class.call(list: list, attributes: { segment_rules: {} })).to be(true)
    expect(list.reload.audience).to include(own)
    expect(list.audience).not_to include(foreign)
  end

  it "fails closed if stored rules become malformed without passing through the write contract" do
    create(:user, customer: customer, first_name: "Ada")
    list.update_columns(segment_rules: { "conditions" => ["invalid"] })
    expect(list.reload.audience).to be_empty
    expect(list.audience_count).to eq(0)
  end
end
