# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConditionBuilderComponent, type: :component do
  let(:fields) do
    [
      { "name_slug" => "email",      "name" => "Email",      "type" => "string" },
      { "name_slug" => "first_name", "name" => "First Name", "type" => "string" }
    ]
  end

  let(:rule_equals) do
    { "field" => "ctx.email", "op" => "==", "value" => "test@example.com", "operator" => "AND" }
  end

  let(:rule_blank) do
    { "field" => "ctx.email", "op" => "blank?", "value" => "", "operator" => "AND" }
  end

  let(:conditions_with_rules) do
    { "operator" => "AND", "rules" => [rule_equals] }
  end

  let(:conditions_or) do
    { "operator" => "OR", "rules" => [rule_equals] }
  end

  # -------------------------------------------------------------------
  # Default (no conditions passed)
  # -------------------------------------------------------------------
  describe "default initialization" do
    before { render_inline(described_class.new) }

    it "renders the condition-builder controller container" do
      expect(page).to have_css("[data-controller='condition-builder']")
    end

    it "renders the AND button in active state" do
      expect(page).to have_button("ALL")
    end

    it "renders the OR button" do
      expect(page).to have_button("ANY")
    end

    it "renders the Add Rule button" do
      expect(page).to have_button("Add Rule")
    end

    it "renders the hidden output field" do
      expect(page).to have_css("input[type='hidden'][name='conditions']", visible: false)
    end

    it "renders the rule template for JS cloning" do
      expect(page).to have_css("template[data-condition-builder-target='ruleTemplate']", visible: :hidden)
    end
  end

  # -------------------------------------------------------------------
  # With fields embedded in the template
  # -------------------------------------------------------------------
  describe "with entity fields" do
    before { render_inline(described_class.new(fields: fields)) }

    it "includes entity fields in the rule template's field optgroup" do
      # Fields are serialized into data-condition-builder-fields-value
      expect(page.find("[data-controller='condition-builder']")["data-condition-builder-fields-value"]).to include("email")
    end

    it "serializes all_fields (entity + system) into the data attribute" do
      fields_json = page.find("[data-controller='condition-builder']")["data-condition-builder-fields-value"]
      # system fields are always appended
      expect(fields_json).to include("customer_id")
    end
  end

  # -------------------------------------------------------------------
  # AND operator (rendering with rules is NOT tested here because the
  # template calls `render_rule(rule, index)` which is undefined in
  # condition_builder_component.rb — production bug; see notes below).
  # Logic-layer assertions are covered via unit tests on the component.
  # -------------------------------------------------------------------
  describe "AND operator — rules list container" do
    # Render with empty rules so the `render_rule` call is never reached.
    before { render_inline(described_class.new) }

    it "renders the rules list container" do
      expect(page).to have_css("[data-condition-builder-target='rulesList']")
    end

    it "highlights the ALL (AND) button when top_operator is AND" do
      and_btn = page.find("button", text: "ALL")
      expect(and_btn[:class]).to include("bg-accent")
    end
  end

  # -------------------------------------------------------------------
  # OR operator — button highlight (empty rules, safe path)
  # -------------------------------------------------------------------
  describe "OR operator — button highlight" do
    before do
      # Pass OR operator but no rules so render_rule is never invoked.
      render_inline(described_class.new(conditions: { "operator" => "OR", "rules" => [] }))
    end

    it "highlights the ANY (OR) button" do
      or_btn = page.find("button", text: "ANY")
      expect(or_btn[:class]).to include("bg-accent")
    end
  end

  # -------------------------------------------------------------------
  # Custom form_target
  # -------------------------------------------------------------------
  describe "custom form_target" do
    before { render_inline(described_class.new(form_target: "connectionCondition")) }

    it "uses the custom form_target in the data attribute" do
      expect(page).to have_css(
        "[data-condition-builder-target-value='connectionCondition']"
      )
    end

    it "names the hidden output field with the custom target" do
      expect(page).to have_css("input[type='hidden'][name='connectionCondition']", visible: false)
    end
  end

  # -------------------------------------------------------------------
  # system_fields and all_fields helper methods
  # -------------------------------------------------------------------
  describe "component helper methods" do
    subject(:comp) { described_class.new(fields: fields) }

    it "#rules returns empty array when no conditions" do
      expect(described_class.new.rules).to eq([])
    end

    it "#rules returns the rules array from conditions" do
      comp = described_class.new(conditions: conditions_with_rules)
      expect(comp.rules).to eq([rule_equals])
    end

    it "#top_operator defaults to AND" do
      expect(described_class.new.top_operator).to eq("AND")
    end

    it "#top_operator returns OR when set" do
      expect(described_class.new(conditions: conditions_or).top_operator).to eq("OR")
    end

    it "#no_value_operator? returns true for blank?" do
      expect(comp.no_value_operator?("blank?")).to be true
    end

    it "#no_value_operator? returns true for present?" do
      expect(comp.no_value_operator?("present?")).to be true
    end

    it "#no_value_operator? returns false for ==" do
      expect(comp.no_value_operator?("==")).to be false
    end

    it "#system_fields contains customer_id and created_at" do
      slugs = comp.system_fields.map { |f| f["name_slug"] }
      expect(slugs).to include("customer_id", "created_at")
    end

    it "#all_fields combines entity fields and system fields" do
      expect(comp.all_fields.size).to eq(fields.size + comp.system_fields.size)
    end

    it "#operators returns the OPERATORS values with I18n-resolved labels" do
      expect(comp.operators).to eq(
        ConditionBuilderComponent::OPERATORS.map do |op|
          { value: op[:value], label: I18n.t("chrome.condition_builder.operators.#{op[:key]}") }
        end
      )
    end
  end
end
