# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartDefinitions::Assistant::SchemaValidator do
  before { FlowchartDefinitions::Palette.reset! }

  def document(flowchart)
    {
      "intent" => "apply_flowchart",
      "reply" => "Creating.",
      "updates_confirmed" => false,
      "flowchart" => flowchart
    }
  end

  it "rejects identity keys on the flowchart fill" do
    result = described_class.call(document(
      "name" => "Create Student",
      "entity_name" => "Student",
      "customer_id" => 1,
      "elements" => [{ "id" => "start_1", "type" => "start" }],
      "connections" => []
    ))
    expect(result).not_to be_ok
    expect(result.errors.join).to include("customer_id")
  end

  it "rejects a deleted step action that is not in ActionCatalog" do
    result = described_class.call(document(
      "name" => "Create Student",
      "entity_name" => "Student",
      "elements" => [
        { "id" => "start_1", "type" => "start" },
        { "id" => "p1", "type" => "process", "steps" => [{ "action" => "validate" }] },
        { "id" => "end_1", "type" => "end" }
      ],
      "connections" => [{ "from" => "start_1", "to" => "end_1" }]
    ))
    expect(result).not_to be_ok
    expect(result.errors.join).to include("validate")
  end

  it "accepts a minimal apply_flowchart document" do
    result = described_class.call(document(
      "name" => "Create Student",
      "elements" => [
        { "id" => "start_1", "type" => "start" },
        { "id" => "end_1", "type" => "end" }
      ],
      "connections" => [{ "from" => "start_1", "to" => "end_1" }]
    ))
    expect(result).to be_ok
  end
end
