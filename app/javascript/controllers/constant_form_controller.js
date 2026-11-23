import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { escapeHtml } from "utils"

/**
 * ConstantFormController
 *
 * Manages the constant form with dynamic options management.
 * Option reordering is handled by SortableJS (drag from the .drag-handle);
 * the controller only renumbers the visible index labels after a drop.
 */
export default class extends Controller {
  static targets = [
    "optionsField",
    "optionsContainer",
    "emptyState"
  ]

  static values = {
    // ── i18n seam: English defaults keep JS specs green without any
    // data-*-value attribute; the mounting form (constants/_form.html.erb)
    // supplies translated strings via
    // data-constant-form-<name>-value="<%= t(...) %>". ──
    duplicateErrorFormat: { type: String, default: "Duplicate option values found: {values}. Each option must be unique." },
    optionValuePlaceholder: { type: String, default: "Option value" },
    removeOptionLabel: { type: String, default: "Remove option" }
  }

  connect() {
    this.optionIndex = this.getExistingOptionsCount()
    this.setupSortable()
    this.attachInputListeners()
  }

  disconnect() {
    this.sortable?.destroy()
    this.sortable = null
  }

  getExistingOptionsCount() {
    if (!this.hasOptionsContainerTarget) return 0
    return this.optionsContainerTarget.querySelectorAll("[data-option-item]").length
  }

  addOption(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }

    this.hideEmptyState()
    this.removeDuplicateError()

    if (!this.hasOptionsContainerTarget) return

    const html = this.buildOptionHtml()
    this.optionsContainerTarget.insertAdjacentHTML("beforeend", html)
    this.optionsContainerTarget.classList.remove("hidden")
    this.optionIndex++

    // Focus the new input
    const newOption = this.optionsContainerTarget.lastElementChild
    const input = newOption.querySelector("input[data-option-input]")
    if (input) {
      input.focus()
      // Add input event listener to clear errors on typing
      input.addEventListener("input", () => this.removeDuplicateError())
    }
  }

  removeOption(event) {
    event.preventDefault()
    event.stopPropagation()

    const optionItem = event.target.closest("[data-option-item]")
    if (!optionItem) return

    optionItem.remove()
    this.renumberOptions()
    this.showEmptyStateIfNeeded()
    this.removeDuplicateError()
  }

  attachInputListeners() {
    if (!this.hasOptionsContainerTarget) return

    this.optionsContainerTarget.querySelectorAll("[data-option-input]").forEach(input => {
      input.addEventListener("input", () => this.removeDuplicateError())
    })
  }

  collectOptions(event) {
    if (!this.hasOptionsFieldTarget || !this.hasOptionsContainerTarget) return

    const options = Array.from(
      this.optionsContainerTarget.querySelectorAll("[data-option-input]")
    ).map(input => input.value.trim()).filter(Boolean)

    // Check for duplicates
    const duplicates = this.findDuplicates(options)
    if (duplicates.length > 0) {
      event.preventDefault()
      this.showDuplicateError(duplicates)
      return false
    }

    this.optionsFieldTarget.value = JSON.stringify(options)
  }

  findDuplicates(array) {
    const seen = new Set()
    const duplicates = new Set()

    array.forEach(item => {
      if (seen.has(item)) {
        duplicates.add(item)
      }
      seen.add(item)
    })

    return Array.from(duplicates)
  }

  showDuplicateError(duplicates) {
    const message = this.duplicateErrorFormatValue.replace("{values}", duplicates.join(", "))

    // Remove existing error if present
    this.removeDuplicateError()

    // Create error message element
    const errorDiv = document.createElement("div")
    errorDiv.className = "mt-3 p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700"
    errorDiv.setAttribute("data-duplicate-error", "")
    errorDiv.innerHTML = `
      <div class="flex items-start">
        <svg class="w-5 h-5 text-red-500 mr-2 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
        </svg>
        <span>${escapeHtml(message)}</span>
      </div>
    `

    // Insert after options container
    if (this.hasOptionsContainerTarget) {
      this.optionsContainerTarget.parentElement.appendChild(errorDiv)
    }

    // Highlight duplicate inputs
    this.highlightDuplicates(duplicates)
  }

  removeDuplicateError() {
    const errorElement = this.element.querySelector("[data-duplicate-error]")
    if (errorElement) {
      errorElement.remove()
    }

    // Remove highlighting from all inputs. Guard with hasOptionsContainerTarget:
    // the `this.optionsContainerTarget` getter THROWS when the target is absent,
    // so an optional chain on its result would not prevent the throw.
    if (this.hasOptionsContainerTarget) {
      this.optionsContainerTarget.querySelectorAll("[data-option-input]").forEach(input => {
        input.classList.remove("border-red-500", "bg-red-50")
      })
    }
  }

  highlightDuplicates(duplicates) {
    if (!this.hasOptionsContainerTarget) return

    const inputs = this.optionsContainerTarget.querySelectorAll("[data-option-input]")
    inputs.forEach(input => {
      if (duplicates.includes(input.value.trim())) {
        input.classList.add("border-red-500", "bg-red-50")
      }
    })
  }

  renumberOptions() {
    if (!this.hasOptionsContainerTarget) return

    const items = this.optionsContainerTarget.querySelectorAll("[data-option-item]")
    items.forEach((item, index) => {
      const numberSpan = item.querySelector("span")
      if (numberSpan) numberSpan.textContent = `${index + 1}.`
    })
  }

  hideEmptyState() {
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.add("hidden")
    }
  }

  showEmptyStateIfNeeded() {
    if (!this.hasOptionsContainerTarget || !this.hasEmptyStateTarget) return

    const hasOptions = this.optionsContainerTarget.querySelectorAll("[data-option-item]").length > 0

    if (!hasOptions) {
      this.emptyStateTarget.classList.remove("hidden")
      this.optionsContainerTarget.classList.add("hidden")
    }
  }

  buildOptionHtml() {
    return `
      <div data-option-item class="flex items-center gap-2">
        <svg class="size-4 text-text-muted shrink-0 drag-handle cursor-grab" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8h16M4 16h16" />
        </svg>
        <span class="text-caption font-medium w-6 shrink-0 tabular-nums">${this.optionIndex + 1}.</span>
        <input type="text"
               data-option-input
               placeholder="${escapeHtml(this.optionValuePlaceholderValue)}"
               class="input-field flex-1 py-1.5">
        <button type="button"
                data-action="click->constant-form#removeOption"
                class="p-1.5 text-text-muted hover:text-danger rounded-md transition-colors"
                title="${escapeHtml(this.removeOptionLabelValue)}">
          <svg class="size-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
    `
  }

  // ===================
  // Drag and Drop (SortableJS)
  // ===================

  setupSortable() {
    if (!this.hasOptionsContainerTarget) return

    this.sortable = Sortable.create(this.optionsContainerTarget, {
      handle: ".drag-handle",
      draggable: "[data-option-item]",
      animation: 150,
      ghostClass: "opacity-50",
      onEnd: () => this.renumberOptions()
    })
  }
}
