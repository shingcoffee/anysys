# frozen_string_literal: true

# Seeds default industry-to-template mappings based on template category relevance.
#
# Supports two modes:
#   - seed_defaults!        : Only creates mappings for industries that have none
#   - seed_all!             : Replaces all mappings with defaults (full reset)
#   - seed_new_templates!   : Adds mappings only for templates not yet mapped to any industry
#
class IndustryTemplateMappingSeeder
  # Categories that apply to ALL industries (universal templates)
  UNIVERSAL_CATEGORIES = %w[
    general registration contact survey feedback scheduling application hr
  ].freeze

  # Maps template categories to industry enum keys
  CATEGORY_INDUSTRY_MAP = {
    "healthcare"      => %i[healthcare pharmaceuticals biotechnology medical_devices mental_health dental veterinary],
    "education"       => %i[education higher_education edtech research training_development],
    "legal"           => %i[legal],
    "business"        => %i[banking financial_services accounting fintech investment_management consulting insurance],
    "payment"         => %i[banking fintech financial_services ecommerce retail],
    "marketing"       => %i[marketing advertising public_relations],
    "realestate"      => %i[real_estate architecture interior_design engineering_services],
    "travel"          => %i[travel_tourism hospitality airlines],
    "nonprofit"       => %i[nonprofit social_services philanthropy religious_organizations],
    "ecommerce"       => %i[ecommerce retail consumer_goods fashion_apparel luxury_goods],
    "social"          => %i[event_management hospitality entertainment],
    "hospitality"     => %i[hospitality travel_tourism restaurants food_beverage],
    "fitness"         => %i[fitness_wellness sports_recreation],
    "creative"        => %i[entertainment media publishing film_television photography_videography advertising music],
    "it"              => %i[technology software cloud_computing cybersecurity artificial_intelligence data_analytics telecommunications internet_of_things gaming blockchain_cryptocurrency],
    "insurance"       => %i[insurance financial_services],
    "government"      => %i[government defense public_administration law_enforcement space_technology],
    "automotive"      => %i[automotive automotive_repair],
    "pets"            => %i[pet_services veterinary],
    "construction"    => %i[construction engineering_services architecture],
    "beauty"          => %i[beauty_cosmetics],
    "childcare"       => %i[childcare],
    "sports"          => %i[sports_recreation fitness_wellness],
    "consulting"      => %i[consulting],
    "logistics"       => %i[logistics transportation shipping warehousing_storage courier_postal maritime railroad],
    "research"        => %i[research biotechnology],
    "banking"         => %i[banking financial_services fintech investment_management],
    "religious"       => %i[religious_organizations],
    "entertainment"   => %i[entertainment media film_television music gaming],
    "dental"          => %i[dental healthcare],
    "homeservices"    => %i[home_services],
    "mentalhealth"    => %i[mental_health healthcare],
    "agriculture"     => %i[agriculture forestry_timber fishing_aquaculture],
    "manufacturing"   => %i[manufacturing automotive aerospace chemicals electronics food_processing textiles_apparel metals_steel plastics_rubber printing_packaging furniture_manufacturing robotics_automation],
    "retail"          => %i[retail ecommerce consumer_goods fashion_apparel luxury_goods jewelry_watches],
    "accounting"      => %i[accounting financial_services],
    "recruitment"     => %i[recruitment],
    "facilities"      => %i[real_estate construction],
    "procurement"     => %i[manufacturing retail logistics],
    "tutoring"        => %i[education edtech training_development],
    "moving"          => %i[logistics transportation home_services],
    "cleaning"        => %i[cleaning_janitorial home_services],
    "security"        => %i[security_services cybersecurity],
    "food"            => %i[food_beverage restaurants],
    "coworking"       => %i[coworking_shared_spaces],
    "saas"            => %i[software technology cloud_computing],
    "hoa"             => %i[real_estate home_services],
    "optometry"       => %i[healthcare],
    "music"           => %i[music entertainment],
    "roofing"         => %i[construction home_services],
    "pestcontrol"     => %i[pest_control home_services],
    "interiordesign"  => %i[interior_design real_estate],
    "telehealth"      => %i[healthcare mental_health telecommunications],
    "creator"         => %i[media entertainment advertising marketing],
    "energy"          => %i[energy oil_gas renewable_energy utilities mining],
    "warranty"        => %i[manufacturing consumer_goods retail ecommerce],
    "compliance"      => %i[government financial_services banking insurance healthcare],
    "seniorcare"      => %i[healthcare social_services],
    "hvac"            => %i[hvac_plumbing_electrical home_services construction],
    "landscaping"     => %i[landscaping_lawn_care home_services],
    "wedding"         => %i[event_management hospitality],
    "pharmacy"        => %i[pharmaceuticals healthcare],
    "waste"           => %i[waste_management_recycling environmental_services],
    "funeral"         => %i[funeral_memorial],
    "tattoo"          => %i[beauty_cosmetics],
    "laundry"         => %i[dry_cleaning_laundry home_services],
    "notary"          => %i[legal],
    "physicaltherapy" => %i[healthcare fitness_wellness],
    "printing"        => %i[printing_packaging advertising marketing],
    "marine"          => %i[maritime shipping fishing_aquaculture],
    "aviation"        => %i[airlines aerospace],
    "staffing"        => %i[recruitment],
    "catering"        => %i[food_beverage restaurants hospitality event_management],
    "library"         => %i[education higher_education research],
    "bidding"         => %i[construction government consulting],
    "inventory"       => %i[retail manufacturing logistics warehousing_storage]
  }.freeze

  class << self
    # Seeds mappings only for industries that currently have NO mappings.
    def seed_defaults!
      all_industries = Customer.industries.keys
      mapped_industries = IndustryTemplateMapping.distinct.pluck(:industry)
      unmapped = all_industries - mapped_industries

      create_mappings_for(unmapped)
    end

    # Replaces ALL mappings with computed defaults.
    def seed_all!
      IndustryTemplateMapping.transaction do
        IndustryTemplateMapping.delete_all
        create_mappings_for(Customer.industries.keys)
      end
    end

    # Adds mappings for templates not yet associated with any industry.
    def seed_new_templates!
      mapped_keys = IndustryTemplateMapping.distinct.pluck(:template_key)
      all_keys = PageLayoutTemplates.keys
      new_keys = all_keys - mapped_keys

      return 0 if new_keys.empty?

      templates = new_keys.map { |k| PageLayoutTemplates.find(k) }.compact
      count = 0

      templates.each do |template|
        industries = industries_for_category(template[:category])
        industries.each do |industry|
          IndustryTemplateMapping.create(industry: industry.to_s, template_key: template[:key])
          count += 1
        end
      end

      count
    end

    # Returns the computed default industries for a given template category.
    def industries_for_category(category)
      if UNIVERSAL_CATEGORIES.include?(category)
        Customer.industries.keys.map(&:to_sym)
      else
        CATEGORY_INDUSTRY_MAP.fetch(category, [])
      end
    end

    private

    def create_mappings_for(industries)
      templates = PageLayoutTemplates.all
      records = []

      industries.each do |industry|
        templates.each do |template|
          target_industries = industries_for_category(template[:category])
          if target_industries.include?(industry.to_sym)
            records << { industry: industry.to_s, template_key: template[:key] }
          end
        end
      end

      IndustryTemplateMapping.insert_all(records) if records.any?
      records.size
    end
  end
end
