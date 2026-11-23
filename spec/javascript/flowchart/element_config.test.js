import { describe, it, expect, afterEach } from "vitest"
import {
  schemaFor,
  isFieldApplicable,
  getDefaultPropertiesForType,
  defaultPropertiesFor,
  coerceElementProperties,
  pruneInapplicableProperties,
  persistableProperties,
  normalizeElementProperties,
  intProperty,
  hasValue,
  schemaDefault,
} from "flowchart/element_config"
import { setElementCatalog } from "flowchart/constants/element_registry"
import { installSampleElementCatalog } from "../support/element_catalog.js"

afterEach(() => installSampleElementCatalog())

describe("schemaFor", () => {
  it("returns the element's catalog fields, or {} for an unknown type", () => {
    expect(schemaFor("end").responseType.control).toBe("select")
    expect(schemaFor("timer")).toEqual({})
    expect(schemaFor("nope")).toEqual({})
    expect(schemaFor(undefined)).toEqual({})
  })
})

describe("isFieldApplicable", () => {
  const schema = { loopType: { default: "while" }, other: {} }

  it("treats a field with no visibleWhen as always applicable", () => {
    expect(isFieldApplicable(undefined, {})).toBe(true)
  })

  it("matches the catalog object form and the legacy field/values shape", () => {
    expect(isFieldApplicable({ loopType: "while" }, { loopType: "while" }, schema)).toBe(true)
    expect(isFieldApplicable({ loopType: ["while", ""] }, { loopType: "for_each" }, schema)).toBe(false)
    expect(isFieldApplicable({ field: "loopType", value: "while" }, { loopType: "while" }, schema)).toBe(true)
    expect(isFieldApplicable({ field: "mode", values: ["manual", "automatic"] }, { mode: "automatic" })).toBe(true)
    expect(isFieldApplicable({ field: "mode", values: ["manual"] }, { mode: "scheduled" })).toBe(false)
  })

  it("falls back to the controlling field's schema default when the value is unset or blank", () => {
    expect(isFieldApplicable({ loopType: "while" }, {}, schema)).toBe(true)
    expect(isFieldApplicable({ field: "loopType", value: "while" }, { loopType: "" }, schema)).toBe(true)
    expect(isFieldApplicable({ field: "other", value: "" }, {}, schema)).toBe(true)
    expect(isFieldApplicable({ field: "missing", value: "x" }, {})).toBe(false)
  })

  it("compares numerically-typed values as strings", () => {
    expect(isFieldApplicable({ n: 200 }, { n: "200" })).toBe(true)
  })
})

describe("defaultPropertiesFor", () => {
  it("seeds applicable catalog defaults, including visibleWhen dependents", () => {
    expect(defaultPropertiesFor("loop")).toEqual({
      description: "",
      loopType: "while",
      runOnceFirst: false,
      maxIterations: 100,
    })
    expect(defaultPropertiesFor("end")).toEqual({
      description: "",
      responseType: "none",
    })
    expect(defaultPropertiesFor("decision")).toEqual({
      description: "",
      routeBy: "condition",
    })
  })

  it("returns only a description for types with no seeded defaults", () => {
    expect(defaultPropertiesFor("start")).toEqual({ description: "" })
    expect(defaultPropertiesFor("process")).toEqual({ description: "" })
    expect(defaultPropertiesFor("nope")).toEqual({ description: "" })
  })

  it("never returns the element's label as a property", () => {
    for (const type of ["start", "end", "process", "decision", "subflow", "loop"]) {
      expect(defaultPropertiesFor(type), type).not.toHaveProperty("label")
    }
  })

  it("returns a new object each call", () => {
    expect(defaultPropertiesFor("start")).not.toBe(defaultPropertiesFor("start"))
  })

  it("seeds an applicable conditional default from a custom catalog", () => {
    setElementCatalog({
      types: {
        test_conditional_default: {
          type: "test_conditional_default",
          fields: [
            { name: "mode", default: "enabled" },
            { name: "dependent", default: "seeded", visibleWhen: { mode: "enabled" } },
          ],
        },
      },
    })
    expect(defaultPropertiesFor("test_conditional_default")).toEqual({
      description: "",
      mode: "enabled",
      dependent: "seeded",
    })
  })
})

describe("getDefaultPropertiesForType", () => {
  it("accepts only the element type and delegates to defaultPropertiesFor", () => {
    expect(getDefaultPropertiesForType.length).toBe(1)
    expect(getDefaultPropertiesForType("loop")).toEqual(defaultPropertiesFor("loop"))
  })
})

describe("coerceElementProperties", () => {
  it("turns FormData strings into numbers for integer fields", () => {
    const result = coerceElementProperties("loop", { maxIterations: " 25 ", loopType: "while" })
    expect(result.maxIterations).toBe(25)
    expect(result.loopType).toBe("while")
  })

  it("drops blank and non-numeric number entries rather than persisting '' or NaN", () => {
    expect(coerceElementProperties("loop", { maxIterations: "abc" })).not.toHaveProperty("maxIterations")
    expect(coerceElementProperties("loop", { maxIterations: null })).not.toHaveProperty("maxIterations")
    expect(coerceElementProperties("loop", { maxIterations: "" })).not.toHaveProperty("maxIterations")
    expect(coerceElementProperties("loop", { maxIterations: NaN })).not.toHaveProperty("maxIterations")
  })

  it("leaves an already-numeric value alone", () => {
    expect(coerceElementProperties("loop", { maxIterations: 45 }).maxIterations).toBe(45)
  })

  it("coerces flag fields from form strings", () => {
    expect(coerceElementProperties("loop", { runOnceFirst: "true" }).runOnceFirst).toBe(true)
    expect(coerceElementProperties("loop", { runOnceFirst: "on" }).runOnceFirst).toBe(true)
    expect(coerceElementProperties("loop", { runOnceFirst: "1" }).runOnceFirst).toBe(true)
    expect(coerceElementProperties("loop", { runOnceFirst: "false" }).runOnceFirst).toBe(false)
    expect(coerceElementProperties("loop", { runOnceFirst: "off" }).runOnceFirst).toBe(false)
    expect(coerceElementProperties("loop", { runOnceFirst: "" }).runOnceFirst).toBe(false)
  })

  it("ignores fields absent from the bag and does not mutate the input", () => {
    const result = coerceElementProperties("decision", { condition: "ctx.flag" })
    expect(result.condition).toBe("ctx.flag")
    const input = { maxIterations: "3" }
    coerceElementProperties("loop", input)
    expect(input.maxIterations).toBe("3")
    expect(coerceElementProperties("end")).toEqual({})
  })
})

describe("pruneInapplicableProperties", () => {
  it("passes unknown legacy keys through so persist can drop them later", () => {
    const result = pruneInapplicableProperties("start", {
      triggerType: "manual",
      description: "keep me",
    })
    expect(result).toEqual({ triggerType: "manual", description: "keep me" })
  })

  it("keeps applicable fields and removes hidden-mode catalog fields", () => {
    expect(pruneInapplicableProperties("end", {
      responseType: "value",
      returnValue: "ctx.result",
    })).toHaveProperty("returnValue", "ctx.result")

    expect(pruneInapplicableProperties("end", {
      responseType: "none",
      returnValue: "ctx.result",
    })).not.toHaveProperty("returnValue")
  })

  it("does not mutate the input and defaults to an empty bag", () => {
    const input = { loopType: "while", collection: "items" }
    pruneInapplicableProperties("loop", input)
    expect(input.collection).toBe("items")
    expect(pruneInapplicableProperties("start")).toEqual({})
  })
})

describe("persistableProperties", () => {
  it("keeps visible catalog fields plus notes, I/O, steps, and a visible condition", () => {
    const result = persistableProperties("loop", {
      loopType: "while",
      runOnceFirst: true,
      maxIterations: 10,
      collection: "items",
      description: "note",
      io_overrides: { inputs: [] },
      condition: { type: "group", joins: [], conditions: [] },
      leftover: "drop",
    })
    expect(result).toMatchObject({
      loopType: "while",
      runOnceFirst: true,
      maxIterations: 10,
      description: "note",
      io_overrides: { inputs: [] },
    })
    expect(result).toHaveProperty("condition")
    expect(result).not.toHaveProperty("collection")
    expect(result).not.toHaveProperty("leftover")
    expect(persistableProperties("decision", { routeBy: "condition", branches: [{ name: "Yes" }] })).not.toHaveProperty("branches")
  })

  it("drops condition when that catalog field is hidden", () => {
    const result = persistableProperties("loop", {
      loopType: "for_each",
      collection: "items",
      condition: { type: "group", joins: [], conditions: [] },
    })
    expect(result).not.toHaveProperty("condition")
    expect(result.collection).toBe("items")
  })
})

describe("normalizeElementProperties", () => {
  it("live-sync keeps hidden-mode values; persist writes the allow-list", () => {
    const bag = {
      loopType: "while",
      collection: "items",
      maxIterations: "12",
      leftover: "drop",
    }
    const live = normalizeElementProperties("loop", bag)
    expect(live.collection).toBe("items")
    expect(live.maxIterations).toBe(12)
    expect(live.leftover).toBe("drop")

    const saved = normalizeElementProperties("loop", bag, { persist: true })
    expect(saved).not.toHaveProperty("collection")
    expect(saved).not.toHaveProperty("leftover")
    expect(saved.maxIterations).toBe(12)
  })

  it("defaults to an empty bag", () => {
    expect(normalizeElementProperties("end")).toEqual({})
  })
})

describe("intProperty", () => {
  it("reads whole numbers whether stored as a number or a FormData string", () => {
    expect(intProperty({ n: 2 }, "n")).toBe(2)
    expect(intProperty({ n: "2" }, "n")).toBe(2)
    expect(intProperty({ n: " -1 " }, "n")).toBe(-1)
    expect(intProperty({ n: 0 }, "n")).toBe(0)
  })

  it("returns null for absent, blank, or non-integer values", () => {
    expect(intProperty({}, "n")).toBeNull()
    expect(intProperty({ n: null }, "n")).toBeNull()
    expect(intProperty({ n: "" }, "n")).toBeNull()
    expect(intProperty({ n: "2.5" }, "n")).toBeNull()
    expect(intProperty({ n: "abc" }, "n")).toBeNull()
    expect(intProperty(undefined, "n")).toBeNull()
  })
})

describe("hasValue", () => {
  it("treats any non-blank scalar, finite number, or non-empty array as present", () => {
    expect(hasValue({ v: "x" }, "v")).toBe(true)
    expect(hasValue({ v: 0 }, "v")).toBe(true)
    expect(hasValue({ v: [1] }, "v")).toBe(true)
  })

  it("treats absent, null, blank, whitespace, NaN, and empty arrays as missing", () => {
    expect(hasValue({}, "v")).toBe(false)
    expect(hasValue({ v: null }, "v")).toBe(false)
    expect(hasValue({ v: "" }, "v")).toBe(false)
    expect(hasValue({ v: "   " }, "v")).toBe(false)
    expect(hasValue({ v: NaN }, "v")).toBe(false)
    expect(hasValue({ v: [] }, "v")).toBe(false)
    expect(hasValue(undefined, "v")).toBe(false)
  })
})

describe("schemaDefault", () => {
  it("reads a field's declared default, or undefined when there is none", () => {
    expect(schemaDefault("loop", "maxIterations")).toBe(100)
    expect(schemaDefault("end", "returnValue")).toBeNull()
    expect(schemaDefault("nope", "maxIterations")).toBeUndefined()
  })
})
