import { Controller } from "@hotwired/stimulus"
import { StepManager } from "controllers/property_editor/step_manager"
import { BranchManager } from "controllers/property_editor/branch_manager"
import { FormBuilder } from "controllers/property_editor/form_builder"
import { TabManager } from "controllers/property_editor/tab_manager"
import { ElementIoManager } from "controllers/property_editor/element_io_manager"
import { LabelDerivationMixin } from "controllers/property_editor/label_derivation"
import { CanvasSyncMixin } from "controllers/property_editor/canvas_sync"
import { normalizeElementProperties, schemaFor } from "flowchart/element_config"
import { collectConditions } from "controllers/property_editor/controls/conditions"
import { collectMapping } from "controllers/property_editor/controls/mapping"
import { connectionFields, chrome as catalogChrome, fieldName, elementLabel } from "flowchart/constants/element_registry"
import { runElementRules } from "flowchart/validation/element_rules"
import { outgoingDecisionConnections } from "flowchart/dynamic_ports"
import { renderCatalogField } from "controllers/property_editor/controls/field_renderer"
import { UiFeedbackMixin } from "controllers/property_editor/ui_feedback"
import { FieldVisibilityMixin } from "controllers/property_editor/field_visibility"
import { SUPPORTED_ELEMENT_TYPES } from "flowchart/constants"

/**
 * Property Editor Controller
 * Manages the sidebar property editor for flowchart elements.
 * Delegates to specialized modules for steps, branches, inputs/outputs, and form building.
 */
export default class PropertyEditorController extends Controller {
  static targets = [
    "sidebar",
    "title",
    "typeIndicator",
    "typeIcon",
    "headerWrapper",
    "form",
    "saveButton",
    "cancelButton",
    "modalContent",
    "tabBar",
    "tabPaneGeneral",
    "tabPaneSteps",
    "tabPaneIo",
    "tabPaneAdvanced",
    "formFieldsGeneral",
    "formFieldsSteps",
    "formFieldsIo",
    "formFieldsAdvanced"
  ]

  static values = {
    elementId: String,
    elementType: String,

    // ── i18n seam: English defaults keep JS specs green without any
    // data-*-value attribute; the flowchart editor mount supplies translated
    // strings via data-property-editor-<name>-value="<%= t(...) %>". ──

    // Connection editor (_buildConnectionForm / openConnectionEditor)
    connectionPropertiesTitle: { type: String, default: "Connection Properties" },
    connectionLabelPlaceholder: { type: String, default: "e.g., Yes, No, Default..." },

    // TabManager tab labels (read via this.controller.xValue — TabManager
    // cannot bake these into TAB_CONFIG since that would hardcode English).
    tabGeneralLabel: { type: String, default: "General" },
    tabStepsLabel: { type: String, default: "Step" },
    tabBranchesLabel: { type: String, default: "Branches" },
    tabIoLabel: { type: String, default: "I/O" },
    tabAdvancedLabel: { type: String, default: "Advanced" },

    // BranchManager Add Branch button
    saveChangesLabel: { type: String, default: "Save Changes" },
    addBranchLabel: { type: String, default: "Add Branch" },

    // BranchManager buildBranchesFieldHTML empty state (embeds addBranchLabel)
    branchesEmptyStateFormat: { type: String, default: 'No branches yet. Click "{addBranchLabel}" to create the first route.' },

    // BranchManager/query_count.js
    couldNotLoadEntitiesLabel: { type: String, default: "Could not load entities" },

    // StepManager/config_fields.js badges
    stepConfigSetCountFormat: { type: String, default: "{count} set" },

    // UiFeedbackMixin save-button captions
    savedLabel: { type: String, default: "Saved!" },
    errorLabel: { type: String, default: "Error!" },
    saveButtonLabel: { type: String, default: "Save" },

    // templates/type_validation.js soft-type hint (threaded through as a call
    // argument — that module is a plain function file with no controller ref)
    softTypeHintTitle: { type: String, default: "Expected a number or a ctx expression" },

    // BranchManager/condition_builder.js — group/condition/operand chrome
    // Word-form operator labels keyed by catalog operator value (symbol operators
    // like ==, !=, >, >=, <, <= render as-is and need no translation).
    branchOperatorLabels: {
      type: Object,
      default: {
        contains: "contains",
        starts_with: "starts with",
        ends_with: "ends with",
        is_empty: "is empty",
        is_not_empty: "is not empty",
        is_true: "is true",
        is_false: "is false",
        matches_regex: "matches regex",
        in_range: "in range",
        is_type: "is type",
        is_nil: "is nil"
      }
    },
    conditionFieldTypeLabel: { type: String, default: "Field" },
    conditionCountTypeLabel: { type: String, default: "Count" },
    entityLabel: { type: String, default: "Entity" },
    selectEntityPlaceholder: { type: String, default: "Select entity..." },
    whereOptionalLabel: { type: String, default: "Where (optional)" },
    addFilterLabel: { type: String, default: "Add Filter" },
    countOperatorLabel: { type: String, default: "Count Operator" },
    countValueLabel: { type: String, default: "Count Value" },
    otherGroupLabel: { type: String, default: "Other" },

    // BranchManager/query_count.js — inline WHERE-filter chrome
    selectFieldPlaceholder: { type: String, default: "Select field..." },
    enterManuallyLabel: { type: String, default: "enter manually…" },
    removeFilterTitle: { type: String, default: "Remove filter" },
    switchToDropdownTitle: { type: String, default: "Switch to dropdown" },
    schemaUnavailableLabel: { type: String, default: "Schema unavailable — enter field names manually" },

    // FormBuilder collapsed "Options" disclosure section

    // BranchManager/query_count.js — inline WHERE-row manual-entry chrome
    columnNamePlaceholder: { type: String, default: "column name" },
    // Shared generic "value" placeholder — used live by query_count.js's WHERE
    // value input AND threaded as templates/conditions.js's default param
    // (that file has no controller reference — see the seam comment there).
    valuePlaceholder: { type: String, default: "value" },

    // templates/branch.js (plain function, no controller ref — BranchManager
    // threads these in as call arguments from this.controller.*)
    matchValueLabel: { type: String, default: "Match Value" },
    matchValuePlaceholder: { type: String, default: "e.g. active" },
    branchNameLabel: { type: String, default: "Branch Name" },
    branchNamePlaceholder: { type: String, default: "e.g. Active" },
    cancelLabel: { type: String, default: "Cancel" },
    removeBranchItemTitle: { type: String, default: "Remove branch" },
    otherwiseLabel: { type: String, default: "Otherwise" },
    yesMatchLabel: { type: String, default: "Yes" },
    noMatchLabel: { type: String, default: "No" },
    routeByClearedNotice: { type: String, default: "Match values were cleared." },
    undoLabel: { type: String, default: "Undo" },

    // element_io_manager.js / element_io/renderers.js — I/O tab (plain-function
    // renderers with no controller ref; ElementIoManager threads these in as
    // a `labels` object built from these Values).
    elementIoInputsLabel: { type: String, default: "Inputs" },
    elementIoOutputsLabel: { type: String, default: "Outputs" },
    elementIoNoInputsLabel: { type: String, default: "No inputs detected" },
    elementIoNoOutputsLabel: { type: String, default: "No outputs detected" },
    elementIoRenamedTitle: { type: String, default: "Auto-renamed to avoid a key collision" },
    elementIoRenamedBadgeLabel: { type: String, default: "renamed" },
    elementIoConfigSourceTitle: { type: String, default: "Driven by a config expression" },
    elementIoConfigSourceLabel: { type: String, default: "config" },
    elementIoAutoSourceTitle: { type: String, default: "Generator-supplied literal" },
    elementIoAutoSourceLabel: { type: String, default: "auto" },
    elementIoNoProducerLabel: { type: String, default: "— no producer —" },
    elementIoProducerAriaLabelFormat: { type: String, default: "Producer for {pin}" },

    // Shared "Branch {index}" fallback name used when a
    // decision branch has no explicit connection label.
    branchFallbackNameFormat: { type: String, default: "Branch {index}" },

    // label_derivation.js (LabelDerivationMixin, mixed onto this controller —
    // reads these directly via this.xValue, no threading needed) — auto-derived
    // canvas element labels.
    deriveStartFallback: { type: String, default: "Start" },
    deriveReturnWithValueFormat: { type: String, default: "Return {value}" },
    deriveReturnValueFallback: { type: String, default: "Return Value" },
    deriveEndFallback: { type: String, default: "End" },
    deriveForEachWithCollectionFormat: { type: String, default: "ForEach {collection}" },
    deriveForEachFallback: { type: String, default: "ForEach" },
    deriveRunOnceFirstWithExprFormat: { type: String, default: "DoWhile {expr}" },
    deriveRunOnceFirstFallback: { type: String, default: "DoWhile" },
    deriveWhileWithExprFormat: { type: String, default: "While {expr}" },
    deriveWhileFallback: { type: String, default: "While" },
    deriveSubflowFallback: { type: String, default: "Subflow" },

    // templates/step.js (buildStepItemTemplate — plain function, no controller
    // ref; StepManager threads these in via _stepItemLabels(), mirroring
    // BranchManager#_branchLabels()).
    stepDragToReorderTitle: { type: String, default: "Drag to reorder" },
    stepChangeButtonLabel: { type: String, default: "Change" },
    stepChangeActionTitle: { type: String, default: "Change action" },
    stepRemoveButtonLabel: { type: String, default: "Remove" },
    stepRemoveButtonTitle: { type: String, default: "Remove step" },
    stepErrorBadgeLabel: { type: String, default: "Error" },
    stepParamsPrefixLabel: { type: String, default: "Params:" },
    stepMoreOptionsLabel: { type: String, default: "More options" },

    // templates/fields.js (plain functions, no controller ref; StepManager
    // threads these in via context.labels). otherGroupLabel,
    // enterManuallyLabel, switchToDropdownTitle, columnNamePlaceholder above
    // are reused as-is (identical English already keyed for query_count.js's
    // entity-column chrome).
    insertVariableTitle: { type: String, default: "Insert variable" },
    joinAndLabel: { type: String, default: "AND" },
    joinOrLabel: { type: String, default: "OR" },
    noVariablesAvailable: { type: String, default: "No variables available" },
    usedInThisElementLabel: { type: String, default: "Used in this element" },
    noMatchingVariablesLabel: { type: String, default: "No matching variables" },
    selectColumnPlaceholder: { type: String, default: "Select column…" },
    kvKeyPlaceholder: { type: String, default: "Key" },
    kvValuePlaceholder: { type: String, default: "Value" },
    kvRemoveRowTitle: { type: String, default: "Remove row" },
    // Shared bare "Add" word — common.js's buildSectionHeader add-button title
    // (currently an unwired dead branch — no caller passes addAction yet) and
    // fields.js's key/value-list "Add" button text.
    addLabel: { type: String, default: "Add" },
    stepPickerSearchPlaceholder: { type: String, default: "Search actions…" },
    stepPickerNoMatchLabel: { type: String, default: "No matching actions" },
    stepPickerAlreadyUsedLabel: { type: String, default: "(already used)" },
    stepPickerAllCategoriesLabel: { type: String, default: "All" },
    stepPickerCategoriesLabel: { type: String, default: "Filter by category" },
    stepPickerRecentLabel: { type: String, default: "Recently used" },
    stepRetryNotIdempotentHint: { type: String, default: "Retry is available only for idempotent requests (safe methods or an idempotency key)." },
    stepTimeoutGivesUpFormat: { type: String, default: "Gives up after {seconds} s" },

    // Step-form field controls (FE-1) — English defaults match the locale files.
    noneOptionLabel: { type: String, default: "None" },
    addRowLabel: { type: String, default: "Add row" },
    removeRowTitle: { type: String, default: "Remove" },
    searchPlaceholder: { type: String, default: "Search…" },
    localeEnLabel: { type: String, default: "English" },
    localeZhCnLabel: { type: String, default: "Chinese" },
    referenceLoadingLabel: { type: String, default: "Loading…" },
    referenceEmptyLabel: { type: String, default: "No matches" },
    referenceErrorLabel: { type: String, default: "Could not load options" },
    referencePlaceholder: { type: String, default: "Select…" },

    // Number-field placeholder when the value is cleared (ICU {value} = catalog default).
    defaultPlaceholderFormat: { type: String, default: "Default: {value}" }
  }

  /**
   * Backward-compatible getter. The old formFields target was removed from the DOM
   * and replaced by per-tab panes. All managers still call this.controller.formFieldsTarget,
   * so this getter redirects to formTarget (the <form> wrapping all tab panes).
   */
  get formFieldsTarget() {
    return this.formTarget
  }

  get hasFormFieldsTarget() {
    return this.hasFormTarget
  }

  // ===================
  // Lifecycle
  // ===================

  connect() {
    this.currentElement = null
    this.currentConnection = null
    this.canvas = null
    this._openSnapshot = null
    this.disclosureState = new Map() // per-session step disclosure open/closed (key: "<stepId>:more")

    // Initialize modules
    this.stepManager = new StepManager(this)
    this.branchManager = new BranchManager(this)
    this.elementIoManager = new ElementIoManager(this)
    this.formBuilder = new FormBuilder(this)
    if (!this.tabManager) this.tabManager = new TabManager(this)

    this._boundHandleKeydown = this._handleKeydown.bind(this)
    this._boundSyncChanges = (event) => {
      this._clearFieldErrorOnInput(event)
      if (event?.type === "branchAdded" || event?.type === "branchRemoved" || event?.type === "branchUpdated") {
        this.clearFieldError("branches")
      }
      this._syncChangesToCanvas(event)
    }
    this._boundRevealInvalidField = this._revealInvalidField.bind(this)
    this._boundFieldFocusIn = this._onFieldFocusIn.bind(this)
    this._boundFieldFocusOut = this._onFieldFocusOut.bind(this)
    document.addEventListener("keydown", this._boundHandleKeydown)

    // Canvas → editor sync: when the canvas structurally changes the open
    // element (e.g. a branch auto-created by drawing a connection), refresh the
    // form from the latest element state. See _onCanvasStructureChanged.
    this._boundStructureChanged = this._onCanvasStructureChanged.bind(this)
    document.addEventListener("flowchartStructureChanged", this._boundStructureChanged)
  }

  disconnect() {
    if (this._syncTimeout) clearTimeout(this._syncTimeout)
    if (this._problemHighlightTimer) clearTimeout(this._problemHighlightTimer)
    if (this._structureRefreshTimer) clearTimeout(this._structureRefreshTimer)
    this._clearHideSidebarTimer()
    this._clearSaveButtonTimer?.()
    document.removeEventListener("keydown", this._boundHandleKeydown)
    document.removeEventListener("flowchartStructureChanged", this._boundStructureChanged)
    this._removeFormChangeListeners()
    if (this.elementIoManager) this.elementIoManager.close()
    this.stepManager.reset()
  }

  /**
   * Canvas → editor sync. When the canvas structurally changes the element that
   * is currently open, the form goes stale; rebuild it from the latest element.
   * Guards keep this safe and quiet:
   *  - _formOutOfSync is false for the editor's own edits / branch-modal ops
   *    (both sides already agree) ⇒ no feedback loop, no flicker;
   *  - skip while the user is typing in a form field ⇒ never clobber focus;
   *  - the active tab is preserved across the rebuild.
   */
  _onCanvasStructureChanged() {
    if (!this.currentElement || !this.canvas || !this.hasFormTarget) return
    const active = document.activeElement
    if (active && this.element.contains(active) && /^(INPUT|SELECT|TEXTAREA)$/.test(active.tagName)) return
    const el = this.canvas.elements.find(e => e.id === this.currentElement.id)
    if (!el || !this._formOutOfSync(el)) return

    clearTimeout(this._structureRefreshTimer)
    this._structureRefreshTimer = setTimeout(() => {
      if (!this.canvas) return
      const fresh = this.canvas.elements.find(e => e.id === el.id)
      if (!fresh) return
      // Canvas is authoritative here — drop any pending editor→canvas sync so
      // openEditor's flush can't write the stale form back over the change.
      if (this._syncTimeout) { clearTimeout(this._syncTimeout); this._syncTimeout = null }
      const activeTab = this.tabManager?.activeTab
      this.openEditor(fresh, this.canvas)
      if (activeTab && this.tabManager?.switchTo) this.tabManager.switchTo(activeTab)
    }, 30)
  }

  /**
   * Whether the open form's collected state diverges from the canvas element.
   * Compares a decision's branch identity (count + elementId + matchValue +
   * name). Editor-initiated changes keep both sides in sync, so this returns
   * true only for genuine external canvas edits (e.g. auto-populated branches).
   */
  _formOutOfSync(el) {
    if (!el || el.type !== "decision" || !this.branchManager) return false
    const formBranches = this.branchManager.collectBranches() || []
    const outgoing = (this.canvas?.connections || [])
      .filter((conn) => conn.from === el.id)
      .slice()
      .sort((left, right) => {
        const ai = Number((/^port_(\d+)$/.exec(left.fromPort || "") || [0, 9999])[1])
        const bi = Number((/^port_(\d+)$/.exec(right.fromPort || "") || [0, 9999])[1])
        return ai - bi
      })
    if (formBranches.length !== outgoing.length) return true
    for (let i = 0; i < outgoing.length; i++) {
      const a = formBranches[i] || {}, b = outgoing[i] || {}
      if ((a.elementId || "") !== (b.to || "")) return true
      if ((a.matchValue || "") !== (b.matchValue || "")) return true
      if ((a.name || "") !== (b.label || "")) return true
    }
    return false
  }

  tabBarTargetConnected() {
    if (!this.tabManager) this.tabManager = new TabManager(this)
    this.tabManager.init(this.tabBarTarget, {
      general: this.hasTabPaneGeneralTarget ? this.tabPaneGeneralTarget : null,
      steps: this.hasTabPaneStepsTarget ? this.tabPaneStepsTarget : null,
      branches: this.hasTabPaneStepsTarget ? this.tabPaneStepsTarget : null,
      io: this.hasTabPaneIoTarget ? this.tabPaneIoTarget : null,
      advanced: this.hasTabPaneAdvancedTarget ? this.tabPaneAdvancedTarget : null
    })
  }

  // ===================
  // Public API
  // ===================

  /**
   * Open the property editor for a flowchart element.
   * Initializes the form with element data, snapshots label + properties for
   * Cancel/close restore, and sets up real-time sync to the canvas.
   * @param {Object} element - The flowchart element to edit
   * @param {string} element.id - Unique identifier of the element
   * @param {string} element.type - Supported element type
   * @param {string} element.label - Display label
   * @param {Object} element.properties - Element-specific properties
   * @param {Object} canvas - The FlowchartCanvas instance for syncing changes
   * @param {Object} [nav] - Optional validation-problem navigation hint
   * @param {string} [nav.tab] - Tab key to switch to (general, steps, io, advanced)
   * @param {string} [nav.anchor] - CSS selector for the field to scroll to and highlight
   * @param {string} [nav.severity] - Problem severity ("error" or "warning") controlling ring color
   * @example
   * // Open editor when element is double-clicked
   * canvas.onElementDoubleClick = (element) => {
   *   propertyEditor.openEditor(element, canvas)
   * }
   */
  openEditor(element, canvas, nav = undefined) {
    if (!SUPPORTED_ELEMENT_TYPES.includes(element?.type)) return

    // Flush any pending debounced sync for the previously-selected element
    // or connection before swapping `currentElement`. Without this, edits
    // made within the 100ms debounce window are silently dropped when the
    // user clicks a different element.
    this._flushPendingSync()
    this._clearUndoCoalesceKey()

    this.elementIoManager.close()
    this.currentElement = element
    this.currentConnection = null
    this.canvas = canvas
    this.elementIdValue = element.id
    this.elementTypeValue = element.type
    this._labelAutoDerived = false

    // Reset module indices
    this.stepManager.reset()
    this.branchManager.reset()

    this._captureOpenSnapshot(element)

    this.formBuilder.buildForm()

    // Show tab bar and configure tabs for this element type
    if (this.hasTabBarTarget) {
      this.tabBarTarget.classList.remove("hidden")
    }
    this.tabManager.configureForElementType(element.type)
    this._updateTabBadges()

    // Auto-derive label after form and tabs are fully configured
    if (!this._isCanvasReadOnly()) this.formBuilder._autoDeriveLabelOnOpen()

    this._setupFormChangeListeners()
    this._showSidebar()
    this._applyReadOnlyState()

    this.applyElementFieldProblems(this._elementFieldProblems(), { reveal: false })
    if (nav?.tab) this._navigateToProblem(nav)
  }

  /**
   * Open the property editor for a connection.
   * Builds the catalog connection fields (label + Notes).
   * @param {Object} connection - The connection to edit
   * @param {Object} canvas - The FlowchartCanvas instance
   */
  openConnectionEditor(connection, canvas) {
    // Flush any pending debounced sync for the currently-open element or
    // connection before swapping selection — see openEditor for the full
    // rationale. Prevents losing in-flight edits when the user jumps from
    // editing an element to editing a connection within the debounce window.
    this._flushPendingSync()
    this._clearUndoCoalesceKey()

    // Clear element editing state
    this.elementIoManager.close()
    this.stepManager.reset()
    this.currentElement = null
    this.currentConnection = connection
    this.canvas = canvas
    this._captureOpenSnapshot(connection)

    this._removeFormChangeListeners()

    // Hide tab bar for connections (no tabs needed)
    if (this.hasTabBarTarget) {
      this.tabBarTarget.classList.add("hidden")
    }
    // Show only the general pane, hide others
    if (this.hasTabPaneGeneralTarget) this.tabPaneGeneralTarget.classList.remove("hidden")
    if (this.hasTabPaneStepsTarget) this.tabPaneStepsTarget.classList.add("hidden")
    if (this.hasTabPaneIoTarget) this.tabPaneIoTarget.classList.add("hidden")
    if (this.hasTabPaneAdvancedTarget) this.tabPaneAdvancedTarget.classList.add("hidden")

    if (this.hasTitleTarget) {
      this.titleTarget.textContent = this.connectionPropertiesTitleValue
    }

    // Set type indicator to a neutral connection color
    if (this.hasTypeIndicatorTarget) {
      this.typeIndicatorTarget.style.backgroundColor = "#64748b"
    }

    // Reset the header band to neutral (no element tint)
    if (this.hasHeaderWrapperTarget) {
      this.headerWrapperTarget.style.backgroundColor = ""
      this.headerWrapperTarget.style.borderBottom = ""
    }

    // Clear stale content from non-general tab panes
    if (this.hasFormFieldsStepsTarget) this.formFieldsStepsTarget.innerHTML = ""
    if (this.hasFormFieldsIoTarget) this.formFieldsIoTarget.innerHTML = ""
    if (this.hasFormFieldsAdvancedTarget) this.formFieldsAdvancedTarget.innerHTML = ""

    if (this.hasFormFieldsTarget) {
      this._buildConnectionForm(connection)
    }

    this._setupFormChangeListeners()
    this._showSidebar()
    this._applyReadOnlyState()
  }

  /**
   * Detect whether the surrounding flowchart canvas is read-only (active flowchart)
   * and disable form inputs + Save button accordingly. The data attribute is
   * the source of truth set by the server and may flip after the canvas copied
   * it, so it is read on every check; the canvas adds subflow preview mode.
   * @private
   */
  _isCanvasReadOnly() {
    const canvasEl = document.querySelector('[data-controller*="flowchart-canvas"]')
    if (canvasEl?.dataset.flowchartCanvasReadOnlyValue === "true") return true
    if (this.canvas && typeof this.canvas.canMutate === "function") {
      return !this.canvas.canMutate()
    }
    const live = canvasEl?.flowchartCanvas
    if (live && typeof live.canMutate === "function") return !live.canMutate()
    return false
  }

  _applyReadOnlyState() {
    if (!this.hasFormTarget) return
    const readOnly = this._isCanvasReadOnly()
    this.formTarget.querySelectorAll("input, textarea, select, button").forEach(el => {
      // Leave the Cancel/Close affordances enabled so users can still dismiss the panel.
      if (el.dataset.action?.includes("property-editor#close")) return
      // Restore only controls disabled by this guard; independently disabled
      // controls (e.g. unavailable actions) retain their own state.
      if (readOnly && !el.disabled) {
        el.dataset.propertyEditorDisabled = "true"
        el.disabled = true
        el.classList.add("opacity-60", "cursor-not-allowed")
      } else if (!readOnly && el.dataset.propertyEditorDisabled) {
        delete el.dataset.propertyEditorDisabled
        el.disabled = false
        el.classList.remove("opacity-60", "cursor-not-allowed")
      }
    })
    this.formTarget.querySelectorAll("[data-step-item]").forEach((item) => {
      item.draggable = !readOnly
    })
    this.formTarget.querySelectorAll("[data-drag-handle]").forEach((handle) => {
      handle.classList.toggle("pointer-events-none", readOnly)
      handle.classList.toggle("opacity-50", readOnly)
    })
  }

  /**
   * Tab activation hook invoked by TabManager whenever the user switches tabs
   * or the editor opens. When the I/O tab becomes active for an element, we
   * ask ElementIoManager to (re)render the auto-detected input/output view
   * into the I/O pane. Silent no-op for other tabs or when no element is
   * selected (e.g. connection editing).
   */
  onTabActivated(tabKey) {
    if (tabKey !== "io" || !this.currentElement || !this.elementIoManager) return
    const pane = this.hasFormFieldsIoTarget ? this.formFieldsIoTarget : null
    if (!pane) return
    this.elementIoManager.openForElement(this.currentElement, pane).catch(() => {})
  }

  /**
   * Get the form fields container for a specific tab.
   * Falls back to formFieldsTarget if tab-specific target is not available.
   * @param {string} tabKey - The tab key (general, steps, io, advanced)
   * @returns {HTMLElement} - The container element for the tab's fields
   */
  getFormFieldsForTab(tabKey) {
    switch (tabKey) {
      case "general": return this.hasFormFieldsGeneralTarget ? this.formFieldsGeneralTarget : this.formTarget
      case "steps":
      case "branches": return this.hasFormFieldsStepsTarget ? this.formFieldsStepsTarget : this.formTarget
      case "io": return this.hasFormFieldsIoTarget ? this.formFieldsIoTarget : this.formTarget
      case "advanced": return this.hasFormFieldsAdvancedTarget ? this.formFieldsAdvancedTarget : this.formTarget
      default: return this.formTarget
    }
  }

  /**
   * Build the connection property form from catalog `connectionFields()`.
   * Label lives on the connection; Notes (`description`) lives on properties.
   * @param {Object} connection - The connection data
   */
  _buildConnectionForm(connection) {
    const props = connection.properties || {}
    const chrome = catalogChrome()
    const catalog = connectionFields()
    const fields = catalog.length > 0 ? catalog : [
      { name: "label", label: chrome.label.label, role: "literal", control: "text" },
      { name: chrome.notes.key, label: chrome.notes.label, role: "literal", control: "textarea", multiline: true }
    ]
    const labels = this.formBuilder?._controlLabels?.() || {}
    const context = { properties: props, fields, labels }
    const html = fields.map((field) => {
      const name = fieldName(field)
      const value = name === "label" ? (connection.label || "") : (props[name] ?? "")
      return renderCatalogField(field, value, context)
    }).join("")
    const container = this.hasFormFieldsGeneralTarget ? this.formFieldsGeneralTarget : this.formTarget
    container.innerHTML = `<div class="space-y-2">${html}</div>`
  }

  /**
   * Escape a string for safe use as an HTML attribute value.
   * @param {string} str - The string to escape
   * @returns {string}
   */
  _escapeAttr(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
  }

  // ===================
  // Action Handlers
  // ===================

  /**
   * Save the current property values to the element and database.
   * Collects all form data including steps, conditions, branches, inputs, and outputs,
   * updates the canvas element, persists to database, and closes the editor on success.
   * @param {Event} event - Form submit event
   * @returns {Promise<void>}
   */
  async save(event) {
    event.preventDefault()

    if (this._isCanvasReadOnly()) return

    // Handle connection save
    if (this.currentConnection && this.canvas) {
      return this._saveConnection()
    }

    if (!this.currentElement || !this.canvas) return

    if (!this._validateBeforeSave()) return

    const newProperties = this._collectFormData({ persist: true })

    // If label was auto-derived, re-derive from current config
    const explicitLabel = this._labelAutoDerived ? "" : (newProperties.label || "")
    delete newProperties.label

    const newLabel = this._deriveLabelFromProperties(newProperties, explicitLabel)

    // Update element properties in canvas
    if (this.canvas.updateElementProperties) {
      this.canvas.updateElementProperties(this.currentElement.id, newLabel, newProperties, true)
    } else {
      this._updateElementFallback(newProperties, newLabel)
    }

    // Persist to database
    const saved = await this._saveToDatabase()

    if (saved) {
      if (this._syncTimeout) {
        clearTimeout(this._syncTimeout)
        this._syncTimeout = null
      }
      this._showSaveSuccess()
      this._scheduleHideSidebar()
    } else {
      this._showSaveError()
    }
  }

  /**
   * Save connection properties from the form.
   */
  async _saveConnection() {
    if (!this.currentConnection || !this.canvas || !this.hasFormTarget) return

    const { label, properties } = this._readConnectionForm()

    if (this.canvas.updateConnectionProperties) {
      this.canvas.updateConnectionProperties(this.currentConnection.id, label, properties)
    } else {
      this.currentConnection.label = label
      this.currentConnection.properties = { ...this.currentConnection.properties, ...properties }
    }

    // Persist to database
    const saved = await this._saveToDatabase()

    if (saved) {
      if (this._syncTimeout) {
        clearTimeout(this._syncTimeout)
        this._syncTimeout = null
      }
      this._showSaveSuccess()
      this._scheduleHideSidebar()
    } else {
      this._showSaveError()
    }
  }

  _clearHideSidebarTimer() {
    if (this._hideSidebarTimer) {
      clearTimeout(this._hideSidebarTimer)
      this._hideSidebarTimer = null
    }
  }

  _scheduleHideSidebar() {
    this._clearHideSidebarTimer()
    this._hideSidebarTimer = setTimeout(() => {
      this._hideSidebarTimer = null
      this._hideSidebar(false)
    }, 500)
  }

  /**
   * Cancel editing and close the property editor.
   * Restores the open snapshot when the canvas drifted; otherwise no-ops.
   * @param {Event} event - Click event
   */
  cancel(event) {
    event.preventDefault()
    this._hideSidebar()
  }

  /**
   * Close the property editor sidebar.
   * Restores the open snapshot when the canvas drifted; otherwise no-ops.
   * @param {Event} [event] - Optional click event
   */
  close(event) {
    if (event) event.preventDefault()
    this._hideSidebar()
  }

  // ===================
  // Step Delegated Actions
  // ===================

  toggleStep(event) {
    this.stepManager.toggleStep(event)
  }

  removeStep(event) {
    this.stepManager.removeStep(event)
  }

  handleStepDragStart(event) {
    this.stepManager.handleStepDragStart(event)
  }

  handleStepDragEnd(event) {
    this.stepManager.handleStepDragEnd(event)
  }

  handleStepDragOver(event) {
    this.stepManager.handleStepDragOver(event)
  }

  handleStepDrop(event) {
    this.stepManager.handleStepDrop(event)
  }

  handleConfigFieldChange(event) {
    this.stepManager.handleConfigFieldChange(event)
  }

  addConfigKvRow(event) {
    this.stepManager.addConfigKvRow(event)
  }

  removeConfigKvRow(event) {
    this.stepManager.removeConfigKvRow(event)
  }

  addConfigListRow(event) {
    this.stepManager.addConfigListRow(event)
  }

  removeConfigListRow(event) {
    this.stepManager.removeConfigListRow(event)
  }

  addConfigConditionRow(event) {
    this.stepManager.addConfigConditionRow(event)
  }

  removeConfigConditionRow(event) {
    this.stepManager.removeConfigConditionRow(event)
  }

  toggleStepConditionJoin(event) {
    this.stepManager.toggleStepConditionJoin(event)
  }

  switchLocalizedLocale(event) {
    this.stepManager.switchLocalizedLocale(event)
  }

  handleEntityColumnSelectChange(event) {
    this.stepManager.handleEntityColumnSelectChange(event)
  }

  swapEntityColumnToManual(event) {
    this.stepManager.swapEntityColumnToManual(event)
  }

  swapEntityColumnToSelect(event) {
    this.stepManager.swapEntityColumnToSelect(event)
  }

  syncEntityColumnManual(event) {
    this.stepManager.syncEntityColumnManual(event)
  }

  stepPickerCommit(event) {
    this.stepManager.stepPickerCommit(event)
  }

  stepPickerEscape(event) {
    this.stepManager.stepPickerEscape(event)
  }

  stepPickerFilter(event) {
    this.stepManager.stepPickerFilter(event)
  }

  stepPickerKeydown(event) {
    this.stepManager.stepPickerKeydown(event)
  }

  stepPickerSelect(event) {
    this.stepManager.stepPickerSelect(event)
  }

  stepPickerCategory(event) {
    this.stepManager.stepPickerCategory(event)
  }

  changeStep(event) {
    this.stepManager.changeStep(event)
  }

  // ===================
  // Branch Delegated Actions
  // ===================

  addBranch(event) {
    this.branchManager.addBranch(event)
  }

  removeBranch(event) {
    this.branchManager.removeBranch(event)
  }

  undoRouteByChange(event) {
    this.branchManager.undoRouteByChange(event)
  }

  // ===================
  // Validation
  // ===================

  _validateBeforeSave() {
    this._clearElementFieldErrors()
    const problems = this._elementFieldProblems()
    this.applyElementFieldProblems(problems)
    return !problems.some((problem) => problem.field && problem.severity === "error")
  }

  _elementFieldProblems() {
    const problems = []
    const seen = new Set()
    const elementId = this.currentElement?.id
    const add = (problem) => {
      if (!problem?.field) return
      const id = problem.elementId || problem.element_id
      if (id && elementId && id !== elementId) return
      const key = `${problem.field}:${id || ""}`
      if (seen.has(key)) return
      seen.add(key)
      problems.push(problem)
    }
    this._liveElementRuleProblems().forEach(add)
    this._canvasValidationProblems().forEach(add)
    return problems
  }

  _liveElementRuleProblems() {
    if (!this.currentElement) return []
    const properties = this.hasFormTarget
      ? this._collectFormData()
      : (this.currentElement.properties || {})
    const canvasCtrl = this._getCanvasController()
    const messages = canvasCtrl?._validationMessages() ?? {}
    return runElementRules({
      element: this.currentElement,
      properties,
      outgoing: outgoingDecisionConnections(this.canvas?.connections, this.currentElement.id),
      flowchartId: canvasCtrl?.idValue,
      msg: (key) => messages[key]
    })
  }

  _canvasValidationProblems() {
    const root = this.element
    const canvasEl = root?.closest?.("[data-controller~='flowchart-canvas']")
    const app = this.application
    if (!canvasEl || !app?.getControllerForElementAndIdentifier) return []
    const canvasCtrl = app.getControllerForElementAndIdentifier(canvasEl, "flowchart-canvas")
    return canvasCtrl?._validationProblems || []
  }

  // ===================
  // Form Data Collection
  // ===================

  /**
   * Collect all form data into a properties object.
   * Used by save, sync, and preserve methods to avoid duplication.
   * @returns {Object} - Collected properties from form
   */
  _collectFormData(options = {}) {
    if (!this.hasFormTarget) return {}

    const type = this.currentElement?.type
    const formData = new FormData(this.formTarget)
    const newProperties = { ...this.currentElement?.properties }
    Object.keys(schemaFor(type)).forEach((key) => { delete newProperties[key] })

    const skipPrefixes = ["steps[", "branches[", "condition["]
    for (const [key, value] of formData.entries()) {
      if (!skipPrefixes.some((prefix) => key.startsWith(prefix))) {
        newProperties[key] = value
      }
    }

    this.formTarget.querySelectorAll('input[type="checkbox"][name]').forEach((box) => {
      newProperties[box.name] = box.checked
    })

    const steps = this.stepManager.collectSteps()
    if (steps !== null) newProperties.steps = steps

    this.formTarget.querySelectorAll("[data-element-field] [data-conditions-editor]").forEach((editor) => {
      const name = editor.closest("[data-element-field]")?.dataset.elementField
      if (name) newProperties[name] = collectConditions(editor)
    })

    this.formTarget.querySelectorAll("[data-element-field] [data-key-value-list]").forEach((list) => {
      newProperties[list.closest("[data-element-field]").dataset.elementField] = collectMapping(list)
    })

    return normalizeElementProperties(type, newProperties, { persist: options.persist === true })
  }

  // ===================
  // Sidebar Visibility
  // ===================

  _showSidebar() {
    const target = this.hasSidebarTarget ? this.sidebarTarget : this.element
    target.classList.remove("hidden")
    target.classList.add("flex", "flex-col")
  }

  /**
   * Discard the editor and close it WITHOUT a final sync. Used when the canvas
   * state is restored out from under the editor (undo/redo): the open form now
   * describes a stale element object, so re-syncing it would write the stale
   * values back and silently clobber the undo/redo. Dropping the pending sync
   * and skipping the close-time sync lets the restored canvas state stand.
   */
  discardAndClose() {
    if (!this._isSidebarVisible()) return
    if (this._syncTimeout) {
      clearTimeout(this._syncTimeout)
      this._syncTimeout = null
    }
    this._hideSidebar(false)
  }

  _hideSidebar(sync = true) {
    this._clearUndoCoalesceKey()
    if (this._syncTimeout) {
      clearTimeout(this._syncTimeout)
      this._syncTimeout = null
    }

    // Remove form change listeners
    this._removeFormChangeListeners()

    // Close element I/O manager to remove structure-change listener
    if (this.elementIoManager) this.elementIoManager.close()

    // Restore the open snapshot when the canvas drifted. Skipped after Save
    // and after undo/redo discard so those paths do not rewrite the canvas.
    if (sync) this._restoreOpenSnapshotIfChanged()
    this.stepManager.reset()

    const target = this.hasSidebarTarget ? this.sidebarTarget : this.element
    target.classList.add("hidden")
    target.classList.remove("flex", "flex-col")
    // Disclosure open/closed state is per element-session (spec C).
    this.disclosureState?.clear()
    this.currentElement = null
    this.currentConnection = null
    this.canvas = null
    this._openSnapshot = null
  }

  _isSidebarVisible() {
    const target = this.hasSidebarTarget ? this.sidebarTarget : this.element
    return !target.classList.contains("hidden")
  }

  // ===================
  // Event Handlers
  // ===================

  _handleKeydown(event) {
    if (event.defaultPrevented) return
    if (event.key === "Escape" && this._isSidebarVisible()) {
      this._hideSidebar()
    }
  }
}

Object.assign(PropertyEditorController.prototype, LabelDerivationMixin)
Object.assign(PropertyEditorController.prototype, CanvasSyncMixin)
Object.assign(PropertyEditorController.prototype, UiFeedbackMixin)
Object.assign(PropertyEditorController.prototype, FieldVisibilityMixin)

const syncToCanvas = PropertyEditorController.prototype._performSync
PropertyEditorController.prototype._performSync = function() {
  syncToCanvas.call(this)
  if (this.hasTitleTarget && this.currentElement) {
    const typeLabel = elementLabel(this.currentElement.type)
    if (typeLabel) this.titleTarget.textContent = typeLabel
  }
}
