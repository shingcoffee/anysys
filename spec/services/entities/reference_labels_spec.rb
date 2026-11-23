# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::ReferenceLabels do
  describe ".labelable?" do
    it "accepts input attributes of the label html types, defaulting to text" do
      %w[text search email tel url number date].each do |html_type|
        expect(described_class.labelable?("name_slug" => "a", "html_type" => html_type)).to be(true)
      end
      expect(described_class.labelable?("name_slug" => "a")).to be(true)
    end

    it "rejects derived and reference attributes, other html types and non-hashes" do
      expect(described_class.labelable?("html_type" => "number", "type" => "Calculated")).to be(false)
      expect(described_class.labelable?("html_type" => "number", "type" => Entity::COMPUTED_TYPE)).to be(false)
      expect(described_class.labelable?("html_type" => "number", "storage" => "computed")).to be(false)
      expect(described_class.labelable?("html_type" => "select", "type" => Entity::ENTITY_REFERENCE_TYPE)).to be(false)
      %w[textarea select radio checkbox password file].each do |html_type|
        expect(described_class.labelable?("html_type" => html_type)).to be(false)
      end
      expect(described_class.labelable?(nil)).to be(false)
    end
  end

  describe ".reference?" do
    it "is true only for an entity_entries options source" do
      expect(described_class.reference?("config" => { "options_source" => "entity_entries" })).to be(true)
      expect(described_class.reference?("config" => { "source" => "manual" })).to be(false)
      expect(described_class.reference?("config" => nil)).to be(false)
      expect(described_class.reference?(nil)).to be(false)
    end
  end

  describe "label text" do
    it "trims labels, falls back to Untitled and names missing records" do
      expect(described_class.text(" Ada ", 7)).to eq("Ada")
      expect(described_class.text(nil, 7)).to eq("Untitled (#7)")
      expect(described_class.missing(7)).to eq("Missing record (#7)")
      expect(described_class.numbered("001", 26)).to eq("001 (#26)")
    end

    it "uses the zh-CN wording" do
      I18n.with_locale(:"zh-CN") do
        expect(described_class.text("", 7)).to eq("未命名（#7）")
        expect(described_class.missing(7)).to eq("记录不存在（#7）")
        expect(described_class.numbered("001", 26)).to eq("001（#26）")
      end
    end
  end

  describe ".disambiguate" do
    it "numbers every repeated label after trimming and leaves unique labels alone" do
      pairs = [["001", 26], ["Ann", 27], ["001 ", 31]]

      expect(described_class.disambiguate(pairs)).to eq([["001 (#26)", 26], ["Ann", 27], ["001 (#31)", 31]])
    end
  end
end
