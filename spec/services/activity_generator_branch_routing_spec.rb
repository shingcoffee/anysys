# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator do
  def build_flowchart(elements, connections, name: "TestFlow")
    instance_double(
      Flowchart,
      name: name,
      elements: elements,
      connections: connections,
      shared?: false,
      customer_owned?: true
    )
  end

  # Flowchart: Start → Decision(status==approved) → Approve → Notify → End
  #                                               → Reject  ↗
  subject(:generated) { described_class.new(build_flowchart(elements, connections)).generate }

  let(:elements) do
    [
      { "id" => "s1", "type" => "start", "label" => "Start", "properties" => {} },
      { "id" => "d1", "type" => "decision", "label" => "Check Status",
        "properties" => {
          "routeBy" => "condition",
          "condition" => {
            "type" => "group",
            "joins" => [],
            "conditions" => [
              { "kind" => "field", "leftOperand" => "ctx.status", "operator" => "==", "rightOperand" => "approved" }
            ]
          }
        }
      },
      { "id" => "a1", "type" => "process", "label" => "Approve Record",
        "properties" => { "steps" => [] }
      },
      { "id" => "b1", "type" => "process", "label" => "Reject Record",
        "properties" => { "steps" => [] }
      },
      { "id" => "n1", "type" => "process", "label" => "Notify User",
        "properties" => { "steps" => [] }
      },
      { "id" => "e1", "type" => "end", "label" => "End", "properties" => { "responseType" => "none" } }
    ]
  end

  let(:connections) do
    [
      { "id" => "c1", "from" => "s1", "to" => "d1" },
      { "id" => "c2", "from" => "d1", "to" => "a1", "label" => "Yes", "matchValue" => "true" },
      { "id" => "c3", "from" => "d1", "to" => "b1", "label" => "No",  "matchValue" => "false" },
      { "id" => "c4", "from" => "a1", "to" => "n1" },
      { "id" => "c5", "from" => "b1", "to" => "n1" },
      { "id" => "c6", "from" => "n1", "to" => "e1" }
    ]
  end


  describe "multi-branch Decision routing" do
    it "generates activity code" do
      expect(generated).to be_present
    end

    it "generates route signals in the decision method" do
      expect(generated).to include("Routes::CheckStatus")
      expect(generated).not_to include("ctx[:_route_")
    end

    it "wires each branch with explicit outputs and no guards" do
      expect(generated).to include("Output(Routes::CheckStatus::Yes, :yes)")
      expect(generated).to include("Output(Routes::CheckStatus::No, :no)")
      expect(generated).not_to include("return true unless ctx[:_route_")
    end

    it "does NOT add a guard to the convergence step notify_user" do
      notify_section = generated.match(/def notify_user(.*?)^  end/m)&.to_s || ""
      expect(notify_section).not_to include("return true unless")
    end
  end

  # ===================================================================
  # Multi-branch Decision — value-switch model (ctx.priority case/when)
  # ===================================================================
  context "with value-switch routing on ctx.priority (multi-branch)" do
    let(:multi_branch_elements) do
      [
        { "id" => "s1", "type" => "start", "label" => "Start", "properties" => {} },
        { "id" => "d1", "type" => "decision", "label" => "Route by Priority",
          "properties" => {
            "routeBy" => "value",
            "subject" => "ctx[:priority]"
          }
        },
        { "id" => "p_high",   "type" => "process", "label" => "Handle High Priority",
          "properties" => { "steps" => [] } },
        { "id" => "p_medium", "type" => "process", "label" => "Handle Medium Priority",
          "properties" => { "steps" => [] } },
        { "id" => "p_low",    "type" => "process", "label" => "Handle Low Priority",
          "properties" => { "steps" => [] } },
        { "id" => "e1", "type" => "end", "label" => "End", "properties" => { "responseType" => "none" } }
      ]
    end

    let(:multi_branch_connections) do
      [
        { "id" => "c1", "from" => "s1",      "to" => "d1" },
        { "id" => "c2", "from" => "d1",      "to" => "p_high",   "label" => "High",   "matchValue" => "high" },
        { "id" => "c3", "from" => "d1",      "to" => "p_medium", "label" => "Medium", "matchValue" => "medium" },
        { "id" => "c4", "from" => "d1",      "to" => "p_low",    "label" => "Low",    "matchValue" => "" },
        { "id" => "c5", "from" => "p_high",  "to" => "e1" },
        { "id" => "c6", "from" => "p_medium", "to" => "e1" },
        { "id" => "c7", "from" => "p_low",   "to" => "e1" }
      ]
    end

    let(:multi_branch_flowchart) do
      build_flowchart(multi_branch_elements, multi_branch_connections, name: "Multi Branch")
    end

    let(:code) { described_class.new(multi_branch_flowchart).generate }

    it "generates case/when routing from value-switch condition" do
      expect(code).to include("case")
      expect(code).to include("ctx[:priority]")
      expect(code).to include(%("high"))
      expect(code).to include("Routes::RouteByPriority::High")
      expect(code).to include("Routes::RouteByPriority::Medium")
      expect(code).to include("else")
    end

    it "wires each branch without guard lines" do
      expect(code).to include("Output(Routes::RouteByPriority::High, :high)")
      expect(code).to include("Output(Routes::RouteByPriority::Medium, :medium)")
      expect(code).not_to include("return true unless ctx[:_route_")
    end

    it "uses empty-matchValue branch as else/default" do
      expect(code).to include("else")
      expect(code).to include("Routes::RouteByPriority::Otherwise")
    end
  end

  context "with reversed connection array order but port_N ports" do
    let(:elements) do
      [
        { "id" => "s1", "type" => "start", "label" => "Start", "properties" => {} },
        { "id" => "d1", "type" => "decision", "label" => "By Port",
          "properties" => { "routeBy" => "value", "subject" => "ctx[:status]" } },
        { "id" => "a1", "type" => "process", "label" => "First", "properties" => { "steps" => [] } },
        { "id" => "b1", "type" => "process", "label" => "Second", "properties" => { "steps" => [] } },
        { "id" => "e1", "type" => "end", "label" => "End", "properties" => { "responseType" => "none" } }
      ]
    end
    let(:connections) do
      [
        { "id" => "c1", "from" => "s1", "to" => "d1" },
        { "id" => "c3", "from" => "d1", "to" => "b1", "fromPort" => "port_1", "label" => "No", "matchValue" => "false" },
        { "id" => "c2", "from" => "d1", "to" => "a1", "fromPort" => "port_0", "label" => "Yes", "matchValue" => "true" },
        { "id" => "c4", "from" => "a1", "to" => "e1" },
        { "id" => "c5", "from" => "b1", "to" => "e1" }
      ]
    end

    it "binds branches in fromPort order" do
      expect(generated).to include("Output(Routes::ByPort::Yes, :yes)")
      expect(generated).to include("Output(Routes::ByPort::No, :no)")
      yes_at = generated.index("Output(Routes::ByPort::Yes, :yes)")
      no_at = generated.index("Output(Routes::ByPort::No, :no)")
      expect(yes_at).to be < no_at
    end
  end
end
