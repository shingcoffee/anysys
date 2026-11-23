# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDefinitions::Api::Vocabulary do
  let(:customer) { create(:customer) }
  let(:context) { Struct.new(:customer).new(customer) }

  def values_for(name)
    described_class.resolve(name, context)[:values]
  end

  describe ".resolve" do
    it "returns values and descriptions for an enum source" do
      result = described_class.resolve("attribute_kinds", context)

      expect(result[:values]).to eq(%w[input calculated computed])
      expect(result[:descriptions].keys).to match_array(result[:values])
      result[:descriptions].each_value { |text| expect(text).to be_present }
    end

    it "returns the live max precision as an Integer" do
      expect(described_class.resolve("aggregate_max_precision", context))
        .to eq(Entities::ComputedCompiler::MAX_PRECISION)
    end

    it "raises on an unknown source" do
      expect { described_class.resolve("not_a_slot", context) }.to raise_error(ArgumentError, /not_a_slot/)
    end
  end

  describe "registry completeness" do
    {
      "html_types" => -> { described_class.html_type_values },
      "selection_html_types" => -> { HtmlTypeOptions::SELECTION_TYPES },
      "attribute_kinds" => -> { described_class::ATTRIBUTE_KINDS },
      "rule_types" => -> { described_class.rule_type_values },
      "rule_types_single_value" => -> { described_class.rule_types_for("single_value") },
      "rule_types_range" => -> { described_class.rule_types_for("range") },
      "rule_types_pattern" => -> { described_class.rule_types_for("pattern") },
      "rule_types_list" => -> { described_class.rule_types_for("list") },
      "group_icons" => -> { EntityAttributeGroupOptions::ICONS.keys },
      "group_colors" => -> { EntityAttributeGroupOptions::COLORS },
      "option_sources" => -> { described_class::OPTION_SOURCES },
      "aggregate_functions" => -> { Entities::ComputedCompiler::FUNCTIONS },
      "filter_operators" => -> { Entities::ComputedCompiler::FILTER_OPS },
      "aggregate_directions" => -> { described_class::AGGREGATE_DIRECTIONS }
    }.each do |name, registry|
      it "describes every #{name} registry value" do
        values = registry.call
        descriptions = described_class.descriptions_for(name)

        expect(descriptions.keys).to match_array(values)
        values.each do |value|
          expect(descriptions[value]).to be_present,
                                         "missing English description for #{name.inspect} value #{value.inspect}"
        end
      end
    end

    it "reads html_types from the live grouped registry (21 controls)" do
      expect(values_for("html_types")).to eq(described_class.html_type_values)
      expect(values_for("html_types").size).to eq(21)
    end

    it "derives rule value-field groups from VALIDATOR_CONFIG_TYPES" do
      expect(values_for("rule_types_single_value")).to include("length_maximum")
      expect(values_for("rule_types_range")).to eq(%w[length_in_range])
      expect(values_for("rule_types_pattern")).to eq(%w[format_custom])
      expect(values_for("rule_types_list")).to include("inclusion", "exclusion")
    end
  end

  describe "rule-type descriptions" do
    it "names the value fields and the authorable html_types from HTML_TYPE_VALIDATORS" do
      text = described_class.descriptions_for("rule_types").fetch("length_maximum")
      authorable = described_class.resolve("html_types", nil)[:values]

      expect(text).to include("`value`")
      ValidatorRegistry::HTML_TYPE_VALIDATORS.each do |html_type, rules|
        next unless rules.include?("length_maximum")

        if authorable.include?(html_type)
          expect(text).to include(html_type)
        else
          expect(text).not_to include(html_type)
        end
      end
    end

    it "says a rule allowed on every authorable control is allowed on every html_type" do
      expect(described_class.descriptions_for("rule_types").fetch("presence")).to include("every html_type")
    end

    it "says a no-config rule takes no value fields" do
      expect(described_class.descriptions_for("rule_types").fetch("presence")).to include("no value fields")
    end
  end

  describe ".rule_config_kind" do
    it "returns the registry config kind or nil" do
      expect(described_class.rule_config_kind("length_maximum")).to eq("single_value")
      expect(described_class.rule_config_kind("presence")).to be_nil
    end
  end

  describe "extendable_models" do
    it "lists class names for the context customer and describes them from the registry" do
      mod = FeatureModules::Module.create!(key: "vocab_mod_#{SecureRandom.hex(4)}", name: "Payments", status: :active)
      FeatureModules::CustomerAssignment.create!(customer: customer, feature_module: mod, status: :active)
      mod.set_extendable_model!("Payments::Order", true)

      other = create(:customer)
      other_mod = FeatureModules::Module.create!(key: "vocab_other_#{SecureRandom.hex(4)}", name: "SMS", status: :active)
      FeatureModules::CustomerAssignment.create!(customer: other, feature_module: other_mod, status: :active)
      other_mod.set_extendable_model!("Sms::Message", true)

      result = described_class.resolve("extendable_models", context)
      expect(result[:values]).to include("Payments::Order")
      expect(result[:values]).not_to include("Sms::Message")
      expect(result[:descriptions]["Payments::Order"]).to include("Order")
      expect(result[:descriptions]["Payments::Order"]).to include(mod.key)
    end

    it "returns an empty source when the context has no customer" do
      expect(described_class.resolve("extendable_models", Struct.new(:customer).new(nil)))
        .to eq(values: [], descriptions: {})
    end
  end
end
