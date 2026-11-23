import { describe, it, expect, afterEach } from "vitest"
import { mountEditor, change, press, sync } from "./_support.js"
import { persistableProperties } from "flowchart/element_config"

let editor
afterEach(async () => { await editor?.dispose(); editor = null })

describe("start property editor", () => {
  it("edits and reopens label/description on the rendered canvas", async () => {
    editor = await mountEditor("start")
    await change(editor.field("label"), "Receive order")
    await change(editor.field("description"), "HTTP entry <safe>")
    sync(editor)
    expect(editor.node.label).toBe("Receive order")
    expect(editor.canvas.elementLayer.textContent).toContain("Receive order")
    await editor.reopen()
    expect(editor.field("description").value).toBe("HTTP entry <safe>")
    expect(editor.node.properties).not.toHaveProperty("label")
  })
})

describe("process property editor", () => {
  it("removes a real step, syncs the empty collection and reopens the picker", async () => {
    editor = await mountEditor("process", { steps: [{ id: "step-a", action: "new_model", config: { resultVar: "order" } }] })
    await press(editor.controller.formTarget.querySelector('[data-action*="#removeStep"]'))
    expect(sync(editor).steps).toEqual([])
    await editor.reopen()
    expect(editor.controller.formTarget.querySelector("[data-step-item]")).toBeNull()
    expect(editor.controller.formTarget.querySelector("[data-step-picker-mount]").classList.contains("hidden")).toBe(false)
  })
})

describe("decision property editor", () => {
  it("collects a structured condition from the shared conditions control", async () => {
    editor = await mountEditor("decision", {
      routeBy: "condition",
      condition: { type: "group", joins: [], conditions: [{ kind: "field", leftOperand: "signal", operator: "==", rightOperand: "success" }] },
    })
    const root = editor.controller.formTarget
    expect(editor.controller.tabManager.activeTab).toBe("branches")
    expect(root.querySelector('[data-element-field="routeBy"]')).not.toBeNull()
    await change(root.querySelector("[data-condition-op]"), "is_empty")
    expect(sync(editor).condition).toEqual({
      type: "group",
      joins: [],
      conditions: [{ kind: "field", leftOperand: "signal", operator: "is_empty", rightOperand: "" }],
    })
    await editor.reopen()
    expect(editor.controller.formTarget.querySelector("[data-condition-op]").value).toBe("is_empty")
  })

  it("opens on Branches with the empty-condition error painted, and Save reveals it", async () => {
    editor = await mountEditor("decision", { routeBy: "condition", condition: { type: "group", joins: [], conditions: [] } })
    const controller = editor.controller
    const wrap = controller.formTarget.querySelector('[data-element-field="condition"]')
    expect(controller.tabManager.activeTab).toBe("branches")
    expect(wrap.querySelector("[data-field-error]").textContent).toBe("Add at least one condition")
    expect(controller.getFormFieldsForTab("branches").contains(wrap)).toBe(false)
    expect(controller._validateBeforeSave()).toBe(false)
    expect(controller.getFormFieldsForTab(controller.tabManager.activeTab).contains(wrap)).toBe(true)
  })

  it.each([[0], [1], [2]])("removing branch row %i drops its connection and keeps every box", async (removed) => {
    editor = await mountEditor("decision", { routeBy: "value", subject: "ctx.status" })
    for (const [index, id] of ["a", "b", "c"].entries()) {
      const child = { id, type: "process", label: id, properties: {}, x: 200 + index * 200, y: 240, width: 160, height: 60 }
      editor.canvas.elements.push(child)
      editor.canvas.renderElement(child)
      editor.canvas.createConnection(editor.node, child, `port_${index}`, "top", { label: id, matchValue: id })
    }
    await editor.reopen()
    await window.happyDOM.waitUntilComplete()
    const rows = editor.controller.formTarget.querySelectorAll("[data-branch-item]")
    expect(Array.from(rows, (row) => row.querySelector("[data-branch-name]").value)).toEqual(["a", "b", "c"])
    await press(rows[removed].querySelector('[data-action*="#removeBranch"]'))
    const kept = ["a", "b", "c"].filter((_, i) => i !== removed)
    const outgoing = editor.canvas.connections.filter((conn) => conn.from === editor.node.id)
    expect(outgoing.map((conn) => [conn.to, conn.label, conn.matchValue])).toEqual(kept.map((id) => [id, id, id]))
    expect(editor.canvas.elements.map((el) => el.id)).toEqual(expect.arrayContaining(["a", "b", "c"]))
    expect(editor.controller.formTarget.querySelectorAll("[data-branch-item]")).toHaveLength(2)
    expect(sync(editor)).not.toHaveProperty("branches")
  })
})

describe("loop property editor", () => {
  it("switches types through the catalog select; hidden values survive until persist", async () => {
    editor = await mountEditor("loop", { loopType: "for_each", collection: "ctx.items", maxIterations: 9 })
    const root = editor.controller.formTarget
    expect(editor.controller.tabManager.activeTab).toBe("general")
    await change(editor.field("loopType"), "while")
    expect(editor.field("collection").closest("[data-element-field]").classList.contains("hidden")).toBe(true)
    const live = sync(editor)
    expect(live.collection).toBe("ctx.items")
    expect(persistableProperties("loop", live)).not.toHaveProperty("collection")
    await change(editor.field("loopType"), "for_each")
    expect(editor.field("collection").value).toBe("ctx.items")
    expect(editor.field("collection").closest("[data-element-field]").classList.contains("hidden")).toBe(false)
    await change(editor.field("maxIterations"), "")
    expect(sync(editor)).not.toHaveProperty("maxIterations")
    await editor.reopen()
    expect(editor.field("maxIterations").value).toBe("")
    expect(editor.field("maxIterations").placeholder).toBe("Default: 100")
  })

  it("does not let an initially hidden empty collection block native validation", async () => {
    editor = await mountEditor("loop")
    expect(editor.controller.formTarget.checkValidity()).toBe(true)
  })
})

describe("subflow property editor", () => {
  it("opens on General and persists a flowchartId from the reference picker", async () => {
    editor = await mountEditor("subflow")
    expect(editor.controller.tabManager.activeTab).toBe("general")
    const wrap = editor.controller.formTarget.querySelector('[data-element-field="flowchartId"]')
    expect(wrap).not.toBeNull()
    expect(wrap.querySelector("[data-reference-picker]")).not.toBeNull()
    const hidden = editor.field("flowchartId")
    await change(hidden, "9")
    expect(sync(editor).flowchartId).toBe("9")
    await editor.reopen()
    expect(editor.field("flowchartId").value).toBe("9")
  })
})

describe("end property editor", () => {
  it("requires only the active response fields and drops legacy HTTP keys on persist", async () => {
    editor = await mountEditor("end", {
      responseType: "none",
      httpStatus: 201,
      responseBody: "ctx.order",
      io_overrides: { inputs: [], outputs: [] },
    })
    expect(editor.controller.formTarget.checkValidity()).toBe(true)
    await change(editor.field("responseType"), "value")
    expect(editor.field("returnValue").closest("[data-element-field]").classList.contains("hidden")).toBe(false)
    await change(editor.field("returnValue"), "ctx.result")
    const live = sync(editor)
    expect(live.httpStatus).toBe(201)
    expect(persistableProperties("end", live)).not.toHaveProperty("httpStatus")
    expect(persistableProperties("end", live)).not.toHaveProperty("responseBody")
    await change(editor.field("responseType"), "none")
    const after = sync(editor)
    expect(after.returnValue).toBe("ctx.result")
    expect(persistableProperties("end", after)).not.toHaveProperty("returnValue")
    expect(editor.node.properties.io_overrides).toEqual({ inputs: [], outputs: [] })
    await editor.reopen()
    expect(editor.field("returnValue").closest("[data-element-field]").classList.contains("hidden")).toBe(true)
  })
})
