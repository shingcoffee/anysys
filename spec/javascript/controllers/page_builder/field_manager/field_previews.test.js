import { describe, it, expect } from "vitest"
import { FieldManager } from "controllers/page_builder/field_manager"
import { makeCtrl, field } from "../../../support/page_builder.js"

// FieldPreviewsMixin methods are pure string builders (they use escapeHtml from
// BaseManager), so a bare FieldManager instance is enough.
const fm = new FieldManager(makeCtrl())
const dataField = (attrs) => field({ property_type: "string", ...attrs })

describe("FieldPreviewsMixin._fieldIconStyle", () => {
  it.each([
    ["email", "bg-blue-100"],
    ["select", "bg-purple-100"],
    ["number", "bg-amber-100"],
    ["date", "bg-green-100"],
    ["file", "bg-pink-100"],
    ["textarea", "bg-teal-100"],
    ["unknownthing", "bg-gray-100"],
  ])("maps html_type %s to %s background", (ht, bg) => {
    expect(fm._fieldIconStyle({ html_type: ht }).bg).toBe(bg)
  })

  it("defaults html_type to empty string when absent (the `|| \"\"` fallback)", () => {
    expect(fm._fieldIconStyle({}).bg).toBe("bg-gray-100")
  })
})

describe("FieldPreviewsMixin._themeClasses", () => {
  it("maps theme config onto Tailwind classes with defaults", () => {
    expect(fm._themeClasses({})).toMatchObject({
      radius: "rounded-lg", size: "py-1.5 px-3 text-sm", style: "border border-gray-300 bg-white", primaryColor: "indigo",
    })
    expect(fm._themeClasses({ border_radius: "full", input_size: "lg", input_style: "filled" })).toMatchObject({
      radius: "rounded-full", size: "py-2 px-4 text-base", style: "border border-transparent bg-gray-100",
    })
  })
})

describe("FieldPreviewsMixin accent helpers", () => {
  it("resolve the themed accent tokens with an indigo default", () => {
    expect(fm._accentBg({ primary_color: "rose" })).toBe("bg-rose-500")
    expect(fm._accentBorder({})).toBe("border-indigo-500")
    expect(fm._accentText({ primary_color: "teal" })).toBe("text-teal-600")
    expect(fm._accentBgLight({ primary_color: "amber" })).toBe("bg-amber-50")
    expect(fm._accentRing(null)).toBe("ring-indigo-200")
  })

  it.each([
    ["_accentBg", "bg-indigo-500"],
    ["_accentBorder", "border-indigo-500"],
    ["_accentText", "text-indigo-600"],
    ["_accentBgLight", "bg-indigo-50"],
    ["_accentRing", "ring-indigo-200"],
  ])("%s falls back to the indigo default for a falsy theme (short-circuits `theme && …`)", (method, expected) => {
    expect(fm[method](null)).toBe(expected)
    expect(fm[method](undefined)).toBe(expected)
  })

  it.each([
    ["_accentBg", "bg-indigo-500"],
    ["_accentBorder", "border-indigo-500"],
    ["_accentText", "text-indigo-600"],
    ["_accentBgLight", "bg-indigo-50"],
    ["_accentRing", "ring-indigo-200"],
  ])("%s falls back to the indigo default for an unmapped primary_color", (method, expected) => {
    expect(fm[method]({ primary_color: "mystery" })).toBe(expected)
  })
})

describe("FieldPreviewsMixin.getFieldPreviewHtml", () => {
  it("returns empty string for layout fields", () => {
    expect(fm.getFieldPreviewHtml({ property_type: "layout" }, {})).toBe("")
  })

  it.each([
    ["search", "M21 21l-6-6"], // leading search icon svg path
    ["hidden", "Hidden field"],
    ["textarea", "min-h-[2.5rem]"],
    ["rich-text", "font-bold text-gray-500"],
    ["email", "you@example.com"],
    ["tel", "+1 (555) 000-0000"],
    ["url", "https://example.com"],
    ["multi-select", "Option 1"],
    ["switch", "Enabled"],
    ["number", 'text-gray-400">0<'],
    ["currency", "0.00"],
    ["range", "calc(50%"],
    ["date", "yyyy-mm-dd"],
    ["time", "HH:MM"],
    ["datetime-local", "yyyy-mm-dd HH:MM"],
    ["month", "yyyy-MM"],
    ["week", "yyyy-W##"],
    ["file", "Drop file or click to upload"],
    ["image", "Click to upload image"],
    ["color", "#6366f1"],
    ["signature", "Sign here"],
  ])("renders a %s preview", (ht, marker) => {
    const html = fm.getFieldPreviewHtml(dataField({ html_type: ht }), {})
    expect(html).toContain(marker)
  })

  it("falls back to field_type when html_type is absent", () => {
    // Raw object (no html_type key at all) with a recognised field_type.
    const html = fm.getFieldPreviewHtml({ property_type: "string", field_type: "hidden", label: "X" }, {})
    expect(html).toContain("Hidden field")
  })

  it("falls back to the generic text input when neither html_type nor field_type is set", () => {
    const html = fm.getFieldPreviewHtml({ property_type: "string", label: "X" }, {})
    expect(html).toContain("pointer-events-none")
  })

  it("uses the caller's theme (`theme || {}` truthy branch) and defaults when no theme is passed", () => {
    expect(() => fm.getFieldPreviewHtml(dataField({ html_type: "text" }))).not.toThrow()
    const html = fm.getFieldPreviewHtml(dataField({ html_type: "text" }))
    expect(html).toContain("pointer-events-none")
  })

  it("builds a lowercase placeholder from the label when none is set, and falls back to 'value' without a label", () => {
    expect(fm.getFieldPreviewHtml({ property_type: "string", html_type: "text", label: "First Name" }, {})).toContain("Enter first name")
    expect(fm.getFieldPreviewHtml({ property_type: "string", html_type: "text" }, {})).toContain("Enter value")
  })

  it("renders more than 3 rating stars with the unfilled (>= 3) color for the tail", () => {
    const html = fm.getFieldPreviewHtml(dataField({ html_type: "rating", max_rating: "5" }), {})
    expect(html).toContain("text-gray-300") // stars beyond the 3-filled default
  })

  it("_previewInput falls back to an empty placeholder and renders without a leading icon", () => {
    const html = fm._previewInput(dataField({}), {}, undefined)
    expect(html).toContain('<span class="truncate"></span>')
    expect(html).not.toContain("flex-shrink-0 text-gray-400 mr-2")
  })

  it("renders a password preview with masked dots", () => {
    const html = fm.getFieldPreviewHtml(dataField({ html_type: "password" }), {})
    expect(html).toContain("&bull;")
  })

  it("renders a select preview with placeholder + chevron", () => {
    const html = fm.getFieldPreviewHtml(dataField({ html_type: "select", label: "Country" }), {})
    expect(html).toContain("Select country")
  })

  it("select uses an explicit placeholder when provided (`field.placeholder` truthy branch)", () => {
    const html = fm.getFieldPreviewHtml(dataField({ html_type: "select", placeholder: "Pick one" }), {})
    expect(html).toContain("Pick one")
  })

  it("select falls back to 'option' when neither placeholder nor label is set", () => {
    const html = fm.getFieldPreviewHtml(dataField({ html_type: "select", label: "" }), {})
    expect(html).toContain("Select option")
  })

  it("rating defaults to 5 stars when max_rating is absent (`|| 5` branch)", () => {
    const html = fm.getFieldPreviewHtml(dataField({ html_type: "rating" }), {})
    expect((html.match(/<svg/g) || []).length).toBe(5)
  })

  it("renders radio options, defaulting to two", () => {
    const html = fm.getFieldPreviewHtml(dataField({ html_type: "radio" }), {})
    expect((html.match(/<label/g) || []).length).toBe(2)
  })

  it("uses provided options when present", () => {
    const html = fm.getFieldPreviewHtml(dataField({ html_type: "checkbox", options: [{ label: "Yes" }, { label: "No" }, { label: "Maybe" }] }), {})
    expect((html.match(/<label/g) || []).length).toBe(3)
    expect(html).toContain("Maybe")
  })

  it("checkbox defaults to two options when none are provided", () => {
    const html = fm.getFieldPreviewHtml(dataField({ html_type: "checkbox" }), {})
    expect((html.match(/<label/g) || []).length).toBe(2)
  })

  it("radio uses provided options when present (non-empty options branch)", () => {
    const html = fm.getFieldPreviewHtml(dataField({ html_type: "radio", options: [{ label: "A" }, { label: "B" }, { label: "C" }] }), {})
    expect((html.match(/<label/g) || []).length).toBe(3)
  })

  it.each(["radio", "checkbox"])("%s treats an empty options array as absent (falls back to the two defaults)", (ht) => {
    const html = fm.getFieldPreviewHtml(dataField({ html_type: ht, options: [] }), {})
    expect((html.match(/<label/g) || []).length).toBe(2)
    expect(html).toContain("Option 1")
  })

  it.each(["radio", "checkbox"])("%s option label falls back to value, then to an indexed placeholder", (ht) => {
    const html = fm.getFieldPreviewHtml(
      dataField({ html_type: ht, options: [{ value: "opt-val" }, {}] }),
      {}
    )
    expect(html).toContain("opt-val")   // opt.label absent → opt.value
    expect(html).toContain("Option 2")  // both absent → indexed placeholder
  })

  it("renders the requested number of rating stars", () => {
    const html = fm.getFieldPreviewHtml(dataField({ html_type: "rating", max_rating: "3" }), {})
    expect((html.match(/<svg/g) || []).length).toBe(3)
  })

  it("falls back to a generic text input for unknown html types", () => {
    const html = fm.getFieldPreviewHtml(dataField({ html_type: "somethingelse", label: "X" }), {})
    expect(html).toContain("pointer-events-none")
  })

  it("escapes hostile placeholder text (no raw script injection)", () => {
    const html = fm.getFieldPreviewHtml(dataField({ html_type: "text", placeholder: "<img src=x onerror=alert(1)>" }), {})
    expect(html).not.toContain("<img src=x")
    // The generic-input path escapes the placeholder twice (once in
    // getFieldPreviewHtml, once in _previewInput), so `<` ends up as `&amp;lt;`.
    expect(html).toContain("&amp;lt;img")
  })
})
