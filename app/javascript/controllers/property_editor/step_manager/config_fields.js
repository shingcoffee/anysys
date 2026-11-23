/**
 * ConfigFieldsMixin — config field change handling, key-value list rows,
 * override badge, "more options" badge, and entity-column widget helpers.
 * Apply to a class using Object.assign(YourClass.prototype, ConfigFieldsMixin)
 */
import { escapeHtml } from "utils"
import { PAIRED_VALUE_FIELDS, columnTypeOf, upsertTypeChip, wireSoftTypeValidation, matchesWhen } from "controllers/property_editor/templates"
import { actionFields, getActionConfig } from "flowchart/constants/action_registry"
import { collectList } from "controllers/property_editor/controls/list"
import { collectMapping } from "controllers/property_editor/controls/mapping"
import { collectConditions } from "controllers/property_editor/controls/conditions"
import { collectLocalizedText } from "controllers/property_editor/controls/localized_text"

export const ConfigFieldsMixin = {
  /**
   * Collect config values from an expanded step item's config fields.
   * Structured editors (list / conditions / localized text) serialize to the
   * catalog shape; everything else matches the historical StepManager collector.
   */
  collectStepConfig(stepItem) {
    const config = {}
    const configFields = stepItem.querySelectorAll("[data-config-field]")

    configFields.forEach(fieldEl => {
      const key = fieldEl.dataset.configField

      const listEditor = fieldEl.querySelector("[data-list-editor]")
      if (listEditor) {
        const items = collectList(listEditor)
        if (items.length > 0) config[key] = items
        return
      }

      const conditionsEditor = fieldEl.querySelector("[data-conditions-editor]")
      if (conditionsEditor) {
        config[key] = collectConditions(conditionsEditor)
        return
      }

      const localized = fieldEl.querySelector("[data-localized-text]")
      if (localized) {
        const hash = collectLocalizedText(localized)
        if (Object.keys(hash).length > 0) config[key] = hash
        return
      }

      const kvList = fieldEl.querySelector("[data-key-value-list]")
      if (kvList) {
        const pairs = collectMapping(kvList)
        if (pairs.length > 0) config[key] = pairs
        return
      }

      const input = fieldEl.querySelector("[data-config-input]")
      if (input) {
        if (input.type === "checkbox") {
          config[key] = input.checked
          return
        }
        const value = input.value?.trim()
        if (value !== "" && value !== undefined) {
          config[key] = input.type === "number" ? Number(value) : value
          if (fieldEl.hasAttribute("data-json-or-expression") && value.startsWith("{")) {
            try { config[key] = JSON.parse(value) } catch { /* keep invalid input */ }
          }
        }
      }
    })

    return config
  },

  /**
   * Handle config field change - toggle dependent field visibility and sync.
   */
  handleConfigFieldChange(event) {
    const stepItem = event.target.closest("[data-step-item]")
    if (!stepItem) return

    // Collect current config values from live DOM
    const currentConfig = this.collectStepConfig(stepItem)

    // Update visibility of config fields based on visibleWhen conditions
    const configFields = stepItem.querySelectorAll("[data-config-field]")
    configFields.forEach(fieldEl => {
      const visibleWhenStr = fieldEl.dataset.visibleWhen
      if (visibleWhenStr) {
        try {
          const isVisible = matchesWhen(JSON.parse(visibleWhenStr), currentConfig)
          fieldEl.classList.toggle("hidden", !isVisible)
        } catch { /* ignore parse errors */ }
      }

    })

    // Widget mode can change even when the field has no visibleWhen clause.
    // Reconcile every required field after visibility, including unconditional
    // entity columns; only the active dropdown/manual alternative validates.
    configFields.forEach(fieldEl => {
      const isVisible = !fieldEl.classList.contains("hidden")
      let required = false
      if (fieldEl.dataset.requiredWhen) {
        try { required = isVisible && matchesWhen(JSON.parse(fieldEl.dataset.requiredWhen), currentConfig) } catch { required = false }
      } else if (fieldEl.hasAttribute("data-conditionally-required")) {
        required = isVisible
      } else {
        return
      }
      fieldEl.querySelectorAll("input, textarea, select").forEach(input => {
        if (input.type === "checkbox" || input.type === "hidden") return
        input.required = required && !input.classList.contains("hidden") && !input.closest("[data-entity-manual-wrap].hidden") && !input.closest("[data-locale-panel].hidden")
      })
    })

    this._refreshCapabilityChrome(stepItem)
    const storedConfig = this.collectStepConfig(stepItem)

    // Update the stored config hidden input
    const configInput = stepItem.querySelector("[data-step-config]")
    if (configInput) {
      configInput.value = JSON.stringify(storedConfig)
    }

    // Notify the step-level I/O manager so it can debounce a re-fetch of
    // pins and re-render the pane if the step is currently open. Config
    // edits commonly change the extracted pin set (e.g. different model
    // class), so stale pins would produce wrong producer options.
    const manager = this.controller.stepIoManager
    if (manager) {
      const canvas = this.controller.canvas
      const stepId = stepItem.dataset.stepId
      const found = canvas?.findStepById?.(stepId)
      if (found) {
        // Mirror the live config onto the in-memory step so the pin fetch
        // sees the latest values.
        found.step.config = { ...(found.step.config || {}), ...storedConfig }
        manager.onStepConfigChanged(found.step)
      }
    }

    const editedField = event.target.closest("[data-config-field]")
    if (editedField) this._clearStepFieldError(editedField)
    this._refreshStepErrorBadge(stepItem)

    // Dispatch event to trigger auto-sync to canvas
    this._dispatchEvent("stepChanged")
  },

  /**
   * Add a new row to a key_value_list config field.
   */
  addConfigKvRow(event) {
    event.preventDefault()
    const kvList = event.target.closest("[data-key-value-list]")
    if (!kvList) return

    const template = kvList.querySelector("[data-kv-row-template]")
    let newRow
    if (template?.content?.firstElementChild) {
      newRow = template.content.firstElementChild.cloneNode(true)
      newRow.querySelectorAll("input, select, textarea").forEach(el => {
        el.value = ""
      })
    } else {
      newRow = document.createElement("div")
      newRow.setAttribute("data-kv-row", "")
      newRow.className = "grid grid-cols-1 sm:grid-cols-[1fr_1fr_auto] gap-1.5 items-center"
      const kvInput = "min-w-0 px-2 py-1.5 text-xs border border-slate-200 bg-white rounded-md placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400"
      const keyPlaceholder = kvList.dataset.keyPlaceholder || this.controller.kvKeyPlaceholderValue
      const valuePlaceholder = kvList.dataset.valuePlaceholder || this.controller.kvValuePlaceholderValue
      newRow.innerHTML = `
      <input type="text" data-kv-key placeholder="${escapeHtml(keyPlaceholder)}" class="${kvInput}">
      <input type="text" data-kv-value placeholder="${escapeHtml(valuePlaceholder)}" class="${kvInput}">
      <button type="button" data-action="click->property-editor#removeConfigKvRow"
              class="p-0.5 text-slate-400 hover:text-red-500 hover:bg-red-50 rounded transition-colors flex-shrink-0" title="${escapeHtml(this.controller.kvRemoveRowTitleValue)}">
        <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    `
    }

    const addBtn = kvList.querySelector("[data-action*='addConfigKvRow']")
    kvList.insertBefore(newRow, addBtn)
    newRow.querySelector("[data-kv-key]")?.focus()
  },

  addConfigListRow(event) {
    event.preventDefault()
    const list = event.target.closest("[data-list-editor]")
    if (!list) return
    const template = list.querySelector("[data-list-row-template]")
    if (!template?.content?.firstElementChild) return
    const newRow = template.content.firstElementChild.cloneNode(true)
    newRow.querySelectorAll("input, select, textarea").forEach(el => { el.value = "" })
    const addBtn = list.querySelector("[data-action*='addConfigListRow']")
    list.insertBefore(newRow, addBtn)
    newRow.querySelector("[data-list-value]")?.focus()
  },

  removeConfigListRow(event) {
    event.preventDefault()
    const row = event.target.closest("[data-list-row]")
    if (!row) return
    const list = row.closest("[data-list-editor]")
    row.remove()
    const liveRows = list ? list.querySelectorAll(":scope > [data-list-row]") : []
    if (list && liveRows.length === 0) {
      this.addConfigListRow({ preventDefault() {}, target: list.querySelector("[data-action*='addConfigListRow']") || list })
    }
    if (list) this.handleConfigFieldChange({ target: list })
  },

  addConfigConditionRow(event) {
    event.preventDefault()
    const editor = event.target.closest("[data-conditions-editor]")
    if (!editor) return
    const rows = editor.querySelector("[data-condition-rows]")
    const template = editor.querySelector("[data-condition-row-template]")
    if (!rows || !template?.content?.firstElementChild) return
    const andLabel = this.controller.joinAndLabelValue || "AND"
    const join = document.createElement("button")
    join.type = "button"
    join.setAttribute("data-condition-join", "AND")
    join.setAttribute("data-action", "click->property-editor#toggleStepConditionJoin")
    join.className = "inline-flex items-center self-start px-1.5 py-0.5 text-[10px] font-semibold rounded bg-amber-200 text-amber-800"
    join.textContent = andLabel
    const newRow = template.content.firstElementChild.cloneNode(true)
    newRow.querySelectorAll("input, select, textarea").forEach(el => { el.value = "" })
    if (rows.querySelector("[data-condition-row]")) rows.appendChild(join)
    rows.appendChild(newRow)
    newRow.querySelector("[data-condition-left]")?.focus()
  },

  removeConfigConditionRow(event) {
    event.preventDefault()
    const row = event.target.closest("[data-condition-row]")
    if (!row) return
    const editor = row.closest("[data-conditions-editor]")
    const joinBefore = row.previousElementSibling?.hasAttribute("data-condition-join")
      ? row.previousElementSibling
      : null
    const joinAfter = row.nextElementSibling?.hasAttribute("data-condition-join")
      ? row.nextElementSibling
      : null
    if (joinBefore) joinBefore.remove()
    else if (joinAfter) joinAfter.remove()
    row.remove()
    const liveConditionRows = editor
      ? editor.querySelectorAll("[data-condition-rows] > [data-condition-row]")
      : []
    if (editor && liveConditionRows.length === 0) {
      this.addConfigConditionRow({ preventDefault() {}, target: editor.querySelector("[data-action*='addConfigConditionRow']") || editor })
    }
    if (editor) this.handleConfigFieldChange({ target: editor })
  },

  toggleStepConditionJoin(event) {
    event.preventDefault()
    const btn = event.target.closest("[data-condition-join]")
    if (!btn) return
    const next = btn.dataset.conditionJoin === "AND" ? "OR" : "AND"
    btn.dataset.conditionJoin = next
    btn.textContent = next === "OR"
      ? (this.controller.joinOrLabelValue || "OR")
      : (this.controller.joinAndLabelValue || "AND")
    btn.className = next === "OR"
      ? "inline-flex items-center self-start px-1.5 py-0.5 text-[10px] font-semibold rounded bg-purple-200 text-purple-800"
      : "inline-flex items-center self-start px-1.5 py-0.5 text-[10px] font-semibold rounded bg-amber-200 text-amber-800"
    this.handleConfigFieldChange({ target: btn })
  },

  switchLocalizedLocale(event) {
    event.preventDefault()
    const tab = event.target.closest("[data-locale-tab]")
    const editor = tab?.closest("[data-localized-text]")
    if (!editor || !tab) return
    const locale = tab.dataset.localeTab
    editor.querySelectorAll("[data-locale-tab]").forEach(btn => {
      const on = btn.dataset.localeTab === locale
      btn.setAttribute("aria-selected", on ? "true" : "false")
      btn.classList.toggle("bg-white", on)
      btn.classList.toggle("text-slate-900", on)
      btn.classList.toggle("shadow-sm", on)
      btn.classList.toggle("ring-1", on)
      btn.classList.toggle("ring-black/5", on)
      btn.classList.toggle("text-slate-500", !on)
    })
    editor.querySelectorAll("[data-locale-panel]").forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.localePanel !== locale)
    })
  },

  /**
   * Remove a row from a key_value_list config field.
   */
  removeConfigKvRow(event) {
    event.preventDefault()
    const row = event.target.closest("[data-kv-row]")
    if (!row) return

    const kvList = row.closest("[data-key-value-list]")
    row.remove()

    // Ensure at least one empty row remains
    if (kvList && kvList.querySelectorAll("[data-kv-row]").length === 0) {
      this.addConfigKvRow({ preventDefault: () => {}, target: kvList.querySelector("[data-action*='addConfigKvRow']") || kvList })
    }
    // Removal has no native input/change event. Notify through the same path
    // as an edit, using the still-attached list rather than the removed row;
    // an element field (outside any step) syncs through the form's listener.
    if (kvList) this.handleConfigFieldChange({ target: kvList })
    if (kvList && !kvList.closest("[data-step-item]")) {
      kvList.dispatchEvent(new Event("change", { bubbles: true }))
    }
  },

  /**
   * Re-count non-default values inside each step card's "More options"
   * disclosure body and update its data-set-count-badge in place.
   * Called from property_editor_controller._performSync (debounced 100ms),
   * so typing, select changes, and KV edits all keep the badge fresh.
   */
  refreshMoreOptionsBadges() {
    const container = this.controller.formFieldsTarget?.querySelector("[data-steps-container]")
    if (!container) return

    container.querySelectorAll("[data-step-item]").forEach(item => {
      const badge = item.querySelector("[data-set-count-badge]")
      if (!badge) return
      const body = badge.closest("[data-disclosure]")?.querySelector("[data-disclosure-body]")
      if (!body) return

      let count = 0
      body.querySelectorAll("[data-config-field]").forEach(fieldEl => {
        const defaultValue = fieldEl.dataset.fieldDefault ?? ""

        const kvList = fieldEl.querySelector("[data-key-value-list]")
        if (kvList) {
          const hasPair = [...kvList.querySelectorAll("[data-kv-row]")]
            .some(row => row.querySelector("[data-kv-key]")?.value?.trim())
          if (hasPair) count++
          return
        }

        const listEditor = fieldEl.querySelector("[data-list-editor]")
        if (listEditor) {
          const hasItem = [...listEditor.querySelectorAll("[data-list-value]")]
            .some(input => input.value?.trim())
          if (hasItem) count++
          return
        }

        const conditionsEditor = fieldEl.querySelector("[data-conditions-editor]")
        if (conditionsEditor) {
          const hasRow = [...conditionsEditor.querySelectorAll("[data-condition-left], [data-condition-op], [data-condition-right]")]
            .some(input => input.value?.trim())
          if (hasRow) count++
          return
        }

        const localized = fieldEl.querySelector("[data-localized-text]")
        if (localized) {
          const hasText = [...localized.querySelectorAll("[data-locale-input]")]
            .some(input => input.value?.trim())
          if (hasText) count++
          return
        }

        const input = fieldEl.querySelector("[data-config-input]")
        if (!input) return
        if (input.type === "checkbox") {
          if (String(input.checked) !== defaultValue) count++
          return
        }
        if (String(input.value ?? "") !== defaultValue) count++
      })

      badge.textContent = this.controller.stepConfigSetCountFormatValue.replace("{count}", count)
      badge.classList.toggle("hidden", count === 0)
    })
  },

  /**
   * Entity column select changed: "__manual__" swaps to the manual input;
   * any real value is mirrored into the hidden data-config-input element
   * that collectStepConfig() reads.
   */
  handleEntityColumnSelectChange(event) {
    const select = event.target
    const wrapper = select.closest("[data-entity-field-wrapper]")
    if (!wrapper) return

    if (select.value === "__manual__") {
      this.swapEntityColumnToManual(event)
      return
    }

    const hidden = wrapper.querySelector("input[type='hidden'][data-config-input]")
    if (hidden) hidden.value = select.value
    this._updatePairedValueTypeAssist(wrapper, select.value)
    this.handleConfigFieldChange(event)
  },

  /**
   * Round-3 advisory assist: when an entityField column select changes and
   * the field has a paired value field (PAIRED_VALUE_FIELDS, e.g.
   * findField→findValue), show a type chip in the paired field's label and
   * soft-validate its input against the column's html_type. Unknown column /
   * cleared selection / manual entry removes both (today's exact behavior).
   * Never blocks save, never mutates the paired value.
   */
  _updatePairedValueTypeAssist(wrapper, columnSlug) {
    const fieldKey = wrapper.querySelector("input[type='hidden'][data-config-input]")?.dataset?.configInput
    const pairedKey = PAIRED_VALUE_FIELDS[fieldKey]
    if (!pairedKey) return

    const stepItem = wrapper.closest("[data-step-item]")
    const pairedField = stepItem?.querySelector(`[data-config-field="${pairedKey}"]`)
    if (!pairedField) return
    const pairedInput = pairedField.querySelector("[data-config-input]")
    if (!pairedInput) return

    const colInfo = columnTypeOf(this.controller.canvas?.entityAttributes, columnSlug)
    const htmlType = colInfo?.htmlType || ""

    const label = pairedField.querySelector("label")
    if (label) upsertTypeChip(label, htmlType)
    wireSoftTypeValidation(pairedInput, htmlType, this.controller.softTypeHintTitleValue)
  },

  swapEntityColumnToManual(event) {
    if (event.preventDefault) event.preventDefault()
    const wrapper = event.target.closest("[data-entity-field-wrapper]")
    if (!wrapper) return
    const select = wrapper.querySelector("[data-entity-column-select]")
    const manualWrap = wrapper.querySelector("[data-entity-manual-wrap]")
    const hidden = wrapper.querySelector("input[type='hidden'][data-config-input]")
    if (select) { select.classList.add("hidden"); select.value = "" }
    if (hidden) hidden.value = ""
    if (manualWrap) {
      manualWrap.classList.remove("hidden")
      const input = manualWrap.querySelector("[data-entity-column-manual]")
      if (input) { input.value = ""; input.focus() }
    }
    this._updatePairedValueTypeAssist(wrapper, "")
    this.handleConfigFieldChange(event)
  },

  swapEntityColumnToSelect(event) {
    event.preventDefault()
    const wrapper = event.target.closest("[data-entity-field-wrapper]")
    if (!wrapper) return
    const select = wrapper.querySelector("[data-entity-column-select]")
    const manualWrap = wrapper.querySelector("[data-entity-manual-wrap]")
    const hidden = wrapper.querySelector("input[type='hidden'][data-config-input]")
    if (manualWrap) {
      manualWrap.classList.add("hidden")
      const input = manualWrap.querySelector("[data-entity-column-manual]")
      if (input) input.value = ""
    }
    if (hidden) hidden.value = ""
    if (select) { select.classList.remove("hidden"); select.value = "" }
    this._updatePairedValueTypeAssist(wrapper, "")
    this.handleConfigFieldChange(event)
  },

  /** Mirror manual column typing into the hidden data-config-input element. */
  syncEntityColumnManual(event) {
    const wrapper = event.target.closest("[data-entity-field-wrapper]")
    const hidden = wrapper?.querySelector("input[type='hidden'][data-config-input]")
    if (hidden) hidden.value = event.target.value
  },

  /**
   * Timeout hint HTML for HTTP-style actions (catalog `timeouts` capability).
   * Live text is refreshed by `_refreshCapabilityChrome`.
   */
  capabilityChromeHTML(actionEntry, currentConfig, labels = {}) {
    if (!actionEntry?.capabilities?.timeouts) return ""
    const seconds = this._effectiveTimeoutSeconds(actionEntry, this._configWithDefaults(actionEntry, currentConfig))
    const format = labels.timeoutGivesUpFormat
      || this.controller.stepTimeoutGivesUpFormatValue
      || "Gives up after {seconds} s"
    return `<p data-step-timeout-hint class="mt-1 text-[10px] text-slate-500">${escapeHtml(format.replace("{seconds}", String(seconds)))}</p>`
  },

  refreshAllCapabilityChrome() {
    const container = this.controller.formFieldsTarget?.querySelector("[data-steps-container]")
    if (!container) return
    container.querySelectorAll("[data-step-item]").forEach(item => this._refreshCapabilityChrome(item))
  },

  _refreshCapabilityChrome(stepItem) {
    const action = stepItem.dataset.stepAction
    const entry = getActionConfig(action)
    if (!entry) return

    const live = this.collectStepConfig(stepItem)
    const stored = this._storedStepConfig(stepItem)
    // A rendered field omitted from `live` was cleared; it must not fall back to the stored value.
    stepItem.querySelectorAll("[data-config-field]").forEach(fieldEl => { delete stored[fieldEl.dataset.configField] })
    const config = this._configWithDefaults(entry, { ...stored, ...live })

    this._syncRetryToggle(stepItem, entry, config)
    this._syncTimeoutHint(stepItem, entry, config)
  },

  _storedStepConfig(stepItem) {
    const input = stepItem.querySelector("[data-step-config]")
    if (!input?.value) return {}
    try { return JSON.parse(input.value) } catch { return {} }
  },

  _configWithDefaults(actionEntry, currentConfig) {
    const merged = {}
    actionFields(actionEntry).forEach(field => {
      const name = field?.name || field?.key
      if (field.default !== undefined && field.default !== null) merged[name] = field.default
    })
    return { ...merged, ...currentConfig }
  },

  /**
   * Mirror ConfigSchema#validate_capabilities: retry is on only when the
   * current config matches `idempotentWhen` or `orPresent` is non-blank.
   */
  _configIsIdempotent(transportRetry, config) {
    if (!transportRetry) return false
    const when = transportRetry.idempotentWhen || {}
    const matchesWhen = Object.keys(when).every(key => {
      const expected = when[key]
      const allowed = (Array.isArray(expected) ? expected : [expected]).map(String)
      return allowed.includes(String(config[key] ?? ""))
    })
    const orPresent = transportRetry.orPresent
    const present = Boolean(orPresent) && String(config[orPresent] ?? "").trim() !== ""
    return matchesWhen || present
  },

  _syncRetryToggle(stepItem, actionEntry, config) {
    const transportRetry = actionEntry.capabilities?.transportRetry
    const retryField = stepItem.querySelector('[data-config-field="retryOnTransportError"]')
    const attemptsField = stepItem.querySelector('[data-config-field="retryAttempts"]')
    if (!transportRetry) {
      retryField?.classList.add("hidden")
      attemptsField?.classList.add("hidden")
      retryField?.querySelector("[data-retry-idempotent-hint]")?.remove()
      return
    }
    if (!retryField) return

    const idempotent = this._configIsIdempotent(transportRetry, config)
    const input = retryField.querySelector("[data-config-input]")
    if (input) {
      input.disabled = !idempotent
      if (!idempotent) input.checked = false
    }
    if (attemptsField) {
      const attemptsInput = attemptsField.querySelector("[data-config-input]")
      if (attemptsInput) attemptsInput.disabled = !idempotent || input?.checked !== true
    }

    let hint = retryField.querySelector("[data-retry-idempotent-hint]")
    if (!idempotent) {
      if (!hint) {
        hint = document.createElement("p")
        hint.setAttribute("data-retry-idempotent-hint", "")
        hint.className = "mt-0.5 text-[10px] text-slate-500"
        retryField.appendChild(hint)
      }
      hint.textContent = this.controller.stepRetryNotIdempotentHintValue
      hint.classList.remove("hidden")
    } else if (hint) {
      hint.classList.add("hidden")
    }
  },

  _syncTimeoutHint(stepItem, actionEntry, config) {
    const hint = stepItem.querySelector("[data-step-timeout-hint]")
    if (!hint || !actionEntry.capabilities?.timeouts) return
    const seconds = this._effectiveTimeoutSeconds(actionEntry, config)
    const format = this.controller.stepTimeoutGivesUpFormatValue || "Gives up after {seconds} s"
    hint.textContent = format.replace("{seconds}", String(seconds))
  },

  _effectiveTimeoutSeconds(actionEntry, config) {
    const timeouts = actionEntry.capabilities?.timeouts
    if (!timeouts) return 0
    const cap = Number(timeouts.cap) || 10
    const connect = Number(config.connectTimeout ?? timeouts.open ?? 3)
    const read = Number(config.readTimeout ?? timeouts.read ?? 7)
    const retryOn = config.retryOnTransportError === true || config.retryOnTransportError === "true"
    const attempts = retryOn ? Number(config.retryAttempts ?? 1) || 0 : 0
    return Math.min(cap, (connect + read) * (1 + attempts))
  },

  applyConfigProblemsFromCanvas() {
    const root = this.controller.element || this.controller.formTarget
    const canvasEl = root?.closest?.("[data-controller~='flowchart-canvas']")
    const app = this.controller.application
    if (!canvasEl || !app?.getControllerForElementAndIdentifier) return
    const canvasCtrl = app.getControllerForElementAndIdentifier(canvasEl, "flowchart-canvas")
    this.applyConfigProblems(canvasCtrl?._validationProblems || [])
  },

  applyConfigProblems(problems) {
    const container = this.controller.formFieldsTarget?.querySelector("[data-steps-container]")
    if (!container) return
    const elementId = this.controller.currentElement?.id
    const relevant = (problems || []).filter(p => {
      if (p.type !== "step_config_invalid") return false
      const id = p.elementId || p.element_id
      return !id || !elementId || id === elementId
    })

    container.querySelectorAll("[data-step-item]").forEach(item => {
      this._clearAllStepFieldErrors(item)
      relevant.forEach(p => {
        if (p.field) this._showStepFieldError(item, p.field, p.message)
      })
      const badge = item.querySelector("[data-step-error-badge]")
      if (badge) badge.classList.toggle("hidden", relevant.length === 0)
      if (relevant.length > 0) this._setStepExpanded?.(item, true)
    })
  },

  _showStepFieldError(stepItem, field, message) {
    const fieldEl = stepItem.querySelector(`[data-config-field="${CSS.escape(field)}"]`)
    if (!fieldEl) return
    const input = fieldEl.querySelector("[data-config-input], select, textarea, input:not([type='hidden'])")
    if (input) input.setAttribute("aria-invalid", "true")
    let err = fieldEl.querySelector("[data-field-error]")
    if (!err) {
      err = document.createElement("p")
      err.setAttribute("data-field-error", "")
      err.className = "mt-0.5 text-[10px] text-red-600"
      fieldEl.appendChild(err)
    }
    err.textContent = message || ""
  },

  _clearStepFieldError(fieldEl) {
    fieldEl.querySelectorAll("[aria-invalid]").forEach(el => el.removeAttribute("aria-invalid"))
    fieldEl.querySelector("[data-field-error]")?.remove()
  },

  _clearAllStepFieldErrors(stepItem) {
    stepItem.querySelectorAll("[data-config-field]").forEach(fieldEl => this._clearStepFieldError(fieldEl))
    const badge = stepItem.querySelector("[data-step-error-badge]")
    if (badge) badge.classList.add("hidden")
  },

  _refreshStepErrorBadge(stepItem) {
    const badge = stepItem.querySelector("[data-step-error-badge]")
    if (!badge) return
    const remaining = stepItem.querySelector("[data-field-error]")
    badge.classList.toggle("hidden", !remaining)
  }
}
