# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartDefinitions::GraphValidator do
  let_it_be(:customer) { create(:customer) }
  let!(:entity) { create(:entity, customer: customer, name: "Student") }

  def normalized(overrides = {})
    FlowchartDefinitions::Normalizer.call({
      "name" => "Create Student",
      "entity_name" => "Student",
      "crud_type" => "create",
      "elements" => [
        { "id" => "start_1", "type" => "start", "label" => "Start" },
        {
          "id" => "p1",
          "type" => "process",
          "label" => "Create",
          "steps" => [{ "action" => "new_model" }]
        },
        { "id" => "end_1", "type" => "end", "label" => "End" }
      ],
      "connections" => [
        { "from" => "start_1", "to" => "p1" },
        { "from" => "p1", "to" => "end_1" }
      ]
    }.merge(overrides))
  end

  def validate(overrides = {})
    described_class.call(normalized: normalized(overrides), customer: customer)
  end

  it "accepts a start-process-end create graph" do
    expect(validate).to be_ok
  end

  it "rejects a second start element" do
    result = validate(
      "elements" => [
        { "id" => "start_1", "type" => "start" },
        { "id" => "start_2", "type" => "start" },
        { "id" => "p1", "type" => "process", "steps" => [{ "action" => "new_model" }] },
        { "id" => "end_1", "type" => "end" }
      ]
    )
    expect(result.errors).to include(I18n.t("ai_assistant.assistant.apply_errors.flowchart_multiple_starts"))
  end

  it "rejects a deleted step action that is not in ActionCatalog" do
    result = validate(
      "elements" => [
        { "id" => "start_1", "type" => "start" },
        { "id" => "p1", "type" => "process", "steps" => [{ "action" => "validate" }] },
        { "id" => "end_1", "type" => "end" }
      ]
    )
    expect(result.errors).to include(I18n.t("ai_assistant.assistant.apply_errors.flowchart_unknown_action", value: "validate"))
  end

  it "rejects a process with no steps" do
    result = validate(
      "elements" => [
        { "id" => "start_1", "type" => "start" },
        { "id" => "p1", "type" => "process", "label" => "Empty" },
        { "id" => "end_1", "type" => "end" }
      ]
    )
    expect(result.errors).to include(I18n.t("ai_assistant.assistant.apply_errors.flowchart_steps_blank"))
  end

  it "rejects a connection into start" do
    result = validate(
      "connections" => [
        { "from" => "p1", "to" => "start_1" },
        { "from" => "start_1", "to" => "end_1" }
      ]
    )
    expect(result.errors).to include(I18n.t("ai_assistant.assistant.apply_errors.flowchart_start_has_incoming"))
  end
end
