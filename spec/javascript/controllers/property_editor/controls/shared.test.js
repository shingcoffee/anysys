import { describe, it, expect, afterEach } from "vitest"
import {
  compactLabels,
  labelsFromEditor,
  resolveControlLabels,
  entityColumns,
  addRowButton,
  DEFAULT_CONTROL_LABELS,
} from "controllers/property_editor/controls/shared"

describe("compactLabels", () => {
  it("drops blank and non-string values", () => {
    expect(compactLabels({ a: "keep", b: "", c: null, d: 1 })).toEqual({ a: "keep" })
  })
})

describe("labelsFromEditor / resolveControlLabels", () => {
  afterEach(() => { document.body.innerHTML = "" })

  it("returns {} when no property-editor mount exists", () => {
    expect(labelsFromEditor()).toEqual({})
    expect(resolveControlLabels()).toMatchObject(DEFAULT_CONTROL_LABELS)
  })

  it("reads non-empty data attributes from the editor mount", () => {
    document.body.innerHTML = `
      <div data-controller="panel-resize property-editor"
           data-property-editor-none-option-label-value="无"
           data-property-editor-add-row-label-value=""
           data-property-editor-join-and-label-value="且"></div>`
    expect(labelsFromEditor()).toEqual({ noneOptionLabel: "无", joinAndLabel: "且" })
    expect(resolveControlLabels({ searchPlaceholder: "找" }).noneOptionLabel).toBe("无")
    expect(resolveControlLabels({ searchPlaceholder: "找" }).searchPlaceholder).toBe("找")
  })
})

describe("entityColumns", () => {
  it("maps slug/label from objects and strings and drops empty slugs", () => {
    expect(entityColumns([
      { name_slug: "email", name: "Email" },
      { name: "age" },
      { name_slug: "only" },
      {},
      "plain",
      "",
    ])).toEqual([
      { slug: "email", label: "Email" },
      { slug: "age", label: "age" },
      { slug: "only", label: "only" },
      { slug: "[object Object]", label: "[object Object]" },
      { slug: "plain", label: "plain" },
    ])
    expect(entityColumns(null)).toEqual([])
  })
})

describe("addRowButton", () => {
  it("wires the given action and label", () => {
    const html = addRowButton("addConfigListRow", "Add row")
    expect(html).toContain("click->property-editor#addConfigListRow")
    expect(html).toContain("Add row")
  })
})
