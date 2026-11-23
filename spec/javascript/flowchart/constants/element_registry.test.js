import { describe, it, expect, beforeEach, afterEach } from "vitest"
import {
  setElementCatalog,
  fieldName,
  elementType,
  elementFields,
  elementTabs,
  elementLabel,
  elementDefaultLabel,
  connectionFields,
  conditionOperators,
  chrome,
  catalogLocale,
  catalogDigest,
  fieldsByName,
  elementSchemaMap,
} from "flowchart/constants/element_registry"
import { SAMPLE_ELEMENT_CATALOG, installSampleElementCatalog, clearElementCatalog } from "../../support/element_catalog.js"

beforeEach(() => installSampleElementCatalog())
afterEach(() => installSampleElementCatalog())

describe("setElementCatalog", () => {
  it("starts empty before a valid catalog is installed", () => {
    clearElementCatalog()
    expect(elementType("start")).toBeUndefined()
    expect(elementFields("start")).toEqual([])
    expect(elementTabs("loop")).toEqual([])
    expect(connectionFields()).toEqual([])
    expect(conditionOperators()).toEqual([])
    expect(catalogLocale()).toBeNull()
    expect(catalogDigest()).toBeNull()
    expect(chrome()).toMatchObject({
      label: { label: "Label" },
      notes: { key: "description", label: "Notes" },
    })
  })

  it("ignores payloads that lack a types object", () => {
    const before = elementLabel("start")
    setElementCatalog({})
    setElementCatalog({ locale: "en" })
    setElementCatalog("nope")
    expect(elementLabel("start")).toBe(before)
  })

  it("null / undefined empties the store", () => {
    expect(elementType("end")).toBeTruthy()
    setElementCatalog(null)
    expect(elementType("end")).toBeUndefined()
    setElementCatalog(undefined)
    expect(elementType("end")).toBeUndefined()
  })

  it("skips malformed type rows, empty keys, and duplicate type names", () => {
    setElementCatalog({
      types: {
        "": { type: "empty" },
        bad: null,
        1: { type: "numeric" },
        start: { type: "start", label: "First", tabs: ["general", 2, "io"], fields: [null, { name: "" }, { name: "ok" }] },
        also: { type: "start", label: "Dup" },
        mystery: { tabs: "nope", fields: { name: "x" } },
      },
      connection: { fields: [null, { key: "priority" }, "x"] },
      operators: [null, { value: 1 }, { value: "==", label: "equals", unary: false }],
      chrome: { label: "nope", notes: "nope" },
      locale: 12,
      digest: 12,
    })
    expect(elementType("start").label).toBe("First")
    expect(elementTabs("start")).toEqual(["general", "io"])
    expect(elementFields("start").map(fieldName)).toEqual(["ok"])
    expect(elementType("also")).toBeUndefined()
    expect(elementType("mystery").defaultLabel).toBe("mystery")
    expect(elementTabs("mystery")).toEqual([])
    expect(connectionFields().map(fieldName)).toEqual(["priority"])
    expect(conditionOperators()).toEqual([{ value: "==", label: "equals", unary: false }])
    expect(chrome()).toMatchObject({
      label: { label: "Label" },
      notes: { key: "description", label: "Notes" },
    })
    expect(catalogLocale()).toBeNull()
    expect(catalogDigest()).toBeNull()
  })

  it("uses the type key as the label and defaultLabel when those strings are missing", () => {
    setElementCatalog({
      types: { custom: { fields: [] } },
      chrome: { label: { label: "名称" }, notes: { key: "notes", label: "备注" } },
      locale: "zh-CN",
      digest: "abc",
    })
    expect(elementLabel("custom")).toBe("custom")
    expect(elementDefaultLabel("custom")).toBe("custom")
    expect(chrome()).toEqual({
      label: { label: "名称" },
      notes: { key: "notes", label: "备注" },
    })
    expect(catalogLocale()).toBe("zh-CN")
    expect(catalogDigest()).toBe("abc")
  })

  it("falls back to label when defaultLabel is missing", () => {
    setElementCatalog({ types: { start: { label: "开始" } } })
    expect(elementDefaultLabel("start")).toBe("开始")
  })
})

describe("sample catalog accessors", () => {
  it("exposes the installed types, tabs, and fields", () => {
    expect(elementType("loop").tabs).toEqual(["general", "io", "advanced"])
    expect(elementTabs("decision")).toEqual(["general", "branches", "io"])
    expect(elementLabel("process")).toBe("Process")
    expect(elementDefaultLabel("end")).toBe("End")
    expect(fieldsByName("end").responseType.control).toBe("select")
    expect(elementSchemaMap().start).toEqual({})
    expect(elementSchemaMap().loop.maxIterations.role).toBe("integer")
    expect(elementType(null)).toBeUndefined()
  })

  it("exposes connection fields, operators, and chrome from the fixture", () => {
    expect(connectionFields().map(fieldName)).toEqual(["label", "description"])
    expect(conditionOperators().some((op) => op.value === "is_empty" && op.unary)).toBe(true)
    expect(chrome().notes).toEqual({ key: "description", label: "Notes" })
    expect(catalogLocale()).toBe(SAMPLE_ELEMENT_CATALOG.locale)
    expect(catalogDigest()).toBe(SAMPLE_ELEMENT_CATALOG.digest)
  })

  it("fieldName accepts export `name` or a test-fake `key`", () => {
    expect(fieldName({ name: "loopType" })).toBe("loopType")
    expect(fieldName({ key: "legacy" })).toBe("legacy")
    expect(fieldName({})).toBeUndefined()
    expect(fieldName(null)).toBeUndefined()
  })
})
