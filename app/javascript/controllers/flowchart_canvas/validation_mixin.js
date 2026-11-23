import { getCSRFToken, escapeHtml } from "utils"
import { flowchartUrl } from "flowchart/urls"
import { ValidationService } from "flowchart/validation_service"
import { InputOutputValidationService } from "flowchart/input_output_validation_service"
import { navFor } from "flowchart/validation_navigation"
import { buildAutoFix, applySafeAutoFixes, countSafeAutoFixes } from "flowchart/validation_autofix"
import { elementFields, fieldName } from "flowchart/constants/element_registry"

/**
 * ValidationMixin
 * Provides flowchart validation, validation-list rendering, and focus-on-issue
 * navigation. Apply with Object.assign(FlowchartCanvasController.prototype, ValidationMixin).
 */
export const ValidationMixin = {
  /**
   * Translated rule-message overrides threaded into the plain-class
   * ValidationService (structural rules have no controller reference — see
   * the i18n seam comment there).
   * @private
   */
  _validationMessages() {
    return {
      missingStart: this.validationMissingStartMsgValue,
      duplicateStart: this.validationDuplicateStartMsgValue,
      missingEnd: this.validationMissingEndMsgValue,
      orphanStartFormat: this.validationOrphanStartFormatValue,
      orphanEndFormat: this.validationOrphanEndFormatValue,
      orphanElementFormat: this.validationOrphanElementFormatValue,
      unreachableFormat: this.validationUnreachableFormatValue,
      duplicateLabelFormat: this.validationDuplicateLabelFormatValue,
      elementProblemFormat: this.validationElementProblemFormatValue,
      emptyProcess: this.validationEmptyProcessValue,
      tooFewBranches: this.validationTooFewBranchesValue,
      duplicateMatchValue: this.validationDuplicateMatchValueValue,
      multipleOtherwise: this.validationMultipleOtherwiseValue,
      invalidConditionMatch: this.validationInvalidConditionMatchValue,
      missingYesBranch: this.validationMissingYesBranchValue,
      emptyLoopCondition: this.validationEmptyLoopConditionValue,
      missingCollection: this.validationMissingCollectionValue,
      missingReturnValue: this.validationMissingReturnValueValue,
      missingFlowchart: this.validationMissingFlowchartValue,
      subflowSelfReference: this.validationSubflowSelfReferenceValue,
      invalidCollectionPath: this.validationInvalidCollectionPathValue,
      reservedLoopVariable: this.validationReservedLoopVariableValue,
      collidingLoopVariables: this.validationCollidingLoopVariablesValue,
      ...Object.fromEntries(
        Object.entries(this.validationConditionErrorsValue).map(([code, text]) => [`condition.${code}`, text])
      ),
      unsupportedStructuralFormat: this.validationUnsupportedStructuralFormatValue,
      danglingConnectionFromFormat: this.validationDanglingConnectionFromFormatValue,
      danglingConnectionToFormat: this.validationDanglingConnectionToFormatValue,
      selfConnection: this.validationSelfConnectionMsgValue,
      duplicateConnection: this.validationDuplicateConnectionMsgValue,
      cycle: this.validationCycleMsgValue
    }
  },

  /**
   * Translated auto-fix button captions threaded into the plain-module
   * flowchart/validation_autofix.js (no controller reference — see the i18n
   * seam comment there).
   * @private
   */
  _autoFixLabels() {
    return {
      deleteExtraStart: this.autoFixDeleteExtraStartValue,
      renameUnique: this.autoFixRenameUniqueValue,
      removeConnection: this.autoFixRemoveConnectionValue,
      addEnd: this.autoFixAddEndValue,
      connectToEnd: this.autoFixConnectToEndValue,
      setReturnValue: this.autoFixSetReturnValueFormatValue,
      clearSubflowTarget: this.autoFixClearSubflowTargetValue
    }
  },

  /**
   * Translated fixHint overrides threaded into the plain-function
   * validation_navigation.js#navFor (no controller reference — see the i18n
   * seam comment there), keyed by rule type.
   * @private
   */
  _fixHints() {
    return {
      duplicate_start: this.fixHintDeleteExtraStartValue,
      duplicate_label: this.fixHintRenameUniqueLabelValue,
      empty_process: this.fixHintAddOneStepValue,
      loop_no_collection: this.fixHintSpecifyCollectionValue,
      empty_loop_condition: this.fixHintDefineLoopConditionValue,
      step_config_invalid: this.fixHintFixStepConfigValue,
      element_config_invalid: this.fixHintFixElementConfigValue,
      subflow_no_target: this.fixHintSelectTargetFlowchartValue,
      subflow_inaccessible: this.fixHintSelectAccessibleFlowchartValue,
      subflow_cycle: this.fixHintRemoveCircularSubflowValue,
      subflow_self_reference: this.fixHintRepointSubflowValue,
      end_no_return_value: this.fixHintProvideReturnValueValue,
      missing_input: this.fixHintPickInputProducerValue,
      codegen_todo: this.fixHintChangeStepOrElementTypeValue
    }
  },

  /**
   * Server problems use snake_case (`element_id`, `fix_hint`); client rules
   * use camelCase. Collapse both so the panel, rings, and field painter
   * share one shape — including `field` on `element_config_invalid`.
   * @private
   */
  _normalizeValidationProblem(problem) {
    if (!problem || typeof problem !== "object") return problem
    return {
      ...problem,
      elementId: problem.elementId ?? problem.element_id ?? null,
      connectionId: problem.connectionId ?? problem.connection_id ?? null,
      field: problem.field ?? null,
      fixHint: problem.fixHint ?? problem.fix_hint ?? null
    }
  },

  /**
   * Tab + anchor for a problem, with `element_config_invalid.field` pointed
   * at the catalog group (general vs advanced) that actually holds it.
   * @private
   */
  _navForProblem(problem) {
    const nav = navFor(problem, this._fixHints())
    if (!nav) return null
    if (!problem.field) return nav
    const element = this.canvas?.elements?.find((el) => el.id === problem.elementId)
    return { ...nav, tab: this._tabForElementField(element, problem.field) }
  },

  /** @private */
  _tabForElementField(element, field) {
    if (!element?.type || !field) return "general"
    const def = elementFields(element.type).find((item) => fieldName(item) === field)
    return def?.group === "advanced" ? "advanced" : "general"
  },

  async validate() {
    const config = this._previewAwareConfiguration?.() ?? {
      elements: this.canvas.elements,
      connections: this.canvas.connections
    }
    const structuralValidator = new ValidationService(
      config.elements,
      config.connections,
      this._validationMessages(),
      { flowchartId: this.idValue }
    )
    const serverCheckPromise = this._runServerValidation() // fire first, await later
    const { errors: structuralErrors, warnings } = structuralValidator.validate()

    const ioValidator = new InputOutputValidationService(
      this._canvasForValidation?.() ?? this.canvas,
      { missingInputFormat: this.validationMissingInputFormatValue }
    )
    await ioValidator.loadImplicitKeys()
    const ioErrors = ioValidator.validate()

    const normalize = (problem) => this._normalizeValidationProblem(problem)
    const clientErrors = [...structuralErrors, ...ioErrors].map(normalize)
    const clientWarnings = warnings.map(normalize)
    const clientProblems = [...clientErrors, ...clientWarnings]
    const serverProblems = (await serverCheckPromise)
      .map(normalize)
      .filter((problem) => !this._coveredByClientProblem(problem, clientProblems))

    const seen = new Set()
    const firstOccurrence = (problem) => {
      const key = JSON.stringify([problem.elementId, problem.connectionId, problem.type, problem.field])
      if (seen.has(key)) return false
      seen.add(key)
      return true
    }
    const allErrors = [...clientErrors, ...serverProblems.filter(p => p.severity === "error")].filter(firstOccurrence)
    const allWarnings = [...clientWarnings, ...serverProblems.filter(p => p.severity === "warning")].filter(firstOccurrence)
    this._showValidationResults(allErrors, allWarnings)

    return allErrors.length === 0
  },

  /**
   * A server problem the client already reports: same element and field, or —
   * for an element-level problem (no field) — same element and type.
   * @private
   */
  _coveredByClientProblem(serverProblem, clientProblems) {
    if (!serverProblem.elementId) return false
    return clientProblems.some((client) =>
      client.elementId === serverProblem.elementId &&
      (serverProblem.field ? client.field === serverProblem.field : client.type === serverProblem.type)
    )
  },

  /**
   * Run the server-side checks (subflow validity, code-gen dry run) against
   * the CURRENT in-memory canvas configuration. Any network/HTTP failure
   * degrades to a single warning so local validation results still render.
   */
  async _runServerValidation() {
    if (!this.idValue || !this.customerIdValue) return []
    const validationUrl = flowchartUrl(this, "validation")
    if (!validationUrl) return []
    try {
      const response = await fetch(validationUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": getCSRFToken(),
          "Accept": "application/json"
        },
        body: JSON.stringify({
          configuration: this._previewAwareConfiguration?.() ?? {
            elements: this.canvas.elements,
            connections: this.canvas.connections
          }
        })
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = await response.json()
      return Array.isArray(data.problems) ? data.problems : []
    } catch (_e) {
      return [{
        type: "server_check_unavailable",
        severity: "warning",
        elementId: null,
        connectionId: null,
        message: this.serverCheckUnavailableMsgValue
      }]
    }
  },

  _showValidationResults(errors, warnings) {
    const total = errors.length + warnings.length

    if (this.hasValidationBadgeTarget) {
      if (total > 0) {
        this.validationBadgeTarget.textContent = total
        this.validationBadgeTarget.title = this.validationSummaryFormatValue
          .replace("{errors}", errors.length)
          .replace("{warnings}", warnings.length)
        this.validationBadgeTarget.classList.remove("hidden")
        // Strip every possible colour class (including the static bg-red-500/
        // text-white the template ships with) before applying the right pair,
        // otherwise a warnings-only result stays red instead of turning yellow.
        this.validationBadgeTarget.classList.remove(
          "bg-red-500", "text-white",
          "bg-red-100", "text-red-800",
          "bg-yellow-100", "text-yellow-800"
        )
        if (errors.length > 0) {
          this.validationBadgeTarget.classList.add("bg-red-100", "text-red-800")
        } else {
          this.validationBadgeTarget.classList.add("bg-yellow-100", "text-yellow-800")
        }
      } else {
        this.validationBadgeTarget.title = this.validationSummaryFormatValue
          .replace("{errors}", 0)
          .replace("{warnings}", 0)
        this.validationBadgeTarget.classList.add("hidden")
      }
    }

    this._validationProblems = [
      ...errors.map(e => ({ ...this._normalizeValidationProblem(e), severity: "error" })),
      ...warnings.map(w => ({ ...this._normalizeValidationProblem(w), severity: "warning" }))
    ]

    this._applyValidationRings()
    this._renderValidationList()
    this.openBottomPanel("problems")
  },

  /**
   * Paint canvas rings for every problem element — error beats warning.
   */
  _applyValidationRings() {
    if (!this.canvas?.clearValidationStates) return
    this.canvas.clearValidationStates()

    const severityByElement = new Map()
    for (const item of this._validationProblems) {
      if (!item.elementId) continue
      if (severityByElement.get(item.elementId) === "error") continue
      severityByElement.set(item.elementId, item.severity === "error" ? "error" : "warning")
    }
    severityByElement.forEach((severity, elementId) => this.canvas.setValidationState(elementId, severity))
  },

  // Must be a plain method, NOT a getter: this mixin is merged onto the controller
  // prototype via `Object.assign`, which INVOKES accessors on the source object at
  // copy time and stores the returned value as a static data property. A getter
  // would therefore be read once (with idValue undefined) and never re-evaluated
  // per instance, defeating the sessionStorage-backed per-flowchart filter.
  _validationFilter() {
    try {
      return sessionStorage.getItem(`flowchartValidationFilter:${this.idValue}`) || "all"
    } catch (_e) {
      return "all"
    }
  },

  _renderValidationList() {
    if (!this.hasValidationListTarget) return

    const items = this._validationProblems || []
    if (items.length === 0) {
      this.validationListTarget.innerHTML = `<div class="px-4 py-3 text-sm text-green-600">${escapeHtml(this.noProblemsFoundLabelValue)}</div>`
      return
    }

    const filter = this._validationFilter()
    const errors = items.filter(i => i.severity === "error")
    const warnings = items.filter(i => i.severity === "warning")

    const pill = (key, label, count) => {
      const active = filter === key
      const classes = active
        ? "bg-slate-200 text-slate-900 rounded-full px-2 py-0.5"
        : "text-slate-500 hover:text-slate-700 px-2 py-0.5"
      return `<button class="${classes}" data-action="click->flowchart-canvas#setValidationFilter" data-filter="${key}">${label} (${count})</button>`
    }

    const canFix = this.canvas.canMutate?.() !== false
    const fixableCount = canFix ? countSafeAutoFixes(items, this.canvas, this._autoFixLabels()) : 0
    const fixAllButton = fixableCount > 0
      ? `<button type="button"
                 data-action="click->flowchart-canvas#applyAllValidationFixes"
                 class="flex-shrink-0 inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium text-indigo-600 border border-indigo-200 bg-indigo-50 rounded hover:bg-indigo-100 transition-colors">
           ${escapeHtml(this.autoFixAllLabelFormatValue.replace("{count}", fixableCount))}
         </button>`
      : ""

    const header = `
      <div class="sticky top-0 z-10 bg-white border-b border-slate-100 px-4 py-2 flex flex-wrap items-center justify-between gap-2">
        <div class="flex items-center space-x-1 text-xs">
          ${pill("all", this.filterAllLabelValue, items.length)}
          ${pill("error", this.filterErrorsLabelValue, errors.length)}
          ${pill("warning", this.filterWarningsLabelValue, warnings.length)}
        </div>
        <div class="flex items-center gap-2 min-w-0">
          <span data-flowchart-canvas-target="validationNotice" class="hidden text-xs text-slate-500 truncate"></span>
          ${fixAllButton}
        </div>
      </div>`

    this._validationCollapsed = this._validationCollapsed || {}
    const group = (key, label, groupItems) => {
      if (filter !== "all" && filter !== key) return ""
      if (groupItems.length === 0) return ""
      const collapsed = !!this._validationCollapsed[key]
      return `
        <div>
          <button class="w-full flex items-center px-4 py-1.5 text-xs font-semibold uppercase tracking-wide text-slate-500 hover:text-slate-700 bg-slate-50"
                  data-action="click->flowchart-canvas#toggleValidationGroup"
                  data-group="${key}">
            <svg class="w-3 h-3 mr-1.5 transition-transform ${collapsed ? "-rotate-90" : ""}" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
              <path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.06l3.71-3.83a.75.75 0 111.08 1.04l-4.25 4.39a.75.75 0 01-1.08 0L5.23 8.27a.75.75 0 01.02-1.06z" clip-rule="evenodd"/>
            </svg>
            ${label} (${groupItems.length})
          </button>
          <div data-validation-group="${key}" class="${collapsed ? "hidden" : ""}">
            ${groupItems.map(item => this._renderValidationItem(item, items.indexOf(item))).join("")}
          </div>
        </div>`
    }

    const groupsHtml = group("error", this.filterErrorsLabelValue, errors) + group("warning", this.filterWarningsLabelValue, warnings)
    this.validationListTarget.innerHTML = header + (groupsHtml ||
      `<div class="px-4 py-3 text-sm text-slate-500">${escapeHtml(this.noProblemsMatchFilterLabelValue)}</div>`)
  },

  /**
   * One problem row: a full-width button that focuses the offending element,
   * plus — when the rule has an auto-correction — a sibling "fix" button.
   * The two are siblings rather than nested (a button inside a button is
   * invalid markup and swallows the inner click).
   * @param {Object} item - the problem
   * @param {number} index - its position in `_validationProblems`, which is
   *   how the fix handler recovers the full problem (including `meta`)
   *   without flattening it into data attributes.
   */
  _renderValidationItem(item, index) {
    const hint = this._navForProblem(item)?.fixHint
    const fix = this.canvas.canMutate?.() === false ? null : buildAutoFix(item, this.canvas, this._autoFixLabels())
    const fixClasses = fix?.safe
      ? "text-indigo-600 border-indigo-200 bg-indigo-50 hover:bg-indigo-100"
      : "text-slate-600 border-slate-200 bg-white hover:bg-slate-100"

    return `
      <div class="flex items-start gap-2 px-4 py-2 hover:bg-slate-50">
        <button class="flex-1 min-w-0 text-left text-sm group"
                data-action="click->flowchart-canvas#focusValidationIssue"
                data-element-id="${escapeHtml(item.elementId || "")}"
                data-connection-id="${escapeHtml(item.connectionId || "")}"
                data-field="${escapeHtml(item.field || "")}"
                data-rule="${escapeHtml(item.type || "")}"
                data-severity="${item.severity}"
                data-pin-key="${escapeHtml(item.meta?.pinKey || "")}">
          <span class="flex items-center space-x-2">
            <span class="flex-shrink-0 w-2 h-2 rounded-full ${item.severity === "error" ? "bg-red-500" : "bg-yellow-500"}"></span>
            <span class="${item.severity === "error" ? "text-red-700" : "text-yellow-700"}">${escapeHtml(item.message)}</span>
          </span>
          ${hint ? `<span class="block pl-4 mt-0.5 text-xs text-slate-400">${escapeHtml(hint)}</span>` : ""}
        </button>
        ${fix ? `<button type="button"
                data-action="click->flowchart-canvas#applyValidationFix"
                data-problem-index="${index}"
                title="${escapeHtml(fix.label)}"
                class="flex-shrink-0 mt-0.5 px-2 py-0.5 text-xs font-medium border rounded transition-colors ${fixClasses}">
          ${escapeHtml(fix.label)}
        </button>` : ""}
      </div>`
  },

  /**
   * Apply one problem's auto-correction, then re-validate so the panel, the
   * badge, and the canvas rings all reflect the new state (a single fix can
   * resolve or introduce other problems).
   */
  async applyValidationFix(event) {
    event.preventDefault()
    if (this.canvas.canMutate?.() === false) return
    const index = Number(event.currentTarget.dataset.problemIndex)
    const problem = (this._validationProblems || [])[index]
    if (!problem) return

    const fix = buildAutoFix(problem, this.canvas, this._autoFixLabels())
    if (!fix || !fix.apply()) {
      this._showValidationNotice(this.autoFixNothingToDoNoticeValue)
      return
    }
    await this.validate()
  },

  /**
   * Apply every safe auto-correction in one pass. Suggested fixes (those that
   * add, delete, or invent a value) are deliberately left for the per-problem
   * buttons.
   */
  async applyAllValidationFixes(event) {
    event.preventDefault()
    if (this.canvas.canMutate?.() === false) return
    const { applied } = applySafeAutoFixes(this._validationProblems || [], this.canvas, this._autoFixLabels())
    await this.validate()
    this._showValidationNotice(
      applied > 0
        ? this.autoFixAppliedFormatValue.replace("{count}", applied)
        : this.autoFixNothingToDoNoticeValue
    )
  },

  setValidationFilter(event) {
    const filter = event.currentTarget.dataset.filter || "all"
    try {
      sessionStorage.setItem(`flowchartValidationFilter:${this.idValue}`, filter)
    } catch (_e) { /* private-mode storage failures are non-fatal */ }
    this._renderValidationList()
  },

  toggleValidationGroup(event) {
    const key = event.currentTarget.dataset.group
    if (!key) return
    this._validationCollapsed = this._validationCollapsed || {}
    this._validationCollapsed[key] = !this._validationCollapsed[key]

    const body = this.validationListTarget.querySelector(`[data-validation-group="${key}"]`)
    if (body) body.classList.toggle("hidden", this._validationCollapsed[key])
    const chevron = event.currentTarget.querySelector("svg")
    if (chevron) chevron.classList.toggle("-rotate-90", this._validationCollapsed[key])
  },

  _showValidationNotice(text) {
    if (!this.hasValidationNoticeTarget) return
    this.validationNoticeTarget.textContent = text
    this.validationNoticeTarget.classList.remove("hidden")
    clearTimeout(this._validationNoticeTimer)
    this._validationNoticeTimer = setTimeout(() => {
      if (this.hasValidationNoticeTarget) this.validationNoticeTarget.classList.add("hidden")
    }, 4000)
  },

  closeValidationPanel() {
    this.closeBottomPanel()
  },

  focusValidationIssue(event) {
    const ds = event.currentTarget.dataset
    const problem = {
      type: ds.rule,
      severity: ds.severity,
      elementId: ds.elementId || null,
      connectionId: ds.connectionId || null,
      field: ds.field || null,
      meta: ds.pinKey ? { pinKey: ds.pinKey } : undefined
    }
    const nav = this._navForProblem(problem)

    if (problem.connectionId) {
      const connection = this.canvas.connections.find(c => c.id === problem.connectionId)
      if (connection) {
        // selectConnection sets selectedConnectionId so Delete removes this edge.
        this.canvas.selectConnection(connection.id)
        const ends = [problem.elementId, connection.from, connection.to]
          .map(id => this.canvas.elements.find(el => el.id === id))
          .filter(Boolean)
        if (ends.length) this.canvas.zoomPanManager.fitToContent(ends, 300)
        this._updateZoomDisplay()
        return
      }
    }

    if (problem.elementId) {
      const element = this._focusElementById(problem.elementId)
      if (element) {
        this._showPropertySidebar(element, nav ? { tab: nav.tab, anchor: nav.anchor, severity: problem.severity } : undefined)
        return
      }
    }

    this._showValidationNotice(this.problemNotTiedNoticeValue)
  },

  /**
   * Select + zoom to a canvas element by id. Shared by focusValidationIssue
   * and focusTraceStep. Returns the element, or null when the id doesn't
   * resolve on the current canvas (stale ids degrade silently).
   */
  _focusElementById(id) {
    const element = this.canvas.elements.find(el => el.id === id)
    if (!element) return null

    this.canvas.clearConnectionSelection()
    this.canvas._selectElement(element)
    this.canvas.zoomPanManager.fitToContent([element], 300)
    this._updateZoomDisplay()
    this._updateAlignmentToolbar()
    return element
  }
}
