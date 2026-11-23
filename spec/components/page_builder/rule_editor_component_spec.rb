# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageBuilder::RuleEditorComponent, type: :component do
  let(:fields) { [{ "id" => "f1", "label" => "Country", "property_type" => "select", "options" => [] }] }
  let(:pages)  { [{ "id" => "p1", "name" => "Page 1" }] }
  let(:rule) do
    {
      "id"         => "r1",
      "name"       => "Show",
      "conditions" => { "logic" => "all", "groups" => [] },
      "actions"    => []
    }
  end

  def render_editor(rule: nil, fields: self.fields, pages: self.pages)
    render_inline(described_class.new(rule: rule, fields: fields, pages: pages))
  end

  before { render_editor(rule: nil) }

  it "keeps the rule-builder controller + JS target hooks" do
    expect(page).to have_css("[data-controller='rule-builder']")
    expect(page).to have_css("[data-rule-builder-target='ruleName']")
    expect(page).to have_css("[data-rule-builder-target='conditionGroups']")
    expect(page).to have_css("[data-rule-builder-target='ruleActions']")
    expect(page).to have_css("[data-rule-builder-target='testToggle']")
    # Templates are inert DOM — use native HTML check
    expect(page.native.to_html).to include("data-operators-template")
    expect(page.native.to_html).to include("data-action-types-template")
  end

  it "still renders all 16 operators and 9 action types" do
    # Component class exposes both — verify count
    expect(described_class::OPERATORS.length).to eq(16)
    expect(described_class::ACTION_TYPES.length).to eq(9)
    # Templates are present as DOM markers (Nokogiri strips <template> contents)
    expect(page.native.to_html).to include("data-operators-template")
    expect(page.native.to_html).to include("data-action-types-template")
  end

  it "exposes the AND/OR conditions logic control" do
    expect(page).to have_css("[data-rule-builder-target='conditionsLogic']")
  end

  it "exposes the live summary target" do
    expect(page).to have_css("[data-rule-builder-target='liveSummary']")
  end

  it "renders rule name input" do
    expect(page).to have_css("[data-rule-builder-target='ruleName']")
  end

  it "renders the test panel target" do
    expect(page).to have_css("[data-rule-builder-target='testPanel']")
    expect(page).to have_css("[data-rule-builder-target='sampleInputs']")
  end

  it "renders save and cancel buttons" do
    expect(page).to have_button("Save Rule")
    expect(page).to have_button("Cancel")
  end

  it "wires save to page-builder#saveRule" do
    expect(page).to have_css("[data-action='click->page-builder#saveRule']")
  end

  it "wires cancel/back to page-builder#closeRuleEditor" do
    # Both back chevron and Cancel button carry this action
    expect(page).to have_css("[data-action='click->page-builder#closeRuleEditor']")
  end

  context "with existing conditions" do
    let(:rule_with_conditions) do
      {
        "id"         => "r1",
        "name"       => "Test",
        "conditions" => {
          "logic"  => "all",
          "groups" => [
            {
              "logic" => "all",
              "items" => [{ "field_id" => "f1", "operator" => "equals", "value" => "US" }]
            }
          ]
        },
        "actions" => []
      }
    end

    it "renders condition rows for each group item" do
      render_editor(rule: rule_with_conditions)
      expect(page).to have_css("[data-condition-group='0']")
      expect(page).to have_css("[data-condition-field]")
      expect(page).to have_css("[data-group-logic='0']")
    end
  end

  context "pre-fills rule name" do
    it "shows an existing rule name" do
      render_editor(rule: rule)
      expect(page).to have_field("rule_name", with: "Show")
    end
  end

  context "layout field filtering" do
    let(:mixed_fields) do
      [
        { "id" => "f_name", "label" => "Name", "property_type" => "string" },
        { "id" => "f_sec", "label" => "Section", "property_type" => "layout", "field_type" => "section" },
        { "id" => "f_grp", "label" => "Group", "type" => "field_group" }
      ]
    end

    before { render_editor(rule: nil, fields: mixed_fields) }

    it "excludes layout/group fields from CONDITION fields (no value to test)" do
      cond = page.find("[data-controller='rule-builder']")["data-rule-builder-fields-value"]
      expect(cond).to include("f_name")
      expect(cond).not_to include("f_sec")
      expect(cond).not_to include("f_grp")
    end

    it "keeps layout fields available as ACTION targets (sections can be shown/hidden)" do
      actions = page.find("[data-controller='rule-builder']")["data-rule-builder-action-fields-value"]
      expect(actions).to include("f_name")
      expect(actions).to include("f_sec")
    end
  end
end
