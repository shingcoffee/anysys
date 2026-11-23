import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/activity_trace_controller"
import { mountController, click } from "../support/stimulus.js"

const html = `
  <div data-controller="activity-trace" data-activity-trace-url-value="/run">
    <button data-activity-trace-target="runButton" data-action="click->activity-trace#run">
      <span data-activity-trace-target="buttonText">Run Activity</span>
    </button>
    <div data-activity-trace-target="placeholder">ph</div>
    <div data-activity-trace-target="results" class="hidden">
      <span data-activity-trace-target="status"></span>
      <span data-activity-trace-target="signal"></span>
      <pre data-activity-trace-target="trace"></pre>
      <div data-activity-trace-target="nodes"></div>
      <pre data-activity-trace-target="context"></pre>
    </div>
    <div data-activity-trace-target="error" class="hidden">
      <span data-activity-trace-target="errorMessage"></span>
    </div>
  </div>`

const flush = () => new Promise((r) => setTimeout(r, 0))

describe("activity-trace controller", () => {
  let element

  afterEach(() => {
    vi.restoreAllMocks()
    document.head.innerHTML = ""
  })

  const mount = async () => {
    ;({ element } = await mountController("activity-trace", Controller, html))
  }

  it("posts to the url and renders a successful result", async () => {
    global.fetch = vi.fn().mockResolvedValue({
      json: async () => ({
        success: true,
        signal: "done",
        trace: "step-1",
        trace_nodes: [{ status: "success", label: "A", signal: "ok" }],
        context: { a: 1 },
      }),
    })
    await mount()
    click(element.querySelector("[data-activity-trace-target='runButton']"))
    await flush()

    expect(global.fetch).toHaveBeenCalledWith("/run", expect.objectContaining({ method: "POST" }))
    const status = element.querySelector("[data-activity-trace-target='status']")
    expect(status.textContent).toBe("Success")
    expect(status.className).toContain("bg-green-100")
    expect(element.querySelector("[data-activity-trace-target='signal']").textContent).toBe("Signal: done")
    expect(element.querySelector("[data-activity-trace-target='trace']").textContent).toBe("step-1")
    expect(element.querySelector("[data-activity-trace-target='context']").textContent).toContain('"a": 1')
    // results shown, placeholder/error hidden
    expect(element.querySelector("[data-activity-trace-target='results']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-activity-trace-target='placeholder']").classList.contains("hidden")).toBe(true)
    // node rendered with a label + signal span
    const nodes = element.querySelector("[data-activity-trace-target='nodes']")
    expect(nodes.textContent).toContain("A")
    expect(nodes.textContent).toContain("(ok)")
    expect(nodes.querySelectorAll("svg").length).toBe(1)
    // button restored after finally
    expect(element.querySelector("[data-activity-trace-target='runButton']").disabled).toBe(false)
    expect(element.querySelector("[data-activity-trace-target='buttonText']").textContent).toBe("Run Activity")
  })

  it("renders a failure badge when success is false", async () => {
    global.fetch = vi.fn().mockResolvedValue({
      json: async () => ({ success: false, trace_nodes: [{ status: "error", label: "B", signal: "boom" }] }),
    })
    await mount()
    click(element.querySelector("[data-activity-trace-target='runButton']"))
    await flush()
    const status = element.querySelector("[data-activity-trace-target='status']")
    expect(status.textContent).toBe("Failure")
    expect(status.className).toContain("bg-red-100")
    expect(element.querySelector("[data-activity-trace-target='signal']").textContent).toBe("")
    expect(element.querySelector("[data-activity-trace-target='trace']").textContent).toBe("No trace available")
  })

  it("shows the error panel when the response carries an error field", async () => {
    global.fetch = vi.fn().mockResolvedValue({ json: async () => ({ error: "bad input" }) })
    await mount()
    click(element.querySelector("[data-activity-trace-target='runButton']"))
    await flush()
    expect(element.querySelector("[data-activity-trace-target='error']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-activity-trace-target='errorMessage']").textContent).toBe("bad input")
  })

  it("shows the error panel when fetch rejects", async () => {
    global.fetch = vi.fn().mockRejectedValue(new Error("network down"))
    await mount()
    click(element.querySelector("[data-activity-trace-target='runButton']"))
    await flush()
    expect(element.querySelector("[data-activity-trace-target='errorMessage']").textContent).toBe("network down")
  })

  it("defaults to an empty node list when trace_nodes is absent from the response", async () => {
    global.fetch = vi.fn().mockResolvedValue({ json: async () => ({ success: true }) })
    await mount()
    click(element.querySelector("[data-activity-trace-target='runButton']"))
    await flush()
    const nodes = element.querySelector("[data-activity-trace-target='nodes']")
    expect(nodes.children.length).toBe(0)
  })

  it("reads the CSRF token from the meta tag", async () => {
    const meta = document.createElement("meta")
    meta.name = "csrf-token"
    meta.content = "tok-123"
    document.head.appendChild(meta)
    global.fetch = vi.fn().mockResolvedValue({ json: async () => ({ success: true, trace_nodes: [] }) })
    await mount()
    click(element.querySelector("[data-activity-trace-target='runButton']"))
    await flush()
    const headers = global.fetch.mock.calls[0][1].headers
    expect(headers["X-CSRF-Token"]).toBe("tok-123")
  })
})
