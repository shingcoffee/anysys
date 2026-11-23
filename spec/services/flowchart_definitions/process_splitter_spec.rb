# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartDefinitions::ProcessSplitter do
  def graph(elements:, connections:)
    { "elements" => elements, "connections" => connections, "metadata" => { "note" => "keep" } }
  end

  def process(id:, y:, label:, steps:, x: 400)
    {
      "id" => id,
      "type" => "process",
      "x" => x,
      "y" => y,
      "width" => 100,
      "height" => 45,
      "label" => label,
      "properties" => { "steps" => steps }
    }
  end

  it "splits a multi-action process into a vertical single-action chain" do
    input = graph(
      elements: [
        { "id" => "start", "type" => "start", "x" => 400, "y" => 80, "label" => "Start", "properties" => {} },
        process(id: "p1", y: 200, label: "Create", steps: [
          { "action" => "a", "config" => { "n" => 1 } },
          { "action" => "b", "config" => { "n" => 2 } },
          { "action" => "c", "config" => { "n" => 3 } }
        ]),
        { "id" => "end", "type" => "end", "x" => 400, "y" => 300, "label" => "End", "properties" => {} }
      ],
      connections: [
        { "id" => "c1", "from" => "start", "to" => "p1" },
        { "id" => "c2", "from" => "p1", "to" => "end" }
      ]
    )

    output = described_class.call(input)
    elements = output.fetch("elements")
    by_id = elements.index_by { |el| el["id"] }

    expect(input.dig("elements", 1, "properties", "steps").size).to eq(3)
    expect(by_id["p1"].dig("properties", "steps")).to eq([{ "action" => "a", "config" => { "n" => 1 } }])
    expect(by_id["p1"]["label"]).to eq("Create")
    expect(by_id["p1"]["y"]).to eq(200)
    expect(by_id["p1_2"].dig("properties", "steps")).to eq([{ "action" => "b", "config" => { "n" => 2 } }])
    expect(by_id["p1_2"]["label"]).to eq(FlowchartDefinitions::Palette.human_label("b"))
    expect(by_id["p1_2"]["y"]).to eq(300)
    expect(by_id["p1_3"].dig("properties", "steps")).to eq([{ "action" => "c", "config" => { "n" => 3 } }])
    expect(by_id["p1_3"]["label"]).to eq(FlowchartDefinitions::Palette.human_label("c"))
    expect(by_id["p1_3"]["y"]).to eq(400)
    expect(by_id["end"]["y"]).to eq(500)
    expect(output["connections"]).to include(
      hash_including("from" => "start", "to" => "p1"),
      hash_including("from" => "p1", "to" => "p1_2", "fromPosition" => "bottom", "toPosition" => "top"),
      hash_including("from" => "p1_2", "to" => "p1_3", "fromPosition" => "bottom", "toPosition" => "top"),
      hash_including("from" => "p1_3", "to" => "end")
    )
    expect(output["metadata"]).to eq("note" => "keep")
  end

  it "leaves single-step and non-process elements unchanged" do
    input = graph(
      elements: [
        { "id" => "start", "type" => "start", "y" => 80, "label" => "Start", "properties" => {} },
        process(id: "p1", y: 180, label: "Query", steps: [{ "action" => "query_models" }]),
        { "id" => "end", "type" => "end", "y" => 280, "label" => "End", "properties" => {} }
      ],
      connections: [
        { "id" => "c1", "from" => "start", "to" => "p1" },
        { "id" => "c2", "from" => "p1", "to" => "end" }
      ]
    )

    expect(described_class.call(input)).to eq(input.deep_stringify_keys)
  end

  it "is idempotent on an already-split graph" do
    split = described_class.call(
      graph(
        elements: [
          { "id" => "start", "type" => "start", "y" => 80, "properties" => {} },
          process(id: "p1", y: 200, label: "Create", steps: [
            { "action" => "a" }, { "action" => "b" }, { "action" => "c" }
          ]),
          { "id" => "end", "type" => "end", "y" => 300, "properties" => {} }
        ],
        connections: [
          { "id" => "c1", "from" => "start", "to" => "p1" },
          { "id" => "c2", "from" => "p1", "to" => "end" }
        ]
      )
    )

    expect(described_class.call(split)).to eq(split)
  end

  it "avoids colliding with existing ids by advancing a suffix counter" do
    input = graph(
      elements: [
        { "id" => "start", "type" => "start", "y" => 80, "properties" => {} },
        process(id: "p1", y: 200, label: "Create", steps: [
          { "action" => "a" }, { "action" => "b" }
        ]),
        process(id: "p1_2", y: 250, label: "Other", steps: [{ "action" => "other" }]),
        { "id" => "end", "type" => "end", "y" => 300, "properties" => {} }
      ],
      connections: [
        { "id" => "c1", "from" => "start", "to" => "p1" },
        { "id" => "c2", "from" => "p1", "to" => "end" },
        { "id" => "c3", "from" => "p1_2", "to" => "end" }
      ]
    )

    ids = described_class.call(input).fetch("elements").map { |el| el["id"] }
    expect(ids).to include("p1", "p1_3")
    expect(ids.count("p1_2")).to eq(1)
  end

  it "keeps a decision branch target id and incoming fromPort/matchValue on the first chain element" do
    input = graph(
      elements: [
        { "id" => "start", "type" => "start", "y" => 80, "properties" => {} },
        {
          "id" => "d1", "type" => "decision", "y" => 180, "label" => "Route",
          "properties" => {
            "branches" => [
              { "elementId" => "p1", "matchValue" => "yes", "name" => "Yes" },
              { "elementId" => "end", "matchValue" => "no", "name" => "No" }
            ]
          }
        },
        process(id: "p1", y: 280, label: "Create", steps: [{ "action" => "a" }, { "action" => "b" }]),
        { "id" => "end", "type" => "end", "y" => 380, "properties" => {} }
      ],
      connections: [
        { "id" => "c1", "from" => "start", "to" => "d1" },
        { "id" => "c2", "from" => "d1", "to" => "p1", "fromPort" => "port_0", "matchValue" => "yes" },
        { "id" => "c3", "from" => "d1", "to" => "end", "fromPort" => "port_1", "matchValue" => "no" },
        { "id" => "c4", "from" => "p1", "to" => "end" }
      ]
    )

    output = described_class.call(input)
    decision = output["elements"].find { |el| el["id"] == "d1" }
    expect(decision.dig("properties", "branches", 0, "elementId")).to eq("p1")
    expect(output["connections"]).to include(
      hash_including("id" => "c2", "from" => "d1", "to" => "p1", "fromPort" => "port_0", "matchValue" => "yes")
    )
  end

  it "moves outgoing edges that feed a decision onto the last chain element, keeping fromPort/matchValue" do
    input = graph(
      elements: [
        { "id" => "start", "type" => "start", "y" => 80, "properties" => {} },
        process(id: "p1", y: 180, label: "Create", steps: [{ "action" => "a" }, { "action" => "b" }]),
        { "id" => "d1", "type" => "decision", "y" => 280, "properties" => {} },
        { "id" => "end", "type" => "end", "y" => 380, "properties" => {} }
      ],
      connections: [
        { "id" => "c1", "from" => "start", "to" => "p1" },
        { "id" => "c2", "from" => "p1", "to" => "d1", "fromPort" => "port_out", "matchValue" => "ready" },
        { "id" => "c3", "from" => "d1", "to" => "end", "matchValue" => "true" }
      ]
    )

    output = described_class.call(input)
    expect(output["connections"]).to include(
      hash_including("from" => "p1_2", "to" => "d1", "fromPort" => "port_out", "matchValue" => "ready")
    )
    expect(output["connections"]).not_to include(hash_including("from" => "p1", "to" => "d1"))
  end

  it "rewires a loop body back-edge from the last chain element and keeps the loop exit" do
    input = graph(
      elements: [
        { "id" => "start", "type" => "start", "y" => 80, "properties" => {} },
        { "id" => "loop", "type" => "loop", "y" => 180, "properties" => { "loopType" => "while" } },
        process(id: "p1", y: 280, label: "Body", steps: [{ "action" => "a" }, { "action" => "b" }]),
        { "id" => "end", "type" => "end", "y" => 380, "properties" => {} }
      ],
      connections: [
        { "id" => "c1", "from" => "start", "to" => "loop" },
        { "id" => "c2", "from" => "loop", "to" => "p1", "fromPort" => "port_body", "matchValue" => "continue" },
        { "id" => "c3", "from" => "p1", "to" => "loop", "fromPort" => "port_back", "matchValue" => "again" },
        { "id" => "c4", "from" => "loop", "to" => "end", "fromPort" => "port_exit", "matchValue" => "done" }
      ]
    )

    output = described_class.call(input)
    expect(output["connections"]).to include(
      hash_including("from" => "loop", "to" => "p1", "fromPort" => "port_body", "matchValue" => "continue"),
      hash_including("from" => "p1_2", "to" => "loop", "fromPort" => "port_back", "matchValue" => "again"),
      hash_including("from" => "loop", "to" => "end", "fromPort" => "port_exit", "matchValue" => "done")
    )
  end

  it "leaves a process with an empty steps list unchanged" do
    input = graph(
      elements: [
        { "id" => "start", "type" => "start", "y" => 80, "properties" => {} },
        process(id: "p1", y: 180, label: "Empty", steps: []),
        { "id" => "end", "type" => "end", "y" => 280, "properties" => {} }
      ],
      connections: [
        { "id" => "c1", "from" => "start", "to" => "p1" },
        { "id" => "c2", "from" => "p1", "to" => "end" }
      ]
    )

    expect(described_class.call(input)).to eq(input.deep_stringify_keys)
  end

  it "labels new chain boxes with the translated action label for the current locale" do
    input = graph(
      elements: [
        { "id" => "start", "type" => "start", "y" => 80, "properties" => {} },
        process(id: "p1", y: 200, label: "Create", steps: [
          { "action" => "new_model", "config" => {} },
          { "action" => "save_model", "config" => {} },
          { "action" => "collection_manipulate", "config" => { "operation" => "unique" } }
        ]),
        { "id" => "end", "type" => "end", "y" => 300, "properties" => {} }
      ],
      connections: [
        { "id" => "c1", "from" => "start", "to" => "p1" },
        { "id" => "c2", "from" => "p1", "to" => "end" }
      ]
    )

    I18n.with_locale(:en) do
      by_id = described_class.call(input).fetch("elements").index_by { |el| el["id"] }
      expect(by_id["p1"]["label"]).to eq("Create")
      expect(by_id["p1_2"]["label"]).to eq(I18n.t("flowchart_elements.template_labels.save_model"))
      expect(by_id["p1_3"]["label"]).to eq(I18n.t("flowchart_actions.collection_manipulate.label"))
      expect(by_id["p1_3"]["label"]).to eq("Collection Manipulate")
    end

    I18n.with_locale(:"zh-CN") do
      by_id = described_class.call(input).fetch("elements").index_by { |el| el["id"] }
      expect(by_id["p1_2"]["label"]).to eq(I18n.t("flowchart_elements.template_labels.save_model"))
      expect(by_id["p1_2"]["label"]).to eq("保存记录")
      expect(by_id["p1_3"]["label"]).to eq(I18n.t("flowchart_actions.collection_manipulate.label"))
      expect(by_id["p1_3"]["label"]).to eq("集合处理")
    end
  end
end
