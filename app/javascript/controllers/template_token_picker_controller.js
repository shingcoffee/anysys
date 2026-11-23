import { Controller } from "@hotwired/stimulus"

const PLAIN_FIELD_SELECTOR = [
  'input[name="email_template[subject]"]',
  'textarea[name="email_template[body_text]"]',
  'textarea[name="email_template[body_html]"]'
].join(", ")

// Inserts a human-readable {{Label}} token into the focused editor surface.
// Lexxy strips custom chip HTML, so rich text must use plain label tokens.
// Storage always normalizes to {{uuid}} on submit / model save.
export default class extends Controller {
  static targets = ["picker"]

  connect() {
    this.lastPlainField = null
    this.lastEditorRange = null
    this.onFocusIn = this.#onFocusIn.bind(this)
    this.onSelectionChange = this.#onSelectionChange.bind(this)
    this.#focusScope().addEventListener("focusin", this.onFocusIn)
    document.addEventListener("selectionchange", this.onSelectionChange)
  }

  disconnect() {
    this.#focusScope().removeEventListener("focusin", this.onFocusIn)
    document.removeEventListener("selectionchange", this.onSelectionChange)
  }

  insert(event) {
    const input = this.#tokenSource(event)
    const token = (input?.value || "").trim()
    if (!token) return

    // Never insert the storage UUID into the editor — only human labels.
    const label = this.#labelFor(input, token)
    if (!label) {
      this.#resetPicker(input)
      return
    }

    const displayToken = `{{${label}}}`
    if (!this.#insertIntoEditor(displayToken)) return

    this.#resetPicker(input)
  }

  #focusScope() {
    return this.element.closest("form") || this.element
  }

  #onFocusIn(event) {
    const target = event.target
    if (!target) return

    if (target.matches?.(PLAIN_FIELD_SELECTOR)) {
      this.lastPlainField = target
      return
    }

    if (target.closest?.("lexxy-editor") || target.isContentEditable || target.getAttribute?.("contenteditable") === "true") {
      this.lastPlainField = null
    }
  }

  // Picking a token from the dropdown steals the DOM selection, so the caret
  // insert path must restore the last range captured while the rich editor
  // still owned the selection — otherwise the token lands at the tail.
  #onSelectionChange() {
    const editable = this.#richEditable()
    if (!editable) return

    const sel = window.getSelection()
    if (!sel || sel.rangeCount === 0) return
    if (!this.#selectionIn(editable)) return

    this.lastEditorRange = sel.getRangeAt(0).cloneRange()
  }

  #richEditable() {
    const host = this.element.querySelector("lexxy-editor")
    if (!host) return null
    return host.querySelector('[contenteditable="true"]') || host
  }

  #labelFor(input, token) {
    const selected = input && input.selectedOptions && input.selectedOptions[0]
    if (selected) {
      const fromOption = this.#readableLabel(selected.getAttribute?.("data-label"), selected.text)
      if (fromOption) return fromOption
    }

    const selectEl = this.element.querySelector('[data-controller~="searchable-select"]')
    if (!selectEl) return null

    const options = selectEl.querySelectorAll('[data-searchable-select-target="option"]')
    for (const option of options) {
      if (option.getAttribute("data-value") !== token) continue
      const fromOption = this.#readableLabel(option.getAttribute("data-label"), option.textContent)
      if (fromOption) return fromOption
    }

    const search = selectEl.querySelector('[data-searchable-select-target="search"]')
    if (search && search.value) {
      // After select(), search shows "Label  —  Group"; keep only the label.
      const fromSearch = this.#readableLabel(search.value.split(/\s+—\s+/)[0])
      if (fromSearch) return fromSearch
    }

    return null
  }

  #readableLabel(...candidates) {
    for (const candidate of candidates) {
      const trimmed = String(candidate || "").trim()
      if (!trimmed) continue
      if (this.#looksLikeUuid(trimmed)) continue
      return trimmed
    }
    return null
  }

  #looksLikeUuid(value) {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(value).trim())
  }

  #tokenSource(event) {
    if (event && event.target && event.target.matches && event.target.matches('input[type="hidden"]')) {
      return event.target
    }
    if (this.hasPickerTarget) return this.pickerTarget
    return this.element.querySelector('[data-searchable-select-target="hidden"]')
  }

  #insertIntoEditor(displayToken) {
    const form = this.element.matches("form") ? this.element : this.element.closest("form")
    const scope = form || this.element

    // Prefer the last-focused plain field (subject / body_text / code HTML).
    // Use isConnected + selector match — HTMLFormElement#contains is unreliable
    // for form controls in some DOM implementations (e.g. happy-dom).
    if (this.lastPlainField?.isConnected && this.lastPlainField.matches?.(PLAIN_FIELD_SELECTOR)) {
      this.#insertIntoTextarea(this.lastPlainField, displayToken)
      return true
    }

    const richContainer = this.element.querySelector("[data-template-editor-mode-target='richContainer']")
    const codeContainer = this.element.querySelector("[data-template-editor-mode-target='codeContainer']")
    const richVisible = richContainer && !richContainer.classList.contains("hidden")
    const codeVisible = codeContainer && !codeContainer.classList.contains("hidden")

    if (richVisible) {
      return this.#insertIntoRich(displayToken)
    }

    if (codeVisible) {
      const textarea = codeContainer.querySelector("textarea")
      if (!textarea) return false
      this.#insertIntoTextarea(textarea, displayToken)
      return true
    }

    // Legacy fixture: lexxy without mode containers
    const editor = this.element.querySelector("lexxy-editor")
    if (editor) {
      return this.#insertIntoRich(displayToken, editor)
    }

    const textField = scope.querySelector(PLAIN_FIELD_SELECTOR) || scope.querySelector("textarea")
    if (textField) {
      this.#insertIntoTextarea(textField, displayToken)
      return true
    }

    return false
  }

  #insertIntoRich(displayToken, editor = null) {
    const host = editor || this.element.querySelector("lexxy-editor")
    if (!host) return false

    const nestedEditable = host.querySelector('[contenteditable="true"]')
    const editable = nestedEditable || host
    this.#restoreEditorSelection(editable)
    if (this.#tryCursorInsertText(editable, displayToken)) return true
    if (this.#appendToLexxyValue(host, displayToken)) return true
    return this.#tryCursorInsertText(editable, displayToken, { force: true })
  }

  #restoreEditorSelection(editable) {
    const saved = this.lastEditorRange
    if (!saved) return

    // A re-render (mode switch, external value set) detaches the saved nodes.
    const container = saved.commonAncestorContainer
    if (!container?.isConnected) {
      this.lastEditorRange = null
      return
    }
    if (editable !== container && !editable.contains(container)) return

    const sel = window.getSelection()
    if (!sel) return

    try {
      sel.removeAllRanges()
      sel.addRange(saved)
    } catch {
      this.lastEditorRange = null
    }
  }

  #tryCursorInsertText(editable, text, { force = false } = {}) {
    if (!force && !this.#selectionIn(editable)) return false

    editable.focus()

    if (this.#exec("insertText", text)) {
      editable.dispatchEvent(new Event("input", { bubbles: true }))
      return true
    }

    const inserted = editable.dispatchEvent(new InputEvent("beforeinput", {
      inputType: "insertText",
      data: text,
      bubbles: true,
      cancelable: true
    }))
    if (inserted !== false) {
      // Some editors apply on beforeinput; also try a DOM fallback below.
    }

    const sel = window.getSelection()
    if (sel && sel.rangeCount > 0) {
      const range = sel.getRangeAt(0)
      if (editable === range.commonAncestorContainer || editable.contains(range.commonAncestorContainer)) {
        range.deleteContents()
        const node = document.createTextNode(text)
        range.insertNode(node)
        range.setStartAfter(node)
        range.collapse(true)
        sel.removeAllRanges()
        sel.addRange(range)
        editable.dispatchEvent(new Event("input", { bubbles: true }))
        return true
      }
    }

    return this.#appendTextViaDom(editable, text)
  }

  #appendTextViaDom(editable, text) {
    editable.appendChild(document.createTextNode(text))
    editable.dispatchEvent(new Event("input", { bubbles: true }))
    return true
  }

  #exec(command, value) {
    try {
      return !!document.execCommand(command, false, value)
    } catch {
      return false
    }
  }

  #selectionIn(editable) {
    const sel = window.getSelection()
    if (!sel || sel.rangeCount === 0) return false
    const anchor = sel.anchorNode
    if (!anchor) return false
    return editable === anchor || editable.contains(anchor)
  }

  #appendToLexxyValue(editor, text) {
    if (typeof editor.value !== "string") return false

    const html = editor.value
    let next
    if (!html.trim()) {
      next = `<p>${text}</p>`
    } else if (/<\/p>\s*$/i.test(html)) {
      next = html.replace(/<\/p>\s*$/i, `${text}</p>`)
    } else {
      next = `${html}<p>${text}</p>`
    }

    editor.value = next
    editor.dispatchEvent(new Event("input", { bubbles: true }))
    return true
  }

  #insertIntoTextarea(textarea, text) {
    const start = textarea.selectionStart == null ? textarea.value.length : textarea.selectionStart
    const end = textarea.selectionEnd == null ? start : textarea.selectionEnd
    const before = textarea.value.slice(0, start)
    const after = textarea.value.slice(end)
    textarea.value = `${before}${text}${after}`
    const caret = start + text.length
    textarea.focus()
    textarea.setSelectionRange(caret, caret)
    textarea.dispatchEvent(new Event("input", { bubbles: true }))
  }

  #resetPicker(input) {
    if (this.hasPickerTarget && input === this.pickerTarget) {
      this.pickerTarget.value = ""
      return
    }

    const selectEl = this.element.querySelector('[data-controller~="searchable-select"]')
    if (!selectEl) {
      if (input) input.value = ""
      return
    }

    const selectCtrl = this.application.getControllerForElementAndIdentifier(selectEl, "searchable-select")
    if (selectCtrl) {
      selectCtrl.hiddenTarget.value = ""
      selectCtrl.searchTarget.value = ""
      selectCtrl.selectedValue = ""
      if (selectCtrl.hasClearTarget) selectCtrl.clearTarget.classList.add("hidden")
      selectCtrl.resetFilter()
      selectCtrl.close()
    } else if (input) {
      input.value = ""
    }
  }
}
