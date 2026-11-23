import { describe, it, expect } from "vitest"
import { buildLocalizedTextField, collectLocalizedText } from "controllers/property_editor/controls/localized_text"

describe("buildLocalizedTextField", () => {
  it("renders en + zh-CN tabs and seeds a hash or a string", () => {
    const hash = buildLocalizedTextField({ name: "title" }, { en: "Hello", "zh-CN": "你好" })
    expect(hash).toContain('data-locale-tab="en"')
    expect(hash).toContain('data-locale-tab="zh-CN"')
    expect(hash).toContain('value="Hello"')
    expect(hash).toContain('value="你好"')
    expect(hash).toContain('aria-selected="true"')

    const fromString = buildLocalizedTextField({ name: "title", required: true }, "Plain")
    expect(fromString).toContain('value="Plain"')
    expect(fromString).toContain(" required")

    const empty = buildLocalizedTextField({ name: "title" }, null)
    expect(empty).toContain('data-locale-input')
    expect(buildLocalizedTextField({ name: "title" }, [])).toContain('data-locale-input')
  })

  it("reads a zh_CN underscore key as the Chinese value", () => {
    const html = buildLocalizedTextField({ name: "title" }, { zh_CN: "嗨" })
    expect(html).toContain('value="嗨"')
  })
})

describe("collectLocalizedText", () => {
  it("keeps only filled locales", () => {
    document.body.innerHTML = `
      <div data-localized-text>
        <input data-locale-input data-locale="en" value="  Hi ">
        <input data-locale-input data-locale="zh-CN" value="  ">
      </div>`
    expect(collectLocalizedText(document.querySelector("[data-localized-text]"))).toEqual({ en: "Hi" })
  })
})
