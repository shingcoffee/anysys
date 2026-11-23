# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::ActionLink do
  describe ".path" do
    it "builds the action path and encodes prefill scalars" do
      expect(described_class.path(customer_id: 42, action_key: "enroll")).to eq("/42/actions/enroll")
      expect(described_class.path(customer_id: 42, action_key: "enroll", prefill: { "course" => "12" }))
        .to eq("/42/actions/enroll?prefill[course]=12")
      expect(described_class.path(customer_id: 42, action_key: "enroll", prefill: { "q" => "a b" }))
        .to eq("/42/actions/enroll?prefill[q]=#{CGI.escape("a b")}")
    end

    it "drops an 11th key, a key that isn't a slug, and a value over 200 characters" do
      keys = (1..11).to_h { |n| ["field_#{n}", n.to_s] }
      path = described_class.path(customer_id: 1, action_key: "enroll", prefill: keys)

      expect(path).to include("prefill[field_1]=1")
      expect(path).to include("prefill[field_10]=10")
      expect(path).not_to include("field_11")

      expect(described_class.path(customer_id: 1, action_key: "enroll", prefill: { "course-id" => "1", "ok" => "2" }))
        .to eq("/1/actions/enroll?prefill[ok]=2")
      expect(described_class.path(customer_id: 1, action_key: "enroll", prefill: { "ok" => "x" * 201 }))
        .to eq("/1/actions/enroll")
    end

    it "returns nil for a malformed action key" do
      ["../admin", "Enroll", "", nil, "a"].each do |key|
        expect(described_class.path(customer_id: 1, action_key: key)).to be_nil
      end
    end
  end

  describe ".sanitized_prefill" do
    it "keeps slug scalars within the query limits" do
      expect(described_class.sanitized_prefill(
        { "ok" => "1", "course-id" => "x", "toolong" => "x" * 201, "nested" => { "a" => "b" } }
      )).to eq("ok" => "1")
    end
  end
end
