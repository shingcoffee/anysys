import { describe, it, expect } from "vitest"
import {
  buildEmptyState,
  buildSectionHeader,
  buildCompactItem,
} from "controllers/property_editor/templates/common"

describe("buildEmptyState", () => {
  it("renders the escaped message inside a dashed placeholder", () => {
    const html = buildEmptyState("No <items> yet")
    expect(html).toContain("border-dashed")
    expect(html).toContain("No &lt;items&gt; yet")
    // No icon block when iconSvg omitted
    expect(html).not.toContain("flex justify-center mb-2")
  })

  it("includes the icon block (unescaped) when iconSvg provided", () => {
    const html = buildEmptyState("Empty", "<svg data-icon></svg>")
    expect(html).toContain("flex justify-center mb-2")
    expect(html).toContain("<svg data-icon></svg>")
  })

  it("is trimmed (no leading/trailing whitespace)", () => {
    const html = buildEmptyState("x")
    expect(html).toBe(html.trim())
  })
})

describe("buildSectionHeader", () => {
  it("renders label; omits count badge and add button by default", () => {
    const html = buildSectionHeader({ label: "Steps" })
    expect(html).toContain(">Steps<")
    expect(html).not.toContain("data-section-count")
    expect(html).not.toContain("<button")
  })

  it("renders a count badge when count is a number (including 0)", () => {
    expect(buildSectionHeader({ label: "S", count: 3 })).toContain(
      'data-section-count>3</span>'
    )
    // count of 0 is not null → badge still shown
    expect(buildSectionHeader({ label: "S", count: 0 })).toContain(
      'data-section-count>0</span>'
    )
  })

  it("renders an add button carrying the (escaped) data-action", () => {
    const html = buildSectionHeader({
      label: "S",
      addAction: "click->property-editor#add",
    })
    expect(html).toContain('data-action="click-&gt;property-editor#add"')
    expect(html).toContain("title=\"Add\"")
  })

  it("honors a translated addLabel override for the add button title", () => {
    const html = buildSectionHeader({
      label: "S",
      addAction: "click->property-editor#add",
      addLabel: "添加",
    })
    expect(html).toContain('title="添加"')
  })

  it("escapes the label", () => {
    expect(buildSectionHeader({ label: "<x>" })).toContain("&lt;x&gt;")
  })
})

describe("buildCompactItem", () => {
  it("applies the accent color to the border and dot and falls back to blue when unknown", () => {
    const html = buildCompactItem({ accentColor: "amber", title: "T" })
    expect(html).toContain("border-amber-400")
    expect(html).toContain("bg-amber-500")

    const fallback = buildCompactItem({ accentColor: "unknown", title: "T" })
    expect(fallback).toContain("border-blue-400")
    expect(fallback).toContain("bg-blue-500")
  })

  it("escapes the title but injects the *HTML slots raw", () => {
    const html = buildCompactItem({
      accentColor: "indigo",
      title: "<b>T</b>",
      subtitleHTML: "<sub data-x></sub>",
      leadingHTML: "<lead></lead>",
      trailingHTML: "<trail></trail>",
      bodyHTML: "<body-slot></body-slot>",
      hiddenInputsHTML: '<input name="h">',
    })
    expect(html).toContain("&lt;b&gt;T&lt;/b&gt;")
    expect(html).toContain("<sub data-x></sub>")
    expect(html).toContain("<lead></lead>")
    expect(html).toContain("<trail></trail>")
    expect(html).toContain("<body-slot></body-slot>")
    expect(html).toContain('<input name="h">')
  })

  it("passes through extraAttrs / extraClasses / headerAttrs verbatim", () => {
    const html = buildCompactItem({
      accentColor: "blue",
      title: "T",
      extraClasses: "step-expanded",
      extraAttrs: 'data-step-item data-step-index="2"',
      headerAttrs: 'data-action="click->x#y"',
    })
    expect(html).toContain("step-expanded")
    expect(html).toContain('data-step-item data-step-index="2"')
    expect(html).toContain('data-action="click->x#y"')
  })
})
