import { describe, it, expect } from "vitest"
import {
  renderCatalogField,
  fieldControlsVisibility,
  configFieldKey,
  configFieldType,
  matchesWhen,
} from "controllers/property_editor/controls/field_renderer"

const labels = {
  noneOptionLabel: "None",
  defaultPlaceholderFormat: "Default: {value}",
  insertVariableTitle: "Insert variable",
}

describe("renderCatalogField", () => {
  it("returns an empty string without a field identity", () => {
    expect(renderCatalogField({}, "x")).toBe("")
  })

  it("renders a labeled text control with help and a required mark", () => {
    const html = renderCatalogField({
      name: "subject",
      role: "expression",
      control: "code",
      label: "Subject",
      help: "Use a ctx path.",
      required: true,
    }, "ctx.status", { labels })
    expect(html).toContain('data-element-field="subject"')
    expect(html).toContain("Subject")
    expect(html).toContain("text-red-500")
    expect(html).toContain("Use a ctx path.")
    expect(html).toContain("<textarea")
    expect(html).toContain("ctx.status")
  })

  it("keeps a cleared number empty and shows Default: {value} in the placeholder", () => {
    const html = renderCatalogField({
      name: "maxIterations",
      role: "integer",
      control: "number",
      label: "Max",
      default: 100,
      min: 1,
      max: 10000,
    }, undefined, { labels })
    expect(html).toContain('type="number"')
    expect(html).toContain('value=""')
    expect(html).toContain('placeholder="Default: 100"')
    expect(html).toContain('min="1"')
    expect(html).toContain('max="10000"')
  })

  it("renders a stored number and falls back to the field placeholder when there is no default", () => {
    const html = renderCatalogField({
      name: "n",
      control: "number",
      placeholder: "count",
    }, 4, { labels })
    expect(html).toContain('value="4"')
    expect(html).toContain('placeholder="count"')
  })

  it("renders an optional select with a None option and a required select without one", () => {
    const optional = renderCatalogField({
      name: "loopType",
      control: "select",
      options: [{ value: "while", label: "Repeat while" }],
    }, "while", { labels })
    expect(optional).toContain('<option value="">None</option>')
    expect(optional).toContain('<option value="while" selected>Repeat while</option>')

    const required = renderCatalogField({
      name: "routeBy",
      control: "select",
      required: true,
      options: [{ value: "value", label: "Value" }],
    }, "missing", { labels })
    expect(required).toContain("selected disabled hidden")
    expect(required).not.toContain(">None<")
  })

  it("hides a field when visibleWhen is not satisfied and still marks it conditionally required", () => {
    const html = renderCatalogField({
      name: "returnValue",
      control: "text",
      label: "Return Value",
      requiredWhen: { responseType: "value" },
      visibleWhen: { responseType: "value" },
    }, "", { properties: { responseType: "none" }, labels })
    expect(html).toContain(" hidden")
    expect(html).toContain("data-conditionally-required")
    expect(html).toContain("data-visible-when")
    expect(html).toContain("data-required-when")
    expect(html).not.toMatch(/\srequired(\s|>)/)
  })

  it("shows a required field when visibleWhen matches the catalog object form", () => {
    const html = renderCatalogField({
      name: "collection",
      control: "text",
      required: true,
      visibleWhen: { loopType: "for_each" },
    }, "items", { properties: { loopType: "for_each" }, labels })
    expect(html).not.toContain(" hidden")
    expect(html).toMatch(/\srequired(\s|>)/)
  })

  it("wires a visibility change action when another field depends on this name", () => {
    const html = renderCatalogField({
      name: "loopType",
      control: "select",
      options: [{ value: "while", label: "While" }],
    }, "while", {
      fields: [{ name: "collection", visibleWhen: { loopType: "for_each" } }],
      labels,
    })
    expect(html).toContain("change->property-editor#handleVisibilityFieldChange")
  })

  it("renders toggle, list, conditions, mapping, localized text, and reference controls", () => {
    const ctx = { labels }
    expect(renderCatalogField({ name: "runOnceFirst", control: "toggle" }, true, ctx)).toContain('type="checkbox"')
    expect(renderCatalogField({ name: "tags", control: "list" }, ["a"], ctx)).toContain("data-list-editor")
    expect(renderCatalogField({ name: "condition", control: "conditions" }, null, ctx)).toContain("data-conditions-editor")
    expect(renderCatalogField({ name: "headers", control: "mapping" }, [], ctx)).toContain("data-key-value-list")
    expect(renderCatalogField({ name: "title", control: "localized_text" }, { en: "Hi" }, ctx)).toContain("data-localized-text")
    expect(renderCatalogField({ name: "flowchartId", control: "reference_picker", source: "flowcharts" }, "9", ctx))
      .toContain("data-reference-picker")
  })

  it("wraps a variable-picker text field in context-autocomplete", () => {
    const html = renderCatalogField({
      name: "collection",
      control: "text",
      variablePicker: true,
    }, "items", { elementId: "loop-1", labels })
    expect(html).toContain("context-autocomplete")
    expect(html).toContain('data-context-autocomplete-element-id-value="loop-1"')
  })

  it("infers a variable picker from a *Var field name and wraps a multiline picker", () => {
    const inferred = renderCatalogField({
      name: "resultVar",
      control: "text",
    }, "order", { elementId: "p1", labels })
    expect(inferred).toContain("context-autocomplete")

    const multiline = renderCatalogField({
      name: "filterExpression",
      control: "code",
      variablePicker: true,
      required: true,
      maxLength: 80,
    }, "ctx.x", { elementId: "p1", labels: { ...labels, noVariablesAvailable: "None left" } })
    expect(multiline).toContain("<textarea")
    expect(multiline).toContain("context-autocomplete")
    expect(multiline).toContain("maxlength=\"80\"")
  })

  it("skips the variable picker when variablePicker is false", () => {
    const html = renderCatalogField({
      name: "resultVar",
      control: "text",
      variablePicker: false,
    }, "order", { elementId: "p1", labels })
    expect(html).not.toContain("context-autocomplete")
  })

  it("stringifies a null display value to an empty string", () => {
    const html = renderCatalogField({ name: "notes", control: "textarea" }, null, { labels })
    expect(html).toContain("<textarea")
    expect(html).not.toContain("null")
  })

  it("hits the role-control default when field.type is an unknown renderer key", () => {
    const html = renderCatalogField({ name: "x", type: "mystery" }, "v", { labels })
    expect(html).toContain('type="text"')
    expect(html).toContain('value="v"')
  })

  it("uses an entity-column select when attributes are present", () => {
    const html = renderCatalogField({
      name: "column",
      control: "text",
      entityField: true,
    }, "email", {
      entityAttributes: [{ name_slug: "email", name: "Email" }],
      labels,
    })
    expect(html).toContain("data-entity-column-select")
  })

  it("falls back to a text control when the entity picker has no usable columns", () => {
    const html = renderCatalogField({
      name: "column",
      type: "attribute_picker",
    }, "x", { entityAttributes: [""], labels })
    expect(html).toContain('type="text"')
    expect(html).not.toContain("data-entity-column-select")
  })

  it("appends an extra action from context", () => {
    const html = renderCatalogField({
      name: "subject",
      control: "text",
    }, "", { extraAction: "input->property-editor#_syncChangesToCanvas", labels })
    expect(html).toContain("input->property-editor#_syncChangesToCanvas")
  })

  it("stringifies object values in a textarea and defaults an unknown control to text", () => {
    const json = renderCatalogField({ name: "payload", control: "code" }, { a: 1 }, { labels })
    expect(json).toContain("{")
    expect(json).toContain("&quot;a&quot;")
    const mystery = renderCatalogField({ name: "x", control: "mystery" }, "v", { labels })
    expect(mystery).toContain('type="text"')
    expect(mystery).toContain('value="v"')
  })

  it("accepts a test-fake key and a string option list", () => {
    const html = renderCatalogField({
      key: "mode",
      control: "select",
      options: ["a", "b"],
    }, "b", { labels })
    expect(html).toContain('data-element-field="mode"')
    expect(html).toContain('<option value="b" selected>b</option>')
  })

  it("uses helperText and an option that only has a value", () => {
    const html = renderCatalogField({
      name: "mode",
      control: "select",
      helperText: "pick one",
      options: [{ value: "solo" }, {}],
    }, "solo", { labels })
    expect(html).toContain("pick one")
    expect(html).toContain('<option value="solo" selected>solo</option>')
  })

  it("stringifies an object in a plain textarea via displayValue", () => {
    const html = renderCatalogField({ name: "notes", control: "textarea" }, { a: 1 }, { labels })
    expect(html).toContain("&quot;a&quot;")
  })

  it("uses the built-in Default: format and an empty number placeholder", () => {
    const withDefault = renderCatalogField({
      name: "maxIterations",
      control: "number",
      default: 100,
    }, undefined, {})
    expect(withDefault).toContain('placeholder="Default: 100"')

    const empty = renderCatalogField({ name: "n", control: "number" }, 1, { labels })
    expect(empty).toContain('placeholder=""')
  })

  it("covers variable-picker textarea row counts for code and multiline text", () => {
    const code = renderCatalogField({
      name: "expr",
      type: "text",
      control: "code",
      variablePicker: true,
    }, "x", { elementId: "p1", labels })
    expect(code).toContain("rows=\"3\"")

    const multiline = renderCatalogField({
      name: "body",
      control: "text",
      multiline: true,
      variablePicker: true,
    }, "y", { elementId: "p1", labels })
    expect(multiline).toContain("rows=\"2\"")
  })

  it("renders a select with no options, a null value, and a null option value", () => {
    const empty = renderCatalogField({ name: "mode", control: "select" }, null, { labels })
    expect(empty).toContain("<select")
    expect(empty).toContain('<option value="" selected>None</option>')

    const nullOpt = renderCatalogField({
      name: "mode",
      control: "select",
      options: [{ value: null }],
    }, null, { labels })
    expect(nullOpt).toContain("<select")
  })

  it("falls back to text when an attribute picker has no entityAttributes list", () => {
    const html = renderCatalogField({
      name: "column",
      type: "attribute_picker",
    }, "x", { labels })
    expect(html).toContain('type="text"')
    expect(html).not.toContain("data-entity-column-select")
  })
})

describe("fieldControlsVisibility", () => {
  it("detects catalog object-form and legacy visibleWhen / requiredWhen drivers", () => {
    expect(fieldControlsVisibility("loopType", [
      { name: "collection", visibleWhen: { loopType: "for_each" } },
    ])).toBe(true)
    expect(fieldControlsVisibility("responseType", [
      { name: "returnValue", requiredWhen: { field: "responseType", value: "value" } },
    ])).toBe(true)
    expect(fieldControlsVisibility("loopType", [{ name: "x" }])).toBe(false)
    expect(fieldControlsVisibility("loopType", [])).toBe(false)
  })
})

describe("re-exported helpers", () => {
  it("exposes configFieldKey, configFieldType, and matchesWhen", () => {
    expect(configFieldKey({ name: "a" })).toBe("a")
    expect(configFieldType({ control: "number" })).toBe("number")
    expect(matchesWhen({ loopType: "while" }, { loopType: "while" })).toBe(true)
    expect(matchesWhen({ field: "loopType", value: "while" }, { loopType: "for_each" })).toBe(false)
  })
})
