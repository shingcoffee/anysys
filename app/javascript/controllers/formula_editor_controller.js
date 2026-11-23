// app/javascript/controllers/formula_editor_controller.js
import { Controller } from "@hotwired/stimulus"
import { validateFormula } from "lib/formula_validator"

const FUNCTION_LIST = [
  { name: "SUM", sig: "SUM(n1, n2, ...)" },
  { name: "SUBTRACT", sig: "SUBTRACT(a, b)" },
  { name: "MULTIPLY", sig: "MULTIPLY(a, b, ...)" },
  { name: "DIVIDE", sig: "DIVIDE(a, b)" },
  { name: "MIN", sig: "MIN(n1, n2, ...)" },
  { name: "MAX", sig: "MAX(n1, n2, ...)" },
  { name: "AVERAGE", sig: "AVERAGE(n1, n2, ...)" },
  { name: "ROUND", sig: "ROUND(number, decimals)" },
  { name: "FLOOR", sig: "FLOOR(number)" },
  { name: "CEIL", sig: "CEIL(number)" },
  { name: "ABS", sig: "ABS(number)" },
  { name: "MOD", sig: "MOD(a, b)" },
  { name: "IF", sig: "IF(condition, then, else)" },
  { name: "AND", sig: "AND(a, b, ...)" },
  { name: "OR", sig: "OR(a, b, ...)" },
  { name: "NOT", sig: "NOT(value)" },
  { name: "SWITCH", sig: "SWITCH(value, case1, result1, ...)" },
  { name: "CONCAT", sig: "CONCAT(s1, s2, ...)" },
  { name: "UPPER", sig: "UPPER(str)" },
  { name: "LOWER", sig: "LOWER(str)" },
  { name: "TRIM", sig: "TRIM(str)" },
  { name: "LENGTH", sig: "LENGTH(str)" },
  { name: "LEFT", sig: "LEFT(str, n)" },
  { name: "RIGHT", sig: "RIGHT(str, n)" },
  { name: "TODAY", sig: "TODAY()" },
  { name: "NOW", sig: "NOW()" },
  { name: "YEAR", sig: "YEAR(date)" },
  { name: "MONTH", sig: "MONTH(date)" },
  { name: "DAY", sig: "DAY(date)" },
  { name: "DATE_DIFF", sig: "DATE_DIFF(date1, date2, unit)" },
  { name: "DATE_ADD", sig: "DATE_ADD(date, amount, unit)" }
]

export default class extends Controller {
  static targets = ["surface", "autocomplete", "status", "preview", "errors", "fnSearch", "fnGrid", "sampleInputs"]
  static values  = {
    fields: Array,
    formula: String,
    // i18n seam: English defaults byte-identical to the former hardcoded copy.
    validLabel: { type: String, default: "Valid" },
    errorsSingularFormat: { type: String, default: "{count} error" },
    errorsPluralFormat: { type: String, default: "{count} errors" },
    previewFormat: { type: String, default: "Preview: {result}" }
  }

  connect() {
    this.fieldMap = new Map(this.fieldsValue.map(f => [f.id, f]))
    this._autocompleteMode = null // 'field' | 'function'
    this._acItems = []
    this._acIndex = -1
    this._activeFnCategory = "Math" // matches the pre-selected tab in the ERB
    this._sampleFieldsKey = null
    this.hydrate(this.formulaValue)
    this.validate()
    this._applyFnFilter() // set initial chip visibility (Math) via inline style
  }

  // --- Public API ---------------------------------------------------------
  getFormula() { return this.serialize() }

  // --- Rendering ----------------------------------------------------------
  hydrate(formula) {
    this.surfaceTarget.innerHTML = ""
    if (!formula) return
    const re = /\{([a-zA-Z0-9_]+)\}/g
    let last = 0, m
    while ((m = re.exec(formula))) {
      if (m.index > last) this.surfaceTarget.appendChild(document.createTextNode(formula.slice(last, m.index)))
      this.surfaceTarget.appendChild(this.buildPill(m[1]))
      last = re.lastIndex
    }
    if (last < formula.length) this.surfaceTarget.appendChild(document.createTextNode(formula.slice(last)))
  }

  buildPill(id) {
    const f = this.fieldMap.get(id)
    const span = document.createElement("span")
    span.contentEditable = "false"
    span.dataset.pill = ""
    span.dataset.fieldId = id
    span.className = "inline-flex items-center rounded bg-indigo-100 px-1.5 py-0.5 text-indigo-700 mx-0.5 text-xs"
    const label = document.createTextNode(f ? f.label : id)
    const x = document.createElement("span")
    x.textContent = " ×"
    x.className = "ml-0.5 cursor-pointer hover:text-indigo-900"
    x.addEventListener("click", () => { span.remove(); this.validate() })
    span.appendChild(label)
    span.appendChild(x)
    return span
  }

  serialize() {
    let out = ""
    this.surfaceTarget.childNodes.forEach(node => {
      if (node.nodeType === Node.TEXT_NODE) {
        out += node.textContent
      } else if (node.dataset && node.dataset.pill !== undefined) {
        out += `{${node.dataset.fieldId}}`
      }
    })
    return out
  }

  // --- Events -------------------------------------------------------------
  onInput() {
    this.updateAutocomplete() // snappy: refresh suggestions on every keystroke
    clearTimeout(this._t)
    this._t = setTimeout(() => this.validate(), 150)
  }

  // Close the suggestion list shortly after the surface loses focus (the delay
  // lets a mousedown on a suggestion land before we tear it down).
  onBlur() {
    clearTimeout(this._blurT)
    this._blurT = setTimeout(() => this.closeAutocomplete(), 150)
  }

  onKeydown(event) {
    // Handle autocomplete navigation
    if (this._autocompleteMode && this._acItems.length > 0) {
      if (event.key === "ArrowDown") {
        event.preventDefault()
        this._acIndex = (this._acIndex + 1) % this._acItems.length
        this.highlightAcItem()
        return
      }
      if (event.key === "ArrowUp") {
        event.preventDefault()
        this._acIndex = (this._acIndex - 1 + this._acItems.length) % this._acItems.length
        this.highlightAcItem()
        return
      }
      // Enter or Tab accepts the highlighted suggestion.
      if ((event.key === "Enter" || event.key === "Tab") && this._acIndex >= 0) {
        event.preventDefault()
        this.selectAcItem(this._acIndex)
        return
      }
      if (event.key === "Escape") {
        event.preventDefault()
        this.closeAutocomplete()
        return
      }
    }

    // Backspace pill deletion: if caret is right after a pill, delete the whole pill
    if (event.key === "Backspace") {
      const sel = window.getSelection()
      if (sel && sel.isCollapsed) {
        const node = sel.anchorNode
        const offset = sel.anchorOffset
        // If we're in a text node at offset 0, check prev sibling
        if (node && node.nodeType === Node.TEXT_NODE && offset === 0) {
          const prev = node.previousSibling
          if (prev && prev.dataset && prev.dataset.pill !== undefined) {
            event.preventDefault()
            prev.remove()
            this.validate()
            return
          }
        }
        // If caret is directly in the surface (not in a text node), check prev sibling
        if (node === this.surfaceTarget && offset > 0) {
          const prev = this.surfaceTarget.childNodes[offset - 1]
          if (prev && prev.dataset && prev.dataset.pill !== undefined) {
            event.preventDefault()
            prev.remove()
            this.validate()
            return
          }
        }
      }
    }

  }

  // --- Autocomplete -------------------------------------------------------

  // Recomputes suggestions from the text immediately before the caret:
  //   - "{" (optionally followed by a partial name) -> field search
  //   - a run of letters                            -> function search (prefix)
  updateAutocomplete() {
    const ctx = this.queryContext()
    if (!ctx) return this.closeAutocomplete()

    if (ctx.mode === "field") {
      // Match on the human label only — the field id is a random hex token, so
      // matching it produces meaningless hits (e.g. "e" matches every id).
      const q = ctx.query.trim().toLowerCase()
      const items = [...this.fieldMap.values()]
        .filter(f => !q || (f.label || "").toLowerCase().includes(q))
        .map(f => ({ label: f.label || f.id, sub: f.type || "", value: f.id, type: "field" }))
      if (!items.length) return this.closeAutocomplete()
      this.showAutocomplete(items, "field")
    } else {
      const q = ctx.query.toLowerCase()
      const items = FUNCTION_LIST
        .filter(fn => fn.name.toLowerCase().startsWith(q))
        .map(fn => ({ label: fn.name, sub: fn.sig, value: fn.name, type: "function" }))
      if (!items.length) return this.closeAutocomplete()
      this.showAutocomplete(items, "function")
    }
  }

  // Returns { mode, query } describing the token being typed before the caret,
  // or null if no suggestion context applies.
  queryContext() {
    const sel = window.getSelection()
    if (!sel || !sel.isCollapsed || sel.rangeCount === 0) return null
    const node = sel.anchorNode
    if (!node || node.nodeType !== Node.TEXT_NODE) return null
    const before = node.textContent.slice(0, sel.anchorOffset)

    const fieldMatch = before.match(/\{([^{}]*)$/)
    if (fieldMatch) return { mode: "field", query: fieldMatch[1] }

    const fnMatch = before.match(/([A-Za-z][A-Za-z0-9_]*)$/)
    if (fnMatch) return { mode: "function", query: fnMatch[1] }

    return null
  }

  showAutocomplete(items, mode) {
    this._autocompleteMode = mode
    this._acItems = items
    if (this._acIndex < 0 || this._acIndex >= items.length) this._acIndex = 0
    const dropdown = this.autocompleteTarget
    dropdown.innerHTML = ""
    items.forEach((item, i) => {
      const el = document.createElement("div")
      el.className = "flex items-center justify-between gap-3 px-3 py-1.5 cursor-pointer hover:bg-purple-50 text-sm"
      const left = document.createElement("span")
      left.className = "font-medium text-gray-800 truncate"
      left.textContent = item.label
      el.appendChild(left)
      if (item.sub) {
        const sub = document.createElement("span")
        sub.className = "text-[11px] text-gray-400 font-mono flex-shrink-0"
        sub.textContent = item.sub
        el.appendChild(sub)
      }
      // mousedown (not click) so it fires before the surface blur tears it down.
      el.addEventListener("mousedown", (e) => { e.preventDefault(); this.selectAcItem(i) })
      dropdown.appendChild(el)
    })
    dropdown.classList.remove("hidden")
    this.positionAutocomplete()
    this.highlightAcItem()
  }

  // Anchors the dropdown to the caret using fixed positioning so it escapes the
  // modal's overflow clipping and follows the cursor.
  positionAutocomplete() {
    const dropdown = this.autocompleteTarget
    const sel = window.getSelection()
    let rect = null
    if (sel && sel.rangeCount) {
      const rects = sel.getRangeAt(0).getClientRects()
      rect = rects && rects.length ? rects[0] : sel.getRangeAt(0).getBoundingClientRect()
    }
    if (!rect || (rect.left === 0 && rect.top === 0)) {
      rect = this.surfaceTarget.getBoundingClientRect()
    }
    dropdown.style.position = "fixed"
    dropdown.style.zIndex = "9999"
    dropdown.style.left = `${Math.round(rect.left)}px`
    dropdown.style.top = `${Math.round(rect.bottom + 4)}px`
  }

  highlightAcItem() {
    const children = this.autocompleteTarget.children
    Array.from(children).forEach((el, i) => {
      const active = i === this._acIndex
      el.classList.toggle("bg-purple-100", active)
      if (active) el.scrollIntoView({ block: "nearest" })
    })
  }

  selectAcItem(index) {
    const item = this._acItems[index]
    if (!item) return
    if (item.type === "field") {
      this.insertFieldFromQuery(item.value)
    } else {
      this.insertFunctionFromQuery(item.value)
    }
    this.closeAutocomplete()
    this.surfaceTarget.focus()
    this.validate()
  }

  // Removes the "{partial" the user typed, then drops in a field pill.
  insertFieldFromQuery(fieldId) {
    const sel = window.getSelection()
    if (sel && sel.isCollapsed && sel.anchorNode?.nodeType === Node.TEXT_NODE) {
      const node = sel.anchorNode
      const offset = sel.anchorOffset
      const before = node.textContent.slice(0, offset)
      const m = before.match(/\{[^{}]*$/)
      if (m) {
        const start = offset - m[0].length
        node.textContent = node.textContent.slice(0, start) + node.textContent.slice(offset)
        const range = document.createRange()
        range.setStart(node, start)
        range.collapse(true)
        sel.removeAllRanges()
        sel.addRange(range)
      }
    }
    this.insertPillAtCaret(fieldId)
  }

  insertPillAtCaret(fieldId) {
    const sel = window.getSelection()
    if (!sel || !sel.isCollapsed) {
      this.surfaceTarget.appendChild(this.buildPill(fieldId))
      return
    }
    const range = sel.getRangeAt(0)
    range.deleteContents()
    const pill = this.buildPill(fieldId)
    range.insertNode(pill)
    // Place caret after the pill
    range.setStartAfter(pill)
    range.collapse(true)
    sel.removeAllRanges()
    sel.addRange(range)
  }

  // Replaces the partial name the user typed with "FUNC()" and parks the caret
  // between the parentheses. Case-insensitive (works whether you typed sum/SUM).
  insertFunctionFromQuery(funcName) {
    const sel = window.getSelection()
    if (!sel || !sel.isCollapsed || sel.anchorNode?.nodeType !== Node.TEXT_NODE) {
      const fallback = document.createTextNode(`${funcName}()`)
      this.surfaceTarget.appendChild(fallback)
      this._placeCaretInsideParens(fallback, funcName)
      return
    }
    const node = sel.anchorNode
    const offset = sel.anchorOffset
    const text = node.textContent
    const before = text.slice(0, offset)
    const match = before.match(/([A-Za-z][A-Za-z0-9_]*)$/)
    const start = match ? offset - match[1].length : offset
    node.textContent = text.slice(0, start) + funcName + "()" + text.slice(offset)
    const newOffset = start + funcName.length + 1 // just after "("
    const range = document.createRange()
    range.setStart(node, newOffset)
    range.collapse(true)
    sel.removeAllRanges()
    sel.addRange(range)
  }

  closeAutocomplete() {
    this._autocompleteMode = null
    this._acItems = []
    this._acIndex = -1
    if (this.hasAutocompleteTarget) {
      this.autocompleteTarget.classList.add("hidden")
      this.autocompleteTarget.innerHTML = ""
    }
  }

  // --- Validation ---------------------------------------------------------
  validate() {
    const formula = this.serialize()
    const { valid, errors, result } = validateFormula(formula, [...this.fieldMap.keys()], this.sampleValues())

    if (this.hasStatusTarget) {
      const errorsText = (errors.length === 1 ? this.errorsSingularFormatValue : this.errorsPluralFormatValue)
        .replace("{count}", errors.length)
      this.statusTarget.textContent = valid ? `✓ ${this.validLabelValue}` : `✗ ${errorsText}`
      this.statusTarget.className = `font-medium ${valid ? "text-green-600" : "text-red-600"}`
    }
    if (this.hasPreviewTarget) {
      this.previewTarget.textContent = valid && result !== null ? this.previewFormatValue.replace("{result}", result) : ""
    }
    if (this.hasErrorsTarget) {
      this.errorsTarget.classList.toggle("hidden", valid || errors.length === 0)
      this.errorsTarget.innerHTML = ""
      errors.forEach(e => {
        const div = document.createElement("div")
        div.textContent = e
        this.errorsTarget.appendChild(div)
      })
    }
    this._syncSampleInputs(formula)
    this.dispatch("changed", { detail: { formula, valid } })
  }

  // Sample values come from the parent calculation editor's preview panel.
  sampleValues() { return this._sampleValues || {} }
  setSampleValues(values) { this._sampleValues = values; this.validate() }

  // Renders one sample-value input per field referenced in the formula, so the
  // live preview reflects realistic inputs. Rebuilds only when the referenced
  // field set changes (so typing in an input doesn't clobber/refocus it).
  _syncSampleInputs(formula) {
    if (!this.hasSampleInputsTarget) return

    const ids = []
    const re = /\{([a-zA-Z0-9_]+)\}/g
    let m
    while ((m = re.exec(formula))) {
      if (this.fieldMap.has(m[1]) && !ids.includes(m[1])) ids.push(m[1])
    }

    const key = ids.join("|")
    if (key === this._sampleFieldsKey) return
    this._sampleFieldsKey = key

    this.sampleInputsTarget.innerHTML = ""
    ids.forEach(id => {
      const field = this.fieldMap.get(id)
      const row = document.createElement("label")
      row.className = "flex items-center gap-2 text-xs"

      const name = document.createElement("span")
      name.className = "w-28 flex-shrink-0 truncate text-gray-600"
      name.textContent = field?.label || id

      const input = document.createElement("input")
      input.type = "text"
      input.className = "flex-1 px-2 py-1 border border-gray-200 rounded text-sm focus:outline-none focus:ring-1 focus:ring-purple-500"
      input.value = (this._sampleValues && this._sampleValues[id] != null) ? this._sampleValues[id] : ""
      input.addEventListener("input", () => {
        this._sampleValues = this._sampleValues || {}
        const v = input.value
        const num = parseFloat(v)
        this._sampleValues[id] = (!isNaN(num) && v.trim() === num.toString()) ? num : v
        this.validate()
      })

      row.appendChild(name)
      row.appendChild(input)
      this.sampleInputsTarget.appendChild(row)
    })
  }

  // -------------------------------------------------------------------------
  // Function Inserter (tab switch, filter, click-to-insert)
  // -------------------------------------------------------------------------

  /** Inserts a function token (e.g. "SUM()") at the cursor in the surface, caret inside the parens */
  insertFunctionToken(event) {
    const fnName = event.currentTarget.dataset.function
    if (!fnName) return
    const token = fnName + "()"
    this.surfaceTarget.focus()
    const sel = window.getSelection()
    // No usable caret, or caret is outside the surface (e.g. user just clicked a chip):
    // append to the end of the surface instead.
    if (!sel || sel.rangeCount === 0 || !this.surfaceTarget.contains(sel.anchorNode)) {
      const node = document.createTextNode(token)
      this.surfaceTarget.appendChild(node)
      this._placeCaretInsideParens(node, fnName)
      this.validate()
      return
    }
    if (!sel.isCollapsed) sel.collapseToEnd()
    const range = sel.getRangeAt(0)
    const textNode = document.createTextNode(token)
    range.insertNode(textNode)
    this._placeCaretInsideParens(textNode, fnName)
    this.validate()
  }

  /** Positions the caret between the parentheses of a just-inserted "FN()" text node */
  _placeCaretInsideParens(textNode, fnName) {
    const sel = window.getSelection()
    if (!sel) return
    const range = document.createRange()
    range.setStart(textNode, fnName.length + 1) // just after "("
    range.collapse(true)
    sel.removeAllRanges()
    sel.addRange(range)
  }

  /** Switches the active function category tab (clears any active filter). */
  switchFunctionTab(event) {
    const category = event.currentTarget.dataset.category
    if (!category) return
    this._activeFnCategory = category

    const tabs = event.currentTarget.closest("[data-fn-tabs]")
    if (tabs) {
      tabs.querySelectorAll("[data-category]").forEach(btn => {
        const isActive = btn.dataset.category === category
        btn.classList.toggle("bg-white", isActive)
        btn.classList.toggle("text-gray-900", isActive)
        btn.classList.toggle("shadow-sm", isActive)
        btn.classList.toggle("text-gray-500", !isActive)
      })
    }

    // Switching tabs resets the filter so the chosen category shows in full.
    if (this.hasFnSearchTarget) this.fnSearchTarget.value = ""
    this._applyFnFilter()
  }

  /** Filters function chips. With a search term, searches across ALL categories
   *  (so typing any function name finds it); empty term reverts to the tab. */
  filterFunctions() {
    this._applyFnFilter()
  }

  _applyFnFilter() {
    if (!this.hasFnGridTarget) return
    const term = this.hasFnSearchTarget ? this.fnSearchTarget.value.toLowerCase().trim() : ""
    const activeCategory = this._activeFnCategory || "Math"

    this.fnGridTarget.querySelectorAll("[data-fn-insert]").forEach(chip => {
      const name = (chip.dataset.function || "").toLowerCase()
      const category = chip.dataset.category || ""
      const show = term ? name.includes(term) : category === activeCategory
      // Toggle via inline style: the chips use `inline-flex`, which overrides the
      // Tailwind `hidden` utility in the cascade, so classList toggling has no
      // visual effect. Inline display always wins.
      chip.style.display = show ? "" : "none"
    })
  }

  /** Inserts a field-reference pill from the "Insert field" picker. */
  insertFieldChip(event) {
    const el = event.currentTarget
    const fieldId = el.dataset.fieldId || el.value
    if (!fieldId) return

    this.surfaceTarget.focus()
    const sel = window.getSelection()
    if (!sel || sel.rangeCount === 0 || !this.surfaceTarget.contains(sel.anchorNode)) {
      this.surfaceTarget.appendChild(this.buildPill(fieldId))
    } else {
      this.insertPillAtCaret(fieldId)
    }
    this.validate()
    if (el.tagName === "SELECT") el.value = ""
  }
}
