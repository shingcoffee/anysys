# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::Audience::Contracts::SegmentRules do
  it "accepts omitted, blank, and explicit empty root input as an intentional all-tenant audience" do
    [nil, "", "{}", '{"type":"group","conditions":[],"joins":[]}'].each do |raw|
      form = described_class.from_json(raw)
      expect(form.errors).to be_empty
      expect(Emails::Audience::SegmentQuery.valid?(form.rules)).to be(true)
    end
  end

  ["[]", "null", "{bad-json", [], {}, " " * (described_class::MAX_JSON_BYTES + 1)].each do |raw|
    it "returns a localized validation error for invalid or oversized input #{raw.class}" do
      form = described_class.from_json(raw)
      expect(form.errors[:rules]).to include(I18n.t("admin_modules.errors.lists.segment_malformed"))
    end
  end

  it "rejects syntactically valid JSON with invalid field/operator/value semantics" do
    raw = { conditions: [{ field: "first_name", operator: "greater_than", value: "Ada" }] }.to_json
    form = described_class.from_json(raw)
    expect(form.errors[:rules]).to be_present
  end
end
