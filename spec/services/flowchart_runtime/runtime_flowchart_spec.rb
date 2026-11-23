# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::RuntimeFlowchart do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  def configuration(value)
    {
      "elements" => [
        { "id" => "start", "type" => "start", "properties" => { "inputs" => [], "outputs" => [] } },
        { "id" => "assign", "type" => "process", "label" => "Assign", "properties" => { "steps" => [
          { "action" => "assign_value", "config" => { "resultVar" => "runtime_marker", "valueType" => "string", "stringValue" => value } }
        ] } },
        { "id" => "end", "type" => "end", "properties" => {} }
      ],
      "connections" => [{ "from" => "start", "to" => "assign" }, { "from" => "assign", "to" => "end" }],
      "metadata" => {}
    }
  end

  it "executes the selected tenant override without replacing the global artifact" do
    shared = create(:flowchart, :shared_type, :launched_status, name: "Scoped runtime", configuration: configuration("global").to_json)
    artifact = shared.activity
    head = shared.current_version_id
    Current.set(customer: customer, shared_resources_mode: false) do
      shared.configuration_json = configuration("tenant")
      shared.commit_version!
      runtime = described_class.new(shared.reload)
      trace = ActivityTracer.new(runtime).call
      expect(trace).to be_success
      expect(trace.ctx[:runtime_marker]).to eq("tenant")
      expect(shared.activity).to eq(artifact)
      expect(shared.current_version_id).to eq(head)
    end
    Current.set(customer: other_customer, shared_resources_mode: false) do
      trace = ActivityTracer.new(described_class.new(shared.reload)).call
      expect(trace).to be_success
      expect(trace.ctx[:runtime_marker]).to eq("global")
      expect(shared.activity).to eq(artifact)
    end
    expect(Object.const_defined?("ScopedRuntimeActivity", false)).to be(false)
  end

  it "resolves launched child overrides during runtime loading" do
    child = create(:flowchart, :shared_type, :launched_status, configuration: configuration("global-child").to_json)
    parent = create(:flowchart, :shared_type, :launched_status)
    Current.set(customer: customer, shared_resources_mode: false) do
      child.configuration_json = configuration("tenant-child")
      child.commit_version!
      parent.configuration_json = {
        "elements" => [
          { "id" => "start", "type" => "start", "properties" => {} },
          { "id" => "subflow", "type" => "subflow", "properties" => { "flowchartId" => child.id } },
          { "id" => "end", "type" => "end", "properties" => {} }
        ],
        "connections" => [{ "from" => "start", "to" => "subflow" }, { "from" => "subflow", "to" => "end" }], "metadata" => {}
      }
      parent.commit_version!
      trace = ActivityTracer.new(parent.reload).call
      expect(trace).to be_success
      expect(trace.ctx[:runtime_marker]).to eq("tenant-child")
    end
  end
end
