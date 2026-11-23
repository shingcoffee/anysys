import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/template_token_picker_controller"
import SearchableSelect from "controllers/searchable_select_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

const uuid = "11111111-1111-4111-8111-111111111102"
const labelToken = "{{First name}}"

const html =
  `<div data-controller="template-token-picker">` +
  `<select data-template-token-picker-target="picker" data-action="change->template-token-picker#insert">` +
  `<option value="">Insert…</option>` +
  `<option value="${uuid}">First name</option>` +
  `</select>` +
  `<lexxy-editor><div contenteditable="true"></div></lexxy-editor>` +
  `</div>`

describe("template-token-picker controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element } = await mountController("template-token-picker", Controller, html))
    ctrl = controllerFor(application, element, "template-token-picker")
  })
  afterEach(() => vi.restoreAllMocks())

  it("does nothing when no token is selected", () => {
    document.execCommand = vi.fn(() => true)
    ctrl.insert()
    expect(document.execCommand).not.toHaveBeenCalled()
  })

  it("inserts a label token via insertText and resets the picker", () => {
    document.execCommand = vi.fn(() => true)
    element.querySelector("select").value = uuid
    ctrl.insert()
    expect(document.execCommand).toHaveBeenCalledWith("insertText", false, labelToken)
    expect(element.querySelector("select").value).toBe("")
  })

  it("falls back to the editor element itself when it has no contenteditable child", async () => {
    const noContentEditableHtml =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker" data-action="change->template-token-picker#insert">` +
      `<option value="">Insert…</option>` +
      `<option value="${uuid}">First name</option>` +
      `</select>` +
      `<lexxy-editor></lexxy-editor>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, noContentEditableHtml)
    const c = controllerFor(app, el, "template-token-picker")
    document.execCommand = vi.fn(() => true)
    const editor = el.querySelector("lexxy-editor")
    const focusSpy = vi.spyOn(editor, "focus")
    el.querySelector("select").value = uuid
    c.insert()
    expect(focusSpy).toHaveBeenCalled()
    expect(document.execCommand).toHaveBeenCalledWith("insertText", false, labelToken)
  })

  it("falls back to DOM text insert when execCommand returns false", () => {
    document.execCommand = vi.fn(() => false)
    const editable = element.querySelector('[contenteditable="true"]')
    element.querySelector("select").value = uuid
    ctrl.insert()
    expect(editable.textContent).toContain(labelToken)
    expect(editable.querySelector("span.email-token-chip")).toBeNull()
  })

  it("inserts label text through the current selection range when execCommand fails", () => {
    document.execCommand = vi.fn(() => false)
    const editable = element.querySelector('[contenteditable="true"]')
    const inserted = []
    const range = {
      deleteContents: vi.fn(),
      insertNode: (node) => { inserted.push(node); editable.appendChild(node) },
      setStartAfter: vi.fn(),
      collapse: vi.fn(),
      commonAncestorContainer: editable
    }
    window.getSelection = () => ({
      rangeCount: 1,
      anchorNode: editable,
      getRangeAt: () => range,
      removeAllRanges: vi.fn(),
      addRange: vi.fn()
    })
    element.querySelector("select").value = uuid
    ctrl.insert()
    expect(range.deleteContents).toHaveBeenCalled()
    expect(inserted[0]?.textContent).toBe(labelToken)
  })

  it("inserts into the HTML textarea when code mode is visible", async () => {
    const codeHtml =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker">` +
      `<option value="${uuid}">First name</option>` +
      `</select>` +
      `<div data-template-editor-mode-target="richContainer" class="hidden"></div>` +
      `<div data-template-editor-mode-target="codeContainer">` +
      `<textarea>Hello </textarea>` +
      `</div>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, codeHtml)
    const c = controllerFor(app, el, "template-token-picker")
    el.querySelector("select").value = uuid
    const area = el.querySelector("textarea")
    area.selectionStart = area.selectionEnd = area.value.length
    c.insert()
    expect(area.value).toBe("Hello {{First name}}")
  })

  it("inserts from searchable-select change and clears the selection", async () => {
    const options = [{ group: "Catalog", items: [["First name", uuid]] }]
    const searchableHtml = `
      <div data-controller="template-token-picker" data-action="change->template-token-picker#insert">
        <div data-controller="searchable-select"
             data-searchable-select-options-value='${JSON.stringify(options)}'
             data-searchable-select-expand-all-value="true">
          <input data-searchable-select-target="search">
          <input type="hidden" data-searchable-select-target="hidden">
          <button data-searchable-select-target="clear" class="hidden"></button>
          <div data-searchable-select-target="dropdown" class="hidden"></div>
        </div>
        <lexxy-editor><div contenteditable="true"></div></lexxy-editor>
      </div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, searchableHtml)
    app.register("searchable-select", SearchableSelect)
    await tick()
    const selectEl = el.querySelector('[data-controller="searchable-select"]')
    const selectCtrl = controllerFor(app, selectEl, "searchable-select")
    expect(selectCtrl).toBeTruthy()
    document.execCommand = vi.fn(() => true)

    selectCtrl.select(uuid, "First name", "Catalog")
    await tick()

    expect(document.execCommand).toHaveBeenCalledWith("insertText", false, labelToken)
    expect(selectEl.querySelector('[data-searchable-select-target="hidden"]').value).toBe("")
    expect(selectEl.querySelector('[data-searchable-select-target="search"]').value).toBe("")
  })

  it("appends via Lexxy value API when cursor insert is unavailable (picker stole focus)", async () => {
    const modeHtml =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker">` +
      `<option value="${uuid}">First name</option>` +
      `</select>` +
      `<div data-template-editor-mode-target="richContainer">` +
      `<lexxy-editor><div contenteditable="true"></div></lexxy-editor>` +
      `</div>` +
      `<div data-template-editor-mode-target="codeContainer" class="hidden"><textarea></textarea></div>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, modeHtml)
    const c = controllerFor(app, el, "template-token-picker")
    document.execCommand = vi.fn(() => false)
    window.getSelection = () => ({ rangeCount: 0, getRangeAt: () => null })

    const editor = el.querySelector("lexxy-editor")
    let stored = "<p>Hello</p>"
    Object.defineProperty(editor, "value", {
      configurable: true,
      get() { return stored },
      set(v) { stored = v }
    })

    el.querySelector("select").value = uuid
    c.insert()

    expect(stored).toContain(labelToken)
    expect(stored).toContain("Hello")
  })

  it("inserts into the subject field when no editor mode is present", async () => {
    const subjectHtml =
      `<form data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `<input name="email_template[subject]" value="Hello ">` +
      `</form>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, subjectHtml)
    const c = controllerFor(app, el, "template-token-picker")
    const input = el.querySelector('input[name="email_template[subject]"]')
    input.focus()
    input.selectionStart = input.selectionEnd = input.value.length
    el.querySelector("select").value = uuid
    c.insert()
    expect(input.value).toBe("Hello {{First name}}")
  })

  it("returns false when rich mode has no editor", async () => {
    const richHtml =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `<div data-template-editor-mode-target="richContainer"></div>` +
      `<div data-template-editor-mode-target="codeContainer" class="hidden"></div>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, richHtml)
    const c = controllerFor(app, el, "template-token-picker")
    el.querySelector("select").value = uuid
    expect(c.insert()).toBeUndefined()
  })

  it("returns false when code mode has no textarea", async () => {
    const codeHtml =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `<div data-template-editor-mode-target="richContainer" class="hidden"></div>` +
      `<div data-template-editor-mode-target="codeContainer"></div>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, codeHtml)
    const c = controllerFor(app, el, "template-token-picker")
    el.querySelector("select").value = uuid
    c.insert()
    expect(el.querySelector("select").value).toBe(uuid)
  })

  it("resolves labels from searchable-select option nodes", async () => {
    const searchableHtml = `
      <div data-controller="template-token-picker">
        <div data-controller="searchable-select">
          <input data-searchable-select-target="search" value="">
          <input type="hidden" data-searchable-select-target="hidden" value="${uuid}">
          <div data-searchable-select-target="option" data-value="${uuid}">Display Label</div>
        </div>
        <lexxy-editor><div contenteditable="true"></div></lexxy-editor>
      </div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, searchableHtml)
    const c = controllerFor(app, el, "template-token-picker")
    document.execCommand = vi.fn(() => true)
    const hidden = el.querySelector('[data-searchable-select-target="hidden"]')
    c.insert({ target: hidden })
    expect(document.execCommand).toHaveBeenCalledWith(
      "insertText",
      false,
      "{{Display Label}}"
    )
  })

  it("falls back to search text for label when option is absent", async () => {
    const searchableHtml = `
      <div data-controller="template-token-picker">
        <div data-controller="searchable-select">
          <input data-searchable-select-target="search" value="Typed label">
          <input type="hidden" data-searchable-select-target="hidden" value="${uuid}">
        </div>
        <div data-template-editor-mode-target="richContainer" class="hidden"></div>
        <div data-template-editor-mode-target="codeContainer"><textarea></textarea></div>
      </div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, searchableHtml)
    const c = controllerFor(app, el, "template-token-picker")
    c.insert({ target: el.querySelector('[data-searchable-select-target="hidden"]') })
    expect(el.querySelector("textarea").value).toBe("{{Typed label}}")
  })

  it("clears a bare hidden input when searchable-select is missing", async () => {
    const bareHtml =
      `<div data-controller="template-token-picker">` +
      `<input type="hidden" data-searchable-select-target="hidden" value="${uuid}">` +
      `<div data-template-editor-mode-target="richContainer" class="hidden"></div>` +
      `<div data-template-editor-mode-target="codeContainer"><textarea></textarea></div>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, bareHtml)
    const c = controllerFor(app, el, "template-token-picker")
    const hidden = el.querySelector("input")
    c.insert({ target: hidden })
    expect(hidden.value).toBe("")
  })

  it("appends a label token into an empty Lexxy value", async () => {
    const modeHtml =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `<div data-template-editor-mode-target="richContainer">` +
      `<lexxy-editor><div contenteditable="true"></div></lexxy-editor>` +
      `</div>` +
      `<div data-template-editor-mode-target="codeContainer" class="hidden"><textarea></textarea></div>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, modeHtml)
    const c = controllerFor(app, el, "template-token-picker")
    document.execCommand = vi.fn(() => false)
    window.getSelection = () => ({ rangeCount: 0, getRangeAt: () => null })
    const editor = el.querySelector("lexxy-editor")
    let stored = ""
    Object.defineProperty(editor, "value", {
      configurable: true,
      get() { return stored },
      set(v) { stored = v }
    })
    el.querySelector("select").value = uuid
    c.insert()
    expect(stored).toContain(labelToken)
    expect(stored.startsWith("<p>")).toBe(true)
  })

  it("inserts label text via insertText", () => {
    document.execCommand = vi.fn((cmd) => cmd === "insertText")
    element.querySelector("select").value = uuid
    ctrl.insert()
    expect(document.execCommand).toHaveBeenCalledWith("insertText", false, labelToken)
  })

  it("returns false when there is no insert target", async () => {
    const emptyHtml =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, emptyHtml)
    const c = controllerFor(app, el, "template-token-picker")
    el.querySelector("select").value = uuid
    c.insert()
    expect(el.querySelector("select").value).toBe(uuid)
  })

  it("appends after non-paragraph Lexxy HTML", async () => {
    const modeHtml =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `<div data-template-editor-mode-target="richContainer">` +
      `<lexxy-editor><div contenteditable="true"></div></lexxy-editor>` +
      `</div>` +
      `<div data-template-editor-mode-target="codeContainer" class="hidden"><textarea></textarea></div>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, modeHtml)
    const c = controllerFor(app, el, "template-token-picker")
    document.execCommand = vi.fn(() => false)
    window.getSelection = () => ({ rangeCount: 0, getRangeAt: () => null })
    const editor = el.querySelector("lexxy-editor")
    let stored = "<div>Body</div>"
    Object.defineProperty(editor, "value", {
      configurable: true,
      get() { return stored },
      set(v) { stored = v }
    })
    el.querySelector("select").value = uuid
    c.insert()
    expect(stored).toContain("<div>Body</div>")
    expect(stored).toContain(labelToken)
  })

  it("does not insert when no human-readable label is available", async () => {
    const htmlNoText =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}"></option></select>` +
      `<div data-template-editor-mode-target="richContainer" class="hidden"></div>` +
      `<div data-template-editor-mode-target="codeContainer"><textarea></textarea></div>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, htmlNoText)
    const c = controllerFor(app, el, "template-token-picker")
    el.querySelector("select").value = uuid
    c.insert()
    expect(el.querySelector("textarea").value).toBe("")
  })

  it("forces cursor insert when Lexxy value append is unavailable", async () => {
    const modeHtml =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `<div data-template-editor-mode-target="richContainer">` +
      `<lexxy-editor><div contenteditable="true"></div></lexxy-editor>` +
      `</div>` +
      `<div data-template-editor-mode-target="codeContainer" class="hidden"><textarea></textarea></div>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, modeHtml)
    const c = controllerFor(app, el, "template-token-picker")
    document.execCommand = vi.fn(() => false)
    window.getSelection = () => ({ rangeCount: 0, getRangeAt: () => null })
    const editor = el.querySelector("lexxy-editor")
    Object.defineProperty(editor, "value", {
      configurable: true,
      get() { return 123 },
      set() {}
    })
    el.querySelector("select").value = uuid
    c.insert()
    expect(document.execCommand).toHaveBeenCalled()
  })

  it("inserts into a plain-text textarea outside editor modes", async () => {
    const subjectHtml =
      `<form data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `<textarea name="email_template[body_text]">Hi </textarea>` +
      `</form>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, subjectHtml)
    const c = controllerFor(app, el, "template-token-picker")
    const area = el.querySelector("textarea")
    area.selectionStart = area.selectionEnd = area.value.length
    el.querySelector("select").value = uuid
    c.insert()
    expect(area.value).toBe("Hi {{First name}}")
  })

  it("does not insert UUID when searchable-select has no label", async () => {
    const searchableHtml = `
      <div data-controller="template-token-picker">
        <div data-controller="searchable-select">
          <input data-searchable-select-target="search" value="">
          <input type="hidden" data-searchable-select-target="hidden" value="${uuid}">
        </div>
        <div data-template-editor-mode-target="richContainer" class="hidden"></div>
        <div data-template-editor-mode-target="codeContainer"><textarea></textarea></div>
      </div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, searchableHtml)
    const c = controllerFor(app, el, "template-token-picker")
    c.insert()
    expect(el.querySelector("textarea").value).toBe("")
  })

  it("does not insert when selected option text is whitespace only", async () => {
    const htmlNoText =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">   </option></select>` +
      `<div data-template-editor-mode-target="richContainer" class="hidden"></div>` +
      `<div data-template-editor-mode-target="codeContainer"><textarea></textarea></div>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, htmlNoText)
    const c = controllerFor(app, el, "template-token-picker")
    el.querySelector("select").value = uuid
    c.insert()
    expect(el.querySelector("textarea").value).toBe("")
  })

  it("does not insert UUID when a searchable option has empty text", async () => {
    const searchableHtml = `
      <div data-controller="template-token-picker">
        <div data-controller="searchable-select">
          <input data-searchable-select-target="search" value="">
          <input type="hidden" data-searchable-select-target="hidden" value="${uuid}">
          <div data-searchable-select-target="option" data-value="${uuid}"></div>
        </div>
        <div data-template-editor-mode-target="richContainer" class="hidden"></div>
        <div data-template-editor-mode-target="codeContainer"><textarea></textarea></div>
      </div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, searchableHtml)
    const c = controllerFor(app, el, "template-token-picker")
    c.insert({ target: el.querySelector('[data-searchable-select-target="hidden"]') })
    expect(el.querySelector("textarea").value).toBe("")
  })

  it("prefers data-label over option text for searchable-select", async () => {
    const searchableHtml = `
      <div data-controller="template-token-picker">
        <div data-controller="searchable-select">
          <input data-searchable-select-target="search" value="">
          <input type="hidden" data-searchable-select-target="hidden" value="${uuid}">
          <div data-searchable-select-target="option" data-value="${uuid}" data-label="First name">ignored text</div>
        </div>
        <div data-template-editor-mode-target="richContainer" class="hidden"></div>
        <div data-template-editor-mode-target="codeContainer"><textarea></textarea></div>
      </div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, searchableHtml)
    const c = controllerFor(app, el, "template-token-picker")
    c.insert({ target: el.querySelector('[data-searchable-select-target="hidden"]') })
    expect(el.querySelector("textarea").value).toBe("{{First name}}")
  })

  it("skips searchable options whose data-value does not match", async () => {
    const searchableHtml = `
      <div data-controller="template-token-picker">
        <div data-controller="searchable-select">
          <input data-searchable-select-target="search" value="From search">
          <input type="hidden" data-searchable-select-target="hidden" value="${uuid}">
          <div data-searchable-select-target="option" data-value="other-id">Other</div>
        </div>
        <lexxy-editor><div contenteditable="true"></div></lexxy-editor>
      </div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, searchableHtml)
    const c = controllerFor(app, el, "template-token-picker")
    document.execCommand = vi.fn(() => true)
    c.insert({ target: el.querySelector('[data-searchable-select-target="hidden"]') })
    expect(document.execCommand).toHaveBeenCalledWith(
      "insertText",
      false,
      "{{From search}}"
    )
  })

  it("falls back when selection has no ranges or no anchor", async () => {
    const modeHtml =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `<div data-template-editor-mode-target="richContainer">` +
      `<lexxy-editor><div contenteditable="true"></div></lexxy-editor>` +
      `</div>` +
      `<div data-template-editor-mode-target="codeContainer" class="hidden"><textarea></textarea></div>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, modeHtml)
    const c = controllerFor(app, el, "template-token-picker")
    const editor = el.querySelector("lexxy-editor")
    let stored = "<p>Body</p>"
    Object.defineProperty(editor, "value", {
      configurable: true,
      get() { return stored },
      set(v) { stored = v }
    })
    document.execCommand = vi.fn(() => false)

    window.getSelection = () => ({ rangeCount: 0, anchorNode: editor })
    el.querySelector("select").value = uuid
    c.insert()
    expect(stored).toContain(labelToken)

    stored = "<p>Body2</p>"
    window.getSelection = () => ({ rangeCount: 1, anchorNode: null })
    el.querySelector("select").value = uuid
    c.insert()
    expect(stored).toContain(labelToken)
  })

  it("inserts via cursor when rich mode has a live selection", async () => {
    const modeHtml =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `<div data-template-editor-mode-target="richContainer">` +
      `<lexxy-editor><div contenteditable="true">Hello</div></lexxy-editor>` +
      `</div>` +
      `<div data-template-editor-mode-target="codeContainer" class="hidden"><textarea></textarea></div>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, modeHtml)
    const c = controllerFor(app, el, "template-token-picker")
    const editable = el.querySelector('[contenteditable="true"]')
    const textNode = editable.firstChild
    window.getSelection = () => ({
      rangeCount: 1,
      anchorNode: textNode,
      getRangeAt: () => null
    })
    document.execCommand = vi.fn(() => true)
    el.querySelector("select").value = uuid
    c.insert()
    expect(document.execCommand).toHaveBeenCalledWith("insertText", false, labelToken)
  })

  it("uses the lexxy-editor itself when rich mode has no contenteditable child", async () => {
    const modeHtml =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `<div data-template-editor-mode-target="richContainer">` +
      `<lexxy-editor></lexxy-editor>` +
      `</div>` +
      `<div data-template-editor-mode-target="codeContainer" class="hidden"><textarea></textarea></div>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, modeHtml)
    const c = controllerFor(app, el, "template-token-picker")
    document.execCommand = vi.fn(() => true)
    const editor = el.querySelector("lexxy-editor")
    const focusSpy = vi.spyOn(editor, "focus")
    window.getSelection = () => ({
      rangeCount: 1,
      anchorNode: editor,
      getRangeAt: () => null
    })
    el.querySelector("select").value = uuid
    c.insert()
    expect(focusSpy).toHaveBeenCalled()
    expect(document.execCommand).toHaveBeenCalledWith("insertText", false, labelToken)
  })

  it("treats a null selection as outside the editor", async () => {
    const modeHtml =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `<div data-template-editor-mode-target="richContainer">` +
      `<lexxy-editor><div contenteditable="true"></div></lexxy-editor>` +
      `</div>` +
      `<div data-template-editor-mode-target="codeContainer" class="hidden"><textarea></textarea></div>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, modeHtml)
    const c = controllerFor(app, el, "template-token-picker")
    window.getSelection = () => null
    document.execCommand = vi.fn(() => false)
    const editor = el.querySelector("lexxy-editor")
    let stored = "<p>Hi</p>"
    Object.defineProperty(editor, "value", {
      configurable: true,
      get() { return stored },
      set(v) { stored = v }
    })
    el.querySelector("select").value = uuid
    c.insert()
    expect(stored).toContain(labelToken)
  })

  it("appends at end when textarea selection is unavailable", async () => {
    const subjectHtml =
      `<form data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `<textarea name="email_template[body_text]">Hi</textarea>` +
      `</form>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, subjectHtml)
    const c = controllerFor(app, el, "template-token-picker")
    const area = el.querySelector("textarea")
    Object.defineProperty(area, "selectionStart", { configurable: true, get: () => null })
    Object.defineProperty(area, "selectionEnd", { configurable: true, get: () => null })
    el.querySelector("select").value = uuid
    c.insert()
    expect(area.value).toBe("Hi{{First name}}")
  })

  it("inserts into the last-focused subject field while rich mode is visible", async () => {
    const formHtml =
      `<form>` +
      `<input name="email_template[subject]" value="Sub ">` +
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `<div data-template-editor-mode-target="richContainer">` +
      `<lexxy-editor><div contenteditable="true"></div></lexxy-editor>` +
      `</div>` +
      `<div data-template-editor-mode-target="codeContainer" class="hidden"><textarea></textarea></div>` +
      `</div>` +
      `</form>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, formHtml)
    const c = controllerFor(app, el, "template-token-picker")
    const subject = el.closest("form").querySelector('input[name="email_template[subject]"]')
    expect(subject).toBeTruthy()
    c.onFocusIn({ target: subject })
    expect(c.lastPlainField).toBe(subject)
    subject.selectionStart = subject.selectionEnd = subject.value.length
    el.querySelector("select").value = uuid
    c.insert()
    expect(subject.value).toBe("Sub {{First name}}")
  })

  it("clears lastPlainField when the rich editor is focused", async () => {
    const formHtml =
      `<form>` +
      `<input name="email_template[subject]" value="Sub ">` +
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `<div data-template-editor-mode-target="richContainer">` +
      `<lexxy-editor><div contenteditable="true"></div></lexxy-editor>` +
      `</div>` +
      `<div data-template-editor-mode-target="codeContainer" class="hidden"><textarea></textarea></div>` +
      `</div>` +
      `</form>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, formHtml)
    const c = controllerFor(app, el, "template-token-picker")
    const subject = el.closest("form").querySelector('input[name="email_template[subject]"]')
    const editable = el.querySelector('[contenteditable="true"]')
    c.onFocusIn({ target: subject })
    c.onFocusIn({ target: editable })
    document.execCommand = vi.fn(() => true)
    window.getSelection = () => ({ rangeCount: 1, anchorNode: editable, getRangeAt: () => null })
    el.querySelector("select").value = uuid
    c.insert()
    expect(subject.value).toBe("Sub ")
    expect(document.execCommand).toHaveBeenCalledWith("insertText", false, labelToken)
  })

  it("removes the focusin listener on disconnect", () => {
    const scope = element.closest("form") || element
    const spy = vi.spyOn(scope, "removeEventListener")
    ctrl.disconnect()
    expect(spy).toHaveBeenCalledWith("focusin", ctrl.onFocusIn)
  })

  it("ignores focusin events without a target", () => {
    ctrl.onFocusIn({})
    expect(ctrl.lastPlainField).toBeNull()
  })

  it("inserts via range when commonAncestorContainer is the editable", () => {
    document.execCommand = vi.fn(() => false)
    const editable = element.querySelector('[contenteditable="true"]')
    const inserted = []
    const range = {
      deleteContents: vi.fn(),
      insertNode: (node) => { inserted.push(node); editable.appendChild(node) },
      setStartAfter: vi.fn(),
      collapse: vi.fn(),
      commonAncestorContainer: editable
    }
    window.getSelection = () => ({
      rangeCount: 1,
      anchorNode: editable,
      getRangeAt: () => range,
      removeAllRanges: vi.fn(),
      addRange: vi.fn()
    })
    element.querySelector("select").value = uuid
    ctrl.insert()
    expect(inserted[0]?.textContent).toBe(labelToken)
  })

  it("inserts via range when commonAncestorContainer is nested inside the editable", () => {
    document.execCommand = vi.fn(() => false)
    const editable = element.querySelector('[contenteditable="true"]')
    const nested = document.createElement("span")
    nested.textContent = "x"
    editable.appendChild(nested)
    const inserted = []
    const range = {
      deleteContents: vi.fn(),
      insertNode: (node) => { inserted.push(node); editable.appendChild(node) },
      setStartAfter: vi.fn(),
      collapse: vi.fn(),
      commonAncestorContainer: nested
    }
    window.getSelection = () => ({
      rangeCount: 1,
      anchorNode: nested,
      getRangeAt: () => range,
      removeAllRanges: vi.fn(),
      addRange: vi.fn()
    })
    element.querySelector("select").value = uuid
    ctrl.insert()
    expect(inserted[0]?.textContent).toBe(labelToken)
  })

  it("returns false from exec when document.execCommand throws", () => {
    document.execCommand = vi.fn(() => { throw new Error("boom") })
    const editable = element.querySelector('[contenteditable="true"]')
    window.getSelection = () => ({
      rangeCount: 1,
      anchorNode: editable,
      getRangeAt: () => ({
        deleteContents: vi.fn(),
        insertNode: (node) => editable.appendChild(node),
        setStartAfter: vi.fn(),
        collapse: vi.fn(),
        commonAncestorContainer: editable
      }),
      removeAllRanges: vi.fn(),
      addRange: vi.fn()
    })
    element.querySelector("select").value = uuid
    expect(() => ctrl.insert()).not.toThrow()
    expect(editable.textContent).toContain(labelToken)
  })

  it("rejects UUID-shaped option labels so they never appear in the editor", async () => {
    const searchableHtml = `
      <div data-controller="template-token-picker">
        <div data-controller="searchable-select">
          <input data-searchable-select-target="search" value="">
          <input type="hidden" data-searchable-select-target="hidden" value="${uuid}">
          <div data-searchable-select-target="option" data-value="${uuid}" data-label="${uuid}">${uuid}</div>
        </div>
        <div data-template-editor-mode-target="richContainer" class="hidden"></div>
        <div data-template-editor-mode-target="codeContainer"><textarea></textarea></div>
      </div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, searchableHtml)
    const c = controllerFor(app, el, "template-token-picker")
    c.insert({ target: el.querySelector('[data-searchable-select-target="hidden"]') })
    expect(el.querySelector("textarea").value).toBe("")
  })

  it("captures the editor caret range on selectionchange", () => {
    const editable = element.querySelector('[contenteditable="true"]')
    const savedRange = { commonAncestorContainer: editable }
    const range = { cloneRange: () => savedRange }
    window.getSelection = () => ({
      rangeCount: 1,
      anchorNode: editable,
      getRangeAt: () => range
    })
    ctrl.onSelectionChange()
    expect(ctrl.lastEditorRange).toBe(savedRange)
  })

  it("captures the range via the editor host when it has no contenteditable child", async () => {
    const bareEditorHtml =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `<lexxy-editor></lexxy-editor>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, bareEditorHtml)
    const c = controllerFor(app, el, "template-token-picker")
    const host = el.querySelector("lexxy-editor")
    const savedRange = { commonAncestorContainer: host }
    window.getSelection = () => ({
      rangeCount: 1,
      anchorNode: host,
      getRangeAt: () => ({ cloneRange: () => savedRange })
    })
    c.onSelectionChange()
    expect(c.lastEditorRange).toBe(savedRange)
  })

  it("ignores selectionchange when the selection leaves the editor", () => {
    window.getSelection = () => ({
      rangeCount: 1,
      anchorNode: document.body,
      getRangeAt: () => ({ cloneRange: vi.fn() })
    })
    ctrl.onSelectionChange()
    expect(ctrl.lastEditorRange).toBeNull()
  })

  it("ignores selectionchange with no ranges or a null selection", () => {
    window.getSelection = () => ({ rangeCount: 0 })
    ctrl.onSelectionChange()
    expect(ctrl.lastEditorRange).toBeNull()

    window.getSelection = () => null
    ctrl.onSelectionChange()
    expect(ctrl.lastEditorRange).toBeNull()
  })

  it("ignores selectionchange when there is no lexxy editor", async () => {
    const noEditorHtml =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, noEditorHtml)
    const c = controllerFor(app, el, "template-token-picker")
    window.getSelection = () => ({ rangeCount: 1, anchorNode: el })
    expect(() => c.onSelectionChange()).not.toThrow()
    expect(c.lastEditorRange).toBeNull()
  })

  it("restores the saved editor range before inserting when the picker stole focus", () => {
    const editable = element.querySelector('[contenteditable="true"]')
    const savedRange = { commonAncestorContainer: editable }
    window.getSelection = () => ({
      rangeCount: 1,
      anchorNode: editable,
      getRangeAt: () => ({ cloneRange: () => savedRange })
    })
    ctrl.onSelectionChange()

    // Picker interaction moved the selection out of the editor.
    const pickerInput = element.querySelector("select")
    const selection = {
      rangeCount: 1,
      anchorNode: pickerInput,
      getRangeAt: () => null,
      removeAllRanges: vi.fn(),
      addRange: vi.fn(function (range) { this.anchorNode = range.commonAncestorContainer })
    }
    window.getSelection = () => selection
    document.execCommand = vi.fn(() => true)

    element.querySelector("select").value = uuid
    ctrl.insert()

    expect(selection.removeAllRanges).toHaveBeenCalled()
    expect(selection.addRange).toHaveBeenCalledWith(savedRange)
    expect(selection.addRange.mock.invocationCallOrder[0])
      .toBeLessThan(document.execCommand.mock.invocationCallOrder[0])
    expect(document.execCommand).toHaveBeenCalledWith("insertText", false, labelToken)
  })

  it("clears a stale saved range whose nodes were re-rendered and falls back", async () => {
    const modeHtml =
      `<div data-controller="template-token-picker">` +
      `<select data-template-token-picker-target="picker"><option value="${uuid}">First name</option></select>` +
      `<div data-template-editor-mode-target="richContainer">` +
      `<lexxy-editor><div contenteditable="true"></div></lexxy-editor>` +
      `</div>` +
      `<div data-template-editor-mode-target="codeContainer" class="hidden"><textarea></textarea></div>` +
      `</div>`
    const { application: app, element: el } = await mountController("template-token-picker", Controller, modeHtml)
    const c = controllerFor(app, el, "template-token-picker")
    const editor = el.querySelector("lexxy-editor")
    let stored = "<p>Body</p>"
    Object.defineProperty(editor, "value", {
      configurable: true,
      get() { return stored },
      set(v) { stored = v }
    })

    // Saved range points at a node a re-render has since detached.
    const detached = document.createElement("span")
    c.lastEditorRange = { commonAncestorContainer: detached }
    window.getSelection = () => ({ rangeCount: 0, getRangeAt: () => null })

    el.querySelector("select").value = uuid
    c.insert()

    expect(c.lastEditorRange).toBeNull()
    expect(stored).toContain(labelToken)
  })

  it("ignores a saved range that belongs to a different element", () => {
    const editable = element.querySelector('[contenteditable="true"]')
    const foreign = document.createElement("div")
    document.body.appendChild(foreign)
    ctrl.lastEditorRange = { commonAncestorContainer: foreign }

    const addRange = vi.fn()
    window.getSelection = () => ({
      rangeCount: 0,
      anchorNode: null,
      removeAllRanges: vi.fn(),
      addRange
    })
    document.execCommand = vi.fn(() => true)

    element.querySelector("select").value = uuid
    ctrl.insert()

    expect(addRange).not.toHaveBeenCalled()
    expect(ctrl.lastEditorRange).not.toBeNull()
    expect(editable.contains(foreign)).toBe(false)
    foreign.remove()
  })

  it("keeps the saved range when no selection is available at restore time", () => {
    const editable = element.querySelector('[contenteditable="true"]')
    const savedRange = { commonAncestorContainer: editable }
    ctrl.lastEditorRange = savedRange
    window.getSelection = () => null
    document.execCommand = vi.fn(() => true)

    element.querySelector("select").value = uuid
    ctrl.insert()

    expect(ctrl.lastEditorRange).toBe(savedRange)
    expect(document.execCommand).toHaveBeenCalledWith("insertText", false, labelToken)
  })

  it("clears the saved range when restoring it throws", () => {
    const editable = element.querySelector('[contenteditable="true"]')
    ctrl.lastEditorRange = { commonAncestorContainer: editable }
    window.getSelection = () => ({
      rangeCount: 1,
      anchorNode: null,
      removeAllRanges: vi.fn(),
      addRange: vi.fn(() => { throw new Error("stale") })
    })
    document.execCommand = vi.fn(() => true)

    element.querySelector("select").value = uuid
    expect(() => ctrl.insert()).not.toThrow()
    expect(ctrl.lastEditorRange).toBeNull()
    expect(document.execCommand).toHaveBeenCalledWith("insertText", false, labelToken)
  })

  it("removes the selectionchange listener on disconnect", () => {
    const spy = vi.spyOn(document, "removeEventListener")
    ctrl.disconnect()
    expect(spy).toHaveBeenCalledWith("selectionchange", ctrl.onSelectionChange)
  })

})
