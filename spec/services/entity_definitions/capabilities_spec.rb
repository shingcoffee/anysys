# frozen_string_literal: true

require "rails_helper"

RSpec.describe EntityDefinitions::Capabilities do
  describe ".controls" do
    it "derives every control from the html type registry, with its category and config kind" do
      expect(described_class.control_values)
        .to eq(HtmlTypeOptions::GROUPED_HTML_TYPES.values.flatten(1).map(&:last))

      select = described_class.controls.find { |control| control.value == "select" }
      expect(select.category).to eq("Selection")
      expect(select.label).to eq("Dropdown")
      expect(select.config_kind).to eq("selection")
      expect(select.validators).to eq(ValidatorRegistry::HTML_TYPE_VALIDATORS["select"])
    end

    it "labels controls in stable English so the prompt does not shift with the locale" do
      english = I18n.with_locale(:en) { described_class.controls.map(&:label) }
      chinese = I18n.with_locale(:"zh-CN") { described_class.controls.map(&:label) }

      expect(chinese).to eq(english)
    end

    it "picks up a newly registered html type without an edit here" do
      registry = HtmlTypeOptions::GROUPED_HTML_TYPES.merge(exotic: [[:quantum_field, "quantum"]])
      stub_const("HtmlTypeOptions::GROUPED_HTML_TYPES", registry)

      expect(described_class.control_values).to include("quantum")
      expect(described_class.controls.last.category).to eq("Exotic")
    end
  end

  describe ".validators" do
    it "lists every validator with the controls it suits and the config it takes" do
      email = described_class.validators.find { |validator| validator.type == "format_email" }
      expect(email.controls).to eq(["email"])
      expect(email.config_kind).to be_nil

      range = described_class.validators.find { |validator| validator.type == "length_in_range" }
      expect(range.config_kind).to eq("range")
      expect(range.config_example).to include("min")
    end

    it "never offers a validator against a control the app does not render" do
      offered = described_class.validators.flat_map(&:controls).uniq

      expect(offered - described_class.control_values).to be_empty
    end

    it "covers every validator the registry knows about" do
      expect(described_class.validator_types).to eq(ValidatorRegistry::VALIDATOR_LABELS.keys)
    end
  end

  describe "grouping, derived fields and audiences" do
    it "reads group icons and colors from the shared option catalog" do
      expect(described_class.group_icons).to eq(EntityAttributeGroupOptions::ICONS.keys)
      expect(described_class.group_colors).to eq(EntityAttributeGroupOptions::COLORS)
    end

    it "reads computed metadata from the compiler" do
      expect(described_class.computed_functions).to eq(Entities::ComputedCompiler::FUNCTIONS)
      expect(described_class.computed_filter_operators).to eq(Entities::ComputedCompiler::FILTER_OPS)
      expect(described_class.computed_max_precision).to eq(Entities::ComputedCompiler::MAX_PRECISION)
      expect(described_class.numeric_control_values).to eq(Entities::ComputedCompiler::NUMERIC_HTML_TYPES)
    end

    it "reads audiences from the shared audience module" do
      expect(described_class.audiences).to eq(EntityAttributeAudience::AUDIENCES)
    end

    it "never offers EntityReference as an authorable attribute type" do
      expect(described_class::AUTHORABLE_ATTRIBUTE_TYPES).not_to include(Entity::ENTITY_REFERENCE_TYPE)
    end
  end

  describe ".extendable_models" do
    let_it_be(:customer) { create(:customer) }

    it "is empty when the tenant has nothing extendable" do
      expect(described_class.extendable_models(customer.id)).to eq([])
    end

    it "returns the class names the registry offers this tenant" do
      allow(ExtendableModelRegistry).to receive(:for_customer).with(customer.id).and_return(
        [{ class_name: "Authentication::User", label: "User", module_key: "auth" }]
      )

      expect(described_class.extendable_models(customer.id)).to eq(["Authentication::User"])
    end
  end

  describe ".person_model and .base_model_fields" do
    let_it_be(:customer) { create(:customer) }

    def allow_extending(*class_names)
      allow(ExtendableModelRegistry).to receive(:for_customer).with(customer.id)
        .and_return(class_names.map { |name| { class_name: name, label: name.demodulize, module_key: "auth" } })
    end

    it "offers the person model and its columns only when the tenant may extend it" do
      expect(described_class.person_model(customer.id)).to be_nil
      expect(described_class.base_model_fields(customer.id, "Authentication::User")).to eq([])

      allow_extending("Authentication::User")

      expect(described_class.person_model(customer.id)).to eq("Authentication::User")
      expect(described_class.base_model_fields(customer.id, "Authentication::User")).to eq([])

      allow(ExtendableModelRegistry).to receive(:selected_attributes)
        .with(customer.id, "Authentication::User").and_return(%w[email])
      expect(described_class.base_model_fields(customer.id, "Authentication::User")).to eq(["email"])
    end

    it "returns no fields for an approved name that is not an ApplicationRecord" do
      allow_extending("String", "Evil::Klass")

      expect(described_class.base_model_fields(customer.id, "String")).to eq([])
      expect(described_class.base_model_fields(customer.id, "Evil::Klass")).to eq([])
    end
  end
end
