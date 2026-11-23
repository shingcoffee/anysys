import { describe, it, expect } from "vitest"
import { FieldManager } from "controllers/page_builder/field_manager"
import { makeCtrl, field } from "../../../support/page_builder.js"

// LayoutCardsMixin methods are pure HTML string builders.
const fm = new FieldManager(makeCtrl())
const lf = (field_type, attrs = {}) => field({ field_type, property_type: "layout", ...attrs })

describe("LayoutCardsMixin.createLayoutCardHtml routing", () => {
  it.each([
    ["section", "Section"],
    ["divider", "border-t-2"],
    ["heading", "Heading"],
    ["paragraph", "Paragraph"],
    ["spacer", "Spacer"],
    ["alert", "Alert"],
    ["image", "Image"],
    ["callout", "Callout"],
    ["quote", "Quote"],
    ["button", "Button"],
    ["video", "Video"],
    ["list", "List"],
    ["code_block", "Code"],
    ["card", "Card"],
    ["progress_bar", "Progress"],
    ["columns", "Columns"],
  ])("renders a %s card", (type, marker) => {
    const html = fm.createLayoutCardHtml(lf(type))
    expect(html).toContain(marker)
  })

  it("falls back to a section card for unknown/undefined layout types", () => {
    expect(fm.createLayoutCardHtml(lf("nonsense"))).toContain("Section")
    expect(fm.createLayoutCardHtml(field({ property_type: "layout" }))).toContain("Section")
  })

  it("defaults the routed type to `section` when field_type is absent (raw object, bypassing the field() factory default)", () => {
    // field() always fills in field_type: "text"; only a raw object with no
    // key at all exercises the `field.field_type || "section"` fallback.
    expect(fm.createLayoutCardHtml({ property_type: "layout" })).toContain("Section")
  })
})

describe("LayoutCardsMixin card specifics", () => {
  it("heading card reflects the heading level", () => {
    expect(fm.createHeadingCardHtml(lf("heading", { heading_level: "h2" }))).toContain("H2 Heading")
  })

  it("heading card falls back to text-sm for an unmapped heading level", () => {
    expect(fm.createHeadingCardHtml(lf("heading", { heading_level: "h5" }))).toContain("text-sm")
  })

  it("heading card prefers content over label, and falls back to placeholder text with neither", () => {
    expect(fm.createHeadingCardHtml(lf("heading", { content: "Custom heading" }))).toContain("Custom heading")
    // Raw object (bypasses field()'s label: "Field" default) to reach the final "Heading Text" fallback.
    expect(fm.createHeadingCardHtml({ property_type: "layout", field_type: "heading" })).toContain("Heading Text")
  })

  it("section card falls back to a placeholder title without a label, and renders content when present", () => {
    expect(fm.createSectionCardHtml({ property_type: "layout", field_type: "section" })).toContain("Section Title")
    expect(fm.createSectionCardHtml(lf("section", { content: "Section description" }))).toContain("Section description")
  })

  it("alert card picks styling per variant", () => {
    expect(fm.createAlertCardHtml(lf("alert", { alert_variant: "danger" }))).toContain("bg-red-50")
    expect(fm.createAlertCardHtml(lf("alert", { alert_variant: "bogus" }))).toContain("bg-blue-50") // info default
  })

  it("progress bar clamps its value between 0 and 100", () => {
    expect(fm.createProgressBarCardHtml(lf("progress_bar", { progress_value: 250 }))).toContain("width: 100%")
    expect(fm.createProgressBarCardHtml(lf("progress_bar", { progress_value: -20 }))).toContain("width: 0%")
  })

  it("progress bar falls back to a placeholder label without one", () => {
    expect(fm.createProgressBarCardHtml({ property_type: "layout", field_type: "progress_bar" })).toContain(">Progress<")
  })

  it("button card reflects variant + size in the header label", () => {
    expect(fm.createButtonCardHtml(lf("button", { button_variant: "outline", button_size: "lg" }))).toContain("Button (outline/lg)")
  })

  it("button card falls back to primary/md styles for unmapped variant/size, and honours an aligned/labelled/content-less field", () => {
    const html = fm.createButtonCardHtml(lf("button", { button_variant: "bogus", button_size: "bogus", alignment: "center" }))
    expect(html).toContain("text-center")
    expect(html).toContain("bg-indigo-600 text-white") // primary fallback
    expect(html).toContain("px-3 py-1 text-xs") // md fallback
  })

  it("button card prefers content over label, and falls back to Click Me with neither", () => {
    expect(fm.createButtonCardHtml(lf("button", { content: "Submit now" }))).toContain("Submit now")
    expect(fm.createButtonCardHtml({ property_type: "layout", field_type: "button" })).toContain("Click Me")
  })

  it("image card shows a placeholder without a url, and an <img> with one", () => {
    expect(fm.createImageCardHtml(lf("image", { image_url: "" }))).toContain("border-dashed")
    expect(fm.createImageCardHtml(lf("image", { image_url: "http://x/y.png" }))).toContain("<img")
  })

  it("video card shows a placeholder without a url, and a preview with the url shown", () => {
    expect(fm.createVideoCardHtml(lf("video", { video_url: "" }))).toContain("border-dashed")
    const html = fm.createVideoCardHtml(lf("video", { video_url: "http://x/clip.mp4" }))
    expect(html).toContain("http://x/clip.mp4")
    expect(html).not.toContain("border-dashed")
  })

  it("quote card renders an attribution line when present", () => {
    expect(fm.createQuoteCardHtml(lf("quote"))).not.toContain("&mdash;")
    expect(fm.createQuoteCardHtml(lf("quote", { attribution: "Jane Doe" }))).toContain("Jane Doe")
  })

  it("card-card falls back to a placeholder title without a label, and renders content when present", () => {
    expect(fm.createCardCardHtml({ property_type: "layout", field_type: "card" })).toContain("Card Title")
    expect(fm.createCardCardHtml(lf("card", { content: "Card body" }))).toContain("Card body")
  })

  it("code block shows the language tag only when one is set", () => {
    expect(fm.createCodeBlockCardHtml(lf("code_block"))).toContain(">Code<")
    expect(fm.createCodeBlockCardHtml(lf("code_block", { code_language: "ruby" }))).toContain("Code (ruby)")
  })

  it("list card renders up to three items with the right tag", () => {
    const html = fm.createListCardHtml(lf("list", { list_style: "numbered", content: "a\nb\nc\nd" }))
    expect(html).toContain("<ol")
    expect((html.match(/<li/g) || []).length).toBe(3)
  })

  it("list card falls back to a plain list for an unrecognised style, and labels it Bullet when unmapped", () => {
    const html = fm.createListCardHtml(lf("list", { list_style: "none" }))
    expect(html).toContain("<ul")
    expect(html).not.toContain("list-disc")
    expect(html).not.toContain("list-decimal")
    // list_style "weird" isn't in styleLabels either → falls back to "Bullet" in the header.
    expect(fm.createListCardHtml(lf("list", { list_style: "weird" }))).toContain("List (Bullet)")
  })

  it("columns card renders per-column drop containers with parent/index datasets", () => {
    const html = fm.createColumnsCardHtml(
      lf("columns", { id: "cols", column_layout: "66-33", columns: [{ fields: [field({ id: "c1", label: "One" })] }, { fields: [] }] })
    )
    expect(html).toContain('data-parent-field-id="cols"')
    expect(html).toContain('data-column-index="0"')
    expect(html).toContain("col-span-2") // 66-33 → [2,1]
    expect(html).toContain("Drop fields here") // empty second column
  })

  it("columns card defaults layout/grid/spans for an unrecognised layout and a column with no `fields` key", () => {
    const html = fm.createColumnsCardHtml(
      lf("columns", { id: "cols", column_layout: "weird-layout", columns: [{}] })
    )
    expect(html).toContain("grid-cols-2") // gridClasses fallback
    expect(html).toContain("Columns (weird-layout)") // layoutLabels fallback → raw layout string
    expect(html).not.toContain("col-span-") // no colSpanMap entry → spanClass ""
    expect(html).toContain("Drop fields here") // col.fields || [] fallback
  })

  it("columns card falls back to the field_type when a child field has no label", () => {
    const html = fm.createColumnsCardHtml(
      lf("columns", { id: "cols", columns: [{ fields: [{ id: "c1", field_type: "text" }] }] })
    )
    expect(html).toMatch(/>\s*text\s*</)
  })

  it("escapes user content in cards (XSS safety)", () => {
    const html = fm.createParagraphCardHtml(lf("paragraph", { content: "<script>evil()</script>" }))
    expect(html).not.toContain("<script>evil")
    expect(html).toContain("&lt;script&gt;")
  })
})

describe("LayoutCardsMixin.cardActionButtons", () => {
  it("wires duplicate + delete actions to the field id", () => {
    const html = fm.cardActionButtons(field({ id: "f9" }))
    expect(html).toContain("page-builder#duplicateFieldFromCard")
    expect(html).toContain("page-builder#removeFieldFromCard")
    expect(html).toContain('data-field-id="f9"')
  })
})
