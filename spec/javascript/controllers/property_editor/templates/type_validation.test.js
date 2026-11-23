import { describe, it, expect, beforeEach } from "vitest"
import {
  columnTypeOf,
  looksLikeExpression,
  buildTypeChip,
  upsertTypeChip,
  applySoftTypeValidation,
  wireSoftTypeValidation,
} from "controllers/property_editor/templates/type_validation"

describe("columnTypeOf", () => {
  const schema = [
    { name_slug: "email", type: "string", html_type: "email" },
    { name: "age", type: "integer", html_type: "number" },
    { name_slug: "notype" },
  ]

  it("returns null for blank slug or unknown column", () => {
    expect(columnTypeOf(schema, "")).toBeNull()
    expect(columnTypeOf(schema, "missing")).toBeNull()
    expect(columnTypeOf(null, "email")).toBeNull()
  })

  it("resolves by name_slug or name", () => {
    expect(columnTypeOf(schema, "email")).toEqual({ type: "string", htmlType: "email" })
    expect(columnTypeOf(schema, "age")).toEqual({ type: "integer", htmlType: "number" })
  })

  it("defaults type/htmlType to empty strings when absent", () => {
    expect(columnTypeOf(schema, "notype")).toEqual({ type: "", htmlType: "" })
  })
})

describe("looksLikeExpression", () => {
  it.each([
    "ctx",
    "ctx.foo",
    "ctx[:bar]",
    "{{x}}",
    "$var",
    "a[:b]",
  ])("treats %s as an expression", (v) => {
    expect(looksLikeExpression(v)).toBe(true)
  })

  it.each(["ctx_count", "42", "hello", "", "  "])("treats %s as a literal", (v) => {
    expect(looksLikeExpression(v)).toBe(false)
  })

  it("trims before testing", () => {
    expect(looksLikeExpression("  ctx.foo ")).toBe(true)
  })

  it("coerces null/undefined to empty (not an expression)", () => {
    expect(looksLikeExpression(null)).toBe(false)
    expect(looksLikeExpression(undefined)).toBe(false)
  })
})

describe("buildTypeChip", () => {
  it("returns empty string for falsy htmlType", () => {
    expect(buildTypeChip("")).toBe("")
    expect(buildTypeChip(null)).toBe("")
  })

  it("renders an escaped chip when htmlType present", () => {
    const html = buildTypeChip("number")
    expect(html).toContain("data-type-chip")
    expect(html).toContain(">number</span>")
  })
})

describe("upsertTypeChip", () => {
  let container
  beforeEach(() => {
    container = document.createElement("div")
  })

  it("no-ops on null container", () => {
    expect(() => upsertTypeChip(null, "number")).not.toThrow()
  })

  it("inserts a chip when none exists", () => {
    upsertTypeChip(container, "number")
    const chip = container.querySelector("[data-type-chip]")
    expect(chip).not.toBeNull()
    expect(chip.textContent).toBe("number")
  })

  it("updates the existing chip text in place", () => {
    upsertTypeChip(container, "number")
    upsertTypeChip(container, "email")
    const chips = container.querySelectorAll("[data-type-chip]")
    expect(chips.length).toBe(1)
    expect(chips[0].textContent).toBe("email")
  })

  it("removes the chip when htmlType is empty", () => {
    upsertTypeChip(container, "number")
    upsertTypeChip(container, "")
    expect(container.querySelector("[data-type-chip]")).toBeNull()
  })
})

describe("applySoftTypeValidation", () => {
  const inputWith = (value) => {
    const i = document.createElement("input")
    i.value = value
    return i
  }

  it("no-ops on null input", () => {
    expect(() => applySoftTypeValidation(null, "number")).not.toThrow()
  })

  it("adds the amber hint + title for a non-numeric, non-expression number field", () => {
    const input = inputWith("abc")
    applySoftTypeValidation(input, "number")
    expect(input.classList.contains("ring-amber-300")).toBe(true)
    expect(input.title).toBe("Expected a number or a ctx expression")
  })

  it("does NOT hint numeric literals", () => {
    const input = inputWith("-3.5")
    applySoftTypeValidation(input, "number")
    expect(input.classList.contains("ring-amber-300")).toBe(false)
  })

  it("does NOT hint ctx expressions", () => {
    const input = inputWith("ctx[:score]")
    applySoftTypeValidation(input, "number")
    expect(input.classList.contains("ring-amber-300")).toBe(false)
  })

  it("never hints non-number html types", () => {
    const input = inputWith("abc")
    applySoftTypeValidation(input, "text")
    expect(input.classList.contains("ring-amber-300")).toBe(false)
  })

  it("coerces a nullish input.value to empty string before trimming", () => {
    // A real <input>.value always coerces to a string; drive the ?? fallback
    // with a minimal fake that can actually hold undefined.
    const fake = { value: undefined, title: "", dataset: {}, classList: { toggle: () => {} } }
    expect(() => applySoftTypeValidation(fake, "number")).not.toThrow()
  })

  it("restores an empty original title when none pre-existed", () => {
    const input = inputWith("abc") // title defaults to ""
    applySoftTypeValidation(input, "number")
    expect(input.dataset.softTypeOrigTitle).toBe("")
    input.value = "5"
    applySoftTypeValidation(input, "number")
    expect(input.title).toBe("")
    expect(input.dataset.softTypeOrigTitle).toBeUndefined()
  })

  it("preserves and restores a pre-existing title", () => {
    const input = inputWith("abc")
    input.title = "original"
    applySoftTypeValidation(input, "number")
    expect(input.title).toBe("Expected a number or a ctx expression")
    expect(input.dataset.softTypeOrigTitle).toBe("original")
    // now clear the hint (valid value)
    input.value = "5"
    applySoftTypeValidation(input, "number")
    expect(input.title).toBe("original")
    expect(input.dataset.softTypeOrigTitle).toBeUndefined()
  })

  it("uses an explicitly-passed hintTitle instead of the English-default fallback (i18n seam)", () => {
    // Callers (the shared conditions control, config_fields.js) thread
    // a translated hint through as the 3rd argument so it can be shown
    // without baking locale copy into this module.
    const input = inputWith("abc")
    applySoftTypeValidation(input, "number", "预期为数字或 ctx 表达式")
    expect(input.title).toBe("预期为数字或 ctx 表达式")
  })
})

describe("wireSoftTypeValidation", () => {
  it("no-ops on null input", () => {
    expect(() => wireSoftTypeValidation(null, "number")).not.toThrow()
  })

  it("stores expectedType and applies validation immediately", () => {
    const input = document.createElement("input")
    input.value = "abc"
    wireSoftTypeValidation(input, "number")
    expect(input.dataset.expectedType).toBe("number")
    expect(input.dataset.softTypeWired).toBe("1")
    expect(input.classList.contains("ring-amber-300")).toBe(true)
  })

  it("re-validates on change events using the stored expectedType", () => {
    const input = document.createElement("input")
    input.value = "5"
    wireSoftTypeValidation(input, "number")
    expect(input.classList.contains("ring-amber-300")).toBe(false)
    // user types a bad value and fires change
    input.value = "abc"
    input.dispatchEvent(new Event("change"))
    expect(input.classList.contains("ring-amber-300")).toBe(true)
  })

  it("clears expectedType when htmlType is empty", () => {
    const input = document.createElement("input")
    wireSoftTypeValidation(input, "number")
    wireSoftTypeValidation(input, "")
    expect(input.dataset.expectedType).toBeUndefined()
  })

  it("re-validates using an empty expectedType when the dataset value was cleared", () => {
    const input = document.createElement("input")
    input.value = "abc"
    wireSoftTypeValidation(input, "") // wires the listener with no expected type
    input.dispatchEvent(new Event("change"))
    // htmlType "" never hints, regardless of value.
    expect(input.classList.contains("ring-amber-300")).toBe(false)
  })

  it("wires the change listener at most once", () => {
    const input = document.createElement("input")
    input.value = "5"
    wireSoftTypeValidation(input, "number")
    wireSoftTypeValidation(input, "number")
    // still a single guard flag; second call re-applies but does not double-wire.
    expect(input.dataset.softTypeWired).toBe("1")
  })

  it("threads an explicit hintTitle through to the change listener (i18n seam)", () => {
    const input = document.createElement("input")
    input.value = "5"
    wireSoftTypeValidation(input, "number", "预期为数字或 ctx 表达式")
    input.value = "abc"
    input.dispatchEvent(new Event("change"))
    expect(input.title).toBe("预期为数字或 ctx 表达式")
  })
})
