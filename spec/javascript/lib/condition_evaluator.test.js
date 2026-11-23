import { describe, it, expect } from "vitest"
import { ConditionEvaluator } from "lib/condition_evaluator"

const cond = (field_id, operator, value) => ({ field_id, operator, value })
const evalOne = (values, c) => new ConditionEvaluator(values).evaluateCondition(c)

describe("ConditionEvaluator — evaluateCondition operators", () => {
  it("equals / not_equals use loose comparison", () => {
    expect(evalOne({ a: "5" }, cond("a", "equals", 5))).toBe(true)
    expect(evalOne({ a: 5 }, cond("a", "not_equals", 6))).toBe(true)
  })

  it("contains / not_contains coerce to string and tolerate null", () => {
    expect(evalOne({ a: "hello" }, cond("a", "contains", "ell"))).toBe(true)
    expect(evalOne({ a: "hello" }, cond("a", "not_contains", "z"))).toBe(true)
    expect(evalOne({}, cond("a", "contains", "x"))).toBe(false) // null -> ""
    expect(evalOne({}, cond("a", "not_contains", "x"))).toBe(true) // null -> ""
  })

  it("starts_with / ends_with tolerate null too", () => {
    expect(evalOne({ a: "abcdef" }, cond("a", "starts_with", "abc"))).toBe(true)
    expect(evalOne({ a: "abcdef" }, cond("a", "ends_with", "def"))).toBe(true)
    expect(evalOne({}, cond("a", "starts_with", "abc"))).toBe(false) // null -> ""
    expect(evalOne({}, cond("a", "ends_with", "def"))).toBe(false) // null -> ""
  })

  it("numeric comparisons treat empty/null as false", () => {
    expect(evalOne({ a: 10 }, cond("a", "greater_than", 5))).toBe(true)
    expect(evalOne({ a: 3 }, cond("a", "less_than", 5))).toBe(true)
    expect(evalOne({ a: 5 }, cond("a", "greater_or_equal", 5))).toBe(true)
    expect(evalOne({ a: 5 }, cond("a", "less_or_equal", 5))).toBe(true)
    expect(evalOne({ a: "" }, cond("a", "greater_than", 5))).toBe(false)
    expect(evalOne({}, cond("a", "less_than", 5))).toBe(false)
    expect(evalOne({ a: "" }, cond("a", "greater_or_equal", 5))).toBe(false)
    expect(evalOne({}, cond("a", "less_or_equal", 5))).toBe(false)
  })

  it("between checks an inclusive range", () => {
    expect(evalOne({ a: 5 }, cond("a", "between", [1, 10]))).toBe(true)
    expect(evalOne({ a: 20 }, cond("a", "between", [1, 10]))).toBe(false)
    expect(evalOne({ a: "" }, cond("a", "between", [1, 10]))).toBe(false)
  })

  it("is_empty / is_not_empty", () => {
    expect(evalOne({ a: "" }, cond("a", "is_empty"))).toBe(true)
    expect(evalOne({}, cond("a", "is_empty"))).toBe(true)
    expect(evalOne({ a: "x" }, cond("a", "is_not_empty"))).toBe(true)
  })

  it("is_selected / is_not_selected handle arrays and scalars", () => {
    expect(evalOne({ a: ["x", "y"] }, cond("a", "is_selected", "y"))).toBe(true)
    expect(evalOne({ a: ["x"] }, cond("a", "is_not_selected", "z"))).toBe(true)
    expect(evalOne({ a: "x" }, cond("a", "is_selected", "x"))).toBe(true)
    expect(evalOne({ a: "x" }, cond("a", "is_not_selected", "y"))).toBe(true)
  })

  it("matches_regex tests a pattern and fails safe on bad regex/null", () => {
    expect(evalOne({ a: "abc123" }, cond("a", "matches_regex", "\\d+"))).toBe(true)
    expect(evalOne({}, cond("a", "matches_regex", "\\d+"))).toBe(false)
    expect(evalOne({ a: "x" }, cond("a", "matches_regex", "("))).toBe(false) // invalid regex
  })

  it("unknown operator returns false", () => {
    expect(evalOne({ a: 1 }, cond("a", "bogus", 1))).toBe(false)
  })
})

describe("ConditionEvaluator — evaluate() tree", () => {
  const engine = (values = {}) => new ConditionEvaluator(values)

  it("no groups => always true", () => {
    expect(engine().evaluate({})).toBe(true)
    expect(engine().evaluate({ groups: [] })).toBe(true)
  })

  it("group logic all vs any", () => {
    const values = { a: 5, b: "hi" }
    const groupAll = { logic: "all", items: [cond("a", "greater_than", 1), cond("b", "equals", "hi")] }
    const groupAny = { logic: "any", items: [cond("a", "greater_than", 99), cond("b", "equals", "hi")] }
    expect(engine(values).evaluate({ logic: "all", groups: [groupAll] })).toBe(true)
    expect(engine(values).evaluate({ logic: "all", groups: [groupAny] })).toBe(true)
  })

  it("top-level logic all requires every group; any requires one", () => {
    const values = { a: 5 }
    const g1 = { logic: "all", items: [cond("a", "greater_than", 1)] }   // true
    const g2 = { logic: "all", items: [cond("a", "greater_than", 99)] }  // false
    expect(engine(values).evaluate({ logic: "all", groups: [g1, g2] })).toBe(false)
    expect(engine(values).evaluate({ logic: "any", groups: [g1, g2] })).toBe(true)
  })

  it("empty group => true", () => {
    expect(engine().evaluateGroup({ items: [] })).toBe(true)
    expect(engine().evaluateGroup(null)).toBe(true)
  })
})
