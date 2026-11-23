import { Controller } from "@hotwired/stimulus"

const MODE_BUTTON_ACTIVE_CLASSES = ["bg-surface", "text-text-primary", "shadow-sm"]
const MODE_BUTTON_INACTIVE_CLASSES = ["text-text-secondary", "hover:text-text-primary"]

// Toggles between the rich_text (Lexxy <lexxy-editor>) and code (raw HTML)
// editor containers when the editor_type <select> value changes, and keeps
// both surfaces in sync so switching modes reflects the same content.
//
// The select is visually hidden (sr-only) and acts as the form value carrier;
// users switch modes through segmented mode buttons.
//
// Targets:
//   select         — the editor_type <select> element
//   richContainer  — the container wrapping the Lexxy rich-text editor
//   codeContainer  — the container wrapping the raw HTML textarea
//   codeInput      — optional raw HTML textarea; `required` only in code mode
//   modeButton     — optional segmented buttons carrying data-mode
export default class extends Controller {
  static targets = ["select", "richContainer", "codeContainer", "codeInput", "modeButton"]
  static values  = { initial: String }

  connect() {
    this.currentMode = this.initialValue || this.selectTarget.value || "rich_text"
    this.applyMode(this.currentMode)
  }

  // Segmented-button entry point: mirror the mode into the hidden select and
  // dispatch change so the select's data-action bindings (switch + preview
  // reload) fire exactly as they do for a native select change.
  choose(event) {
    event.preventDefault()
    const mode = event.currentTarget.dataset.mode
    if (!mode) return

    this.selectTarget.value = mode
    this.selectTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  switch() {
    const next = this.selectTarget.value
    const prev = this.currentMode || this.initialValue || "rich_text"
    if (next !== prev) this.syncContent(prev, next)
    this.applyMode(next)
    this.currentMode = next
  }

  applyMode(mode) {
    const isRich = mode === "rich_text"
    this.richContainerTarget.classList.toggle("hidden", !isRich)
    this.codeContainerTarget.classList.toggle("hidden", isRich)
    if (this.hasCodeInputTarget) {
      this.codeInputTarget.required = !isRich
    }
    this.#syncModeButtons(mode)
  }

  syncContent(from, to) {
    const editor = this.richContainerTarget.querySelector("lexxy-editor")
    const textarea = this.codeContainerTarget.querySelector("textarea")
    if (!editor || !textarea) return

    if (from === "rich_text" && to === "code") {
      textarea.value = typeof editor.value === "string" ? editor.value : (textarea.value || "")
      textarea.dispatchEvent(new Event("input", { bubbles: true }))
      return
    }

    if (from === "code" && to === "rich_text") {
      const html = textarea.value
      editor.value = html && html.trim() !== "" ? html : "<p></p>"
      editor.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }

  #syncModeButtons(mode) {
    if (!this.hasModeButtonTarget) return

    this.modeButtonTargets.forEach((button) => {
      const active = button.dataset.mode === mode
      button.setAttribute("aria-pressed", String(active))
      MODE_BUTTON_ACTIVE_CLASSES.forEach((cls) => button.classList.toggle(cls, active))
      MODE_BUTTON_INACTIVE_CLASSES.forEach((cls) => button.classList.toggle(cls, !active))
    })
  }
}
