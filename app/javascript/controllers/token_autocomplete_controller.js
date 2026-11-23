import { Controller } from "@hotwired/stimulus"

// Typing "{{" in the attached text field opens a token autocomplete menu.
// Typing further filters by label (case-insensitive); ArrowUp/ArrowDown move
// the active option, Enter or click inserts "{{label}}" replacing the partial
// "{{query", Escape or blur dismisses. Tokens arrive from the server as a
// JSON Value so this file holds no literal UI strings (i18n rule).
export default class extends Controller {
  static targets = ["input"]
  static values = {
    tokens: { type: Array, default: [] },
    noMatches: { type: String, default: "No matching tokens" }
  }

  connect() {
    this._activeIndex = 0
    this._matches = []
    this._triggerStart = -1

    this._boundOnInput = this.#onInput.bind(this)
    this._boundOnKeydown = this.#onKeydown.bind(this)
    this._boundOnBlur = this.#onBlur.bind(this)

    this._input.addEventListener("input", this._boundOnInput)
    this._input.addEventListener("keydown", this._boundOnKeydown)
    this._input.addEventListener("blur", this._boundOnBlur)

    this._menu = this.#buildMenu()
    this.element.appendChild(this._menu)
  }

  disconnect() {
    this._input.removeEventListener("input", this._boundOnInput)
    this._input.removeEventListener("keydown", this._boundOnKeydown)
    this._input.removeEventListener("blur", this._boundOnBlur)
    this._menu?.remove()
    this._menu = null
  }

  get _input() {
    return this.hasInputTarget ? this.inputTarget : this.element.querySelector("input")
  }

  get _open() {
    return this._menu && !this._menu.classList.contains("hidden")
  }

  #buildMenu() {
    const menu = document.createElement("div")
    menu.className = "token-autocomplete-menu absolute left-0 top-full z-50 mt-1 hidden max-h-60 w-full overflow-y-auto rounded-lg border border-border bg-surface shadow-lg"
    menu.setAttribute("role", "listbox")
    // mousedown fires before the input's blur; preventDefault keeps focus in
    // the field so a menu click never triggers a dismiss-then-miss.
    menu.addEventListener("mousedown", (event) => event.preventDefault())
    return menu
  }

  #onInput() {
    const trigger = this.#triggerAtCaret()
    if (!trigger) {
      this.#close()
      return
    }

    this._triggerStart = trigger.start
    this._matches = this.tokensValue.filter((token) =>
      token.label.toLowerCase().includes(trigger.query.toLowerCase())
    )
    this._activeIndex = 0
    this.#renderOptions()
    this.#open()
  }

  // Returns { start, query } when the caret sits inside an unfinished
  // "{{query" run, or null when no live trigger is present.
  #triggerAtCaret() {
    const caret = this._input.selectionStart
    if (caret == null) return null

    const value = this._input.value
    const start = value.lastIndexOf("{{", caret - 1)
    if (start === -1) return null

    // A "}}" anywhere after the opening pair means the token is already
    // closed (the caret is editing a finished label or sitting past it).
    if (value.indexOf("}}", start + 2) !== -1) return null

    return { start, query: value.slice(start + 2, caret) }
  }

  #renderOptions() {
    this._menu.replaceChildren()

    if (this._matches.length === 0) {
      const empty = document.createElement("div")
      empty.className = "token-autocomplete-empty px-3 py-2 text-sm text-text-muted"
      empty.textContent = this.noMatchesValue
      this._menu.appendChild(empty)
      return
    }

    this._matches.forEach((token, index) => {
      const option = document.createElement("button")
      option.type = "button"
      option.setAttribute("role", "option")
      option.dataset.index = String(index)
      option.className = this.#optionClasses(index === this._activeIndex)

      const label = document.createElement("span")
      label.className = "truncate text-text-primary"
      label.textContent = token.label
      option.appendChild(label)

      const group = document.createElement("span")
      group.className = "shrink-0 text-xs text-text-muted"
      group.textContent = token.group
      option.appendChild(group)

      option.addEventListener("mousedown", (event) => {
        event.preventDefault()
        this.#choose(index)
      })
      this._menu.appendChild(option)
    })
  }

  #optionClasses(active) {
    const base = "token-autocomplete-option flex w-full items-center justify-between gap-2 px-3 py-2 text-left text-sm cursor-pointer"
    return active ? `${base} bg-surface-hover` : `${base} hover:bg-surface-hover`
  }

  #onKeydown(event) {
    if (!this._open) return

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.#moveActive(1)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.#moveActive(-1)
    } else if (event.key === "Enter") {
      event.preventDefault()
      this.#choose(this._activeIndex)
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.#close()
    }
  }

  #moveActive(delta) {
    if (this._matches.length === 0) return

    this._activeIndex = (this._activeIndex + delta + this._matches.length) % this._matches.length
    this._menu.querySelectorAll(".token-autocomplete-option").forEach((option, index) => {
      option.className = this.#optionClasses(index === this._activeIndex)
    })
    this._menu.querySelector(`[data-index="${this._activeIndex}"]`)?.scrollIntoView({ block: "nearest" })
  }

  #choose(index) {
    const token = this._matches[index]
    if (!token) return

    const caret = this._input.selectionStart == null ? this._input.value.length : this._input.selectionStart
    const inserted = `{{${token.label}}}`
    this._input.value = this._input.value.slice(0, this._triggerStart) + inserted + this._input.value.slice(caret)

    const nextCaret = this._triggerStart + inserted.length
    this._input.focus()
    this._input.setSelectionRange(nextCaret, nextCaret)
    // Re-dispatch so ancestor preview controllers (input->...#debouncedLoadPreview)
    // refresh with the inserted token.
    this._input.dispatchEvent(new Event("input", { bubbles: true }))
    this.#close()
  }

  #onBlur() {
    this.#close()
  }

  #open() {
    this._menu.classList.remove("hidden")
  }

  #close() {
    this._menu?.classList.add("hidden")
    this._triggerStart = -1
  }
}
