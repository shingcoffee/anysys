// app/javascript/controllers/context_autocomplete_controller.js

import { Controller } from "@hotwired/stimulus"
import { getAvailableVariables, filterVariables } from "flowchart/context_variable_provider"
import { OUTPUT_VAR_KEYS } from "controllers/property_editor/templates"
import { escapeHtml } from "utils"

/**
 * Context Autocomplete Controller
 *
 * Attaches to text/textarea config fields to show available context variables.
 * Shows a dropdown on typing, supports keyboard navigation, inserts selection.
 *
 * Round-2: can be mounted on a `relative` wrapper div (new) — the input gets
 * data-context-autocomplete-target="input". Legacy mounts directly on the input
 * keep working identically via the `_input` getter.
 */
export default class extends Controller {
  static targets = ["input"]
  static values = {
    elementId: String,
    stepIndex: { type: Number, default: -1 },
    // i18n seam: English defaults byte-identical to the former hardcoded copy.
    // NOTE: this controller's mount markup is generated dynamically by the
    // out-of-scope property_editor/* JS family (form_builder.js,
    // branch_manager.js, templates/fields.js) rather than an ERB — see notes
    // in the frontend delivery report. The Values keep the seam ready for
    // reuse once that family wires translated values through.
    noVariablesAvailable: { type: String, default: "No variables available" },
    usedInThisElementLabel: { type: String, default: "Used in this element" },
    noMatchingVariablesLabel: { type: String, default: "No matching variables" }
  }

  /**
   * The text input/textarea this controller manages. New round-2 markup mounts
   * the controller on a `relative` wrapper (so the {x} button is in scope) and
   * marks the input with data-context-autocomplete-target="input". Legacy
   * markup mounts directly on the input — both keep working.
   */
  get _input() {
    return this.hasInputTarget ? this.inputTarget : this.element
  }

  connect() {
    this._dropdown = null
    this._selectedIndex = 0
    this._filteredGroups = []
    this._allOptions = []
    this._canvas = null
    this._debounceTimer = null

    this._boundOnInput = this._onInput.bind(this)
    this._boundOnKeydown = this._onKeydown.bind(this)
    this._boundOnBlur = this._onBlur.bind(this)
    this._boundOnClickOutside = this._onClickOutside.bind(this)

    this._input.addEventListener("input", this._boundOnInput)
    this._input.addEventListener("keydown", this._boundOnKeydown)
    this._input.addEventListener("blur", this._boundOnBlur)

    this._resolveCanvas()
  }

  disconnect() {
    this._input.removeEventListener("input", this._boundOnInput)
    this._input.removeEventListener("keydown", this._boundOnKeydown)
    this._input.removeEventListener("blur", this._boundOnBlur)
    document.removeEventListener("mousedown", this._boundOnClickOutside)
    if (this._debounceTimer) {
      clearTimeout(this._debounceTimer)
    }
    this._destroyDropdown()
  }

  _resolveCanvas() {
    const canvasEl = document.querySelector('[data-controller*="flowchart-canvas"]')
    this._canvas = canvasEl?.flowchartCanvas || null
  }

  _getWordAtCursor() {
    const input = this._input
    const value = input.value || ""
    const cursorPos = input.selectionStart || 0

    // Find word boundaries
    let start = cursorPos
    while (start > 0 && /\w/.test(value[start - 1])) {
      start--
    }

    let end = cursorPos
    while (end < value.length && /\w/.test(value[end])) {
      end++
    }

    return value.slice(start, end)
  }

  _flattenOptions(groups) {
    const options = []
    for (const group of groups) {
      for (const variable of group.variables) {
        options.push({ variable, groupLabel: group.label })
      }
    }
    return options
  }

  _ensureDropdown() {
    if (this._dropdown) return
    this._dropdown = document.createElement("div")
    this._dropdown.className = "context-autocomplete-dropdown bg-white border border-slate-200 rounded-lg shadow-lg max-h-64 overflow-y-auto w-64"
    this._dropdown.style.cssText = "position: fixed; z-index: 9999;"
    document.body.appendChild(this._dropdown)
    document.addEventListener("mousedown", this._boundOnClickOutside)
  }

  _renderDropdown() {
    this._ensureDropdown()
    this._positionDropdown()
    this._dropdown.innerHTML = this._buildDropdownHTML()
    this._updateSelection()
    this._wireOptionClicks()
  }

  /** mousedown handler on the {x} button — keeps focus on the input. */
  keepFocus(event) {
    event.preventDefault()
  }

  /**
   * Variable-pick button entry point: opens the same dropdown the keystroke
   * path uses, with the full (unfiltered) variable list plus a leading
   * "Used in this element" group of sibling-step output variables.
   * Purely additive — the typed path is unchanged.
   */
  async picker(event) {
    event.preventDefault()
    if (!this._canvas) this._resolveCanvas()

    // Stale-call guard: rapid re-clicks each bump the token; only the most
    // recent invocation may touch dropdown state after its await resolves.
    const token = (this._pickerToken = (this._pickerToken || 0) + 1)

    let groups = []
    try {
      const result = await getAvailableVariables(this._canvas, this.elementIdValue, this.stepIndexValue)
      groups = result.groups || []
    } catch {
      groups = []
    }
    if (token !== this._pickerToken) return

    this._filteredGroups = this._buildPickerGroups(groups, this._collectSiblingStepVars())
    this._allOptions = this._flattenOptions(this._filteredGroups)
    this._selectedIndex = 0

    if (this._allOptions.length > 0) {
      this._renderDropdown()
    } else {
      this._renderNoVariablesDropdown()
    }

    // Restore focus so ↓/↑/Enter/Escape are handled by _onKeydown immediately.
    this._input.focus()
  }

  /**
   * Sibling-step output variables (resultVar/outputKey/targetVariable) read
   * from the live DOM — the same [data-step-item]/[data-step-config] elements
   * collectSteps() uses. Empty under the current one-step-per-element cap;
   * future-proof for multi-step elements.
   */
  _collectSiblingStepVars() {
    const ownItem = this._input.closest("[data-step-item]")
    const container = ownItem?.closest("[data-steps-container]")
    if (!container) return []

    const vars = []
    container.querySelectorAll("[data-step-item]").forEach(item => {
      if (item === ownItem) return
      const configInput = item.querySelector("[data-step-config]")
      if (!configInput?.value) return
      try {
        const config = JSON.parse(configInput.value)
        OUTPUT_VAR_KEYS.forEach(key => {
          const v = config[key]
          if (typeof v === "string" && v.trim() !== "" && !vars.includes(v)) vars.push(v)
        })
      } catch { /* ignore malformed config JSON */ }
    })
    return vars
  }

  _buildPickerGroups(existingGroups, siblingVars) {
    if (!siblingVars || siblingVars.length === 0) return existingGroups
    return [
      { label: this.usedInThisElementLabelValue, source: "sibling-steps", variables: siblingVars },
      ...existingGroups
    ]
  }

  /** Non-interactive empty state for the picker path (UX 2.1e). */
  _renderNoVariablesDropdown() {
    this._ensureDropdown()
    this._positionDropdown()
    this._dropdown.innerHTML = `<div class="px-3 py-2 text-[11px] text-slate-400 italic">${this.noVariablesAvailableValue}</div>`
  }

  _positionDropdown() {
    const rect = this._input.getBoundingClientRect()
    const spaceBelow = window.innerHeight - rect.bottom
    const dropdownHeight = 256 // max-h-64 = 16rem = 256px

    if (spaceBelow < dropdownHeight && rect.top > dropdownHeight) {
      // Position above
      this._dropdown.style.top = `${rect.top - dropdownHeight}px`
    } else {
      // Position below
      this._dropdown.style.top = `${rect.bottom + 4}px`
    }
    this._dropdown.style.left = `${rect.left}px`
  }

  _buildDropdownHTML() {
    if (this._filteredGroups.length === 0) {
      return `<div class="px-3 py-2 text-xs text-slate-500 italic">${escapeHtml(this.noMatchingVariablesLabelValue)}</div>`
    }

    return this._filteredGroups.map(group => `
      <div class="context-autocomplete-group">
        <div class="px-2 py-1 text-[10px] font-semibold text-slate-500 uppercase tracking-wide bg-slate-50 sticky top-0">
          ${escapeHtml(group.label)}
        </div>
        ${group.variables.map(v => `
          <div class="context-autocomplete-option px-3 py-1.5 text-xs text-slate-700 cursor-pointer hover:bg-indigo-50"
               data-value="${escapeHtml(v)}">
            ${escapeHtml(v)}
          </div>
        `).join("")}
      </div>
    `).join("")
  }


  _wireOptionClicks() {
    const options = this._dropdown.querySelectorAll(".context-autocomplete-option")
    options.forEach((opt, _idx) => {
      opt.addEventListener("mousedown", (e) => {
        e.preventDefault()
        this._selectOption(opt.dataset.value)
      })
    })
  }

  async _onInput(_event) {
    if (this._debounceTimer) {
      clearTimeout(this._debounceTimer)
    }

    this._debounceTimer = setTimeout(async () => {
      if (!this._canvas) {
        this._resolveCanvas()
        if (!this._canvas) {
          this._destroyDropdown()
          return
        }
      }

      const term = this._getWordAtCursor()
      const result = await getAvailableVariables(this._canvas, this.elementIdValue, this.stepIndexValue)
      const filtered = filterVariables(result, term)

      this._filteredGroups = filtered.groups
      this._allOptions = this._flattenOptions(filtered.groups)
      this._selectedIndex = 0

      if (this._allOptions.length > 0) {
        this._renderDropdown()
      } else {
        this._destroyDropdown()
      }
    }, 100)
  }

  _onKeydown(event) {
    if (!this._dropdown) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this._selectedIndex = Math.min(this._selectedIndex + 1, this._allOptions.length - 1)
        this._updateSelection()
        break

      case "ArrowUp":
        event.preventDefault()
        this._selectedIndex = Math.max(this._selectedIndex - 1, 0)
        this._updateSelection()
        break

      case "Enter":
      case "Tab":
        if (this._allOptions.length > 0) {
          event.preventDefault()
          const selected = this._allOptions[this._selectedIndex]
          if (selected) {
            this._selectOption(selected.variable)
          }
        }
        break

      case "Escape":
        event.preventDefault()
        this._destroyDropdown()
        break
    }
  }

  _updateSelection() {
    if (!this._dropdown) return

    const options = this._dropdown.querySelectorAll(".context-autocomplete-option")
    options.forEach((opt, idx) => {
      if (idx === this._selectedIndex) {
        opt.classList.add("bg-indigo-100", "text-indigo-900")
        opt.classList.remove("hover:bg-indigo-50")
        opt.scrollIntoView({ block: "nearest" })
      } else {
        opt.classList.remove("bg-indigo-100", "text-indigo-900")
        opt.classList.add("hover:bg-indigo-50")
      }
    })
  }

  _selectOption(variable) {
    const input = this._input
    const value = input.value || ""
    const cursorPos = input.selectionStart || 0

    // Find word boundaries to replace
    let start = cursorPos
    while (start > 0 && /\w/.test(value[start - 1])) {
      start--
    }

    let end = cursorPos
    while (end < value.length && /\w/.test(value[end])) {
      end++
    }

    // Replace word with selected variable
    const before = value.slice(0, start)
    const after = value.slice(end)
    input.value = before + variable + after

    // Position cursor after inserted variable
    const newPos = start + variable.length
    input.setSelectionRange(newPos, newPos)

    // Dispatch input event to trigger form sync
    input.dispatchEvent(new Event("input", { bubbles: true }))

    // Clear debounce timer to prevent re-opening dropdown after synthetic input event
    if (this._debounceTimer) {
      clearTimeout(this._debounceTimer)
      this._debounceTimer = null
    }

    this._destroyDropdown()
  }

  _onBlur(_event) {
    // Close dropdown after short delay to allow click on option. Keep it open
    // when focus has already returned to the input (picker() refocuses it).
    setTimeout(() => {
      if (!this._dropdown?.contains(document.activeElement) && document.activeElement !== this._input) {
        this._destroyDropdown()
      }
    }, 150)
  }

  _onClickOutside(event) {
    if (this._dropdown && !this._dropdown.contains(event.target) && !this.element.contains(event.target)) {
      this._destroyDropdown()
    }
  }

  _destroyDropdown() {
    if (this._dropdown) {
      this._dropdown.remove()
      this._dropdown = null
      document.removeEventListener("mousedown", this._boundOnClickOutside)
    }
    this._selectedIndex = 0
    this._filteredGroups = []
    this._allOptions = []
  }
}
