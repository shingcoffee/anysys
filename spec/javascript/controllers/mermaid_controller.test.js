import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"

// mermaid is a dynamic import in connect(); mock it so no real renderer runs.
const initialize = vi.fn()
const render = vi.fn(async (id) => ({ svg: `<svg data-id='${id}'></svg>` }))
vi.mock("mermaid", () => ({ default: { initialize, render } }))

import Controller from "controllers/mermaid_controller"
import { mountController } from "../support/stimulus.js"

const html = ({ source = "", alternate = "" } = {}) => `
  <div data-controller="mermaid"
       data-mermaid-source-value="${source}"
       data-mermaid-alternate-value="${alternate}">
    <input type="checkbox" data-action="change->mermaid#switch" data-role="switch">
    <div data-mermaid-target="diagram" data-role="diagram"></div>
  </div>`

const q = (el, role) => el.querySelector(`[data-role='${role}']`)
const flush = async () => { for (let i = 0; i < 5; i++) await Promise.resolve(); await new Promise(r => setTimeout(r, 0)) }
const toggle = (el, checked) => {
  const box = q(el, "switch")
  box.checked = checked
  box.dispatchEvent(new Event("change", { bubbles: true }))
}

describe("mermaid controller", () => {
  beforeEach(() => { initialize.mockClear(); render.mockClear() })
  afterEach(() => vi.restoreAllMocks())

  it("initializes mermaid and injects the rendered SVG on connect", async () => {
    const { element } = await mountController("mermaid", Controller, html({ source: "graph TD; A-->B" }))
    await flush()
    expect(initialize).toHaveBeenCalledOnce()
    expect(initialize).toHaveBeenCalledWith(expect.objectContaining({ securityLevel: "strict", theme: "base" }))
    expect(render).toHaveBeenCalledWith(expect.stringMatching(/^mermaid-diagram-\d+$/), "graph TD; A-->B")
    expect(q(element, "diagram").querySelector("svg")).not.toBeNull()
  })

  it("waits for web fonts before the first render", async () => {
    let fontsLoaded
    Object.defineProperty(document, "fonts", {
      configurable: true,
      value: { ready: new Promise(resolve => { fontsLoaded = resolve }) }
    })
    try {
      await mountController("mermaid", Controller, html({ source: "graph TD; A-->B" }))
      await flush()
      expect(render).not.toHaveBeenCalled()

      fontsLoaded()
      await flush()
      expect(render).toHaveBeenCalledOnce()
    } finally {
      delete document.fonts
    }
  })

  it("gives every render its own id", async () => {
    await mountController("mermaid", Controller, html({ source: "graph TD; A-->B" }))
    await flush()
    await mountController("mermaid", Controller, html({ source: "graph TD; C-->D" }))
    await flush()
    const ids = render.mock.calls.map(([id]) => id)
    expect(new Set(ids).size).toBe(ids.length)
  })

  it("switches to the alternate source when checked and back when unchecked", async () => {
    const { element } = await mountController("mermaid", Controller, html({ source: "main", alternate: "with failures" }))
    await flush()

    toggle(element, true)
    await flush()
    expect(render).toHaveBeenLastCalledWith(expect.any(String), "with failures")

    toggle(element, false)
    await flush()
    expect(render).toHaveBeenLastCalledWith(expect.any(String), "main")
    expect(render).toHaveBeenCalledTimes(3)
    expect(initialize).toHaveBeenCalledOnce()
  })

  it("drops a render that finishes after a newer one started", async () => {
    let finishFirst
    render.mockImplementationOnce(() => new Promise(resolve => { finishFirst = resolve }))
    const { element } = await mountController("mermaid", Controller, html({ source: "main", alternate: "alt" }))
    await flush()

    toggle(element, true)
    await flush()
    const latest = q(element, "diagram").innerHTML

    finishFirst({ svg: "<svg data-id='stale'></svg>" })
    await flush()
    expect(q(element, "diagram").innerHTML).toBe(latest)
    expect(q(element, "diagram").innerHTML).not.toContain("stale")
  })

  it("renders an inline error message when mermaid.render rejects", async () => {
    render.mockRejectedValueOnce(new Error("bad syntax"))
    const errSpy = vi.spyOn(console, "error").mockImplementation(() => {})
    const { element } = await mountController("mermaid", Controller, html({ source: "bogus" }))
    await flush()
    expect(q(element, "diagram").innerHTML).toContain("Error rendering diagram: bad syntax")
    expect(errSpy).toHaveBeenCalled()
  })

  it("escapes HTML in mermaid render error messages", async () => {
    render.mockRejectedValueOnce(new Error("<img src=x onerror=alert(1)>"))
    const errSpy = vi.spyOn(console, "error").mockImplementation(() => {})
    const { element } = await mountController("mermaid", Controller, html({ source: "bogus" }))
    await flush()
    expect(q(element, "diagram").querySelector("img")).toBeNull()
    expect(q(element, "diagram").innerHTML).toContain("&lt;img src=x onerror=alert(1)&gt;")
    expect(errSpy).toHaveBeenCalled()
  })

  it("does nothing when there is no source", async () => {
    const { element } = await mountController("mermaid", Controller, html())
    await flush()
    expect(render).not.toHaveBeenCalled()
    expect(initialize).not.toHaveBeenCalled()
    expect(q(element, "diagram").innerHTML).toBe("")
  })
})
