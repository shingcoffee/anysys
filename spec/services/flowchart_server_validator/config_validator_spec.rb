# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartServerValidator::ConfigValidator do
  subject(:problems) { described_class.new.call(elements, connections) }

  let(:elements) do
    [
      {
        "id" => "switch",
        "type" => "switch",
        "label" => "Switch",
        "properties" => {
          "sourceVariable" => "status",
          "_route_index" => "0]; Kernel.raise('SWITCH_ROUTE_INJECTION'); ctx[:_route_0",
          "_connection_match_values" => [
            {
              "branch" => "branch_0; Kernel.raise('SWITCH_BRANCH_INJECTION'); :branch_0",
              "matchValue" => "persisted"
            },
            { "branch" => "branch_1", "matchValue" => "" }
          ]
        }
      }
    ]
  end
  let(:connections) do
    [
      { "id" => "c1", "from" => "switch", "to" => "active", "matchValue" => "active" },
      { "id" => "c2", "from" => "switch", "to" => "default", "matchValue" => "" }
    ]
  end

  it "skips removed Switch elements because no generator is registered" do
    expect(problems).to be_empty
  end

  it "translates step problems and copies ConfigError#field" do
    elements.replace(
      [
        { "id" => "s", "type" => "start", "label" => "S", "properties" => {} },
        {
          "id" => "p",
          "type" => "process",
          "label" => "P",
          "properties" => {
            "steps" => [
              { "id" => "step_1", "action" => "save_model", "label" => "Save", "config" => {} }
            ]
          }
        }
      ]
    )
    connections.replace([])

    allow_any_instance_of(CodeGenerators::ElementTypes::Process::ModelOperations::SaveModelGenerator)
      .to receive(:validate_config)
      .and_return([CodeGenerators::ConfigError.new(field: "contractRef", code: :required, message: "contractRef is required")])

    expect(problems).to include(
      hash_including(
        type: "step_config_invalid",
        element_id: "p",
        field: "contractRef",
        message: I18n.t(
          "maint_core.flowcharts.config_problems.step_invalid",
          step: "Save",
          action: FlowchartDefinitions::ActionLabel.for("save_model"),
          error: "contractRef is required"
        ),
        fix_hint: I18n.t("maint_core.flowcharts.config_problems.fix_step")
      )
    )
  end

  it "names an unlabelled step by its box label and the translated action name" do
    elements.replace(
      [
        {
          "id" => "p",
          "type" => "process",
          "label" => "Call partner",
          "properties" => {
            "steps" => [{ "id" => "step_1", "action" => "api_call", "config" => { "url" => '"https://x"', "resultVar" => "result" } }]
          }
        },
        {
          "id" => "q",
          "type" => "process",
          "properties" => {
            "steps" => [{ "id" => "step_2", "action" => "api_call", "config" => { "url" => '"https://x"', "resultVar" => "result" } }]
          }
        }
      ]
    )
    connections.replace([])

    I18n.with_locale(:"zh-CN") do
      messages = problems.to_h { |problem| [problem[:element_id], problem[:message]] }
      expect(messages["p"]).to start_with("步骤“Call partner”（HTTP 请求）：")
      expect(messages["q"]).to start_with("步骤“HTTP 请求”（HTTP 请求）：")
      expect(messages.values.join).not_to include("api_call")
    end
  end

  it "forwards ConfigError#field on element_config_invalid and uses the translated type label" do
    elements.replace(
      [
        {
          "id" => "e",
          "type" => "end",
          "label" => "Done",
          "properties" => { "responseType" => "value" }
        }
      ]
    )
    connections.replace([])

    expect(problems).to include(
      hash_including(
        type: "element_config_invalid",
        element_id: "e",
        field: "returnValue",
        message: I18n.t(
          "maint_core.flowcharts.config_problems.element_invalid",
          label: "Done",
          type: I18n.t("flowchart_elements.end.label"),
          error: I18n.t("flowchart_elements.shared.errors.required", field: "returnValue")
        ),
        fix_hint: I18n.t("maint_core.flowcharts.config_problems.fix_element")
      )
    )
  end

  it "skips a step action that is not a canonical registry key, leaving it to the codegen dry run" do
    elements.replace(
      [
        {
          "id" => "p",
          "type" => "process",
          "properties" => {
            "steps" => [{ "action" => "API_call", "config" => { "url" => '"https://x"' } }]
          }
        }
      ]
    )
    connections.replace([])

    expect(CodeGenerators::GeneratorRegistry.instance.find_step_action("API_call")).to be_nil
    expect(problems).to be_empty
  end
end
