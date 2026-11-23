# frozen_string_literal: true

require "rails_helper"

RSpec.describe IndustryTemplateMappingSeeder do
  before { IndustryTemplateMapping.delete_all }

  describe ".seed_defaults!" do
    it "creates mappings for all industries" do
      described_class.seed_defaults!
      mapped_industries = IndustryTemplateMapping.distinct.pluck(:industry)
      expect(mapped_industries.size).to eq(Customer.industries.keys.size)
    end

    it "only seeds industries that have no mappings" do
      # Seed once
      described_class.seed_defaults!
      initial_count = IndustryTemplateMapping.count

      # Manually remove one industry's mappings
      IndustryTemplateMapping.for_industry("technology").delete_all

      # Seed again - should only seed the removed industry
      described_class.seed_defaults!
      expect(IndustryTemplateMapping.count).to eq(initial_count)
    end

    it "assigns universal templates to every industry" do
      described_class.seed_defaults!

      # Pick a universal category template
      universal_template = PageLayoutTemplates.all.find { |t| t[:category] == "general" }
      return unless universal_template

      industries = IndustryTemplateMapping.industries_for(universal_template[:key])
      expect(industries.size).to eq(Customer.industries.keys.size)
    end

    it "assigns category-specific templates to matching industries" do
      described_class.seed_defaults!

      healthcare_template = PageLayoutTemplates.all.find { |t| t[:category] == "healthcare" }
      return unless healthcare_template

      industries = IndustryTemplateMapping.industries_for(healthcare_template[:key])
      expect(industries).to include("healthcare")
      expect(industries).not_to include("technology")
    end
  end

  describe ".seed_all!" do
    it "replaces all existing mappings" do
      IndustryTemplateMapping.create!(industry: "technology", template_key: PageLayoutTemplates.keys.first)

      described_class.seed_all!
      expect(IndustryTemplateMapping.count).to be > 1
    end

    it "produces the same result when run multiple times" do
      described_class.seed_all!
      first_count = IndustryTemplateMapping.count

      described_class.seed_all!
      expect(IndustryTemplateMapping.count).to eq(first_count)
    end
  end

  describe ".seed_new_templates!" do
    it "returns 0 when all templates are already mapped" do
      described_class.seed_all!
      expect(described_class.seed_new_templates!).to eq(0)
    end

    it "only creates mappings for unmapped templates" do
      described_class.seed_all!
      initial_count = IndustryTemplateMapping.count

      # Simulate: remove mappings for one template
      first_key = PageLayoutTemplates.keys.first
      IndustryTemplateMapping.for_template(first_key).delete_all

      count = described_class.seed_new_templates!
      expect(count).to be > 0
      expect(IndustryTemplateMapping.for_template(first_key).count).to be > 0
    end
  end

  describe ".industries_for_category" do
    it "returns all industries for universal categories" do
      described_class::UNIVERSAL_CATEGORIES.each do |category|
        result = described_class.industries_for_category(category)
        expect(result.size).to eq(Customer.industries.keys.size),
          "Expected universal category '#{category}' to map to all industries"
      end
    end

    it "returns specific industries for category-specific templates" do
      result = described_class.industries_for_category("healthcare")
      expect(result).to include(:healthcare, :dental, :veterinary)
      expect(result).not_to include(:technology)
    end

    it "returns empty array for unknown categories" do
      expect(described_class.industries_for_category("unknown")).to be_empty
    end

    it "has a mapping for every non-universal template category" do
      all_categories = PageLayoutTemplates.all.map { |t| t[:category] }.uniq
      non_universal = all_categories - described_class::UNIVERSAL_CATEGORIES

      non_universal.each do |category|
        mapping = described_class::CATEGORY_INDUSTRY_MAP[category]
        expect(mapping).to be_present,
          "Missing CATEGORY_INDUSTRY_MAP entry for category '#{category}'"
      end
    end
  end
end
