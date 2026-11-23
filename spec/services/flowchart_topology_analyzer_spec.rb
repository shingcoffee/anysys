# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartTopologyAnalyzer do
  it "keeps linear graphs free of branch metadata" do
    elements = [
      { "id" => "s", "type" => "start" },
      { "id" => "p", "type" => "process" },
      { "id" => "e", "type" => "end" }
    ]
    connections = [
      { "id" => "c1", "from" => "s", "to" => "p" },
      { "id" => "c2", "from" => "p", "to" => "e" }
    ]

    result = described_class.new(elements, connections).analyze
    expect(result.branch_groups).to be_empty
    expect(result).not_to respond_to(:node_guards)
    expect(result).not_to respond_to(:decision_indices)
  end

  it "derives decision branch order and match values from outgoing connections" do
    elements = [
      { "id" => "s", "type" => "start" },
      { "id" => "b", "type" => "decision" },
      { "id" => "a", "type" => "process" },
      { "id" => "d", "type" => "process" },
      { "id" => "e", "type" => "end" }
    ]
    connections = [
      { "id" => "c1", "from" => "s", "to" => "b" },
      { "id" => "c2", "from" => "b", "to" => "a", "matchValue" => "active", "label" => "Active" },
      { "id" => "c3", "from" => "b", "to" => "d", "matchValue" => "", "label" => "Else" },
      { "id" => "c4", "from" => "a", "to" => "e" },
      { "id" => "c5", "from" => "d", "to" => "e" }
    ]

    result = described_class.new(elements, connections).analyze
    group = result.branch_groups.fetch("b")
    expect(group[:branches].keys).to eq(%i[branch_0 branch_1])
    expect(group[:branches][:branch_0]).to include(connection_id: "c2", match_value: "active", label: "Active")
    expect(group[:branches][:branch_1]).to include(connection_id: "c3", match_value: "", label: "Else")
    expect(group[:merge_node_id]).to eq("e")
    expect(group).not_to have_key(:route_index)
  end

  it "finds the merge of nested decisions independently" do
    elements = [
      { "id" => "s", "type" => "start" },
      { "id" => "outer", "type" => "decision" },
      { "id" => "inner", "type" => "decision" },
      { "id" => "a", "type" => "process" },
      { "id" => "b", "type" => "process" },
      { "id" => "other", "type" => "process" },
      { "id" => "e", "type" => "end" }
    ]
    connections = [
      { "from" => "s", "to" => "outer" },
      { "from" => "outer", "to" => "inner" },
      { "from" => "outer", "to" => "other" },
      { "from" => "inner", "to" => "a" },
      { "from" => "inner", "to" => "b" },
      { "from" => "a", "to" => "e" },
      { "from" => "b", "to" => "e" },
      { "from" => "other", "to" => "e" }
    ]

    result = described_class.new(elements, connections).analyze
    expect(result.branch_groups.fetch("outer")[:merge_node_id]).to eq("e")
    expect(result.branch_groups.fetch("inner")[:merge_node_id]).to eq("e")
  end
end
