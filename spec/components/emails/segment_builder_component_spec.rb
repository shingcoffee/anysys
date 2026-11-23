# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::Audience::SegmentBuilderComponent, type: :component do
  # Use a plain struct so the spec does not require DB interaction.
  # The component only reads segment_rules from the list.
  ListStub = Struct.new(:segment_rules, keyword_init: true)

  let(:catalog) { Emails::SendActivities::FieldCatalog.new }

  # ── Rendering with a new (empty) list ─────────────────────────────────────

  describe "rendering with a new list (no existing rules)" do
    let(:list) { ListStub.new(segment_rules: {}) }

    before { render_inline(described_class.new(list: list, catalog: catalog)) }

    # For options inside <template> elements Capybara can't traverse into them,
    # so we assert on the raw rendered HTML for template-internal content.
    it "renders a field <select> whose options include 'email'" do
      expect(rendered_content).to include("value=\"email\"")
    end

    it "renders a field <select> whose options include 'roles.key'" do
      expect(rendered_content).to include("value=\"roles.key\"")
    end

    it "provides a join-toggle template for inserting AND/OR between members" do
      expect(rendered_content).to include("data-segment-builder-target=\"joinTemplate\"")
      expect(rendered_content).to include("data-sb-join=\"AND\"")
    end

    it "renders the hidden segment_rules_json input" do
      expect(page).to have_css(
        "input[name='email_list[segment_rules_json]']",
        visible: :all
      )
    end

    it "renders an 'Add condition' control" do
      expect(page).to have_button(/Add condition/i, disabled: false)
        .or have_css("button", text: /Add condition/i)
      expect(rendered_content).to include("Add condition")
    end

    it "carries the data-controller attribute on the root element" do
      expect(page).to have_css("[data-controller='segment-builder']")
    end

    it "sets data-segment-builder-target='output' on the hidden input" do
      expect(rendered_content).to include("data-segment-builder-target=\"output\"")
    end

    it "includes a <template> for the row template target" do
      expect(rendered_content).to include("data-segment-builder-target=\"rowTemplate\"")
    end

    it "does NOT render an Advanced raw JSON section" do
      expect(rendered_content).not_to include("Advanced")
      expect(rendered_content).not_to include("data-segment-builder-target=\"raw\"")
    end

    it "renders a root group container" do
      expect(rendered_content).to include("data-segment-builder-target=\"groupRoot\"")
    end

    it "renders an Add group control" do
      expect(rendered_content).to include("Add group")
    end

    it "does not render Preview unless preview: true" do
      expect(rendered_content).not_to include('data-email-list-form-target="previewButton"')
    end

    it "provides a group template for nested groups" do
      expect(rendered_content).to include("data-segment-builder-target=\"groupTemplate\"")
    end
  end

  describe "rendering with preview: true" do
    let(:list) { ListStub.new(segment_rules: {}) }

    before { render_inline(described_class.new(list: list, catalog: catalog, preview: true)) }

    it "renders Preview after the root Add group control inside a bordered card" do
      expect(rendered_content).to include(I18n.t("admin_modules.emails.lists.preview.button"))
      expect(rendered_content).to include('data-email-list-form-target="previewButton"')
      expect(rendered_content).to include("email-list-form#preview")
      # Root group itself is the bordered card (rows + footer), so new rows stay inside.
      expect(page).to have_css('[data-segment-builder-target="groupRoot"].rounded-xl.border.min-h-28')
    end

    it "does not put Preview inside nested group templates" do
      expect(rendered_content.scan('data-email-list-form-target="previewButton"').size).to eq(1)
    end
  end

  # ── Rendering with existing segment_rules (edit form) ─────────────────────

  describe "rendering a list with existing segment_rules" do
    let(:rules) do
      {
        "match"      => "all",
        "conditions" => [
          { "field" => "first_name", "operator" => "equals", "value" => "Ada" }
        ]
      }
    end
    let(:list) { ListStub.new(segment_rules: rules) }

    before { render_inline(described_class.new(list: list, catalog: catalog)) }

    it "pre-renders the existing condition row's field value (first_name selected)" do
      # Server-rendered rows are outside <template>, so Capybara can see them.
      expect(page).to have_css("select option[value='first_name'][selected]")
    end

    it "pre-renders the existing condition row's operator value (equals selected)" do
      expect(page).to have_css("select option[value='equals'][selected]")
    end

    it "pre-renders the existing condition row's text value (Ada)" do
      expect(page).to have_css("input[value='Ada']")
    end

    it "renders a hover-revealed remove control for the pre-rendered row" do
      expect(page).to have_css(
        "button[aria-label='#{I18n.t("comp_misc.segment_builder.remove_condition_aria")}'][data-action='segment-builder#removeRow']",
        visible: :all
      )
      expect(rendered_content).to include("group-hover:opacity-100")
      expect(rendered_content).not_to match(/>\s*Remove\s*</)
    end

    it "populates the hidden output with the serialized rules" do
      output = page.find(
        "input[name='email_list[segment_rules_json]']",
        visible: :all
      ).value
      expect(output).to be_present
      parsed = JSON.parse(output)
      expect(parsed.dig("conditions", 0, "field")).to eq("first_name")
    end
  end

  # ── Legacy match:"any" migrates to per-join OR toggles ────────────────────

  describe "rendering a legacy list with match='any' and two conditions" do
    let(:rules) do
      {
        "match"      => "any",
        "conditions" => [
          { "field" => "first_name", "operator" => "equals", "value" => "Ada" },
          { "field" => "last_name",  "operator" => "equals", "value" => "Lovelace" }
        ]
      }
    end
    let(:list) { ListStub.new(segment_rules: rules) }

    before { render_inline(described_class.new(list: list, catalog: catalog)) }

    it "renders an OR join toggle between the two conditions" do
      expect(page).to have_css("[data-sb-join='OR']")
    end

    it "serializes legacy match:any into a per-join joins array" do
      output = page.find("input[name='email_list[segment_rules_json]']", visible: :all).value
      parsed = JSON.parse(output)
      expect(parsed["joins"]).to eq(["OR"])
      expect(parsed["conditions"].size).to eq(2)
    end
  end

  # ── Per-join groups (the flowchart model) ─────────────────────────────────

  describe "rendering a group with mixed per-join operators" do
    let(:rules) do
      {
        "type"  => "group",
        "joins" => %w[AND OR],
        "conditions" => [
          { "field" => "first_name", "operator" => "equals", "value" => "A" },
          { "field" => "last_name",  "operator" => "equals", "value" => "B" },
          { "field" => "email",      "operator" => "contains", "value" => "c" }
        ]
      }
    end
    let(:list) { ListStub.new(segment_rules: rules) }

    before { render_inline(described_class.new(list: list, catalog: catalog)) }

    it "renders one AND toggle and one OR toggle (independent joins)" do
      expect(page).to have_css("[data-sb-join='AND']", count: 1)
      expect(page).to have_css("[data-sb-join='OR']",  count: 1)
    end

    it "round-trips the joins array in the hidden output" do
      output = page.find("input[name='email_list[segment_rules_json]']", visible: :all).value
      expect(JSON.parse(output)["joins"]).to eq(%w[AND OR])
    end
  end
end
