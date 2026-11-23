# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDefinitions::AttributeMerge do
  describe ".attribute_key" do
    it "returns an empty key for anything that is not a Hash" do
      expect(described_class.attribute_key(nil)).to eq("")
      expect(described_class.attribute_key("email")).to eq("")
      expect(described_class.attribute_key([{ "name" => "Email" }])).to eq("")
    end

    it "prefers the stored slug over the one the name would produce" do
      expect(described_class.attribute_key("name" => "Email address", "name_slug" => "email")).to eq("email")
    end

    it "falls back to the parameterized name when no slug is given" do
      expect(described_class.attribute_key("name" => "Enrollment date")).to eq("enrollment_date")
    end

    it "falls back to the name when the slug is blank or whitespace" do
      expect(described_class.attribute_key("name" => "First name", "name_slug" => "   ")).to eq("first_name")
    end

    it "returns an empty key when neither a name nor a slug is present" do
      expect(described_class.attribute_key("html_type" => "text")).to eq("")
    end

    it "matches an incoming name against the twin it was stored under" do
      stored = { "name" => "E-mail address", "name_slug" => "email" }
      incoming = { "name" => "Email" }

      expect(described_class.attribute_key(incoming)).to eq(described_class.attribute_key(stored))
    end
  end

  describe ".merge_attributes" do
    it "returns the incoming list when nothing is stored yet" do
      incoming = [{ "name" => "Email", "name_slug" => "email" }]

      expect(described_class.merge_attributes([], incoming)).to eq(incoming)
      expect(described_class.merge_attributes(nil, incoming)).to eq(incoming)
    end

    it "keeps the stored list when the caller sends nothing" do
      existing = [{ "name" => "Email", "name_slug" => "email" }]

      expect(described_class.merge_attributes(existing, [])).to eq(existing)
      expect(described_class.merge_attributes(existing, nil)).to eq(existing)
    end

    it "keeps a stored status lifecycle the incoming twin omits, and replaces it when sent" do
      lifecycle = { "transitions" => [{ "from" => "draft", "to" => "submitted", "by" => ["member"] }] }
      existing = [{ "name" => "Status", "name_slug" => "status", "html_type" => "select", "lifecycle" => lifecycle }]
      replacement = { "transitions" => [{ "from" => "draft", "to" => "approved", "by" => ["admin"] }] }

      kept = described_class.merge_attributes(existing, [{ "name" => "Status", "name_slug" => "status", "display_label" => "State" }])
      replaced = described_class.merge_attributes(existing, [{ "name_slug" => "status", "lifecycle" => replacement }])

      expect(kept.sole).to include("display_label" => "State", "lifecycle" => lifecycle)
      expect(replaced.sole["lifecycle"]).to eq(replacement)
    end

    it "keeps the stored order and appends genuinely new attributes" do
      existing = [
        { "name" => "Email", "name_slug" => "email" },
        { "name" => "Phone", "name_slug" => "phone" }
      ]
      incoming = [
        { "name" => "Notes", "name_slug" => "notes" },
        { "name" => "Phone", "name_slug" => "phone", "html_type" => "tel" }
      ]

      merged = described_class.merge_attributes(existing, incoming)

      expect(merged.map { |attr| attr["name_slug"] }).to eq(%w[email phone notes])
    end

    it "merges a matched pair key-wise, so an omitted key keeps its stored value" do
      existing = [{ "name" => "Email", "name_slug" => "email", "html_type" => "email", "visibility" => "always" }]
      incoming = [{ "name_slug" => "email", "html_type" => "text" }]

      merged = described_class.merge_attributes(existing, incoming)

      expect(merged).to eq(
        [{ "name" => "Email", "name_slug" => "email", "html_type" => "text", "visibility" => "always" }]
      )
    end

    it "merges onto the stored twin an incoming attribute only names" do
      existing = [{ "name" => "E-mail address", "name_slug" => "email", "html_type" => "email" }]
      incoming = [{ "name" => "Email", "html_type" => "text" }]

      merged = described_class.merge_attributes(existing, incoming)

      expect(merged.size).to eq(1)
      expect(merged.first).to include("name" => "Email", "name_slug" => "email", "html_type" => "text")
    end

    it "replaces a stored entry that is not a Hash rather than merging onto it" do
      expect(described_class.merge_attributes(["junk"], ["replacement"])).to eq(["replacement"])
    end
  end
end
