import { describe, it, expect, beforeEach, afterEach } from "vitest"
import { LabelDerivationMixin } from "controllers/property_editor/label_derivation"
import { clearElementCatalog, installSampleElementCatalog } from "../../support/element_catalog.js"

// English defaults mirroring the Stimulus `static values` on
// PropertyEditorController — see property_editor_controller.js. LabelDerivationMixin
// is mixed directly onto the controller (reads this.xValue), so this bare host
// fake needs the same defaults duplicated here (byte-identical) to resolve to
// the same strings the real controller would when no data-*-value attribute
// is present.
const LABEL_DERIVATION_I18N_DEFAULTS = {
  deriveStartFallbackValue: "Start",
  deriveReturnWithValueFormatValue: "Return {value}",
  deriveReturnValueFallbackValue: "Return Value",
  deriveEndFallbackValue: "End",
  deriveForEachWithCollectionFormatValue: "ForEach {collection}",
  deriveForEachFallbackValue: "ForEach",
  deriveRunOnceFirstWithExprFormatValue: "DoWhile {expr}",
  deriveRunOnceFirstFallbackValue: "DoWhile",
  deriveWhileWithExprFormatValue: "While {expr}",
  deriveWhileFallbackValue: "While",
  deriveSubflowFallbackValue: "Subflow",
}

// The mixin is a bag of methods meant to be Object.assign'd onto the controller
// prototype. We exercise them against a lightweight host that supplies the
// `this.currentElement` / `this.canvas` state they read.
const makeHost = (type, canvas = null) => {
  const host = {
    currentElement: type ? { type, id: "self" } : null,
    canvas,
    ...LABEL_DERIVATION_I18N_DEFAULTS,
  }
  Object.assign(host, LabelDerivationMixin)
  return host
}

describe("_deriveLabelFromProperties — explicit label + type dispatch", () => {
  it("returns the explicit label verbatim when non-empty", () => {
    const host = makeHost("start")
    expect(host._deriveLabelFromProperties({}, "My Label")).toBe("My Label")
  })

  it("returns undefined when there is no current element type", () => {
    const host = makeHost(null)
    expect(host._deriveLabelFromProperties({}, "")).toBeUndefined()
  })

  it("returns undefined for an unknown element type", () => {
    const host = makeHost("mystery")
    expect(host._deriveLabelFromProperties({}, "")).toBeUndefined()
  })
})

describe("_deriveLabelFromProperties — full type dispatch", () => {
  it("dispatches process to _deriveLabelFromSteps", () => {
    const host = makeHost("process")
    expect(
      host._deriveLabelFromProperties({ steps: [{ action: "send_email" }] }, "")
    ).toBe("send_email")
  })

  it("dispatches decision to _summarizeCondition", () => {
    const host = makeHost("decision")
    expect(
      host._deriveLabelFromProperties(
        { condition: { leftOperand: "x", operator: ">", rightOperand: "1" } },
        ""
      )
    ).toBe("x > 1")
  })

  it("decision falls back to undefined when the condition summarizes to an empty string", () => {
    const host = makeHost("decision")
    expect(host._deriveLabelFromProperties({}, "")).toBeUndefined()
  })

  it("dispatches retained types and ignores unsupported structural types", () => {
    expect(makeHost("start")._deriveLabelFromProperties({}, "")).toBe("Start")
    expect(makeHost("end")._deriveLabelFromProperties({}, "")).toBe("End")
    expect(makeHost("loop")._deriveLabelFromProperties({}, "")).toBe("While")
    expect(makeHost("timer")._deriveLabelFromProperties({}, "")).toBeUndefined()
    expect(makeHost("subflow")._deriveLabelFromProperties({}, "")).toBe("Subflow")
    expect(makeHost("join")._deriveLabelFromProperties({}, "")).toBeUndefined()
  })
})

describe("start labels", () => {
  afterEach(() => installSampleElementCatalog())

  it("uses the catalog defaultLabel (or the Stimulus fallback)", () => {
    const host = makeHost("start")
    expect(host._deriveLabelForStart()).toBe("Start")
    expect(host._deriveLabelForStart({ triggerType: "http" })).toBe("Start")
  })

  it("falls back to Stimulus values when the catalog has no defaultLabel", () => {
    clearElementCatalog()
    expect(makeHost("start")._deriveLabelForStart()).toBe("Start")
    expect(makeHost("end")._deriveLabelForEnd({})).toBe("End")
    expect(makeHost("subflow")._deriveLabelForSubflow()).toBe("Subflow")
  })
})

describe("end labels", () => {
  const host = makeHost("end")
  it.each([
    [{}, "End"],
    [{ responseType: "none" }, "End"],
    [{ responseType: "value" }, "Return Value"],
    [{ responseType: "value", returnValue: "ok" }, "Return ok"],
  ])("%o → %s", (props, expected) => {
    expect(host._deriveLabelForEnd(props)).toBe(expected)
  })
})

describe("loop labels", () => {
  const host = makeHost("loop")
  it("for_each with/without collection", () => {
    expect(host._deriveLabelForLoop({ loopType: "for_each" })).toBe("ForEach")
    expect(host._deriveLabelForLoop({ loopType: "for_each", collection: "orders" })).toBe(
      "ForEach orders"
    )
  })
  it("while / runOnceFirst use the condition summary", () => {
    const cond = { leftOperand: "x", operator: ">", rightOperand: "1" }
    expect(host._deriveLabelForLoop({ loopType: "while", condition: cond })).toBe("While x > 1")
    expect(host._deriveLabelForLoop({ loopType: "while", runOnceFirst: true, condition: cond })).toBe(
      "DoWhile x > 1"
    )
    expect(host._deriveLabelForLoop({ loopType: "while" })).toBe("While")
  })
  it("falls back to while when loopType is absent", () => {
    expect(host._deriveLabelForLoop({})).toBe("While")
  })
  it("runOnceFirst without a condition falls back to 'DoWhile'", () => {
    expect(host._deriveLabelForLoop({ loopType: "while", runOnceFirst: true })).toBe("DoWhile")
  })
})

describe("subflow labels", () => {
  it("uses the catalog defaultLabel", () => {
    const host = makeHost("subflow")
    expect(host._deriveLabelForSubflow()).toBe("Subflow")
    expect(host._deriveLabelForSubflow({ flowchartId: "9" })).toBe("Subflow")
  })
})

describe("_deriveLabelFromSteps", () => {
  it("returns undefined for no steps", () => {
    const host = makeHost("process")
    expect(host._deriveLabelFromSteps([])).toBeUndefined()
    expect(host._deriveLabelFromSteps(undefined)).toBeUndefined()
  })

  it("joins selectionLabels with ' - ' and multiple steps with ', '", () => {
    const host = makeHost("process")
    const steps = [
      { selectionLabels: ["New", "Model"] },
      { selectionLabels: ["Build", "Contract"] },
    ]
    expect(host._deriveLabelFromSteps(steps)).toBe("New - Model, Build - Contract")
  })

  it("falls back to action name when selectionLabels absent", () => {
    const host = makeHost("process")
    expect(host._deriveLabelFromSteps([{ action: "send_email" }])).toBe("send_email")
  })

  it("filters out steps with neither selectionLabels nor action, leaving nothing", () => {
    const host = makeHost("process")
    expect(host._deriveLabelFromSteps([{}])).toBeUndefined()
  })

  it("returns the base label unchanged when it doesn't collide with an existing one", () => {
    const canvas = { elements: [{ id: "other", label: "Something Else" }] }
    const host = makeHost("process", canvas)
    expect(host._deriveLabelFromSteps([{ action: "send_email" }])).toBe("send_email")
  })

  it("appends a unique suffix when the derived label collides", () => {
    const canvas = {
      elements: [
        { id: "other", label: "send_email" },
        { id: "other2", label: "send_email 2" },
      ],
    }
    const host = makeHost("process", canvas)
    expect(host._deriveLabelFromSteps([{ action: "send_email" }])).toBe("send_email 3")
  })
})

describe("_summarizeCondition", () => {
  const host = makeHost("decision")

  it("returns empty string for non-objects", () => {
    expect(host._summarizeCondition(null)).toBe("")
    expect(host._summarizeCondition("x")).toBe("")
  })

  it("renders a field row with symbolic operator", () => {
    expect(
      host._summarizeCondition({ leftOperand: "age", operator: ">=", rightOperand: "18" })
    ).toBe("age >= 18")
  })

  it("humanises underscore operators", () => {
    expect(host._summarizeCondition({ leftOperand: "name", operator: "is_empty" })).toBe(
      "name is empty"
    )
  })

  it("bare operand when no operator", () => {
    expect(host._summarizeCondition({ leftOperand: "flag" })).toBe("flag")
  })

  it("query_count rows", () => {
    expect(
      host._summarizeCondition({
        kind: "query_count",
        queryConfig: { entityName: "Order" },
        countOperator: ">",
        countValue: 5,
      })
    ).toBe("count(Order) > 5")
  })

  it("groups join sub-conditions with per-join AND/OR", () => {
    const group = {
      type: "group",
      joins: ["OR"],
      conditions: [
        { leftOperand: "a", operator: "==", rightOperand: "1" },
        { leftOperand: "b", operator: "==", rightOperand: "2" },
      ],
    }
    expect(host._summarizeCondition(group)).toBe("a == 1 OR b == 2")
  })

  it("truncates long top-level group summaries to 48 chars with an ellipsis", () => {
    // Truncation only applies to a depth-0 group summary.
    const long = "x".repeat(60)
    const out = host._summarizeCondition({ type: "group", conditions: [{ leftOperand: long }] })
    expect(out.length).toBe(48)
    expect(out.endsWith("…")).toBe(true)
  })

  it("empty group with no conditions summarizes to an empty string", () => {
    expect(host._summarizeCondition({ type: "group" })).toBe("")
  })

  it("wraps a nested non-empty group in parens and defaults a missing join to AND", () => {
    const group = {
      type: "group",
      conditions: [
        {
          type: "group",
          conditions: [{ leftOperand: "a", operator: "==", rightOperand: "1" }],
        },
        { leftOperand: "b", operator: "==", rightOperand: "2" },
      ],
    }
    expect(host._summarizeCondition(group)).toBe("(a == 1) AND b == 2")
  })

  it("drops an empty nested group from the joined output instead of rendering '()'", () => {
    const group = {
      type: "group",
      joins: ["OR"],
      conditions: [
        { type: "group", conditions: [] },
        { leftOperand: "b", operator: "==", rightOperand: "2" },
      ],
    }
    expect(host._summarizeCondition(group)).toBe("b == 2")
  })

  it("ignores leftover conditionType keys that are not kind: query_count", () => {
    expect(
      host._summarizeCondition({ conditionType: "query_count", queryConfig: {} })
    ).toBe("")
  })

  it("query_count defaults queryConfig itself to {} when absent", () => {
    expect(host._summarizeCondition({ kind: "query_count" })).toBe("count(#?) > 0")
  })

  it("returns empty string when leftOperand is absent", () => {
    expect(host._summarizeCondition({})).toBe("")
  })
})
