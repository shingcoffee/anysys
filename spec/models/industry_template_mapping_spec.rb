# frozen_string_literal: true

require "rails_helper"

RSpec.describe IndustryTemplateMapping, type: :model do
  let(:valid_template_key) { PageLayoutTemplates.keys.first }

  def build_mapping(industry: "technology", template_key: valid_template_key)
    described_class.new(industry: industry, template_key: template_key)
  end

  describe "validations" do
    it "is valid with a known industry and template_key" do
      expect(build_mapping).to be_valid
    end

    it "requires industry" do
      mapping = build_mapping(industry: nil)
      expect(mapping).not_to be_valid
      expect(mapping.errors[:industry]).to include("can't be blank")
    end

    it "requires template_key" do
      mapping = build_mapping(template_key: nil)
      expect(mapping).not_to be_valid
      expect(mapping.errors[:template_key]).to include("can't be blank")
    end

    it "rejects an industry that is not a valid Customer industry" do
      mapping = build_mapping(industry: "invalid_industry")
      expect(mapping).not_to be_valid
      expect(mapping.errors[:industry]).to include("is not a valid industry")
    end

    it "rejects a template_key that does not exist in PageLayoutTemplates" do
      mapping = build_mapping(template_key: "nonexistent_template")
      expect(mapping).not_to be_valid
      expect(mapping.errors[:template_key]).to include("is not a valid template")
    end

    it "enforces uniqueness of template_key within an industry" do
      described_class.create!(industry: "technology", template_key: valid_template_key)
      duplicate = build_mapping
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:template_key]).to include("has already been taken")
    end

    it "allows the same template_key for different industries" do
      described_class.create!(industry: "technology", template_key: valid_template_key)
      expect(build_mapping(industry: "healthcare")).to be_valid
    end
  end

  describe "scopes" do
    let!(:tech_mapping) { described_class.create!(industry: "technology", template_key: valid_template_key) }
    let!(:health_mapping) { described_class.create!(industry: "healthcare", template_key: valid_template_key) }

    describe ".for_industry" do
      it "returns mappings for the given industry" do
        results = described_class.for_industry("technology")
        expect(results).to include(tech_mapping)
        expect(results).not_to include(health_mapping)
      end
    end

    describe ".for_template" do
      it "returns mappings for the given template_key" do
        results = described_class.for_template(valid_template_key)
        expect(results).to include(tech_mapping, health_mapping)
      end
    end
  end

  describe ".template_keys_for" do
    it "returns template keys for a given industry" do
      keys = PageLayoutTemplates.keys.first(3)
      keys.each { |k| described_class.create!(industry: "technology", template_key: k) }

      result = described_class.template_keys_for("technology")
      expect(result).to match_array(keys)
    end

    it "returns empty array for unmapped industry" do
      expect(described_class.template_keys_for("other")).to be_empty
    end
  end

  describe ".industries_for" do
    it "returns industries for a given template key" do
      described_class.create!(industry: "technology", template_key: valid_template_key)
      described_class.create!(industry: "healthcare", template_key: valid_template_key)

      result = described_class.industries_for(valid_template_key)
      expect(result).to match_array(%w[technology healthcare])
    end
  end

  describe ".replace_for_industry!" do
    it "replaces all mappings for an industry" do
      old_key = PageLayoutTemplates.keys.first
      new_keys = PageLayoutTemplates.keys[1..3]

      described_class.create!(industry: "technology", template_key: old_key)
      described_class.replace_for_industry!("technology", new_keys)

      result = described_class.template_keys_for("technology")
      expect(result).to match_array(new_keys)
      expect(result).not_to include(old_key)
    end

    it "does not affect other industries" do
      described_class.create!(industry: "healthcare", template_key: valid_template_key)
      described_class.replace_for_industry!("technology", [valid_template_key])

      expect(described_class.for_industry("healthcare").count).to eq(1)
    end

    it "handles empty template_keys array" do
      described_class.create!(industry: "technology", template_key: valid_template_key)
      described_class.replace_for_industry!("technology", [])

      expect(described_class.template_keys_for("technology")).to be_empty
    end
  end
end
