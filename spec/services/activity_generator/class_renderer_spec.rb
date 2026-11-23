# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityGenerator::ClassRenderer do
  def step(id, type, method_name, **attrs)
    ActivityGenerator::Step.new(element: { "id" => id, "type" => type }, method_name: method_name, magnetic: true, outputs: [], **attrs)
  end

  def render(steps, canvas: nil, method_sources: [])
    canvas ||= { steps: steps.to_h { |item| [item.method_name.to_sym, item.element_id] }, routes: {}, ends: {} }
    described_class.new(class_name: "SampleActivity", steps: steps, canvas: canvas, method_sources: method_sources).render
  end

  it "lays out CANVAS, declarations, methods and collect_errors in a Railway class" do
    source = render([step("p1", "process", "load")], method_sources: ["def load(ctx, **)\n  true\nend"])

    expect(source).to eq(<<~RUBY)
      class SampleActivity < Trailblazer::Activity::Railway
        CANVAS = {
          steps: { load: "p1" }
        }.freeze

        step :load
        fail :collect_errors

        def load(ctx, **)
          true
        end

        def collect_errors(ctx, **)
          ctx[:errors] = FlowchartRuntime::Errors.collect(ctx)
        end
      end
    RUBY
  end

  it "keeps routes and ends in CANVAS only when present" do
    canvas = { steps: { check: "d1" }, routes: { check: { yes: "c2" } }, ends: { check: { no: "e1" } } }
    source = render([step("d1", "decision", "check", route_module: "Check", branches: [{ const_name: "Yes" }])], canvas: canvas)

    expect(source).to include(%(routes: { check: { yes: "c2" } }), %(ends: { check: { no: "e1" } }))
  end

  it "wraps a CANVAS line that would run past the width" do
    steps = (1..8).map { |index| step("element_#{index}", "process", "a_longer_step_name_#{index}") }
    source = render(steps)

    expect(source.lines.map { |line| line.chomp.length }.max).to be <= described_class::WIDTH + 2
    expect(source).to include(%(      a_longer_step_name_1: "element_1",\n))
  end

  it "declares Routes signals for decisions and loops" do
    decision = step("d1", "decision", "check", route_module: "Check", branches: [{ const_name: "Yes" }, { const_name: "No" }])
    loop_step = step("l1", "loop", "each_item", route_module: "EachItem")
    source = render([decision, loop_step])

    expect(source).to include(<<~RUBY.indent(2))
      module Routes
        module Check
          Yes = Class.new(Trailblazer::Activity::Signal)
          No = Class.new(Trailblazer::Activity::Signal)
        end
        module EachItem
          Done = Class.new(Trailblazer::Activity::Signal)
        end
      end
    RUBY
  end

  it "keeps simple wiring on the declaration line" do
    source = render([step("p1", "process", "load", magnetic: false, outputs: [["Output(:success)", "End(:success)"]])])
    expect(source).to include("  step :load, magnetic_to: nil, Output(:success) => End(:success)\n")
  end

  it "puts each output of a router on its own line" do
    outputs = [["Output(Routes::Check::Yes, :yes)", "Id(:approve)"], ["Output(Routes::Check::No, :no)", "Id(:reject)"]]
    source = render([step("d1", "decision", "check", route_module: "Check", branches: [{ const_name: "Yes" }], outputs: outputs)])

    expect(source).to include(<<~RUBY.indent(2))
      step :check,
        Output(Routes::Check::Yes, :yes) => Id(:approve),
        Output(Routes::Check::No, :no) => Id(:reject)
    RUBY
  end

  it "declares subflows as a Subprocess with the step id" do
    sub = step("sf1", "subflow", "check_child", subprocess: { activity_class_name: "ChildActivity" })
    expect(render([sub])).to include("  step Subprocess(ChildActivity), id: :check_child\n")
  end

  it "clears loop state when the run fails" do
    source = render([step("l1", "loop", "each_item", route_module: "EachItem")])
    expect(source).to include(<<~RUBY.indent(2))
      def collect_errors(ctx, **)
        ctx.delete(:_each_item)
        ctx[:errors] = FlowchartRuntime::Errors.collect(ctx)
      end
    RUBY
  end
end
