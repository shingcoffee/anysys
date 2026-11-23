# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartDocumenter do
  # Documenter specs intentionally exercise incomplete / legacy configuration
  # shapes. Activity generation is out of scope here and is covered elsewhere.
  before do
    allow_any_instance_of(Flowchart).to receive(:generate_activity)
  end

  subject(:markdown) { described_class.new(flowchart).generate }

  let_it_be(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }
  let(:flowchart) do
    create(:flowchart,
           customer: customer,
           name: "Test Flowchart",
           description: "A test flowchart for documentation generation",
           configuration: configuration)
  end

  let(:configuration) do
    {
      "elements" => [
        {
          "id" => "el_1",
          "type" => "start",
          "label" => "Start Process",
          "properties" => {
            "description" => "Manual start for the workflow"
          }
        },
        {
          "id" => "el_2",
          "type" => "process",
          "label" => "Validate Data",
          "properties" => {
            "steps" => [
              { "action" => "validate_contract", "selectionLabels" => ["Validate", "Contract"] }
            ],
            "description" => "Validates and saves the data"
          }
        },
        {
          "id" => "el_2_2",
          "type" => "process",
          "label" => "Save Model",
          "properties" => {
            "steps" => [
              { "action" => "save_model", "selectionLabels" => ["Save", "Model"] }
            ]
          }
        },
        {
          "id" => "el_3",
          "type" => "decision",
          "label" => "Check Status",
          "properties" => {
            "condition" => { "expression" => "ctx.status == 'active'" },
            "description" => "Checks if status is active"
          }
        },
        {
          "id" => "el_4",
          "type" => "end",
          "label" => "Success",
          "properties" => {
            "description" => "Successful completion"
          }
        },
        {
          "id" => "el_5",
          "type" => "end",
          "label" => "Failure",
          "properties" => {
            "description" => "Failed completion"
          }
        }
      ],
      "connections" => [
        { "id" => "c1", "from" => "el_1", "to" => "el_2" },
        { "id" => "c1b", "from" => "el_2", "to" => "el_2_2" },
        { "id" => "c2", "from" => "el_2_2", "to" => "el_3" },
        { "id" => "c3", "from" => "el_3", "to" => "el_4", "label" => "true" },
        { "id" => "c4", "from" => "el_3", "to" => "el_5", "label" => "false" }
      ],
      "metadata" => {
        "created_at" => "2024-01-01T00:00:00Z"
      }
    }.to_json
  end

  describe "#generate" do
    it "generates markdown documentation" do
      expect(markdown).to be_a(String)
      expect(markdown).not_to be_empty
    end

    it "includes the flowchart name as title" do
      expect(markdown).to include("# Test Flowchart")
    end

    it "includes the flowchart description" do
      expect(markdown).to include("A test flowchart for documentation generation")
    end

    it "includes overview section with statistics" do
      expect(markdown).to include("## Overview")
      expect(markdown).to include("**Elements:** 6")
      expect(markdown).to include("**Connections:** 5")
    end

    it "includes flow description section" do
      expect(markdown).to include("## Flow Description")
    end

    it "includes elements table" do
      expect(markdown).to include("## Elements")
      expect(markdown).to include("| Type | Label | Description | Properties |")
      expect(markdown).to include("| start | Start Process |")
      expect(markdown).to include("| process | Validate Data |")
      expect(markdown).to include("| decision | Check Status |")
    end

    it "includes connections list" do
      expect(markdown).to include("## Connections")
      expect(markdown).to include("Start Process → Validate Data")
      expect(markdown).to include("Validate Data → Save Model")
      expect(markdown).to include("Save Model → Check Status")
      expect(markdown).to include("Check Status → Success [true]")
      expect(markdown).to include("Check Status → Failure [false]")
    end

    it "includes step details in process elements" do
      expect(markdown).to include("1 steps")
    end

    it "includes condition in decision elements" do
      expect(markdown).to include("condition: ctx.status == 'active'")
    end

    context "when flowchart has no description" do
      before do
        flowchart.update!(description: nil)
      end

      it "generates documentation without description" do
        expect(markdown).to include("# Test Flowchart")
        expect(markdown).not_to include("A test flowchart")
      end
    end

    context "when flowchart has no start element" do
      let(:configuration) do
        {
          "elements" => [
            {
              "id" => "el_1",
              "type" => "process",
              "label" => "Process",
              "properties" => {}
            }
          ],
          "connections" => [],
          "metadata" => {}
        }.to_json
      end

      it "indicates no start element found" do
        expect(markdown).to include("No start element found")
      end
    end
  end

  describe "flow narrative" do
    it "traverses the flow from start to end" do
      expect(markdown).to match(/1\. \*\*Start\*\* — Start Process/)
      expect(markdown).to match(/2\. \*\*Process\*\* — Validate Data/)
      expect(markdown).to match(/3\. \*\*Process\*\* — Save Model/)
      expect(markdown).to match(/4\. \*\*Decision\*\* — Check Status/)
    end

    it "names start elements without a trigger leftover" do
      expect(markdown).to include("**Start** — Start Process")
      expect(markdown).not_to include("trigger:")
    end

    it "includes step names for process elements" do
      expect(markdown).to include("Validate Contract")
      expect(markdown).to include("Save Model")
    end

    it "includes condition expression for decision elements" do
      expect(markdown).to include("(ctx.status == 'active')")
    end
  end

  # ── Branch coverage for element types not exercised by the main fixture ──

  describe "loop element in narrative" do
    let(:configuration) do
      {
        "elements" => [
          { "id" => "el_1", "type" => "start", "label" => "Start", "properties" => {} },
          { "id" => "el_2", "type" => "loop",  "label" => "Repeat Step", "properties" => {} },
          { "id" => "el_3", "type" => "end",   "label" => "Done",  "properties" => {} }
        ],
        "connections" => [
          { "id" => "c1", "from" => "el_1", "to" => "el_2" },
          { "id" => "c2", "from" => "el_2", "to" => "el_3" }
        ],
        "metadata" => {}
      }.to_json
    end

    it "emits Loop narrative entry" do
      expect(markdown).to include("**Loop** — Repeat Step")
    end
  end

  describe "unknown element type in narrative" do
    let(:configuration) do
      {
        "elements" => [
          { "id" => "el_1", "type" => "start",   "label" => "Start", "properties" => {} },
          { "id" => "el_2", "type" => "subflow",  "label" => "Call Sub", "properties" => {} },
          { "id" => "el_3", "type" => "end",      "label" => "Done",  "properties" => {} }
        ],
        "connections" => [
          { "id" => "c1", "from" => "el_1", "to" => "el_2" },
          { "id" => "c2", "from" => "el_2", "to" => "el_3" }
        ],
        "metadata" => {}
      }.to_json
    end

    it "capitalises the type and uses it as header for unknown types (else branch)" do
      expect(markdown).to include("**Subflow** — Call Sub")
    end
  end

  describe "element without label" do
    let(:configuration) do
      {
        "elements" => [
          { "id" => "el_1", "type" => "start", "properties" => {} },
          { "id" => "el_2", "type" => "end",   "properties" => {} }
        ],
        "connections" => [{ "id" => "c1", "from" => "el_1", "to" => "el_2" }],
        "metadata" => {}
      }.to_json
    end

    it "falls back to (unnamed) when label is absent" do
      expect(markdown).to include("(unnamed)")
    end
  end

  describe "start element without extra properties" do
    let(:configuration) do
      {
        "elements" => [
          { "id" => "el_1", "type" => "start", "label" => "Go", "properties" => {} },
          { "id" => "el_2", "type" => "end",   "label" => "Stop", "properties" => {} }
        ],
        "connections" => [{ "id" => "c1", "from" => "el_1", "to" => "el_2" }],
        "metadata" => {}
      }.to_json
    end

    it "renders the start label without a trigger leftover" do
      expect(markdown).to include("**Start** — Go")
      expect(markdown).not_to include("trigger:")
    end
  end

  describe "decision element without condition expression" do
    let(:configuration) do
      {
        "elements" => [
          { "id" => "el_1", "type" => "start",    "label" => "Start",    "properties" => {} },
          { "id" => "el_2", "type" => "decision",  "label" => "Choose",   "properties" => {} },
          { "id" => "el_3", "type" => "end",       "label" => "Done",     "properties" => {} }
        ],
        "connections" => [
          { "id" => "c1", "from" => "el_1", "to" => "el_2" },
          { "id" => "c2", "from" => "el_2", "to" => "el_3" }
        ],
        "metadata" => {}
      }.to_json
    end

    it "omits the parenthesised expression when nil" do
      expect(markdown).to match(/\*\*Decision\*\* — Choose\n/)
    end
  end

  describe "process element without selectionLabels" do
    let(:configuration) do
      {
        "elements" => [
          { "id" => "el_1", "type" => "start",   "label" => "Start",   "properties" => {} },
          {
            "id" => "el_2", "type" => "process", "label" => "Work",
            "properties" => {
              "steps" => [
                { "action" => "save_entry" }
              ]
            }
          },
          {
            "id" => "el_2_2", "type" => "process", "label" => "Notify",
            "properties" => {
              "steps" => [
                { "action" => "notify_user" }
              ]
            }
          },
          { "id" => "el_3", "type" => "end",     "label" => "Done",    "properties" => {} }
        ],
        "connections" => [
          { "id" => "c1", "from" => "el_1", "to" => "el_2" },
          { "id" => "c1b", "from" => "el_2", "to" => "el_2_2" },
          { "id" => "c2", "from" => "el_2_2", "to" => "el_3" }
        ],
        "metadata" => {}
      }.to_json
    end

    it "uses the action string when selectionLabels is absent" do
      expect(markdown).to include("save_entry")
      expect(markdown).to include("notify_user")
    end
  end

  describe "connection without label" do
    let(:configuration) do
      {
        "elements" => [
          { "id" => "el_1", "type" => "start", "label" => "S", "properties" => {} },
          { "id" => "el_2", "type" => "end",   "label" => "E", "properties" => {} }
        ],
        "connections" => [{ "id" => "c1", "from" => "el_1", "to" => "el_2" }],
        "metadata" => {}
      }.to_json
    end

    it "omits the bracketed label suffix" do
      # No [label_text] appended when connection label is absent
      expect(markdown).to include("- S → E\n").or(include("- S → E"))
      expect(markdown).not_to match(/- S → E \[/)
    end
  end

  describe "connection whose from/to element is missing" do
    let(:configuration) do
      {
        "elements" => [
          { "id" => "el_1", "type" => "start", "label" => "Known", "properties" => {} },
          { "id" => "el_2", "type" => "end",   "label" => "End",   "properties" => {} }
        ],
        # Connection references an element id that doesn't exist in elements
        "connections" => [
          { "id" => "c1", "from" => "el_1",    "to" => "el_2" },
          { "id" => "c2", "from" => "ghost_id", "to" => "el_2", "label" => "ghost" }
        ],
        "metadata" => {}
      }.to_json
    end

    it "falls back to the raw id when the element is not found" do
      expect(markdown).to include("ghost_id →")
    end
  end
end
