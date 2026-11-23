import { describe, it, expect, vi, afterEach } from "vitest"
import Controller from "controllers/code_editor_controller"
import { mountController, click } from "../support/stimulus.js"

const html = (url = "/validate") => `
  <div data-controller="code-editor" data-code-editor-validate-url-value="${url}">
    <textarea data-code-editor-target="editor">puts 1</textarea>
    <div data-code-editor-target="validationResult" class="hidden"></div>
    <button data-action="click->code-editor#validate">Validate</button>
  </div>`

const flush = () => new Promise((r) => setTimeout(r, 0))
const result = (el) => el.querySelector("[data-code-editor-target='validationResult']")

describe("code-editor controller", () => {
  afterEach(() => {
    vi.restoreAllMocks()
    document.head.innerHTML = ""
  })

  it("sends the CSRF token from the meta tag when present", async () => {
    const meta = document.createElement("meta")
    meta.name = "csrf-token"
    meta.content = "tok-456"
    document.head.appendChild(meta)
    global.fetch = vi.fn().mockResolvedValue({ json: async () => ({ valid: true }) })
    const { element } = await mountController("code-editor", Controller, html())
    click(element.querySelector("button"))
    await flush()
    expect(global.fetch.mock.calls[0][1].headers["X-CSRF-Token"]).toBe("tok-456")
  })

  it("does nothing when no validate URL is configured", async () => {
    global.fetch = vi.fn()
    const { element } = await mountController("code-editor", Controller, html(""))
    click(element.querySelector("button"))
    await flush()
    expect(global.fetch).not.toHaveBeenCalled()
  })

  it("posts the source and renders a success state when valid", async () => {
    global.fetch = vi.fn().mockResolvedValue({ json: async () => ({ valid: true }) })
    const { element } = await mountController("code-editor", Controller, html())
    click(element.querySelector("button"))
    await flush()
    const body = global.fetch.mock.calls[0][1].body
    expect(body.toString()).toBe("methods_body=puts+1")
    expect(result(element).className).toContain("emerald")
    expect(result(element).textContent).toContain("All checks passed")
    expect(result(element).classList.contains("hidden")).toBe(false)
  })

  it("lists errors when validation fails", async () => {
    global.fetch = vi.fn().mockResolvedValue({
      json: async () => ({ valid: false, errors: ["missing end", "bad syntax"] }),
    })
    const { element } = await mountController("code-editor", Controller, html())
    click(element.querySelector("button"))
    await flush()
    expect(result(element).className).toContain("red")
    expect(result(element).textContent).toContain("Validation failed")
    expect(result(element).textContent).toContain("missing end")
    expect(result(element).textContent).toContain("bad syntax")
  })

  it("escapes HTML in validator error strings", async () => {
    const payload = `<img src=x onerror=alert(1)>`
    global.fetch = vi.fn().mockResolvedValue({
      json: async () => ({ valid: false, errors: [`Syntax error: ${payload}`] }),
    })
    const { element } = await mountController("code-editor", Controller, html())
    click(element.querySelector("button"))
    await flush()
    expect(result(element).querySelector("img")).toBeNull()
    expect(result(element).innerHTML).toContain("&lt;img src=x onerror=alert(1)&gt;")
  })

  it("renders a request-failed state when fetch rejects", async () => {
    global.fetch = vi.fn().mockRejectedValue(new Error("boom"))
    const { element } = await mountController("code-editor", Controller, html())
    click(element.querySelector("button"))
    await flush()
    expect(result(element).className).toContain("amber")
    expect(result(element).textContent).toContain("Request failed: boom")
  })

  it("escapes HTML in fetch error messages", async () => {
    global.fetch = vi.fn().mockRejectedValue(new Error("<img src=x onerror=alert(1)>"))
    const { element } = await mountController("code-editor", Controller, html())
    click(element.querySelector("button"))
    await flush()
    expect(result(element).querySelector("img")).toBeNull()
    expect(result(element).innerHTML).toContain("&lt;img src=x onerror=alert(1)&gt;")
  })
})
