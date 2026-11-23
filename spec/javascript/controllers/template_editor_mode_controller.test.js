import { describe, it, expect } from "vitest"
import Controller from "controllers/template_editor_mode_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = ({ selected = "rich_text", initial = "", modeButtons = false } = {}) =>
  `<div data-controller="template-editor-mode" ${initial ? `data-template-editor-mode-initial-value="${initial}"` : ""}>` +
  (modeButtons
    ? `<button type="button" data-template-editor-mode-target="modeButton" data-mode="rich_text" data-action="template-editor-mode#choose"` +
      ` class="rounded-md bg-surface text-text-primary shadow-sm" aria-pressed="true">Rich</button>` +
      `<button type="button" data-template-editor-mode-target="modeButton" data-mode="code" data-action="template-editor-mode#choose"` +
      ` class="rounded-md text-text-secondary hover:text-text-primary" aria-pressed="false">Code</button>`
    : "") +
  `<select data-template-editor-mode-target="select" data-action="change->template-editor-mode#switch">` +
  `<option value="rich_text" ${selected === "rich_text" ? "selected" : ""}>Rich</option>` +
  `<option value="code" ${selected === "code" ? "selected" : ""}>Code</option>` +
  `</select>` +
  `<div data-template-editor-mode-target="richContainer"><lexxy-editor></lexxy-editor></div>` +
  `<div data-template-editor-mode-target="codeContainer">` +
  `<textarea data-template-editor-mode-target="codeInput"></textarea>` +
  `</div>` +
  `</div>`

const modeButton = (el, mode) => el.querySelector(`[data-template-editor-mode-target='modeButton'][data-mode='${mode}']`)

const hidden = (el, name) => el.querySelector(`[data-template-editor-mode-target='${name}']`).classList.contains("hidden")

function stubLexxyValue(editor, initial = "<p></p>") {
  let stored = initial
  Object.defineProperty(editor, "value", {
    configurable: true,
    get() { return stored },
    set(v) { stored = v }
  })
  return () => stored
}

describe("template-editor-mode controller", () => {
  it("applies rich mode from the select value on connect", async () => {
    const { element } = await mountController("template-editor-mode", Controller, html({ selected: "rich_text" }))
    expect(hidden(element, "richContainer")).toBe(false)
    expect(hidden(element, "codeContainer")).toBe(true)
  })

  it("initial value overrides the select value on connect", async () => {
    const { element } = await mountController("template-editor-mode", Controller, html({ selected: "rich_text", initial: "code" }))
    expect(hidden(element, "richContainer")).toBe(true)
    expect(hidden(element, "codeContainer")).toBe(false)
  })

  it("switch() reflects the current select value", async () => {
    const { application, element } = await mountController("template-editor-mode", Controller, html({ selected: "rich_text" }))
    const ctrl = controllerFor(application, element, "template-editor-mode")
    element.querySelector("select").value = "code"
    ctrl.switch()
    expect(hidden(element, "richContainer")).toBe(true)
    expect(hidden(element, "codeContainer")).toBe(false)
  })

  it("copies Lexxy HTML into the code textarea when switching rich_text → code", async () => {
    const { application, element } = await mountController("template-editor-mode", Controller, html({ selected: "rich_text" }))
    const ctrl = controllerFor(application, element, "template-editor-mode")
    const editor = element.querySelector("lexxy-editor")
    const area = element.querySelector("textarea")
    stubLexxyValue(editor, "<p>Hello {{first_name}}</p>")

    element.querySelector("select").value = "code"
    ctrl.switch()

    expect(area.value).toBe("<p>Hello {{first_name}}</p>")
  })

  it("loads code textarea HTML into Lexxy when switching code → rich_text", async () => {
    const { application, element } = await mountController("template-editor-mode", Controller, html({ selected: "code", initial: "code" }))
    const ctrl = controllerFor(application, element, "template-editor-mode")
    const editor = element.querySelector("lexxy-editor")
    const area = element.querySelector("textarea")
    const read = stubLexxyValue(editor, "<p></p>")
    area.value = "<p>From code {{email}}</p>"

    element.querySelector("select").value = "rich_text"
    ctrl.switch()

    expect(read()).toBe("<p>From code {{email}}</p>")
  })

  it("requires the code textarea only in code mode", async () => {
    const { application, element } = await mountController("template-editor-mode", Controller, html({ selected: "rich_text" }))
    const ctrl = controllerFor(application, element, "template-editor-mode")
    const area = element.querySelector("textarea")
    expect(area.required).toBe(false)

    element.querySelector("select").value = "code"
    ctrl.switch()
    expect(area.required).toBe(true)

    element.querySelector("select").value = "rich_text"
    ctrl.switch()
    expect(area.required).toBe(false)
  })

  it("falls back to rich_text when select value and initial are blank", async () => {
    const { element } = await mountController(
      "template-editor-mode",
      Controller,
      `<div data-controller="template-editor-mode">` +
        `<select data-template-editor-mode-target="select"><option value="" selected></option></select>` +
        `<div data-template-editor-mode-target="richContainer"><lexxy-editor></lexxy-editor></div>` +
        `<div data-template-editor-mode-target="codeContainer"><textarea data-template-editor-mode-target="codeInput"></textarea></div>` +
      `</div>`
    )
    expect(hidden(element, "richContainer")).toBe(false)
    expect(hidden(element, "codeContainer")).toBe(true)
  })

  it("switch() falls back through currentMode/initial/rich_text when prev is unset", async () => {
    const { application, element } = await mountController("template-editor-mode", Controller, html({ selected: "rich_text" }))
    const ctrl = controllerFor(application, element, "template-editor-mode")
    ctrl.currentMode = undefined
    ctrl.initialValue = ""
    element.querySelector("select").value = "code"
    ctrl.switch()
    expect(hidden(element, "codeContainer")).toBe(false)
  })

  it("syncContent no-ops when Lexxy or textarea is missing", async () => {
    const { application, element } = await mountController(
      "template-editor-mode",
      Controller,
      `<div data-controller="template-editor-mode" data-template-editor-mode-initial-value="rich_text">` +
        `<select data-template-editor-mode-target="select"><option value="rich_text" selected>Rich</option><option value="code">Code</option></select>` +
        `<div data-template-editor-mode-target="richContainer"></div>` +
        `<div data-template-editor-mode-target="codeContainer"></div>` +
      `</div>`
    )
    const ctrl = controllerFor(application, element, "template-editor-mode")
    element.querySelector("select").value = "code"
    expect(() => ctrl.switch()).not.toThrow()
  })

  it("applyMode skips required toggling when codeInput target is absent", async () => {
    const { application, element } = await mountController(
      "template-editor-mode",
      Controller,
      `<div data-controller="template-editor-mode">` +
        `<select data-template-editor-mode-target="select"><option value="rich_text" selected>Rich</option><option value="code">Code</option></select>` +
        `<div data-template-editor-mode-target="richContainer"><lexxy-editor></lexxy-editor></div>` +
        `<div data-template-editor-mode-target="codeContainer"><textarea></textarea></div>` +
      `</div>`
    )
    const ctrl = controllerFor(application, element, "template-editor-mode")
    element.querySelector("select").value = "code"
    expect(() => ctrl.switch()).not.toThrow()
    expect(element.querySelector("textarea").required).toBe(false)
  })

  it("choose() mirrors the mode into the select and switches containers via the dispatched change", async () => {
    const { element } = await mountController("template-editor-mode", Controller, html({ modeButtons: true }))

    modeButton(element, "code").click()

    expect(element.querySelector("select").value).toBe("code")
    expect(hidden(element, "richContainer")).toBe(true)
    expect(hidden(element, "codeContainer")).toBe(false)
  })

  it("choose() re-renders segmented button state and aria-pressed", async () => {
    const { element } = await mountController("template-editor-mode", Controller, html({ modeButtons: true }))

    modeButton(element, "code").click()

    const active = modeButton(element, "code")
    const inactive = modeButton(element, "rich_text")
    expect(active.getAttribute("aria-pressed")).toBe("true")
    expect(active.classList.contains("bg-surface")).toBe(true)
    expect(active.classList.contains("text-text-primary")).toBe(true)
    expect(active.classList.contains("text-text-secondary")).toBe(false)
    expect(inactive.getAttribute("aria-pressed")).toBe("false")
    expect(inactive.classList.contains("text-text-secondary")).toBe(true)
    expect(inactive.classList.contains("bg-surface")).toBe(false)
  })

  it("applies the initial segmented button state on connect", async () => {
    const { element } = await mountController("template-editor-mode", Controller, html({ selected: "code", initial: "code", modeButtons: true }))

    expect(modeButton(element, "code").getAttribute("aria-pressed")).toBe("true")
    expect(modeButton(element, "rich_text").getAttribute("aria-pressed")).toBe("false")
  })

  it("choose() ignores a button without data-mode", async () => {
    const { application, element } = await mountController("template-editor-mode", Controller, html({ modeButtons: true }))
    const ctrl = controllerFor(application, element, "template-editor-mode")

    ctrl.choose({ preventDefault() {}, currentTarget: { dataset: {} } })

    expect(element.querySelector("select").value).toBe("rich_text")
    expect(hidden(element, "richContainer")).toBe(false)
  })
})

