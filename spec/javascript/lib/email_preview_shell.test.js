import { describe, it, expect } from "vitest"
import { wrapEmailPreviewHtml } from "lib/email_preview_shell"

describe("wrapEmailPreviewHtml", () => {
  it("wraps a fragment in a full HTML document with base styles", () => {
    const result = wrapEmailPreviewHtml("<p>Hi</p>")
    expect(result).toContain("<!DOCTYPE html>")
    expect(result).toContain("<body><p>Hi</p></body>")
    expect(result).toContain("font-family:")
    expect(result).toContain("img { max-width: 100%")
  })

  it("treats blank input as an empty body", () => {
    expect(wrapEmailPreviewHtml("")).toContain("<body></body>")
    expect(wrapEmailPreviewHtml(null)).toContain("<body></body>")
  })
})
