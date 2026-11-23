# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flowcharts::Compatibility do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity, :with_name_status_schema, customer: customer, name: "Student", display_label: "Student")
  end

  def flowchart_with_assignments(assignments)
    create(:flowchart, :launched_status, customer: customer, configuration: {
      "elements" => [
        { "id" => "s", "type" => "start", "label" => "Start", "properties" => {} },
        { "id" => "p", "type" => "process", "label" => "Set", "properties" => {
          "steps" => [{
            "action" => "set_record_fields",
            "config" => { "modelVariable" => "model", "assignments" => assignments }
          }]
        } },
        { "id" => "e", "type" => "end", "label" => "End", "properties" => {} }
      ],
      "connections" => [
        { "id" => "c1", "from" => "s", "to" => "p" },
        { "id" => "c2", "from" => "p", "to" => "e" }
      ],
      "metadata" => {}
    }.to_json)
  end

  it "returns no errors when the flowchart and entity are blank" do
    expect(described_class.errors(nil, entity)).to eq([])
    expect(described_class.errors(create(:flowchart, customer: customer), nil)).to eq([])
  end

  it "returns no errors when every named attribute exists on the entity" do
    flowchart = flowchart_with_assignments([
      { "key" => "name", "value" => "ctx[:params][:name]" }
    ])

    expect(described_class.errors(flowchart, entity)).to eq([])
  end

  it "returns a submitter-safe message when a step names an attribute the entity does not have" do
    flowchart = flowchart_with_assignments([
      { "key" => "missing_field", "value" => "ctx[:params][:missing_field]" }
    ])

    expect(described_class.errors(flowchart, entity)).to eq([
      I18n.t("maint_core.errors.page_launch.submission_process_incompatible", entity: entity.display_label)
    ])
  end

  it "explains the mismatch to the platform owner in the generator's words" do
    flowchart = flowchart_with_assignments([
      { "key" => "missing_field", "value" => "ctx[:params][:missing_field]" }
    ])

    problems = described_class.problems(flowchart, entity)
    expect(problems.size).to eq(1)
    expect(problems.first).to include("missing_field")
  end

  it "names the step at fault" do
    flowchart = flowchart_with_assignments([
      { "key" => "missing_field", "value" => "ctx[:params][:missing_field]" }
    ])

    expect(described_class.problems(flowchart, entity).first).to start_with(
      "Step \"Set\" (#{FlowchartDefinitions::ActionLabel.for('set_record_fields')}): Invalid generator configuration:"
    )
  end

  it "has no problems for a compatible flowchart or without an entity" do
    flowchart = flowchart_with_assignments([])

    expect(described_class.problems(flowchart, entity)).to eq([])
    expect(described_class.problems(flowchart, nil)).to eq([])
  end
end
