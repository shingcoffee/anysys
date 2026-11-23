# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartDefinitions::Persist do
  let_it_be(:customer) { create(:customer) }

  def fill(name: "Create Student", action: "new_model")
    last_action = action == "new_model" ? "save_model" : action
    actions = [
      ["p1", "new_model", { "resultVar" => "model" }],
      ["p2", "build_contract", nil],
      ["p3", "validate_contract", nil],
      ["p4", last_action, nil]
    ]
    processes = actions.map do |id, step_action, config|
      step = { "action" => step_action }
      step["config"] = config if config
      { "id" => id, "type" => "process", "label" => step_action, "steps" => [step] }
    end
    ids = %w[start_1] + actions.map(&:first) + %w[end_1]
    {
      "name" => name,
      "description" => "Create a student",
      "elements" => [
        { "id" => "start_1", "type" => "start", "label" => "Start" },
        *processes,
        { "id" => "end_1", "type" => "end", "label" => "End" }
      ],
      "connections" => ids.each_cons(2).map { |from, to| { "from" => from, "to" => to } }
    }
  end

  def persist!(raw = fill)
    normalized = FlowchartDefinitions::Normalizer.call(raw)
    graph = FlowchartDefinitions::GraphValidator.call(normalized: normalized, customer: customer)
    expect(graph).to be_ok
    described_class.call(normalized: normalized, customer: customer)
  end

  it "creates a launched customer-owned flowchart and its first version" do
    result = persist!
    expect(result).to be_ok
    expect(result.created).to eq("Create Student")
    record = Flowchart.find_by(customer_id: customer.id, name: "Create Student")
    expect(record).to be_launched
    expect(record.customer_id).to eq(customer.id)
    expect(record.elements.map { |el| el["type"] }).to include("start", "process", "end")
    expect(record.flowchart_versions.count).to eq(1)
  end

  it "writes a new version of an existing draft" do
    record = create(:flowchart, :draft, customer: customer, name: "Create Student", configuration: FlowchartDefinitions::Normalizer.call(fill).configuration.to_json)
    raw = fill
    raw["description"] = "Updated create student"
    raw["elements"][1]["steps"] << { "action" => "log", "config" => { "messageTemplate" => "step", "includeBacktrace" => false, "structured" => false } }
    result = persist!(raw)
    expect(result.updated).to eq("Create Student")
    expect(result.created).to be_nil
    record.reload
    expect(record).to be_draft
    expect(record.description).to eq("Updated create student")
    expect(record.flowchart_versions.count).to eq(2)
  end

  it "writes a new version of a launched flowchart without changing status" do
    persist!
    record = Flowchart.find_by!(customer_id: customer.id, name: "Create Student")
    expect(record).to be_launched
    raw = fill
    raw["description"] = "Launched update"
    raw["elements"][1]["steps"] << { "action" => "log", "config" => { "messageTemplate" => "step", "includeBacktrace" => false, "structured" => false } }
    result = persist!(raw)
    expect(result.updated).to eq("Create Student")
    record.reload
    expect(record).to be_launched
    expect(record.description).to eq("Launched update")
    expect(record.flowchart_versions.count).to eq(2)
  end

  it "does not write another tenant's flowchart" do
    other = create(:customer)
    foreign = create(:flowchart, :draft, customer: other, name: "Create Student")
    original_head = foreign.current_version_id
    persist!
    expect(foreign.reload).to be_draft
    expect(foreign.current_version_id).to eq(original_head)
    expect(Flowchart.where(customer_id: other.id)).to contain_exactly(foreign)
  end

  it "does not update a shared flowchart with the same name" do
    shared = create(:flowchart, :shared_type, name: "Create Student")
    expect(shared.customer_id).to be_nil
    persist!
    owned = Flowchart.find_by(customer_id: customer.id, name: "Create Student")
    expect(owned).to be_present
    expect(owned.id).not_to eq(shared.id)
    expect(Flowchart.unscoped.find(shared.id).customer_id).to be_nil
  end

  it "rejects a deleted flowchart with the same name" do
    persist!
    Flowchart.find_by!(customer_id: customer.id, name: "Create Student").soft_delete
    normalized = FlowchartDefinitions::Normalizer.call(fill)
    graph = FlowchartDefinitions::GraphValidator.call(normalized: normalized, customer: customer)
    expect(graph).not_to be_ok
    expect(graph.errors.join).to include("Create Student")
    result = described_class.call(normalized: normalized, customer: customer)
    expect(result).not_to be_ok
  end

  it "rejects an unknown step action" do
    normalized = FlowchartDefinitions::Normalizer.call(fill(action: "not_a_real_action"))
    graph = FlowchartDefinitions::GraphValidator.call(normalized: normalized, customer: customer)
    expect(graph).not_to be_ok
    expect(graph.errors.join).to include("not_a_real_action")
  end

  it "rejects missing upstream inputs without leaving a flowchart or version" do
    raw = fill(action: "api_call")
    raw["elements"][-2]["steps"][0]["config"] = {
      "url" => "ctx[:missing_api_url]", "method" => "GET"
    }
    result = nil

    expect { result = persist!(raw) }
      .not_to change { [Flowchart.unscoped.count, FlowchartVersion.count] }

    expect(result).not_to be_ok
    expect(result.created).to be_nil
    expect(result.errors.join).to include(
      I18n.t("maint_core.flowcharts.server_validation.missing_input", key: "missing_api_url")
    )
  end

  it "rejects server-invalid step configuration without leaving a flowchart or version" do
    raw = fill(action: "api_call")
    normalized = FlowchartDefinitions::Normalizer.call(raw)
    candidate = Flowchart.new(customer: customer,
                             configuration: normalized.configuration.to_json)
    errors = FlowchartServerValidator.new(candidate, normalized.configuration.deep_dup).call
                                    .select { |problem| problem[:severity] == "error" }
    expect(errors).not_to be_empty
    result = nil

    expect { result = persist!(raw) }
      .not_to change { [Flowchart.unscoped.count, FlowchartVersion.count] }

    expect(result).not_to be_ok
    expect(result.errors).to include(*errors.map { |problem| problem[:message] })
  end

  it "launches despite server warnings without saving validator-only mutations" do
    normalized = FlowchartDefinitions::Normalizer.call(fill)
    submitted = normalized.configuration.deep_dup
    allow(FlowchartServerValidator).to receive(:new).and_wrap_original do |original, candidate, configuration|
      original.call(candidate, configuration).tap do |validator|
        allow(validator).to receive(:call).and_wrap_original do |validate|
          problems = validate.call
          configuration["elements"][0]["label"] = "Validator-only label"
          candidate.configuration_json = configuration
          candidate.description = "Validator-only description"
          problems + [{ severity: "warning", message: "Dry-run timed out" }]
        end
      end
    end

    result = described_class.call(normalized: normalized, customer: customer)

    expect(result).to be_ok
    record = Flowchart.find_by!(customer_id: customer.id, name: "Create Student")
    expect(record).to be_launched
    expect(record.description).to eq("Create a student")
    expect(record.configuration_json).to eq(submitted)
    expect(normalized.configuration).to eq(submitted)
    expect(record.flowchart_versions.count).to eq(1)
  end

  it "persists Query Models editor config" do
    raw = fill
    raw["name"] = "List Students"
    raw["elements"][1]["label"] = "Query"
    raw["elements"][1]["steps"] = [
      {
        "action" => "query_models",
        "config" => {
          "queryType" => "where",
          "conditions" => { "status" => "active" },
          "orderBy" => "email",
          "limit" => 25,
          "resultVar" => "models"
        }
      }
    ]
    raw["elements"] = [raw["elements"].first, raw["elements"][1], raw["elements"].last]
    raw["connections"] = [{ "from" => "start_1", "to" => "p1" }, { "from" => "p1", "to" => "end_1" }]
    result = persist!(raw)
    expect(result).to be_ok
    record = Flowchart.find_by!(customer_id: customer.id, name: "List Students")
    step = record.elements.find { |el| el["type"] == "process" }.dig("properties", "steps", 0)
    expect(step["action"]).to eq("query_models")
    expect(step["config"]).to include(
      "queryType" => "where",
      "conditions" => { "status" => "active" },
      "orderBy" => "email",
      "limit" => 25,
      "resultVar" => "models"
    )
  end
end
