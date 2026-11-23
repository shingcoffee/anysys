# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator::WiringPlanner do
  def plan(descriptors, branches: {}, stepless_ends: [], terminal_targets: nil)
    described_class.new(
      descriptors: descriptors,
      decision_branches: branches,
      stepless_end_ids: stepless_ends,
      terminal_targets: terminal_targets
    ).call
  end

  def step(id, element_id, kind: :step, successors: [])
    { id: id, element_id: element_id, kind: kind, successors: successors }
  end

  def branch(semantic, signal, target, connection_id)
    { semantic: semantic, signal: signal, target: target, connection_id: connection_id }
  end

  def plan_for(id, result)
    result.step_plans.find { |item| item.id == id }
  end

  FAILURE_OUTPUT = ["Output(:success)", "Track(:failure)"].freeze

  def route_outputs(*pairs)
    pairs + [FAILURE_OUTPUT]
  end

  describe "linear chain" do
    subject(:result) do
      plan(
        [
          step(:a, "el_a", successors: ["el_b"]),
          step(:b, "el_b", successors: ["el_c"]),
          step(:c, "el_c", successors: ["end_1"])
        ],
        stepless_ends: ["end_1"]
      )
    end

    it "keeps implicit success between consecutive attracted steps" do
      expect(plan_for(:a, result).magnetic).to be(true)
      expect(plan_for(:a, result).outputs).to eq([])
      expect(plan_for(:b, result).magnetic).to be(true)
      expect(plan_for(:b, result).outputs).to eq([])
    end

    it "leaves the last step implicit to End.success and records the stepless End" do
      expect(plan_for(:c, result).magnetic).to be(true)
      expect(plan_for(:c, result).outputs).to eq([])
      expect(result.ends).to eq(c: { success: "end_1" })
      expect(result.routes).to eq({})
    end
  end

  describe "decision with both branches to a merge" do
    subject(:result) do
      plan(
        [
          step(:is_large_order, "d1", kind: :decision, successors: ["p1", "p2"]),
          step(:manual_review, "p1", successors: ["p3"]),
          step(:auto_approve, "p2", successors: ["p3"]),
          step(:finalize, "p3", successors: ["end_1"])
        ],
        branches: {
          is_large_order: [
            branch(:yes, "Routes::IsLargeOrder::Yes", "p1", "c2"),
            branch(:no, "Routes::IsLargeOrder::No", "p2", "c3")
          ]
        },
        stepless_ends: ["end_1"]
      )
    end

    it "emits explicit route outputs and demagnetizes both branch heads" do
      decision = plan_for(:is_large_order, result)
      expect(decision.magnetic).to be(true)
      expect(decision.outputs).to eq(route_outputs(
        ["Output(Routes::IsLargeOrder::Yes, :yes)", "Id(:manual_review)"],
        ["Output(Routes::IsLargeOrder::No, :no)", "Id(:auto_approve)"]
      ))
      expect(plan_for(:manual_review, result).magnetic).to be(false)
      expect(plan_for(:manual_review, result).outputs).to eq([
        ["Output(:success)", "Id(:finalize)"]
      ])
      expect(plan_for(:auto_approve, result).magnetic).to be(false)
      expect(plan_for(:auto_approve, result).outputs).to eq([])
      expect(plan_for(:finalize, result).magnetic).to be(true)
    end

    it "records routes and the merge tail End" do
      expect(result.routes).to eq(is_large_order: { yes: "c2", no: "c3" })
      expect(result.ends).to eq(finalize: { success: "end_1" })
    end
  end

  describe "nested decisions" do
    subject(:result) do
      plan(
        [
          step(:outer, "d1", kind: :decision, successors: ["d2", "other"]),
          step(:inner, "d2", kind: :decision, successors: ["a", "b"]),
          step(:a, "a", successors: ["end_1"]),
          step(:b, "b", successors: ["end_1"]),
          step(:other, "other", successors: ["end_1"])
        ],
        branches: {
          outer: [
            branch(:yes, "Routes::Outer::Yes", "d2", "c2"),
            branch(:no, "Routes::Outer::No", "other", "c3")
          ],
          inner: [
            branch(:yes, "Routes::Inner::Yes", "a", "c4"),
            branch(:no, "Routes::Inner::No", "b", "c5")
          ]
        },
        stepless_ends: ["end_1"]
      )
    end

    it "wires each decision independently and demagnetizes steps after a decision" do
      expect(plan_for(:inner, result).magnetic).to be(false)
      expect(plan_for(:inner, result).outputs).to eq(route_outputs(
        ["Output(Routes::Inner::Yes, :yes)", "Id(:a)"],
        ["Output(Routes::Inner::No, :no)", "Id(:b)"]
      ))
      expect(plan_for(:a, result).magnetic).to be(false)
      expect(plan_for(:a, result).outputs).to eq([["Output(:success)", "End(:success)"]])
      expect(plan_for(:b, result).magnetic).to be(false)
      expect(plan_for(:b, result).outputs).to eq([["Output(:success)", "End(:success)"]])
      expect(plan_for(:other, result).magnetic).to be(false)
      expect(plan_for(:other, result).outputs).to eq([])
    end
  end

  describe "non-nested merge (cross edge)" do
    subject(:result) do
      plan(
        [
          step(:route, "d1", kind: :decision, successors: ["p2", "p3"]),
          step(:cross, "p3", successors: ["p2"]),
          step(:shared, "p2", successors: ["p4"]),
          step(:after, "p4", successors: ["end_1"])
        ],
        branches: {
          route: [
            branch(:yes, "Routes::Route::Yes", "p2", "c2"),
            branch(:no, "Routes::Route::No", "p3", "c3")
          ]
        },
        stepless_ends: ["end_1"]
      )
    end

    it "keeps the cross-edge step explicit to the shared merge and implicit after it" do
      expect(plan_for(:route, result).outputs).to eq(route_outputs(
        ["Output(Routes::Route::Yes, :yes)", "Id(:shared)"],
        ["Output(Routes::Route::No, :no)", "Id(:cross)"]
      ))
      expect(plan_for(:cross, result).magnetic).to be(false)
      expect(plan_for(:cross, result).outputs).to eq([])
      expect(plan_for(:shared, result).magnetic).to be(true)
      expect(plan_for(:shared, result).outputs).to eq([])
    end
  end

  describe "branches ending at two different Ends" do
    subject(:result) do
      plan(
        [
          step(:route, "d1", kind: :decision, successors: ["p_high", "p_low"]),
          step(:handle_high, "p_high", successors: ["end_yes"]),
          step(:handle_low, "p_low", successors: ["end_no"])
        ],
        branches: {
          route: [
            branch(:high, "Routes::Route::High", "p_high", "c2"),
            branch(:otherwise, "Routes::Route::Otherwise", "p_low", "c3")
          ]
        },
        stepless_ends: ["end_yes", "end_no"]
      )
    end

    it "terminates the non-last branch explicitly and records both Ends" do
      expect(plan_for(:handle_high, result).outputs).to eq([["Output(:success)", "End(:success)"]])
      expect(plan_for(:handle_low, result).outputs).to eq([])
      expect(result.ends).to eq(
        handle_high: { success: "end_yes" },
        handle_low: { success: "end_no" }
      )
    end
  end

  describe "decision branch straight to a stepless End" do
    subject(:result) do
      plan(
        [
          step(:is_large_order, "d1", kind: :decision, successors: ["end_3", "p1"]),
          step(:auto_approve, "p1", successors: ["end_1"])
        ],
        branches: {
          is_large_order: [
            branch(:yes, "Routes::IsLargeOrder::Yes", "end_3", "c2"),
            branch(:no, "Routes::IsLargeOrder::No", "p1", "c3")
          ]
        },
        stepless_ends: ["end_1", "end_3"]
      )
    end

    it "wires the empty/end branch to End.success and records it under the decision semantic" do
      expect(plan_for(:is_large_order, result).outputs).to eq(route_outputs(
        ["Output(Routes::IsLargeOrder::Yes, :yes)", "End(:success)"],
        ["Output(Routes::IsLargeOrder::No, :no)", "Id(:auto_approve)"]
      ))
      expect(result.ends).to eq(
        is_large_order: { yes: "end_3" },
        auto_approve: { success: "end_1" }
      )
    end
  end

  describe "empty branch straight to the merge node" do
    subject(:result) do
      plan(
        [
          step(:route, "d1", kind: :decision, successors: ["p1", "p2"]),
          step(:work, "p1", successors: ["p2"]),
          step(:merge, "p2", successors: ["end_1"])
        ],
        branches: {
          route: [
            branch(:yes, "Routes::Route::Yes", "p1", "c2"),
            branch(:no, "Routes::Route::No", "p2", "c3")
          ]
        },
        stepless_ends: ["end_1"]
      )
    end

    it "points the empty branch at the merge step and keeps work implicit into it" do
      expect(plan_for(:route, result).outputs).to eq(route_outputs(
        ["Output(Routes::Route::Yes, :yes)", "Id(:work)"],
        ["Output(Routes::Route::No, :no)", "Id(:merge)"]
      ))
      expect(plan_for(:work, result).outputs).to eq([])
      expect(plan_for(:merge, result).magnetic).to be(true)
    end
  end

  describe "terminal step that is not last" do
    subject(:result) do
      plan(
        [
          step(:review, "p1", successors: ["p2"]),
          step(:reject, "p2", successors: ["end_1"]),
          step(:approve, "p3", successors: ["end_2"])
        ],
        stepless_ends: ["end_1", "end_2"]
      )
    end

    it "emits Output(:success) => End(:success) on the non-last terminal" do
      expect(plan_for(:reject, result).outputs).to eq([["Output(:success)", "End(:success)"]])
      expect(plan_for(:approve, result).magnetic).to be(false)
      expect(plan_for(:approve, result).outputs).to eq([])
    end
  end

  describe "End with response" do
    it "treats a last response End as an implicit success terminus" do
      result = plan(
        [step(:notify_team, "end_2", kind: :end_response, successors: [])],
        stepless_ends: []
      )
      expect(plan_for(:notify_team, result).outputs).to eq([])
      expect(result.ends).to eq({})
    end

    it "wires a non-last response End to End.success" do
      result = plan(
        [
          step(:notify_team, "end_2", kind: :end_response, successors: []),
          step(:other, "p1", successors: ["end_1"])
        ],
        stepless_ends: ["end_1"]
      )
      expect(plan_for(:notify_team, result).outputs).to eq([["Output(:success)", "End(:success)"]])
      expect(plan_for(:other, result).magnetic).to be(false)
    end
  end

  describe "subflow in a branch" do
    subject(:result) do
      plan(
        [
          step(:route, "d1", kind: :decision, successors: ["sf1", "p1"]),
          step(:child, "sf1", kind: :subflow, successors: ["end_1"]),
          step(:other, "p1", successors: ["end_1"])
        ],
        branches: {
          route: [
            branch(:yes, "Routes::Route::Yes", "sf1", "c2"),
            branch(:no, "Routes::Route::No", "p1", "c3")
          ]
        },
        stepless_ends: ["end_1"]
      )
    end

    it "applies the same successor wiring to a subflow step" do
      expect(plan_for(:route, result).outputs).to eq(route_outputs(
        ["Output(Routes::Route::Yes, :yes)", "Id(:child)"],
        ["Output(Routes::Route::No, :no)", "Id(:other)"]
      ))
      expect(plan_for(:child, result).magnetic).to be(false)
      expect(plan_for(:child, result).outputs).to eq([["Output(:success)", "End(:success)"]])
      expect(result.ends).to eq(
        child: { success: "end_1" },
        other: { success: "end_1" }
      )
    end
  end

  describe "element id colliding with another step name" do
    it "resolves string successors only as element ids" do
      result = plan(
        [
          step(:process_1, "process_2", successors: ["process_1"]),
          step(:prepare, "process_1", successors: ["end_1"])
        ],
        stepless_ends: ["end_1"]
      )

      expect(plan_for(:process_1, result).outputs).to eq([])
      expect(plan_for(:prepare, result).magnetic).to be(true)
      expect(plan_for(:process_1, result).outputs).not_to include(["Output(:success)", "Id(:process_1)"])
    end

    it "still resolves Symbol successors as step ids" do
      result = plan(
        [
          step(:a, "el_a", successors: [:b]),
          step(:b, "el_b", successors: ["end_1"])
        ],
        stepless_ends: ["end_1"]
      )

      expect(plan_for(:a, result).outputs).to eq([])
      expect(plan_for(:b, result).magnetic).to be(true)
    end
  end

  describe "loop header with body and exit" do
    subject(:result) do
      plan(
        [
          step(:init_total, "init", successors: ["loop"]),
          step(:each_item, "loop", kind: :loop, successors: ["add", "report"]).merge(
            body_id: "add",
            exit_id: "report",
            done_signal: "Routes::EachItem::Done",
            done_connection_id: "c_exit"
          ),
          step(:add_item, "add", successors: ["loop"]),
          step(:report, "report", successors: ["end_1"])
        ],
        stepless_ends: ["end_1"]
      )
    end

    it "wires the body as implicit success and the exit as a Done signal" do
      header = plan_for(:each_item, result)
      expect(header.magnetic).to be(true)
      expect(header.outputs).to eq([
        ["Output(Routes::EachItem::Done, :done)", "Id(:report)"]
      ])
      expect(plan_for(:add_item, result).magnetic).to be(true)
      expect(plan_for(:add_item, result).outputs).to eq([
        ["Output(:success)", "Id(:each_item)"]
      ])
      expect(plan_for(:report, result).magnetic).to be(false)
    end

    it "records the header done route and the report End" do
      expect(result.routes).to eq(each_item: { done: "c_exit" })
      expect(result.ends).to eq(report: { success: "end_1" })
    end
  end

  describe "empty-body loop header to a stepless End" do
    it "wires unused success to Track(:failure) and Done to End.success" do
      result = plan(
        [
          step(:repeat, "loop", kind: :loop, successors: ["end_1"]).merge(
            body_id: nil,
            exit_id: "end_1",
            done_signal: "Routes::Repeat::Done",
            done_connection_id: "c_end"
          )
        ],
        stepless_ends: ["end_1"]
      )
      expect(plan_for(:repeat, result).outputs).to eq([
        ["Output(:success)", "Track(:failure)"],
        ["Output(Routes::Repeat::Done, :done)", "End(:success)"]
      ])
      expect(result.ends).to eq(repeat: { done: "end_1" })
      expect(result.routes).to eq(repeat: { done: "c_end" })
    end
  end

  describe "loop whose exit is a stepless End" do
    it "wires Done to End.success and records the End under :done" do
      result = plan(
        [
          step(:repeat, "loop", kind: :loop, successors: ["work", "end_1"]).merge(
            body_id: "work",
            exit_id: "end_1",
            done_signal: "Routes::Repeat::Done",
            done_connection_id: "c_end"
          ),
          step(:work, "work", successors: ["loop"])
        ],
        stepless_ends: ["end_1"]
      )
      expect(plan_for(:repeat, result).outputs).to eq([
        ["Output(Routes::Repeat::Done, :done)", "End(:success)"]
      ])
      expect(plan_for(:work, result).outputs).to eq([
        ["Output(:success)", "Id(:repeat)"]
      ])
      expect(result.ends).to eq(repeat: { done: "end_1" })
      expect(result.routes).to eq(repeat: { done: "c_end" })
    end
  end

  describe "while loop whose body has a decision" do
    subject(:result) do
      plan(
        [
          step(:repeat, "loop", kind: :loop, successors: ["route", "after"]).merge(
            body_id: "route",
            exit_id: "after",
            done_signal: "Routes::Repeat::Done",
            done_connection_id: "c_exit"
          ),
          step(:route, "route", kind: :decision, successors: ["work", "skipped"]),
          step(:work, "work", successors: ["loop"]),
          step(:skipped, "skipped", successors: ["loop"]),
          step(:after, "after", successors: ["end_1"])
        ],
        branches: {
          route: [
            branch(:yes, "Routes::Route::Yes", "work", "c_yes"),
            branch(:no, "Routes::Route::No", "skipped", "c_no")
          ]
        },
        stepless_ends: ["end_1"]
      )
    end

    it "keeps every body tail explicit back to the header" do
      expect(plan_for(:repeat, result).outputs).to eq([
        ["Output(Routes::Repeat::Done, :done)", "Id(:after)"]
      ])
      expect(plan_for(:route, result).magnetic).to be(true)
      expect(plan_for(:work, result).outputs).to eq([
        ["Output(:success)", "Id(:repeat)"]
      ])
      expect(plan_for(:skipped, result).outputs).to eq([
        ["Output(:success)", "Id(:repeat)"]
      ])
      expect(plan_for(:after, result).magnetic).to be(false)
    end
  end
end
