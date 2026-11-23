# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlatformAnnouncements::TargetRules do
  let(:customer) { create(:customer, name: "Acme") }

  def id_rules(id)
    {
      "type" => "group",
      "joins" => [],
      "conditions" => [ { "field" => "id", "operator" => "equals", "value" => id.to_s } ]
    }
  end

  describe ".parse" do
    it "parses a JSON string into a rules hash" do
      rules = described_class.parse(id_rules(customer.id).to_json)

      expect(rules).not_to be_malformed
      expect(rules.rules).to eq(id_rules(customer.id))
    end

    it "accepts an already-parsed hash" do
      expect(described_class.parse(id_rules(customer.id)).rules).to eq(id_rules(customer.id))
    end

    it "treats blank input as empty rather than malformed" do
      [ nil, "", "  ", {} ].each do |raw|
        parsed = described_class.parse(raw)
        expect(parsed).not_to be_malformed
        expect(parsed.rules).to eq({})
      end
    end

    it "flags unparseable JSON as malformed instead of raising" do
      parsed = described_class.parse("{not json")

      expect(parsed).to be_malformed
      expect(parsed.rules).to eq({})
      expect(parsed).not_to be_usable
    end

    it "flags a non-hash JSON document as malformed without exposing an audience" do
      rules = described_class.parse("[1,2]")
      expect(rules.rules).to eq({})
      expect(rules).to be_malformed
      expect(rules).not_to be_usable
    end
  end

  describe "#usable?" do
    it "is false for empty rules so a segment never means everyone" do
      expect(described_class.empty).not_to be_usable
    end

    it "is true once a resolvable condition exists" do
      expect(described_class.parse(id_rules(customer.id))).to be_usable
    end
  end

  describe "#matching_customers" do
    it "returns the matched tenants" do
      create(:customer)
      expect(described_class.parse(id_rules(customer.id)).matching_customers).to eq([ customer ])
    end

    it "returns none for unusable rules" do
      expect(described_class.empty.matching_customers).to be_empty
    end
  end
end
