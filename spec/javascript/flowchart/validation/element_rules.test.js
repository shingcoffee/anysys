import { describe, it, expect, afterEach } from "vitest"
import { ELEMENT_RULES, runElementRules } from "flowchart/validation/element_rules"
import { setElementCatalog } from "flowchart/constants/element_registry"

const msg = (key, tokens = {}) => `${key}:${JSON.stringify(tokens)}`

function run(element, { incoming = [], outgoing = [], flowchartId = null, msgFn = msg } = {}) {
  return runElementRules({
    element,
    properties: element.properties || {},
    label: element.label ?? "",
    incoming,
    outgoing,
    flowchartId,
    msg: msgFn
  })
}

const el = (type, properties = {}, id = "e1", label = "L") => ({ id, type, label, properties })
const conn = (id, from, to, extra = {}) => ({ id, from, to, ...extra })
const typesOf = (found) => found.map((f) => f.type)
const row = (extra = {}) => ({ kind: "field", leftOperand: "ctx.x", operator: "is_true", ...extra })
const group = (...conditions) => ({ type: "group", joins: [], conditions })
const VALID = group(row())
const messagesOf = (found) => found.map((f) => f.message)

describe("runElementRules", () => {
  it("stamps every problem with the element id, field, and a null connectionId", () => {
    const [found] = run(el("process", { steps: [] }))
    expect(found.elementId).toBe("e1")
    expect(found.connectionId).toBeNull()
    expect(found.field).toBe("steps")
    expect(found.severity).toBe("warning")
  })

  it("returns nothing for an element type with no registered rules", () => {
    expect(run(el("saga"))).toEqual([])
  })

  it("registers a rule for every core element type", () => {
    for (const type of ["end", "process", "decision", "loop", "subflow"]) {
      expect(typeof ELEMENT_RULES[type], type).toBe("function")
    }
  })
})

describe("end rules", () => {
  it("accepts an End that returns nothing", () => {
    expect(run(el("end"))).toEqual([])
    expect(run(el("end", { responseType: "none" }))).toEqual([])
  })

  it("requires returnValue when the response type is value", () => {
    const found = run(el("end", { responseType: "value" }))
    expect(typesOf(found)).toEqual(["end_no_return_value"])
    expect(found[0].field).toBe("returnValue")
    expect(found[0].severity).toBe("error")
    expect(run(el("end", { responseType: "value", returnValue: "ctx.result" }))).toEqual([])
  })

  it("ignores leftover http_response shapes", () => {
    expect(run(el("end", { responseType: "http_response" }))).toEqual([])
  })

  it("falls back to the English default when msg is omitted", () => {
    const found = runElementRules({
      element: el("end", { responseType: "value" }),
      properties: { responseType: "value" },
      label: "L",
      incoming: [],
      outgoing: []
    })
    expect(found[0].message).toBe("Return Value is required")
  })
})

describe("process rules", () => {
  it("warns on an empty step list and accepts a populated one", () => {
    expect(typesOf(run(el("process", { steps: [] })))).toEqual(["empty_process"])
    expect(typesOf(run(el("process")))).toEqual(["empty_process"])
    expect(run(el("process", { steps: [{ action: "find_model" }] }))).toEqual([])
  })
})

describe("decision rules", () => {
  const yesNo = {
    outgoing: [
      conn("c1", "e1", "a", { matchValue: "true" }),
      conn("c2", "e1", "b", { matchValue: "false" })
    ]
  }

  it("treats a missing outgoing list as no branches", () => {
    const found = runElementRules({
      element: el("decision", { routeBy: "value" }),
      properties: { routeBy: "value" },
      label: "L",
      incoming: [],
      msg
    })
    expect(typesOf(found)).toContain("too_few_branches")
  })

  it("flags too few outgoing connections", () => {
    const found = run(el("decision", { routeBy: "value" }), { outgoing: [conn("c1", "e1", "a", { matchValue: "x" })] })
    expect(typesOf(found)).toContain("too_few_branches")
    expect(found[0].field).toBe("branches")
  })

  it("flags duplicate match values and multiple Otherwise", () => {
    const outgoing = [
      conn("c1", "e1", "a", { matchValue: "x" }),
      conn("c2", "e1", "b", { matchValue: "x" }),
      conn("c3", "e1", "c", { matchValue: "" }),
      conn("c4", "e1", "d")
    ]
    const found = run(el("decision", { routeBy: "value" }), { outgoing })
    expect(typesOf(found)).toEqual(expect.arrayContaining(["duplicate_match_value", "multiple_otherwise"]))
  })

  it("requires Yes plus No or Otherwise in condition mode", () => {
    const missing = run(el("decision", { routeBy: "condition" }), {
      outgoing: [conn("c1", "e1", "a", { matchValue: "true" }), conn("c2", "e1", "b", { matchValue: "maybe" })]
    })
    expect(typesOf(missing)).toEqual(expect.arrayContaining(["invalid_condition_match", "missing_yes_branch"]))

    expect(run(el("decision", { routeBy: "condition", condition: VALID }), yesNo)).toEqual([])
    expect(run(el("decision", { routeBy: "condition", condition: VALID }), {
      outgoing: [conn("c1", "e1", "a", { matchValue: "true" }), conn("c2", "e1", "b", { matchValue: "" })]
    })).toEqual([])
  })

  it("requires a non-empty, valid condition group in condition mode", () => {
    const missing = run(el("decision", { routeBy: "condition" }), yesNo)
    expect(missing).toEqual([expect.objectContaining({ type: "condition_invalid", field: "condition", message: "condition.empty_condition:{}" })])
    expect(messagesOf(run(el("decision", { routeBy: "condition", condition: group() }), yesNo)))
      .toEqual(["condition.empty_condition:{}"])
    expect(messagesOf(run(el("decision", { routeBy: "condition", condition: group(row({ leftOperand: "" })) }), yesNo)))
      .toEqual(["condition.missing_left:{}"])
  })

  it("does not check the condition group when routing by value", () => {
    const outgoing = [conn("c1", "e1", "a", { matchValue: "x" }), conn("c2", "e1", "b", { matchValue: "y" })]
    expect(run(el("decision", { routeBy: "value", condition: "junk" }), { outgoing })).toEqual([])
  })

  it("defaults routeBy to condition", () => {
    const found = run(el("decision"), {
      outgoing: [conn("c1", "e1", "a", { matchValue: "x" }), conn("c2", "e1", "b", { matchValue: "y" })]
    })
    expect(typesOf(found)).toContain("invalid_condition_match")
  })

  it("uses English fallbacks when msg returns a blank string", () => {
    const found = run(el("decision", { routeBy: "value" }), {
      outgoing: [conn("c1", "e1", "a")],
      msgFn: () => ""
    })
    expect(found[0].message).toBe("Decision requires at least two outgoing connections")
  })
})

describe("loop rules", () => {
  it("requires a collection for for_each and rejects ctx-prefixed paths", () => {
    expect(typesOf(run(el("loop", { loopType: "for_each" })))).toEqual(["loop_no_collection"])
    expect(run(el("loop", { loopType: "for_each", collection: "items" }))).toEqual([])
    for (const collection of ["ctx.items", "ctx[:items]"]) {
      const found = run(el("loop", { loopType: "for_each", collection }))
      expect(found).toEqual([expect.objectContaining({ type: "loop_invalid_collection", field: "collection", message: "invalidCollectionPath:{}" })])
    }
  })

  it("requires a condition for while (including the catalog default)", () => {
    const found = run(el("loop"))
    expect(typesOf(found)).toEqual(["empty_loop_condition"])
    expect(found[0].field).toBe("condition")
    expect(found[0].severity).toBe("error")
    expect(typesOf(run(el("loop", { condition: group() })))).toEqual(["empty_loop_condition"])
    expect(run(el("loop", { condition: VALID }))).toEqual([])
  })

  it("accepts unary, binary, and record-count rows", () => {
    expect(run(el("loop", {
      condition: group(row({ operator: "is_empty" }), row({ operator: "==", rightOperand: "1" }),
        { kind: "query_count", queryConfig: { entityId: 4 }, countOperator: ">" })
    }))).toEqual([])
  })

  it("reports the first problem of each row with its 1-based index, like ConditionRules", () => {
    const found = run(el("loop", {
      condition: group(
        null,
        group(),
        { kind: "query_count", queryConfig: {} },
        row({ leftOperand: " " }),
        row({ operator: "" }),
        row({ operator: "==", rightOperand: "" }),
        row({ operator: "matches_regex", rightOperand: "(" })
      )
    }))
    expect(found.every((f) => f.type === "condition_invalid" && f.field === "condition")).toBe(true)
    expect(messagesOf(found)).toEqual([
      'condition.invalid_row:{}',
      'condition.nested_group:{}',
      'condition.missing_entity:{}',
      'condition.missing_left:{}',
      'condition.missing_operator:{}',
      'condition.missing_right:{}'
    ])
  })

  it("rejects a condition that is not a flat group", () => {
    for (const condition of ["ctx.x", { leftOperand: "ctx.x", operator: "is_true" }, { type: "group", conditions: "x" }]) {
      expect(messagesOf(run(el("loop", { condition })))).toEqual(["condition.invalid_condition:{}"])
    }
  })

  it("validates the optional stopWhen and for_each skipWhen groups", () => {
    expect(run(el("loop", { condition: VALID, stopWhen: group() }))).toEqual([])
    const found = run(el("loop", {
      loopType: "for_each", collection: "items", stopWhen: group(row({ leftOperand: "" })), skipWhen: "junk"
    }))
    expect(found.map((f) => [f.field, f.message])).toEqual([
      ["stopWhen", "condition.missing_left:{}"],
      ["skipWhen", "condition.invalid_condition:{}"]
    ])
    expect(run(el("loop", { condition: VALID, skipWhen: "junk" }))).toEqual([])
  })

  it("rejects loop-header names and colliding item/index variables for for_each", () => {
    const base = { loopType: "for_each", collection: "items" }
    const reserved = run(el("loop", { ...base, itemVariable: "state", indexVariable: "ctx" }))
    expect(reserved.map((f) => [f.type, f.field])).toEqual([
      ["loop_reserved_variable", "itemVariable"],
      ["loop_reserved_variable", "indexVariable"]
    ])
    expect(reserved[0].message).toBe('reservedLoopVariable:{}')
    const colliding = run(el("loop", { ...base, itemVariable: "row", indexVariable: "row" }))
    expect(colliding).toEqual([expect.objectContaining({ type: "loop_colliding_variables", field: "itemVariable" })])
    expect(typesOf(run(el("loop", { ...base, itemVariable: "index" })))).toEqual(["loop_colliding_variables"])
    expect(run(el("loop", { ...base, itemVariable: " ", indexVariable: "i" }))).toEqual([])
  })

  it("interpolates row index, operator, and loop names into English fallbacks", () => {
    const found = run(el("loop", {
      loopType: "for_each", collection: "items", itemVariable: "ctx",
      stopWhen: group(row(), row({ operator: "contains" }))
    }), { msgFn: () => "" })
    expect(messagesOf(found)).toEqual([
      "Condition row 2 needs a value for contains",
      "itemVariable cannot be ctx because that name is reserved for the loop header"
    ])
  })

  it("interpolates tokens into the caller's translated template", () => {
    const found = run(el("loop", { condition: group(row({ leftOperand: "" })) }), {
      msgFn: (key) => key === "condition.missing_left" ? "第 {index} 行条件缺少比较值" : ""
    })
    expect(found[0].message).toBe("第 1 行条件缺少比较值")
  })

  it("uses the caller's translated message for the rule key", () => {
    const found = runElementRules({
      element: el("loop", { loopType: "for_each" }),
      properties: { loopType: "for_each" },
      incoming: [],
      outgoing: [],
      msg: (key) => key === "missingCollection" ? "请选择集合" : ""
    })
    expect(found[0].message).toBe("请选择集合")
  })

  describe("operator sources", () => {
    afterEach(() => setElementCatalog(null))

    it("falls back to the built-in unary list and skips operator checks without a catalog", () => {
      setElementCatalog(null)
      const found = run(el("loop", {
        condition: group(
          row({ operator: "is_nil" }),
          row({ operator: "~=", rightOperand: "1" }),
          row({ operator: "~=" }),
          { kind: "field", leftOperand: "ctx.x" },
          { kind: "query_count", queryConfig: { entityId: 1 }, countOperator: "anything" }
        )
      }))
      expect(messagesOf(found)).toEqual(["condition.missing_right:{}", "condition.missing_operator:{}"])
    })

    it("rejects unknown operators and count comparisons, and uses the catalog's unary list", () => {
      setElementCatalog({
        types: {},
        operators: [
          { value: "==", unary: false, count: true },
          { value: "is_true", unary: true, count: false },
          { value: "custom_unary", unary: true, count: false }
        ]
      })
      const found = run(el("loop", {
        condition: group(
          row({ operator: "~=" }),
          row({ operator: "custom_unary" }),
          { kind: "query_count", queryConfig: { entityId: 1 }, countOperator: "is_true" },
          { kind: "query_count", queryConfig: { entityId: 1 } },
          { kind: "query_count", queryConfig: { entityId: 1 }, countOperator: "==" }
        )
      }))
      expect(messagesOf(found)).toEqual([
        "condition.unknown_operator:{}",
        "condition.unknown_count_operator:{}",
        "condition.unknown_count_operator:{}"
      ])
    })
  })
})

describe("subflow rules", () => {
  it("requires a flowchart id", () => {
    const found = run(el("subflow"))
    expect(typesOf(found)).toEqual(["subflow_no_target"])
    expect(found[0].field).toBe("flowchartId")
    expect(run(el("subflow", { flowchartId: "9" }))).toEqual([])
  })

  it("flags a Subflow pointing at the flowchart being edited", () => {
    expect(typesOf(run(el("subflow", { flowchartId: "7" }), { flowchartId: 7 }))).toEqual(["subflow_self_reference"])
    expect(run(el("subflow", { flowchartId: "7" }))).toEqual([])
  })
})
