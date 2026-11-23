import { describe, it, expect, afterEach, vi } from "vitest"
import { primeAllStepPins } from "controllers/property_editor/step_io/io_params_client"
import { primeAllElementPins, refreshElementPins } from "controllers/property_editor/element_io/io_params_client"
import { applyFlowchartUrls, clearFlowchartUrls } from "../../../support/flowchart_urls.js"
import { mountEditor, change, sync } from "./_support.js"

const PIN_URLS = {
  stepIoParams: "/81721200/admin/maintenance/flowcharts/step_actions/__ACTION__/io_params",
  elementIoParams: "/81721200/admin/maintenance/flowcharts/element_types/__TYPE__/io_params",
}

let editor
afterEach(async () => {
  await editor?.dispose()
  editor = null
  clearFlowchartUrls()
  vi.unstubAllGlobals()
  window.history.replaceState({}, "", "/")
})

describe("pin extraction request ownership", () => {
  it.each(["step", "element"])("coalesces identical %s bulk/refresh requests and permits later refreshes", async kind => {
    editor = await mountEditor("process", { steps: [{ id: "lookup", action: "find_model" }] })
    applyFlowchartUrls(PIN_URLS)
    window.history.replaceState({}, "", "/81721200/admin/maintenance/flowcharts/1/edit")
    const responses = []
    vi.stubGlobal("fetch", vi.fn(() => new Promise(resolve => responses.push(resolve))))
    const { canvas, node } = editor
    const bulk = () => kind === "step" ? primeAllStepPins(canvas) : primeAllElementPins(canvas)
    const refresh = () => kind === "step" ? primeAllStepPins(canvas) : refreshElementPins(canvas, node.id)
    const jobs = [bulk(), refresh()]
    expect(responses).toHaveLength(1)
    responses[0](new Response(JSON.stringify({ inputs: [], outputs: [{ pin: "model" }] })))
    await Promise.all(jobs)
    const next = refresh()
    expect(responses).toHaveLength(2)
    responses[1](new Response(JSON.stringify({ inputs: [], outputs: [] })))
    await next
    expect((kind === "step" ? canvas.getStepPins("lookup") : canvas.getElementPins(node.id)).outputs).toEqual([])
  })

  it.each(["pane", "background"])("shares identical in-flight config when %s starts first, rendering without reopening", async first => {
    editor = await mountEditor("process")
    applyFlowchartUrls(PIN_URLS)
    window.history.replaceState({}, "", "/81721200/admin/maintenance/flowcharts/1/edit")
    const responses = []
    vi.stubGlobal("fetch", () => new Promise(resolve => responses.push(resolve)))
    const { controller, canvas, node } = editor
    const pane = controller.formFieldsIoTarget
    const open = () => controller.elementIoManager.openForElement(node, pane)
    const refresh = () => refreshElementPins(canvas, node.id)
    const jobs = first === "pane" ? [open(), refresh()] : [refresh(), open()]
    jobs.push(open()) // repeated tab activation replaces, rather than duplicates, the subscription
    expect(responses).toHaveLength(1)
    responses[0](new Response(JSON.stringify({ inputs: [], outputs: [{ pin: "fresh" }] })))
    await Promise.all(jobs)
    expect(canvas.getElementPins(node.id).outputs).toEqual([{ pin: "fresh" }])
    expect(pane.textContent).toContain("fresh")
    expect(pane.textContent).not.toContain("obsolete")
  })

  it.each(["old", "fresh"])("hands a changed-config background result to the active pane (%s responds first)", async first => {
    editor = await mountEditor("process")
    applyFlowchartUrls(PIN_URLS)
    window.history.replaceState({}, "", "/81721200/admin/maintenance/flowcharts/1/edit")
    const responses = []
    vi.stubGlobal("fetch", () => new Promise(resolve => responses.push(resolve)))
    const { controller, canvas, node } = editor
    const pane = controller.formFieldsIoTarget
    const old = controller.elementIoManager.openForElement(node, pane)
    node.properties.steps = [{ id: "new", action: "find_model" }]
    const fresh = refreshElementPins(canvas, node.id)
    const finishOld = async () => { responses[0](new Response(JSON.stringify({ inputs: [], outputs: [{ pin: "obsolete" }] }))); await old }
    const finishFresh = async () => { responses[1](new Response(JSON.stringify({ inputs: [], outputs: [{ pin: "model" }] }))); await fresh }
    if (first === "old") {
      await finishOld()
      expect(pane.textContent).not.toContain("obsolete")
      await finishFresh()
    } else {
      await finishFresh()
      // The winning result must appear while the obsolete request is pending.
      expect(pane.textContent).toContain("model")
      await finishOld()
    }
    expect(pane.textContent).toContain("model")
    expect(pane.textContent).not.toContain("obsolete")
    expect(responses).toHaveLength(2)
  })

  it("renders subsequent background refreshes from a populated cache without fetching again for the pane", async () => {
    editor = await mountEditor("process")
    const { controller, canvas, node } = editor
    canvas.setElementPins(node.id, { inputs: [], outputs: [{ pin: "before" }] })
    const pane = controller.formFieldsIoTarget
    await controller.elementIoManager.openForElement(node, pane)
    applyFlowchartUrls(PIN_URLS)
    window.history.replaceState({}, "", "/81721200/admin/maintenance/flowcharts/1/edit")
    const fetch = vi.fn().mockResolvedValue(new Response(JSON.stringify({ inputs: [], outputs: [{ pin: "after" }] })))
    vi.stubGlobal("fetch", fetch)
    await refreshElementPins(canvas, node.id)
    expect(pane.textContent).toContain("after")
    expect(pane.textContent).not.toContain("before")
    expect(fetch).toHaveBeenCalledTimes(1)
  })

  it.each(["step", "element"])("discards %s pins after config changes without a second request", async kind => {
    editor = await mountEditor("process", { steps: [{ id: "changed", action: "find_model" }] })
    applyFlowchartUrls(PIN_URLS)
    window.history.replaceState({}, "", "/81721200/admin/maintenance/flowcharts/1/edit")
    let respond
    vi.stubGlobal("fetch", () => new Promise(resolve => { respond = resolve }))
    const { canvas, node } = editor
    const pending = kind === "step" ? primeAllStepPins(canvas) : refreshElementPins(canvas, node.id)
    node.properties.steps[0].action = "save_model"
    respond(new Response(JSON.stringify({ inputs: [], outputs: [{ pin: "obsolete" }] })))
    await pending
    const pins = kind === "step" ? canvas.getStepPins("changed") : canvas.getElementPins(node.id)
    expect(pins.outputs).toEqual([])
  })

  it.each(["step", "element"])("does not let an older %s response replace pins from edited config", async kind => {
    editor = await mountEditor("process", { steps: [{ id: "lookup", action: "find_model", config: { resultVar: "old_model" } }] })
    applyFlowchartUrls(PIN_URLS)
    window.history.replaceState({}, "", "/81721200/admin/maintenance/flowcharts/1/edit")
    const responses = []
    vi.stubGlobal("fetch", () => new Promise(resolve => responses.push(resolve)))
    const { canvas, node } = editor
    const old = kind === "step" ? primeAllStepPins(canvas) : primeAllElementPins(canvas)
    await change(editor.controller.formTarget.querySelector('[data-config-input="resultVar"]'), "new_model")
    sync(editor)
    const fresh = kind === "step" ? primeAllStepPins(canvas) : refreshElementPins(canvas, node.id)
    responses[1](new Response(JSON.stringify({ inputs: [], outputs: [{ pin: "new_model" }] })))
    await fresh
    responses[0](new Response(JSON.stringify({ inputs: [], outputs: [{ pin: "old_model" }] })))
    await old
    const pins = kind === "step" ? canvas.getStepPins("lookup") : canvas.getElementPins(node.id)
    expect(pins.outputs).toEqual([{ pin: "new_model" }])
  })

  it.each(["step", "element"])("does not cache a %s response after its record is removed", async kind => {
    editor = await mountEditor("process", { steps: [{ id: "removed", action: "find_model" }] })
    applyFlowchartUrls(PIN_URLS)
    window.history.replaceState({}, "", "/81721200/admin/maintenance/flowcharts/1/edit")
    let respond
    vi.stubGlobal("fetch", () => new Promise(resolve => { respond = resolve }))
    const { canvas, node } = editor
    const pending = kind === "step" ? primeAllStepPins(canvas) : refreshElementPins(canvas, node.id)
    canvas.elements = []
    respond(new Response(JSON.stringify({ inputs: [], outputs: [{ pin: "obsolete" }] })))
    await pending
    const pins = kind === "step" ? canvas.getStepPins("removed") : canvas.getElementPins(node.id)
    expect(pins.outputs).toEqual([])
  })
})
