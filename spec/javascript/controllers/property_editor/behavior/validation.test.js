import { describe, it, expect, afterEach } from "vitest"
import { mountEditor, press, change, sync } from "./_support.js"

let editor
afterEach(async () => { await editor?.dispose(); editor = null })

describe("native invalid controls in collapsed editor sections", () => {
  it("transfers amountField required validation between the dropdown and manual input", async () => {
    editor = await mountEditor("process", { steps: [{ id: "p3", action: "phase3_fixture", config: { sourceVariable: "ctx.items", predicate: "true" } }] })
    editor.canvas.entityAttributes = [{ name_slug: "amount", name: "Amount", html_type: "number" }]
    await editor.reopen()
    const form = editor.controller.formTarget
    const wrapper = form.querySelector('[data-config-field="amountField"]')
    wrapper.setAttribute("data-conditionally-required", "")
    editor.controller.stepManager.handleConfigFieldChange({ target: wrapper.querySelector("[data-config-input]") })
    const select = wrapper.querySelector("[data-entity-column-select]")
    const manual = wrapper.querySelector("[data-entity-column-manual]")
    await change(select, "amount")
    expect(select.checkValidity()).toBe(true)
    await change(select, "__manual__")
    expect(select.required).toBe(false)
    expect(manual.required).toBe(true)
    expect(manual.checkValidity()).toBe(false)
    await change(manual, "external_amount")
    expect(select.checkValidity() && manual.checkValidity()).toBe(true)
    expect(sync(editor).steps[0].config.amountField).toBe("external_amount")
    await press(wrapper.querySelector('[data-action*="#swapEntityColumnToSelect"]'))
    expect(select.required).toBe(true)
    expect(manual.required).toBe(false)
    expect(select.checkValidity()).toBe(false)
    await change(select, "amount")
    expect(select.checkValidity() && manual.checkValidity()).toBe(true)
    expect(sync(editor).steps[0].config.amountField).toBe("amount")
  })

  it("validates a required findField once findBy is attribute", async () => {
    editor = await mountEditor("process", { steps: [{ id: "find", action: "find_model", config: { findBy: "id" } }] })
    await editor.reopen()
    const root = editor.controller.formTarget
    await change(root.querySelector('[data-config-input="findBy"]'), "attribute")
    const field = root.querySelector('[data-config-field="findField"]')
    expect(field.classList.contains("hidden")).toBe(false)
    const input = field.querySelector("[data-config-input]")
    expect(input.required).toBe(true)
    expect(input.checkValidity()).toBe(false)
    await change(input, "email")
    expect(input.checkValidity()).toBe(true)
    expect(sync(editor).steps[0].config.findField).toBe("email")
    await change(root.querySelector('[data-config-input="findBy"]'), "id")
    expect(field.classList.contains("hidden")).toBe(true)
    expect(input.required).toBe(false)
  })

  it("reveals a collapsed step and its More options disclosure without allowing an invalid submit", async () => {
    editor = await mountEditor("process", { steps: [{ id: "p3", action: "phase3_fixture", config: { sourceVariable: "ctx.items", predicate: "true" } }] })
    const form = editor.controller.formTarget
    const input = form.querySelector('[data-config-field="connectTimeout"] [data-config-input]')
    expect(input.disabled).toBe(false)
    input.value = "9"
    const disclosure = input.closest("[data-disclosure-body]")
    editor.controller.tabManager.switchTo("general")
    expect(input.checkValidity()).toBe(false)
    expect(editor.controller.tabManager.activeTab).toBe("steps")
    expect(form.querySelector("[data-step-item]").classList.contains("step-expanded")).toBe(true)
    expect(disclosure.classList.contains("hidden")).toBe(false)
    expect(input.checkValidity()).toBe(false)
    expect(disclosure.classList.contains("hidden")).toBe(false)
  })

  it("threads the editor's translated operator labels and value placeholder into step conditions", async () => {
    editor = await mountEditor("process", { steps: [{ id: "p3", action: "phase3_fixture", config: { sourceVariable: "ctx.items", predicate: "true" } }] })
    editor.controller.branchOperatorLabelsValue = { contains: "包含" }
    editor.controller.valuePlaceholderValue = "值"
    await editor.reopen()
    const filter = editor.controller.formTarget.querySelector('[data-config-field="filter"]')
    expect(filter.querySelector('[data-condition-op] option[value="contains"]').textContent).toBe("包含")
    expect(filter.querySelector("[data-condition-right]").placeholder).toBe("值")
  })

  it("re-evaluates the retry toggle while an idempotency key is typed", async () => {
    editor = await mountEditor("process", { steps: [{ id: "p3", action: "phase3_fixture", config: { sourceVariable: "ctx.items", predicate: "true", operation: "avg" } }] })
    const form = editor.controller.formTarget
    const retry = form.querySelector('[data-config-field="retryOnTransportError"] [data-config-input]')
    const key = form.querySelector('[data-config-field="idempotencyKey"] [data-config-input]')
    sync(editor)
    expect(retry.disabled).toBe(true)
    key.value = "ctx[:request_id]"
    key.dispatchEvent(new Event("input", { bubbles: true }))
    sync(editor)
    expect(retry.disabled).toBe(false)
    key.value = ""
    key.dispatchEvent(new Event("input", { bubbles: true }))
    sync(editor)
    expect(retry.disabled).toBe(true)
  })

  it("captures invalid events on a general field and detaches the handler on close", async () => {
    editor = await mountEditor("start")
    const label = editor.field("label")
    label.required = true
    label.value = ""
    editor.controller.tabManager.switchTo("advanced")
    expect(label.checkValidity()).toBe(false)
    expect(editor.controller.tabManager.activeTab).toBe("general")
    await press(editor.controller.formTarget.querySelector('[data-action="property-editor#close"]'))
    editor.controller.tabManager.switchTo("advanced")
    label.checkValidity()
    expect(editor.controller.tabManager.activeTab).toBe("advanced")
  })
})
