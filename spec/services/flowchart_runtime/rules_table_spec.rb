# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::RulesTable do
  def evaluate(ctx, rules, **opts)
    described_class.evaluate(
      ctx,
      rules,
      hit_policy: opts.fetch(:hit_policy, "first"),
      default_value: opts.fetch(:default_value, nil),
      on_no_match: opts.fetch(:on_no_match, "default"),
      unique_results: opts.fetch(:unique_results, false)
    )
  end

  def rules(*rows)
    rows.map { |cond, result| [-> { cond }, -> { result }] }
  end

  it "returns the first matching result and does not evaluate later results" do
    later = 0
    rows = [
      [-> { false }, -> { "no" }],
      [-> { true }, -> { "yes" }],
      [-> { later += 1; true }, -> { later += 10; "later" }]
    ]
    expect(evaluate({}, rows)).to eq(result: "yes", matched: [2])
    expect(later).to eq(0)
  end

  it "collects matching results and optionally uniques them" do
    rows = rules([true, "a"], [false, "x"], [true, "a"], [true, "b"])
    expect(evaluate({}, rows, hit_policy: "collect")).to eq(result: %w[a a b], matched: [1, 3, 4])
    expect(evaluate({}, rows, hit_policy: "collect", unique_results: true))
      .to eq(result: %w[a b], matched: [1, 3, 4])
  end

  it "sums, counts, mins, and maxes numeric matches" do
    rows = rules([true, 4], [false, 99], [true, "6"])
    expect(evaluate({}, rows, hit_policy: "sum")).to eq(result: BigDecimal("10"), matched: [1, 3])
    expect(evaluate({}, rows, hit_policy: "count")).to eq(result: 2, matched: [1, 3])
    expect(evaluate({}, rows, hit_policy: "min")).to eq(result: BigDecimal("4"), matched: [1, 3])
    expect(evaluate({}, rows, hit_policy: "max")).to eq(result: BigDecimal("6"), matched: [1, 3])
  end

  it "sums decimal results without binary float drift" do
    rows = rules([true, "0.1"], [true, "0.2"])
    expect(evaluate({}, rows, hit_policy: "sum")).to eq(result: BigDecimal("0.3"), matched: [1, 2])
  end

  it "does not evaluate result lambdas when counting" do
    called = false
    rows = [[-> { true }, -> { called = true; 1 }]]
    expect(evaluate({}, rows, hit_policy: "count")).to eq(result: 1, matched: [1])
    expect(called).to be(false)
  end

  it "returns the shared value on any and fails when matches differ" do
    same = rules([true, "vip"], [true, "vip"])
    expect(evaluate({}, same, hit_policy: "any")).to eq(result: "vip", matched: [1, 2])

    ctx = { errors: [] }
    expect(evaluate(ctx, rules([true, "vip"], [true, "std"]), hit_policy: "any")).to eq(false)
    expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.evaluate_rules.any_conflict")])
  end

  it "uses the default when nothing matches" do
    expect(evaluate({}, rules([false, "x"]), default_value: "none")).to eq(result: "none", matched: [])
  end

  it "fails when nothing matches and on_no_match is fail" do
    ctx = { errors: [] }
    expect(evaluate(ctx, rules([false, "x"]), on_no_match: "fail")).to eq(false)
    expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.evaluate_rules.no_match")])
  end

  it "fails when sum/min/max sees a non-numeric result" do
    ctx = { errors: [] }
    expect(evaluate(ctx, rules([true, "vip"]), hit_policy: "sum")).to eq(false)
    expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.evaluate_rules.non_numeric")])
  end

  it "raises for an unknown hit policy" do
    expect { evaluate({}, rules([true, 1]), hit_policy: "bogus") }
      .to raise_error(described_class::Error, /unknown hit policy/)
  end
end
