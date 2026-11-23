import { describe, it, expect } from "vitest"
import { BaseManager, CSS } from "controllers/page_builder/base_manager"

const make = (controller = {}) => new BaseManager(controller)

describe("CSS constants", () => {
  it("exposes a frozen hidden token", () => {
    expect(CSS.hidden).toBe("hidden")
    expect(Object.isFrozen(CSS)).toBe(true)
  })
})

describe("BaseManager wiring", () => {
  it("exposes the controller via `c` and proxies id values", () => {
    const controller = { customerIdValue: "81721200", idValue: "42" }
    const m = make(controller)
    expect(m.c).toBe(controller)
    expect(m.customerIdValue).toBe("81721200")
    expect(m.idValue).toBe("42")
  })
})

describe("escapeHtml", () => {
  const m = make()
  it("escapes HTML-significant characters", () => {
    expect(m.escapeHtml("<script>alert(1)</script>")).toBe(
      "&lt;script&gt;alert(1)&lt;/script&gt;"
    )
    expect(m.escapeHtml("a & b")).toBe("a &amp; b")
  })

  it("returns empty string for null/undefined/empty input", () => {
    expect(m.escapeHtml(null)).toBe("")
    expect(m.escapeHtml(undefined)).toBe("")
    expect(m.escapeHtml("")).toBe("")
  })

  it("passes plain text through unchanged", () => {
    expect(m.escapeHtml("hello world")).toBe("hello world")
  })
})

describe("generateSlug", () => {
  const m = make()
  it("lowercases and collapses non-alphanumerics to single underscores", () => {
    expect(m.generateSlug("First Name")).toBe("first_name")
    expect(m.generateSlug("Email  Address!!")).toBe("email_address")
    expect(m.generateSlug("A/B & C")).toBe("a_b_c")
  })

  it("trims leading and trailing underscores", () => {
    expect(m.generateSlug("  spaced  ")).toBe("spaced")
    expect(m.generateSlug("!!!weird!!!")).toBe("weird")
  })
})

describe("formatLabel", () => {
  const m = make()
  it("capitalizes the first letter and replaces underscores with spaces", () => {
    expect(m.formatLabel("text")).toBe("Text")
    expect(m.formatLabel("rich_text")).toBe("Rich text")
    expect(m.formatLabel("progress_bar")).toBe("Progress bar")
  })
})
