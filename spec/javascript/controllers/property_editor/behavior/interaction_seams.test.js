import { describe, it, expect, afterEach, vi } from "vitest"
import { mountEditor, change, press, sync } from "./_support.js"
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

describe("property editor interaction seams", () => {
  it.each([[false], [0]])("preserves a saved %s operand on the shared conditions control", async (value) => {
    const row = { kind: "field", leftOperand: "signal", operator: "==", rightOperand: value }
    editor = await mountEditor("decision", { routeBy: "condition", condition: { type: "group", joins: [], conditions: [row] } })
    const collected = sync(editor).condition
    expect(collected.conditions[0].rightOperand).toBe(String(value))
    await editor.reopen()
    expect(sync(editor).condition).toEqual(collected)
  })

  it.each([[0, false], ["0", "false"]])("preserves key-value values (%s, %s) and syncs row deletion without another edit", async (zero, flag) => {
    editor = await mountEditor("process", { steps: [{ id: "kv", action: "api_call", config: {
      headers: [{ key: "zero", value: zero }, { key: "flag", value: flag }]
    } }] })
    const list = editor.controller.formTarget.querySelector("[data-key-value-list]")
    expect([...list.querySelectorAll("[data-kv-value]")].map(input => input.value)).toEqual(["0", "false"])
    sync(editor)
    await press(list.querySelector('[data-action*="#removeConfigKvRow"]'))
    await vi.waitFor(() => expect(editor.node.properties.steps[0].config.headers).toEqual([{ key: "flag", value: "false" }]))
    await press(list.querySelector('[data-action*="#removeConfigKvRow"]'))
    await vi.waitFor(() => expect(editor.node.properties.steps[0].config).not.toHaveProperty("headers"))
    await editor.reopen()
    expect(editor.controller.stepManager.collectSteps()[0].config).not.toHaveProperty("headers")
  })

  it("restores Save when switching from a read-only editor to an editable editor", async () => {
    editor = await mountEditor("process", {}, { readOnly: true })
    const save = editor.controller.saveButtonTarget
    expect(save.disabled).toBe(true)
    editor.controller.close()
    document.querySelector('[data-controller="flowchart-canvas"]').dataset.flowchartCanvasReadOnlyValue = "false"
    editor.canvas.isReadOnly = false
    editor.controller.openEditor(editor.node, editor.canvas)
    expect(save.disabled).toBe(false)
    expect(save.classList.contains("cursor-not-allowed")).toBe(false)
  })

  it("restores the open snapshot when Cancel/close follows an uncommitted action change", async () => {
    editor = await mountEditor("process", { steps: [{ id: "guarded", action: "find_model", config: { resultVar: "order" } }] })
    const resultVar = editor.controller.formTarget.querySelector('[data-config-field="resultVar"] [data-config-input]')
    await change(resultVar, "edited")
    await press(editor.controller.formTarget.querySelector('[data-action*="#changeStep"]'))
    editor.controller.close()
    expect(editor.node.properties.steps[0]).toMatchObject({ id: "guarded", action: "find_model", config: { resultVar: "order" } })
    editor.controller.openEditor(editor.node, editor.canvas)
    await press(editor.controller.formTarget.querySelector('[data-action*="#removeStep"]'))
    document.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }))
    expect(editor.controller.formTarget.querySelector("[data-step-item]")).toBeNull()
  })

  it("keeps independently disabled controls disabled across repeated guard applications", async () => {
    editor = await mountEditor("process")
    const input = editor.field("description")
    input.disabled = true
    const canvasElement = document.querySelector('[data-controller="flowchart-canvas"]')
    canvasElement.dataset.flowchartCanvasReadOnlyValue = "true"
    editor.controller._applyReadOnlyState()
    editor.controller._applyReadOnlyState()
    canvasElement.dataset.flowchartCanvasReadOnlyValue = "false"
    editor.controller._applyReadOnlyState()
    expect(input.disabled).toBe(true)
    expect(editor.controller.saveButtonTarget.disabled).toBe(false)
  })

  it.each(["element", "connection"])("invalidates pending I/O when switching to another %s", async target => {
    editor = await mountEditor("process")
    applyFlowchartUrls(PIN_URLS)
    window.history.replaceState({}, "", "/81721200/admin/maintenance/flowcharts/1/edit")
    let respond
    vi.stubGlobal("fetch", () => new Promise(resolve => { respond = resolve }))
    const { controller, node, canvas } = editor
    const pane = controller.formFieldsIoTarget
    const pending = controller.elementIoManager.openForElement(node, pane)
    if (target === "element") {
      const other = { ...node, id: "other", properties: {} }
      canvas.elements.push(other)
      controller.openEditor(other, canvas)
    } else {
      controller.openConnectionEditor({ id: "edge", properties: {} }, canvas)
    }
    respond(new Response(JSON.stringify({ inputs: [], outputs: [{ pin: "obsolete" }] })))
    await pending
    expect(pane.textContent).not.toContain("obsolete")
    expect(controller.elementIoManager._currentElement).toBeNull()
    expect(node.properties).not.toHaveProperty("io_overrides")
  })
})
