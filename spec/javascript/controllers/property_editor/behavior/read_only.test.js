import { describe, it, expect, afterEach, vi } from "vitest"
import { mountEditor, change, sync } from "./_support.js"
import { tick } from "../../../support/stimulus.js"
import { applyFlowchartUrls, clearFlowchartUrls } from "../../../support/flowchart_urls.js"

const PIN_URLS = {
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

function producers() {
  const { canvas, node } = editor
  canvas.elements.unshift(
    { id: "producer-a", type: "process", label: "First", properties: {} },
    { id: "producer-b", type: "process", label: "Second", properties: { io_overrides: { outputs: [{ pin: "model", renamed_to: "model_abcd" }] } } }
  )
  canvas.connections = [
    { id: "ab", from: "producer-a", to: "producer-b" },
    { id: "bc", from: "producer-b", to: node.id }
  ]
  for (const id of ["producer-a", "producer-b"]) canvas.setElementPins(id, { inputs: [], outputs: [{ pin: "model" }] })
}

describe("launched property editors", () => {
  it.each(["start", "process", "decision", "loop", "subflow", "end"])(
    "%s remains byte-identical on open, queued input, preserve, save and close", async type => {
      editor = await mountEditor(type, {}, { readOnly: true })
      editor.node.label = "" // even auto-label derivation is a mutation
      const before = JSON.stringify(editor.node)
      expect(editor.controller.unsavedChangesCache).toBeUndefined()
      editor.controller.openEditor(editor.node, editor.canvas)
      expect(JSON.stringify(editor.node)).toBe(before)
      await change(editor.field("description"), "synthetic late event")
      sync(editor)
      await editor.controller.save(new Event("submit"))
      editor.controller.close()
      expect(JSON.stringify(editor.node)).toBe(before)
      editor.controller.openEditor(editor.node, editor.canvas)
      expect(JSON.stringify(editor.node)).toBe(before)
    }
  )

  it("disables asynchronously rendered producer controls and refuses both events and direct updates", async () => {
    editor = await mountEditor("process", {}, { readOnly: true })
    producers()
    editor.canvas.setElementPins(editor.node.id, { inputs: [{ pin: "model" }], outputs: [] })
    const before = JSON.stringify(editor.canvas.elements)
    await editor.controller.elementIoManager.openForElement(editor.node, editor.controller.formFieldsIoTarget)
    const select = editor.controller.formFieldsIoTarget.querySelector("select")
    expect(select).not.toBeNull()
    expect(select.disabled).toBe(true)
    await change(select, "model_abcd")
    editor.controller.elementIoManager.updateProducer(editor.node.id, "model", "")
    sync(editor)
    expect(JSON.stringify(editor.canvas.elements)).toBe(before)
  })

  it("checks read-only state after a delayed HTTP pin response, not just when opening", async () => {
    editor = await mountEditor("process")
    producers()
    applyFlowchartUrls(PIN_URLS)
    window.history.replaceState({}, "", "/81721200/admin/maintenance/flowcharts/1/edit")
    let respond
    // Only the external HTTP transport is controlled: pin client, override
    // computation, reachability, rendering, handlers and canvas are real.
    vi.stubGlobal("fetch", () => new Promise(resolve => { respond = resolve }))
    const before = JSON.stringify(editor.node)
    const opening = editor.controller.elementIoManager.openForElement(editor.node, editor.controller.formFieldsIoTarget)
    document.querySelector('[data-controller="flowchart-canvas"]').dataset.flowchartCanvasReadOnlyValue = "true"
    respond(new Response(JSON.stringify({ inputs: [{ pin: "model" }], outputs: [] }), { status: 200 }))
    await opening
    expect(editor.controller.formFieldsIoTarget.querySelector("select").disabled).toBe(true)
    expect(JSON.stringify(editor.node)).toBe(before)
  })

  it("does not let an older response overwrite a closed and reopened I/O session", async () => {
    editor = await mountEditor("process")
    applyFlowchartUrls(PIN_URLS)
    window.history.replaceState({}, "", "/81721200/admin/maintenance/flowcharts/1/edit")
    const responses = []
    vi.stubGlobal("fetch", () => new Promise(resolve => responses.push(resolve)))
    const manager = editor.controller.elementIoManager
    const pane = editor.controller.formFieldsIoTarget
    const old = manager.openForElement(editor.node, pane)
    manager.close()
    editor.node.properties.description = "updated while closed"
    const fresh = manager.openForElement(editor.node, pane)
    responses[1](new Response(JSON.stringify({ inputs: [], outputs: [{ pin: "fresh" }] })))
    await fresh
    responses[0](new Response(JSON.stringify({ inputs: [], outputs: [{ pin: "stale" }] })))
    await old
    expect(pane.textContent).toContain("fresh")
    expect(pane.textContent).not.toContain("stale")
    expect(editor.canvas.getElementPins(editor.node.id).outputs).toEqual([{ pin: "fresh" }])
  })

  it("reopening after Cancel shows the canvas snapshot, not a producer draft", async () => {
    editor = await mountEditor("process")
    producers()
    editor.canvas.setElementPins(editor.node.id, { inputs: [{ pin: "model" }], outputs: [] })
    const beforeInputs = structuredClone(editor.node.properties.io_overrides?.inputs)
    await editor.controller.elementIoManager.openForElement(editor.node, editor.controller.formFieldsIoTarget)
    await tick()
    await change(editor.controller.formFieldsIoTarget.querySelector("select"), "model")
    expect(sync(editor).io_overrides.inputs).toEqual([{ pin: "model", override_key: "model" }])
    editor.controller.cancel({ preventDefault() {} })
    editor.controller.openEditor(editor.node, editor.canvas)
    await tick()
    expect(editor.node.properties.io_overrides?.inputs).toEqual(beforeInputs)
  })
})
