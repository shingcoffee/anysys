import { Controller } from "@hotwired/stimulus"
import { escapeHtml } from "utils"
import { fetchReferenceOptions, filterReferenceOptions } from "controllers/property_editor/controls/reference_options"

export default class extends Controller {
  static targets = ["hidden", "trigger", "label", "dropdown", "search", "status", "list"]
  static values = {
    source: { type: String, default: "" },
    selected: { type: String, default: "" },
    searchPlaceholder: { type: String, default: "Search…" },
    loadingLabel: { type: String, default: "Loading…" },
    emptyLabel: { type: String, default: "No matches" },
    errorLabel: { type: String, default: "Could not load options" },
    placeholder: { type: String, default: "Select…" }
  }

  connect() {
    this.open = false
    this.options = []
    this.loaded = false
    this.boundClickOutside = this.clickOutside.bind(this)
    document.addEventListener("click", this.boundClickOutside)
    this.#paintLabel()
    if (this.selectedValue) this.#resolveSelectedLabel()
  }

  disconnect() {
    document.removeEventListener("click", this.boundClickOutside)
  }

  async toggle(event) {
    event.preventDefault()
    if (this.open) {
      this.#close()
      return
    }
    this.#open()
    if (!this.loaded) {
      this.#setStatus(this.loadingLabelValue)
      const result = await fetchReferenceOptions(this.sourceValue)
      this.loaded = true
      this.options = result.options
      if (!result.ok) {
        this.#setStatus(this.errorLabelValue)
        this.listTarget.innerHTML = ""
        return
      }
      this.#paintLabel()
    }
    this.#render(this.searchTarget.value)
  }

  filter() {
    this.#render(this.searchTarget.value)
  }

  keydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.#close()
    }
  }

  pick(event) {
    const button = event.target.closest("[data-reference-option]")
    if (!button) return
    const value = button.dataset.referenceOption
    const label = button.dataset.referenceLabel || value
    this.selectedValue = value
    if (this.hasHiddenTarget) {
      this.hiddenTarget.value = value
      this.hiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }
    if (this.hasLabelTarget) this.labelTarget.textContent = label
    this.triggerTarget.classList.remove("text-slate-400")
    this.triggerTarget.classList.add("text-slate-800")
    this.#close()
  }

  clickOutside(event) {
    if (!this.open) return
    if (this.element.contains(event.target)) return
    this.#close()
  }

  #open() {
    this.open = true
    this.dropdownTarget.classList.remove("hidden")
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.searchTarget.focus()
  }

  #close() {
    this.open = false
    this.dropdownTarget.classList.add("hidden")
    this.triggerTarget.setAttribute("aria-expanded", "false")
  }

  #setStatus(text) {
    this.statusTarget.textContent = text
    this.statusTarget.classList.toggle("hidden", !text)
  }

  async #resolveSelectedLabel() {
    const result = await fetchReferenceOptions(this.sourceValue)
    if (!result.ok) return
    this.loaded = true
    this.options = result.options
    this.#paintLabel()
  }

  #paintLabel() {
    if (!this.hasLabelTarget) return
    const match = this.selectedValue
      ? this.options.find(opt => String(opt.value ?? "") === this.selectedValue)
      : null
    this.labelTarget.textContent = match
      ? String(match.label ?? match.value)
      : (this.selectedValue || this.placeholderValue)
  }

  #render(query) {
    const matches = filterReferenceOptions(this.options, query)
    if (matches.length === 0) {
      this.#setStatus(this.emptyLabelValue)
      this.listTarget.innerHTML = ""
      return
    }
    this.#setStatus("")
    this.listTarget.innerHTML = matches.map(opt => {
      const value = String(opt.value ?? "")
      const label = String(opt.label ?? value)
      const active = value === this.selectedValue ? " bg-indigo-50 text-indigo-700" : " text-slate-700 hover:bg-slate-50"
      return `<button type="button" data-reference-option="${escapeHtml(value)}" data-reference-label="${escapeHtml(label)}"
                  data-action="click->property-editor--controls--reference-picker#pick"
                  class="flex w-full px-2 py-1.5 text-xs text-left${active}">${escapeHtml(label)}</button>`
    }).join("")
  }
}
