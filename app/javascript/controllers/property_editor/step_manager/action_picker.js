/**
 * ActionPickerMixin — inline action picker, commit, change, and output-variable
 * auto-suggest logic for step items.
 * Apply to a class using Object.assign(YourClass.prototype, ActionPickerMixin)
 */
import { escapeHtml, generateStepId } from "utils"
import { OUTPUT_VAR_KEYS } from "controllers/property_editor/templates"
import { getAvailableVariables } from "flowchart/context_variable_provider"
import { actionFields, fieldName, getActionConfig, getActionsByCategory } from "flowchart/constants/action_registry"

const PICKER_ICON_COLORS = {
  blue: "text-blue-500", cyan: "text-cyan-500", green: "text-green-500",
  red: "text-red-500", indigo: "text-indigo-500", purple: "text-purple-500",
  emerald: "text-emerald-500", amber: "text-amber-500", pink: "text-pink-500",
  teal: "text-teal-500", gray: "text-slate-500"
}

const RECENT_STORAGE_KEY = "anysys.flowchart.recentStepActions"
const RECENT_LIMIT = 5

const CHIP_ACTIVE_CLASSES = ["border-indigo-200", "bg-indigo-50", "text-indigo-700"]
const CHIP_IDLE_CLASSES = ["border-slate-200", "bg-white", "text-slate-600", "hover:bg-slate-50"]

// Per-token weights: where a query word lands decides how high the action ranks.
const SCORE_LABEL_PREFIX = 100
const SCORE_LABEL_WORD = 60
const SCORE_LABEL = 40
const SCORE_KEY = 30
const SCORE_CATEGORY = 15
const SCORE_DESCRIPTION = 10
const SCORE_EXACT_LABEL = 200

export const ActionPickerMixin = {
  // ===================
  // Inline Action Picker
  // ===================

  /**
   * Build the inline picker HTML and (re)build the leaf lookup map.
   * Empty query: "Recently used" first, then every category expanded.
   * Typing: one flat list ranked by match quality (label > key > category >
   * description), each row tagged with its category. Category chips narrow
   * either view. subOptions trees are flattened to selectable leaves; the
   * leaf value encodes "action" or "action::sub/path". singleUse actions
   * already present render disabled but visible.
   */
  buildStepPickerHTML() {
    const usedSingleUse = this.getUsedSingleUseActions()

    this._pickerLeafMap = {}
    this._pickerHighlightIndex = -1
    this._pickerQuery = ""
    this._pickerCategory = ""
    this._pickerCategories = []
    this._pickerEntries = []

    getActionsByCategory().forEach(g => {
      const items = this._flattenActionLeaves(g.actions, usedSingleUse)
      if (items.length === 0) return
      this._pickerCategories.push(g.category)
      items.forEach(([display, value, meta]) => {
        this._pickerEntries.push(this._pickerEntry(display, value, meta, g.category))
      })
    })

    const c = this.controller
    const listHTML = this._pickerListHTML()

    return `
      <div data-step-picker class="rounded-lg border border-slate-200 bg-white shadow-sm">
        <div class="flex items-center gap-2 border-b border-slate-200 px-2">
          <svg class="size-4 flex-shrink-0 text-slate-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
          <input type="text"
                 data-step-picker-search
                 data-action="input->property-editor#stepPickerFilter keydown->property-editor#stepPickerKeydown keydown.esc->property-editor#stepPickerEscape"
                 placeholder="${escapeHtml(c.stepPickerSearchPlaceholderValue)}"
                 autocomplete="off"
                 role="combobox"
                 aria-expanded="true"
                 aria-autocomplete="list"
                 class="h-10 w-full bg-transparent text-sm text-slate-800 placeholder:text-slate-400 focus:outline-none">
        </div>
        ${this._pickerChipsHTML()}
        <div data-step-picker-list role="listbox" class="${listHTML ? "" : "hidden "}flex max-h-80 flex-col gap-1 overflow-y-auto p-1">
          ${listHTML}
        </div>
        <div data-step-picker-empty class="${listHTML ? "hidden " : ""}px-3 py-6 text-center text-sm text-slate-400">${escapeHtml(c.stepPickerNoMatchLabelValue)}</div>
        <input type="hidden" data-action="change->property-editor#stepPickerCommit">
      </div>
    `.trim()
  },

  _pickerEntry(display, value, meta, category) {
    return {
      display,
      value,
      meta,
      categoryKey: category.key,
      categoryLabel: category.label,
      labelFold: this._foldPickerText(display),
      keyFold: this._foldPickerText(value.replace(/::|[_/]/g, " ")),
      categoryFold: this._foldPickerText(category.label),
      descriptionFold: this._foldPickerText(meta.description)
    }
  },

  _pickerChipsHTML() {
    const c = this.controller
    const chip = (key, label) => {
      const active = key === this._pickerCategory
      const classes = active ? CHIP_ACTIVE_CLASSES : CHIP_IDLE_CLASSES
      return `
        <button type="button"
                data-step-picker-category="${escapeHtml(key)}"
                data-action="click->property-editor#stepPickerCategory"
                aria-pressed="${active}"
                class="h-6 flex-shrink-0 cursor-pointer whitespace-nowrap rounded-full border px-2.5 text-[11px] font-medium ${classes.join(" ")}">${escapeHtml(label)}</button>`
    }
    const chipsHTML = [
      chip("", c.stepPickerAllCategoriesLabelValue),
      ...this._pickerCategories.map(cat => chip(cat.key, cat.label))
    ].join("")
    return `
      <div data-step-picker-categories role="group" aria-label="${escapeHtml(c.stepPickerCategoriesLabelValue)}"
           class="flex gap-1 overflow-x-auto border-b border-slate-200 px-2 py-1.5">${chipsHTML}</div>`
  },

  /** List body for the current query + category; "" when nothing matches. */
  _pickerListHTML() {
    const tokens = this._pickerTokens()
    const category = this._pickerCategory
    const entries = category
      ? this._pickerEntries.filter(e => e.categoryKey === category)
      : this._pickerEntries

    if (tokens.length > 0) {
      const ranked = entries
        .map((entry, index) => ({ entry, index, score: this._scorePickerEntry(entry, tokens) }))
        .filter(r => r.score > 0)
        .sort((a, b) => b.score - a.score || a.index - b.index)
        .map(r => r.entry)
      return ranked.length ? this._pickerGroupHTML("", ranked, tokens, !category) : ""
    }

    const groups = []
    if (!category) {
      const recent = this._recentPickerEntries()
      if (recent.length) groups.push(this._pickerGroupHTML(this.controller.stepPickerRecentLabelValue, recent, [], true))
    }
    const order = category ? this._pickerCategories.filter(cat => cat.key === category) : this._pickerCategories
    order.forEach(cat => {
      groups.push(this._pickerGroupHTML(cat.label, entries.filter(e => e.categoryKey === cat.key), [], false))
    })
    return groups.join("")
  },

  _pickerGroupHTML(heading, entries, tokens, showCategory) {
    const headingHTML = heading
      ? `<div class="px-2 py-1.5 text-[11px] font-medium text-slate-500">${escapeHtml(heading)}</div>`
      : ""
    const optionsHTML = entries.map(entry => this._pickerOptionHTML(entry, tokens, showCategory)).join("")
    return `
      <div data-step-picker-group class="flex flex-col gap-0.5">
        ${headingHTML}
        <div class="flex flex-col gap-0.5" role="group">${optionsHTML}</div>
      </div>`
  },

  _pickerOptionHTML(entry, tokens = [], showCategory = false) {
    const { display, value, meta, categoryLabel } = entry
    const disabled = meta.disabled === true
    const description = meta.description || ""
    const colorClass = PICKER_ICON_COLORS[meta.color] || PICKER_ICON_COLORS.gray
    const iconHTML = meta.icon
      ? `<span class="inline-flex size-4 flex-shrink-0 items-center justify-center">
           <svg class="size-3.5 ${colorClass}" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true">
             <path stroke-linecap="round" stroke-linejoin="round" d="${escapeHtml(meta.icon)}" />
           </svg>
         </span>`
      : ""
    const usedHTML = disabled
      ? `<span class="text-[10px] text-slate-400">${escapeHtml(this.controller.stepPickerAlreadyUsedLabelValue)}</span>`
      : ""
    const categoryHTML = showCategory && !disabled
      ? `<span data-step-picker-option-category class="flex-shrink-0 rounded bg-slate-100 px-1.5 py-0.5 text-[10px] text-slate-500">${escapeHtml(categoryLabel)}</span>`
      : ""
    const descHTML = description
      ? `<span class="truncate text-[11px] text-slate-500">${escapeHtml(description)}</span>`
      : ""
    const stateClass = disabled
      ? "cursor-not-allowed opacity-40"
      : "cursor-pointer hover:bg-indigo-50"
    const disabledAttr = disabled ? ` data-disabled="true" aria-disabled="true"` : ""
    return `
      <button type="button"
              role="option"
              aria-selected="false"
              data-step-picker-option
              data-value="${escapeHtml(value)}"
              data-action="click->property-editor#stepPickerSelect"
              class="flex min-h-10 w-full items-center gap-2 rounded-md px-2 py-1.5 text-left ${stateClass}"
              ${disabledAttr}>
        ${iconHTML}
        <span class="flex min-w-0 flex-1 flex-col">
          <span class="truncate text-xs font-medium text-slate-800">${this._highlightPickerText(display, tokens)}</span>
          ${descHTML}
        </span>
        ${categoryHTML}
        ${usedHTML}
      </button>`
  },

  _pickerTokens() {
    return this._foldPickerText(this._pickerQuery).split(/[\s_]+/).filter(Boolean)
  },

  /**
   * Every query word must appear somewhere (label, action key, category, or
   * description); 0 means no match. Words in any order: "email send" finds
   * "Send Template Email".
   */
  _scorePickerEntry(entry, tokens) {
    let score = 0
    for (const token of tokens) {
      if (entry.labelFold.startsWith(token)) score += SCORE_LABEL_PREFIX
      else if (entry.labelFold.includes(` ${token}`)) score += SCORE_LABEL_WORD
      else if (entry.labelFold.includes(token)) score += SCORE_LABEL
      else if (entry.keyFold.includes(token)) score += SCORE_KEY
      else if (entry.categoryFold.includes(token)) score += SCORE_CATEGORY
      else if (entry.descriptionFold.includes(token)) score += SCORE_DESCRIPTION
      else return 0
    }
    if (entry.labelFold === tokens.join(" ")) score += SCORE_EXACT_LABEL
    return score
  },

  /**
   * Bold the query words inside a label. Falls back to plain text when
   * folding changes the length (e.g. decomposed accents), since character
   * offsets would no longer line up with the original string.
   */
  _highlightPickerText(text, tokens) {
    const folded = this._foldPickerText(text)
    if (tokens.length === 0 || folded.length !== text.length) return escapeHtml(text)

    const marked = new Array(text.length).fill(false)
    tokens.forEach(token => {
      let at = folded.indexOf(token)
      while (at !== -1) {
        marked.fill(true, at, at + token.length)
        at = folded.indexOf(token, at + token.length)
      }
    })

    let html = ""
    let i = 0
    while (i < text.length) {
      const on = marked[i]
      let j = i
      while (j < text.length && marked[j] === on) j++
      const segment = escapeHtml(text.slice(i, j))
      html += on ? `<mark class="bg-transparent font-semibold text-indigo-700">${segment}</mark>` : segment
      i = j
    }
    return html
  },

  _recentPickerEntries() {
    const byValue = new Map(this._pickerEntries.map(e => [e.value, e]))
    return this._readRecentPickerValues()
      .map(value => byValue.get(value))
      .filter(entry => entry && entry.meta.disabled !== true)
  },

  _readRecentPickerValues() {
    try {
      const parsed = JSON.parse(window.localStorage.getItem(RECENT_STORAGE_KEY) || "[]")
      return Array.isArray(parsed) ? parsed.filter(v => typeof v === "string") : []
    } catch {
      return []
    }
  },

  _rememberPickerValue(value) {
    const values = [value, ...this._readRecentPickerValues().filter(v => v !== value)].slice(0, RECENT_LIMIT)
    try {
      window.localStorage.setItem(RECENT_STORAGE_KEY, JSON.stringify(values))
    } catch {
      // Storage full or disabled: recents are a convenience only.
    }
  },

  _flattenActionLeaves(actions, usedSingleUse) {
    const items = []
    const walk = (node, rootAction, pathValues, pathLabels) => {
      const subOptions = node.subOptions || []
      if (subOptions.length === 0) {
        const subPath = pathValues.slice(1).join("/")
        const rootKey = rootAction.key || rootAction.value
        const value = subPath ? `${rootKey}::${subPath}` : rootKey
        const display = pathLabels.join(" › ")
        const disabled = rootAction.singleUse === true && usedSingleUse.includes(rootKey)
        this._pickerLeafMap[value] = {
          action: rootKey,
          suboption: subPath,
          selectionLabels: [...pathLabels],
          actionOption: rootAction
        }
        items.push([display, value, {
          icon: rootAction.icon,
          color: rootAction.color,
          description: node.description || rootAction.description,
          disabled
        }])
        return
      }
      subOptions.forEach(sub => walk(sub, rootAction, [...pathValues, sub.value], [...pathLabels, sub.label]))
    }
    actions.forEach(a => walk(a, a, [a.key || a.value], [a.label]))
    return items
  },

  /**
   * Accent- and case-insensitive fold. Combining marks drop so "café" matches
   * "cafe"; CJK is unchanged so zh-CN label/description/category search works.
   */
  _foldPickerText(value) {
    return String(value || "")
      .normalize("NFD")
      .replace(/\p{M}/gu, "")
      .toLowerCase()
  },

  stepPickerFilter(event) {
    const picker = event.target?.closest?.("[data-step-picker]")
    if (!picker) return
    this._pickerQuery = event.target.value
    this._renderPickerList(picker)
  },

  stepPickerCategory(event) {
    const chip = event.currentTarget
    const picker = chip?.closest?.("[data-step-picker]")
    if (!picker) return
    this._pickerCategory = chip.dataset.stepPickerCategory || ""
    picker.querySelectorAll("[data-step-picker-category]").forEach(el => {
      const active = el === chip
      el.setAttribute("aria-pressed", String(active))
      el.classList.remove(...CHIP_ACTIVE_CLASSES, ...CHIP_IDLE_CLASSES)
      el.classList.add(...(active ? CHIP_ACTIVE_CLASSES : CHIP_IDLE_CLASSES))
    })
    this._renderPickerList(picker)
    picker.querySelector("[data-step-picker-search]")?.focus()
  },

  /**
   * Re-render the list for the current query + category. While a query is
   * typed the best match is pre-highlighted so Enter picks it immediately.
   */
  _renderPickerList(picker) {
    const list = picker.querySelector("[data-step-picker-list]")
    const empty = picker.querySelector("[data-step-picker-empty]")
    if (!list) return
    const html = this._pickerListHTML()
    list.innerHTML = html
    list.scrollTop = 0
    list.classList.toggle("hidden", html === "")
    empty?.classList.toggle("hidden", html !== "")

    const visible = this._visiblePickerOptions(picker)
    this._pickerHighlightIndex = this._pickerTokens().length > 0 && visible.length > 0 ? 0 : -1
    this._updatePickerHighlight(visible)
  },

  stepPickerKeydown(event) {
    const picker = event.target?.closest?.("[data-step-picker]")
    if (!picker) return
    const visible = this._visiblePickerOptions(picker)
    const key = event.key

    if (key === "ArrowDown") {
      event.preventDefault()
      if (visible.length === 0) return
      this._pickerHighlightIndex = Math.min((this._pickerHighlightIndex ?? -1) + 1, visible.length - 1)
      this._updatePickerHighlight(visible)
      return
    }
    if (key === "ArrowUp") {
      event.preventDefault()
      if (visible.length === 0) return
      this._pickerHighlightIndex = Math.max((this._pickerHighlightIndex ?? 0) - 1, 0)
      this._updatePickerHighlight(visible)
      return
    }
    if (key === "Enter") {
      event.preventDefault()
      const opt = visible[this._pickerHighlightIndex]
      if (opt) this.stepPickerSelect({ currentTarget: opt, target: opt })
    }
  },

  stepPickerSelect(event) {
    const opt = event.currentTarget || event.target?.closest?.("[data-step-picker-option]")
    if (!opt || opt.dataset.disabled === "true") return
    const picker = opt.closest("[data-step-picker]")
    const hidden = picker?.querySelector("input[type='hidden']")
    if (!hidden) return
    hidden.value = opt.dataset.value || ""
    hidden.dispatchEvent(new Event("change", { bubbles: true }))
  },

  _visiblePickerOptions(picker) {
    return [...picker.querySelectorAll("[data-step-picker-option]")].filter(opt => {
      if (opt.classList.contains("hidden")) return false
      if (opt.dataset.disabled === "true") return false
      const group = opt.closest("[data-step-picker-group]")
      if (group?.classList.contains("hidden")) return false
      return true
    })
  },

  _updatePickerHighlight(visible) {
    visible.forEach((opt, i) => {
      const active = i === this._pickerHighlightIndex
      opt.classList.toggle("bg-indigo-50", active)
      opt.classList.toggle("text-indigo-700", active)
      opt.setAttribute("aria-selected", String(active))
    })
    visible[this._pickerHighlightIndex]?.scrollIntoView({ block: "nearest" })
  },

  /**
   * Commit handler — fired by the picker's hidden input `change` event
   * (dispatched by searchable_select_controller#select). Commits immediately:
   * builds the expanded card with defaulted config and removes the picker.
   */
  stepPickerCommit(event) {
    const value = event.target.value
    if (!value) return
    const leaf = this._pickerLeafMap?.[value]
    if (!leaf) return

    const container = this.controller.formFieldsTarget.querySelector("[data-steps-container]")
    if (!container) return
    // One step per process element
    if (container.querySelectorAll("[data-step-item]").length >= 1) return

    // A commit during a Change flow confirms the replacement — drop the snapshot.
    this._changeSnapshot = null
    this._disarmChangeOutsideClick()

    const actionEntry = getActionConfig(leaf.action)
    const defaultConfig = {}
    let schema = []
    if (actionEntry) {
      schema = actionFields(actionEntry)
      schema.forEach(field => {
        const name = fieldName(field)
        if (field.default !== undefined && field.default !== null) defaultConfig[name] = field.default
      })
      this._applyResultVarAutoSuggest(schema, defaultConfig, leaf.action)
    }

    const stepHtml = this.buildStepItemHTML(
      this.stepIndex, leaf.action, "", null,
      true, // expanded — just-added
      leaf.suboption, leaf.actionOption, leaf.selectionLabels, [],
      defaultConfig, generateStepId()
    )
    container.insertAdjacentHTML("beforeend", stepHtml)
    this.stepIndex++
    this._rememberPickerValue(value)

    this._hideStepPicker()
    this._dispatchEvent("stepAdded")

    const added = container.lastElementChild
    if (added) this._refreshCapabilityChrome(added)

    // Round-3: refine output-variable names against upstream pins AFTER the
    // card is in the DOM, so commit never waits on the implicit-keys fetch.
    this._refineOutputVarsWithUpstream(added, schema, defaultConfig)
  },

  /**
   * Async post-commit refinement: if an auto-suggested output variable
   * collides with an upstream element output pin, bump its suffix. Only
   * touches an input whose value still equals the auto-suggestion (a user
   * edit in the gap wins). Any failure leaves the sibling-only suggestion —
   * today's behavior. Never blocks or delays the commit itself.
   */
  async _refineOutputVarsWithUpstream(stepItem, schema, defaultConfig) {
    if (!stepItem || !schema.some(field => OUTPUT_VAR_KEYS.includes(fieldName(field)))) return

    let upstream = []
    try {
      const canvas = this.controller.canvas
      const elementId = this.controller.currentElement?.id
      if (!canvas || !elementId) return
      const { groups } = await getAvailableVariables(canvas, elementId, -1)
      groups.forEach(group => {
        if (group.source !== "element") return
        group.variables.forEach(v => {
          if (typeof v === "string" && v.trim() !== "") upstream.push(v)
        })
      })
    } catch { return }
    if (upstream.length === 0) return

    let changed = false
    schema.forEach(field => {
      const name = fieldName(field)
      if (!OUTPUT_VAR_KEYS.includes(name)) return
      const input = stepItem.querySelector(`[data-config-field="${name}"] [data-config-input]`)
      if (!input) return
      const suggested = defaultConfig[name]
      // Respect user edits made while the fetch was in flight.
      if (suggested === undefined || input.value !== String(suggested)) return
      if (!upstream.includes(input.value)) return
      // Canonical ctx names stay un-suffixed so later steps can share `model` / `contract`.
      if (this._isCanonicalOutputVar(input.value)) return

      const taken = [...upstream, ...this._collectSiblingOutputVars()]
      const base = String(suggested).replace(/_\d+$/, "")
      let candidate = base
      let suffix = 2
      while (taken.includes(candidate) && suffix <= 9) {
        candidate = `${base}_${suffix}`
        suffix++
      }
      if (candidate !== input.value) {
        input.value = candidate
        changed = true
      }
    })

    if (changed) {
      const anyInput = stepItem.querySelector("[data-config-input]")
      if (anyInput) this.handleConfigFieldChange({ target: anyInput })
      this._dispatchEvent("stepAdded")
    }
  },

  /**
   * "Change" affordance: detach the committed card (live DOM node — preserves
   * edited input values), re-open the picker. Escape restores the node unchanged.
   */
  changeStep(event) {
    event.preventDefault()
    const stepItem = event.target.closest("[data-step-item]")
    if (!stepItem) return
    this._changeSnapshot = stepItem
    stepItem.remove()
    this._showStepPicker({ focus: true })
    this._armChangeOutsideClick()
  },

  stepPickerEscape(event) {
    if (!this._changeSnapshot) return
    event?.preventDefault?.()
    event?.stopPropagation?.()
    const container = this.controller.formFieldsTarget.querySelector("[data-steps-container]")
    if (container) container.appendChild(this._changeSnapshot)
    this._changeSnapshot = null
    this._disarmChangeOutsideClick()
    this._hideStepPicker()
  },

  /**
   * Give-up restore: while a "Change" is pending (the step is detached into
   * _changeSnapshot and the picker is open), a click anywhere OUTSIDE the picker
   * means the user abandoned the change — put the unchanged step back. Clicking
   * INSIDE the picker (search, dropdown, an option) is a normal interaction and
   * must NOT restore — an earlier blur-based version fired on every focus loss
   * and aborted legitimate switches ("can't switch to another step").
   */
  _armChangeOutsideClick() {
    this._disarmChangeOutsideClick()
    this._changeOutsideHandler = (e) => {
      if (!this._changeSnapshot) return
      if (e.target?.closest?.("[data-step-picker]")) return
      this.stepPickerEscape()
    }
    // mousedown in capture phase: fires before any click that might re-render.
    document.addEventListener("mousedown", this._changeOutsideHandler, true)
  },

  _disarmChangeOutsideClick() {
    if (!this._changeOutsideHandler) return
    document.removeEventListener("mousedown", this._changeOutsideHandler, true)
    this._changeOutsideHandler = null
  },

  _showStepPicker({ focus = false } = {}) {
    const mount = this.controller.formFieldsTarget.querySelector("[data-step-picker-mount]")
    if (!mount) return
    // Re-render so singleUse disabled states reflect the current step list
    mount.innerHTML = this.buildStepPickerHTML()
    mount.classList.remove("hidden")
    if (focus) {
      setTimeout(() => mount.querySelector("input[type='text']")?.focus(), 50)
    }
  },

  _hideStepPicker() {
    const mount = this.controller.formFieldsTarget.querySelector("[data-step-picker-mount]")
    if (!mount) return
    mount.classList.add("hidden")
    const search = mount.querySelector("input[type='text']")
    if (search) search.value = ""
    const hidden = mount.querySelector("input[type='hidden']")
    if (hidden) hidden.value = ""
  },

  /**
   * Pre-fill output-variable fields (resultVar/outputKey/targetVariable) at
   * step-commit time only: schema default first, derived base otherwise, with
   * _2.._9 suffix on collision against sibling steps' stored configs.
   * Runs exactly once per committed step — nothing re-derives after the user
   * edits the field (reloads render from stored config; changeStep restores
   * the live DOM node), so no dirty flag is needed.
   */
  _applyResultVarAutoSuggest(schema, defaultConfig, actionKey) {
    // Synchronous sibling-only pass — keeps commit instant. Upstream-pin
    // collisions are refined post-insert by _refineOutputVarsWithUpstream.
    const usedVars = this._collectSiblingOutputVars()

    schema.forEach(field => {
      const name = fieldName(field)
      if (!OUTPUT_VAR_KEYS.includes(name)) return

      let base = defaultConfig[name]
      if (base === undefined || String(base).trim() === "") {
        base = this._deriveOutputVarBase(actionKey)
      }
      base = String(base)

      let candidate = base
      if (!this._isCanonicalOutputVar(base)) {
        let suffix = 2
        while (usedVars.includes(candidate) && suffix <= 9) {
          candidate = `${base}_${suffix}`
          suffix++
        }
      }
      defaultConfig[name] = candidate
      usedVars.push(candidate)
    })
  },

  /** Shared ctx names that must never be auto-suffixed (`model_2`, `contract_2`). */
  _isCanonicalOutputVar(name) {
    return name === "model" || name === "contract"
  },

  _deriveOutputVarBase(actionKey) {
    if (/_models$/.test(actionKey)) return "models"
    if (/_model$/.test(actionKey)) return "model"
    return "result"
  },

  /** Output-variable values already used by step cards in the live DOM. */
  _collectSiblingOutputVars() {
    const container = this.controller.formFieldsTarget?.querySelector("[data-steps-container]")
    if (!container) return []

    const vars = []
    container.querySelectorAll("[data-step-item]").forEach(item => {
      const configInput = item.querySelector("[data-step-config]")
      if (!configInput?.value) return
      try {
        const config = JSON.parse(configInput.value)
        OUTPUT_VAR_KEYS.forEach(key => {
          const v = config[key]
          if (typeof v === "string" && v.trim() !== "" && !vars.includes(v)) vars.push(v)
        })
      } catch { /* ignore */ }
    })
    return vars
  }
}
