import { Controller } from "@hotwired/stimulus"
import { FlowchartCanvas } from "flowchart/canvas"
import { DEFAULT_LABELS } from "flowchart/constants"
import { getCSRFToken } from "utils"
import { SubflowManager } from "controllers/flowchart_canvas/subflow_manager"
import { UndoRedoManager } from "controllers/flowchart_canvas/undo_redo_manager"
import { ExportManager } from "flowchart/export_manager"
import { SearchManager } from "flowchart/search_manager"
import { MinimapManager } from "flowchart/minimap_manager"
import { TestRunnerManager } from "flowchart/test_runner_manager"
import { ValidationMixin } from "controllers/flowchart_canvas/validation_mixin"
import { VersionHistoryMixin } from "controllers/flowchart_canvas/version_history_mixin"
import { SearchMixin } from "controllers/flowchart_canvas/search_mixin"
import { BottomPanelMixin } from "controllers/flowchart_canvas/bottom_panel_mixin"
import { setPortLabels } from "flowchart/dynamic_ports"
import { setContextGroupLabels } from "flowchart/context_variable_provider"
import { flowchartUrl } from "flowchart/urls"
import { setActionCatalog } from "flowchart/constants/action_registry"
import { setElementCatalog } from "flowchart/constants/element_registry"

/**
 * Flowchart Canvas Controller
 * Manages the main flowchart editing canvas with undo/redo support.
 * Delegates to specialized modules for subflow and undo/redo operations.
 */
export default class FlowchartCanvasController extends Controller {
  static values = {
    id: Number,
    customerId: Number,
    configuration: String,
    entityAttributes: Array,
    flowchartType: String,
    basedOnVersionId: String,
    // Line head the editor loaded; sent as expected_head_version_id so the
    // server can refuse a save that would overwrite a newer head (409).
    headVersionId: String,
    // A draft head is revised in place and keeps its id; its revision is
    // sent as expected_head_revision for the same check.
    headRevision: String,
    readOnly: { type: Boolean, default: false },
    autoValidate: { type: Boolean, default: false },
    urls: { type: Object, default: {} },
    // Server ActionCatalog export. Installed into the JS store on connect,
    // before the canvas renders step labels and before the nested
    // property-editor controller connects. Embedded once on this element
    // (~390 KB) — do not also put it on the property editor.
    actionCatalog: { type: Object, default: {} },
    elementCatalog: { type: Object, default: {} },

    // ── i18n seam: English defaults keep JS specs green without any
    // data-*-value attribute; the flowchart editor view (_editor.html.erb)
    // supplies translated strings via data-flowchart-canvas-<name>-value="<%= t(...) %>". ──

    // App locale (I18n.locale) for Intl date/time formatting
    appLocale: { type: String, default: "en" },

    // BottomPanelMixin
    unnamedElementLabel: { type: String, default: "(unnamed)" },
    elementConnectionsFormat: { type: String, default: "{incoming} in / {outgoing} out" },

    // SearchMixin
    searchCountZero: { type: String, default: "0 of 0" },
    searchCountFormat: { type: String, default: "{current} of {total}" },

    // ValidationMixin
    validationSummaryFormat: { type: String, default: "{errors} errors, {warnings} warnings" },
    noProblemsFoundLabel: { type: String, default: "No problems found" },
    filterAllLabel: { type: String, default: "All" },
    filterErrorsLabel: { type: String, default: "Errors" },
    filterWarningsLabel: { type: String, default: "Warnings" },
    noProblemsMatchFilterLabel: { type: String, default: "No problems match this filter" },
    problemNotTiedNotice: { type: String, default: "This problem isn't tied to a specific element — fix it on the canvas" },
    serverCheckUnavailableMsg: { type: String, default: "Server-side checks (subflow validity, code generation) could not run — showing local results only" },

    // ValidationMixin -> flowchart/validation_service.js (plain class, no
    // controller reference — see the i18n seam comment there). Threaded in via
    // ValidationMixin._validationMessages().
    validationMissingStartMsg: { type: String, default: "Flowchart must have a Start element" },
    validationDuplicateStartMsg: { type: String, default: "Only one Start element is allowed" },
    validationMissingEndMsg: { type: String, default: "Flowchart should have at least one End element" },
    validationOrphanStartFormat: { type: String, default: 'Start element "{label}" has no outgoing connections' },
    validationOrphanEndFormat: { type: String, default: 'End element "{label}" has no incoming connections' },
    validationOrphanElementFormat: { type: String, default: '"{label}" is not connected to any other element' },
    validationUnreachableFormat: { type: String, default: '"{label}" is not reachable from Start' },
    validationDuplicateLabelFormat: { type: String, default: '{count} elements share the label "{label}" — generated step names derive from labels, so duplicates are renamed unpredictably' },
    validationElementProblemFormat: { type: String, default: "{label} ({type}): {message}" },
    validationEmptyProcess: { type: String, default: "Add at least one step" },
    validationTooFewBranches: { type: String, default: "Decision requires at least two outgoing connections" },
    validationDuplicateMatchValue: { type: String, default: "Match values must be unique" },
    validationMultipleOtherwise: { type: String, default: "Only one Otherwise branch is allowed" },
    validationInvalidConditionMatch: { type: String, default: "Condition branches must match Yes (true), No (false), or Otherwise" },
    validationMissingYesBranch: { type: String, default: "Condition routing needs a Yes branch and either No or Otherwise" },
    validationEmptyLoopCondition: { type: String, default: "Add at least one condition" },
    validationMissingCollection: { type: String, default: "Collection is required" },
    validationMissingReturnValue: { type: String, default: "Return Value is required" },
    validationMissingFlowchart: { type: String, default: "Flowchart is required" },
    validationSubflowSelfReference: { type: String, default: "Flowchart cannot target itself" },
    validationInvalidCollectionPath: { type: String, default: "collection must be a valid identifier path" },
    validationReservedLoopVariable: { type: String, default: "{field} cannot be {name} because that name is reserved for the loop header" },
    validationCollidingLoopVariables: { type: String, default: "itemVariable and indexVariable must be different" },
    validationConditionErrors: {
      type: Object,
      default: {
        invalid_condition: "Conditions must be a flat group of rows",
        empty_condition: "Add at least one condition",
        invalid_row: "Condition row {index} must be a field or record-count row",
        nested_group: "Condition row {index} cannot be a nested group",
        missing_entity: "Condition row {index} needs an entity",
        unknown_count_operator: "Condition row {index} needs a count comparison",
        missing_left: "Condition row {index} needs a value to compare",
        missing_operator: "Condition row {index} needs an operator",
        unknown_operator: "Condition row {index} has an unknown operator",
        missing_right: "Condition row {index} needs a value for {operator}"
      }
    },
    validationUnsupportedStructuralFormat: { type: String, default: 'Element "{label}" uses unsupported structural type "{type}"' },
    validationDanglingConnectionFromFormat: { type: String, default: "Connection references missing element (from: {id})" },
    validationDanglingConnectionToFormat: { type: String, default: "Connection references missing element (to: {id})" },
    validationSelfConnectionMsg: { type: String, default: "Element cannot connect to itself" },
    validationDuplicateConnectionMsg: { type: String, default: "Duplicate connection between elements" },
    validationCycleMsg: { type: String, default: "Potential infinite loop: cycle detected not involving a Loop element" },

    // ValidationMixin -> flowchart/input_output_validation_service.js
    validationMissingInputFormat: { type: String, default: 'Input "{key}" has no upstream output' },

    // ValidationMixin -> flowchart/validation_navigation.js fixHint overrides
    // (plain lookup module, no controller reference — see the i18n seam
    // comment there). Threaded in via ValidationMixin._fixHints().
    fixHintDeleteExtraStart: { type: String, default: "Delete the extra Start element" },
    fixHintRenameUniqueLabel: { type: String, default: "Rename this element to a unique label" },
    fixHintAddOneStep: { type: String, default: "Add at least one step" },
    fixHintSpecifyCollection: { type: String, default: "Specify the collection to iterate" },
    fixHintDefineLoopCondition: { type: String, default: "Define the loop condition" },
    fixHintFixStepConfig: { type: String, default: "Fix this step's configuration" },
    fixHintFixElementConfig: { type: String, default: "Fix this element's configuration" },
    fixHintSelectTargetFlowchart: { type: String, default: "Select a target flowchart" },
    fixHintSelectAccessibleFlowchart: { type: String, default: "Select a flowchart that belongs to this customer or is shared" },
    fixHintRemoveCircularSubflow: { type: String, default: "Remove the circular subflow reference" },
    fixHintProvideReturnValue: { type: String, default: "Provide the Return Value expression" },
    fixHintPickInputProducer: { type: String, default: "Pick a producer for this input or add an upstream step that emits it" },
    fixHintChangeStepOrElementType: { type: String, default: "This step/element has no code generator — change the action or element type" },
    fixHintRepointSubflow: { type: String, default: "Point this Subflow at a different flowchart" },

    // ValidationMixin -> flowchart/validation_autofix.js auto-correct button
    // captions (plain module, no controller reference — see the i18n seam
    // comment there). Threaded in via ValidationMixin._autoFixLabels().
    autoFixAllLabelFormat: { type: String, default: "Fix all ({count})" },
    autoFixAppliedFormat: { type: String, default: "Applied {count} fixes" },
    autoFixNothingToDoNotice: { type: String, default: "Nothing left to fix automatically" },
    autoFixDeleteExtraStart: { type: String, default: "Delete this Start" },
    autoFixRenameUnique: { type: String, default: "Rename uniquely" },
    autoFixRemoveConnection: { type: String, default: "Remove connection" },
    autoFixAddEnd: { type: String, default: "Add an End element" },
    autoFixConnectToEnd: { type: String, default: "Connect from the last step" },
    autoFixSetReturnValueFormat: { type: String, default: "Use {value}" },
    autoFixClearSubflowTarget: { type: String, default: "Clear the target" },

    // VersionHistoryMixin
    versionsLoadFailedLabel: { type: String, default: "Failed to load versions" },
    networkErrorFormat: { type: String, default: "Network error: {message}" },
    versionCountSingularFormat: { type: String, default: "{count} version" },
    versionCountPluralFormat: { type: String, default: "{count} versions" },
    noVersionsSavedLabel: { type: String, default: "No versions saved yet. Save the flowchart to create the first version." },
    noDescriptionFallback: { type: String, default: "No description" },
    restoreButtonLabel: { type: String, default: "Restore" },
    versionLabelFormat: { type: String, default: "v{number}" },
    restoreVersionConfirmFormat: { type: String, default: "Restore version {version}? This creates a new head version with its content; the current head stays in the version history." },
    restoreFailedHttpFormat: { type: String, default: "Restore failed (HTTP {status})" },

    // Save path (_saveToServer / Ctrl+S)
    saveFailedHttpFormat: { type: String, default: "Save failed (HTTP {status})" },
    readOnlySaveToast: { type: String, default: "Cannot save a launched flowchart. Take it offline first." },

    // FlowchartCanvasController (clear / generateDocs / navigation / subflow)
    clearFlowchartConfirm: { type: String, default: "Are you sure you want to clear the entire flowchart?" },
    generateDocsFailedLabel: { type: String, default: "Failed to generate documentation. Please try again." },
    unsavedChangesConfirm: { type: String, default: "You have unsaved changes. Leave this page?" },
    expandSubflowTitle: { type: String, default: "Expand sub-flow" },
    collapseSubflowTitle: { type: String, default: "Collapse sub-flow" },
    subflowSelfReferenceToast: { type: String, default: "Cannot expand: subflow references this flowchart (self-reference)." },

    // flowchart/connection_manager.js (threaded onto canvas.labels — plain
    // class, not a mixin, so it cannot read this.xValue directly)
    connectionLabelPlaceholder: { type: String, default: "Label..." },
    edgeInsertButtonLabel: { type: String, default: "Insert an element" },
    edgeInsertMenuLabel: { type: String, default: "Choose an element to insert" },
    connectionIntoStartRejected: { type: String, default: "A Start element cannot have incoming connections" },
    connectionOutOfEndRejected: { type: String, default: "An End element cannot have outgoing connections" },
    branchFallbackNameFormat: { type: String, default: "Branch {index}" },

    // flowchart/canvas/element_management.js, canvas/external_drop.js,
    // canvas/serialization.js (mixins on the plain FlowchartCanvas class —
    // threaded onto canvas.labels same as connectionLabelPlaceholder above)
    onlyOneStartAllowedToast: { type: String, default: "Only one Start element allowed per flowchart" },
    loadConfigFailedToast: { type: String, default: "Failed to load flowchart configuration. Please reload the page." },
    elementDefaultLabels: { type: Object, default: { ...DEFAULT_LABELS } },
    uniqueLabelFormat: { type: String, default: "{label} {n}" },
    // Fallback port labels (dynamic_ports.js) + context-variable group labels
    // (context_variable_provider.js), installed on connect.
    defaultPortLabel: { type: String, default: "Default" },
    branchPortLabel: { type: String, default: "Branch" },
    ctxAlwaysAvailableLabel: { type: String, default: "Always Available" },
    ctxFromFormat: { type: String, default: "From '{label}'" },
    ctxFromStepFormat: { type: String, default: "From '{label}' (this element)" },

    // flowchart/test_runner_manager.js (reads via this.controller.xValue)
    testRunningLabel: { type: String, default: "Running..." },
    testInvalidJsonInputFormat: { type: String, default: "Invalid JSON input: {message}" },
    testInvalidJsonFormat: { type: String, default: "Invalid JSON: {message}" },
    testServerErrorFormat: { type: String, default: "Server error ({status})" },
    testClientTimeoutFormat: { type: String, default: "Request timed out after {seconds} seconds — the server did not respond" },
    testHistoryViewTitle: { type: String, default: "View this run's results" },
    testHistoryUseInputTitle: { type: String, default: "Copy this run's input back into the editor" },
    testUseInputLabel: { type: String, default: "use input" },
    testTimedOutLabel: { type: String, default: "Timed out" },
    testSuccessFormat: { type: String, default: "Success ({signal})" },
    testCompletedFallback: { type: String, default: "completed" },
    testExecutionFailedLabel: { type: String, default: "Execution failed" },
    testContextLabel: { type: String, default: "Context:" },
    testTraceOutputLabel: { type: String, default: "Trace Output" },
    testDefaultTimeoutBanner: { type: String, default: "Timed out after 10 seconds — execution aborted" },
    testExecutionSucceededLabel: { type: String, default: "Execution succeeded" },
    testNoTracedStepsLabel: { type: String, default: "Run completed without traced steps" },
    testContextNotCapturedLabel: { type: String, default: "context not captured" },
    testContextToggleLabel: { type: String, default: "context" },
    testStepsLabel: { type: String, default: "Steps:" },
    testUnnamedStepFallback: { type: String, default: "(unnamed step)" },
    testNoQueriesLabel: { type: String, default: "No SQL queries executed" },
    testQuerySummarySingularFormat: { type: String, default: "{count} query · {duration} ms total" },
    testQuerySummaryPluralFormat: { type: String, default: "{count} queries · {duration} ms total" },
    testQueryDurationFormat: { type: String, default: "{duration} ms" },
    testSqlQueriesLabelFormat: { type: String, default: "SQL Queries — {summary}" },
    testErrorLabel: { type: String, default: "Error" },
    testDecisionBranchFormat: { type: String, default: "{step} → {branch}" },
    testTraceTruncatedFormat: { type: String, default: "Showing the first {count} steps; the run had more." }
  }

  static targets = [
    "canvas",
    "overlay",
    "propertySidebar",
    "canvasContainer",
    "canvasWrapper",
    "toastContainer",
    "alignmentToolbar",
    "distributeSeparator",
    "distributeHBtn",
    "distributeVBtn",
    "validationBadge",
    "validationList",
    "validationNotice",
    "unsavedIndicator",
    "testInput",
    "testOutput",
    "testStatus",
    "testRunButton",
    "testInputError",
    "testHistory",
    "searchBar",
    "searchInput",
    "searchCount",
    "minimapContainer",
    "versionList",
    "versionCount",
    "elementsCount",
    "elementsList",
    "bottomPanel",
    "bottomTab",
    "saveConflictBanner",
    "saveConflictMessage",
    "previewNotice"
  ]

  // ===================
  // Lifecycle
  // ===================

  connect() {
    // Guard: ensure canvas target exists before initializing
    if (!this.hasCanvasTarget) {
      console.warn("FlowchartCanvasController: canvas target not found, skipping initialization")
      return
    }

    // Parent controller connects before the nested property-editor, and
    // loadConfiguration renders step labels — install the catalog first.
    setActionCatalog(this.actionCatalogValue)
    setElementCatalog(this.elementCatalogValue)

    this.isCanvasReady = false
    this.hasUnsavedChanges = false

    // Install i18n overlays for the controller-less flowchart/ helper modules.
    setPortLabels({ default: this.defaultPortLabelValue, branch: this.branchPortLabelValue })
    setContextGroupLabels({
      alwaysAvailable: this.ctxAlwaysAvailableLabelValue,
      from: this.ctxFromFormatValue,
      fromStep: this.ctxFromStepFormatValue
    })

    // Initialize modules
    this.undoRedoManager = new UndoRedoManager(this)
    this.subflowManager = new SubflowManager(this)
    this.exportManager = null // Will be initialized after canvas
    this.searchManager = null // Will be initialized after canvas
    this.minimapManager = null // Will be initialized after canvas
    this._searchDebounceTimer = null

    this._initializeCanvas()
    this._bindEventListeners()

    this.element.flowchartCanvas = this.canvas

    // Test runner: restore the last input for this flowchart and gate the
    // Run button on its validity (targets are static in the ERB, so they
    // exist by connect time when the panel markup is present).
    this._testRunner = new TestRunnerManager(this)
    this._testRunner.restoreSavedInput()
    this._testRunner.validateInput()
  }

  disconnect() {
    clearTimeout(this._validationNoticeTimer)
    clearTimeout(this._searchDebounceTimer)
    this._searchDebounceTimer = null
    if (this._boundStructureChanged) {
      this.element.removeEventListener("flowchartStructureChanged", this._boundStructureChanged)
    }
    if (this._boundHandleElementDrop) {
      this.element.removeEventListener("elementDrop", this._boundHandleElementDrop)
    }
    if (this._boundHandleElementSelected) {
      this.element.removeEventListener("elementSelected", this._boundHandleElementSelected)
    }
    if (this._beforeUnload) {
      window.removeEventListener("beforeunload", this._beforeUnload)
    }
    if (this._beforeVisit) {
      document.removeEventListener("turbo:before-visit", this._beforeVisit)
    }
    this.minimapManager?.destroy()
    if (this.canvas) {
      this.canvas.destroy()
    }
  }

  // ===================
  // Initialization
  // ===================

  _initializeCanvas() {
    this.canvas = new FlowchartCanvas(this.canvasTarget)
    this.canvas.entityAttributes = this.entityAttributesValue || []
    this.canvas.flowchartType = this.flowchartTypeValue || "customer_specific"
    // Propagate read-only state to the canvas so its own mouse / keyboard
    // handlers refuse to mutate. Without this, an "active" flowchart can
    // still be edited by drag, paste, delete — the server later rejects
    // the save but the user sees a stale, broken state until reload.
    this.canvas.isReadOnly = this.readOnlyValue
    // Thread i18n labels onto the canvas for non-mixin flowchart/ helpers
    // (e.g. connection_manager.js) that have no reference to this controller.
    this.canvas.labels = {
      connectionLabelPlaceholder: this.connectionLabelPlaceholderValue,
      edgeInsertButtonLabel: this.edgeInsertButtonLabelValue,
      edgeInsertMenuLabel: this.edgeInsertMenuLabelValue,
      onlyOneStartAllowedToast: this.onlyOneStartAllowedToastValue,
      loadConfigFailedToast: this.loadConfigFailedToastValue,
      elementDefaultLabels: this.elementDefaultLabelsValue,
      uniqueLabelFormat: this.uniqueLabelFormatValue,
      expandSubflowTitle: this.expandSubflowTitleValue,
      collapseSubflowTitle: this.collapseSubflowTitleValue,
      connectionIntoStartRejected: this.connectionIntoStartRejectedValue,
      connectionOutOfEndRejected: this.connectionOutOfEndRejectedValue,
      branchFallbackNameFormat: this.branchFallbackNameFormatValue
    }
    this.exportManager = new ExportManager(this.canvas)
    this.searchManager = new SearchManager(this.canvas)
    if (this.hasMinimapContainerTarget) {
      this.minimapManager = new MinimapManager(this.canvas, this.minimapContainerTarget)
    }
    this._setupCanvasCallbacks()
    this._setupBeforeUnloadWarning()
    this._onCanvasReady()

    // Prime the step I/O pin cache for all existing steps so the step modal's
    // I/O tab renders without waiting for a per-open fetch.
    import("controllers/property_editor/step_io/io_params_client").then(({ primeAllStepPins }) => {
      primeAllStepPins(this.canvas).catch(() => {})
    })
    // Parallel: prime element-level pins for the I/O tab on each element.
    import("controllers/property_editor/element_io/io_params_client").then(({ primeAllElementPins }) => {
      primeAllElementPins(this.canvas).catch(() => {})
    })

    // React to structural changes (add/remove element, connect, edit props):
    // re-fetch pins for the affected element (or all) and prune now-stale
    // overrides. All imports are lazy to avoid bloating the initial bundle.
    this._boundStructureChanged = async (event) => {
      const elementId = event.detail?.elementId || null
      try {
        const [{ refreshElementPins, primeAllElementPins }, { validateOverrides }] = await Promise.all([
          import("controllers/property_editor/element_io/io_params_client"),
          import("controllers/property_editor/element_io/override_validator")
        ])
        if (elementId) await refreshElementPins(this.canvas, elementId)
        else await primeAllElementPins(this.canvas)
        validateOverrides(this.canvas)
      } catch (_e) { /* non-fatal — I/O tab will re-fetch on next open */ }
    }
    this.element.addEventListener("flowchartStructureChanged", this._boundStructureChanged)
  }

  _setupBeforeUnloadWarning() {
    this._beforeUnload = (e) => {
      if (this.hasUnsavedChanges) {
        e.preventDefault()
        e.returnValue = ""
      }
    }
    window.addEventListener("beforeunload", this._beforeUnload)

    this._beforeVisit = (e) => {
      if (!this.hasUnsavedChanges) return
      if (!confirm(this.unsavedChangesConfirmValue)) {
        e.preventDefault()
      }
    }
    document.addEventListener("turbo:before-visit", this._beforeVisit)
  }

  _setupCanvasCallbacks() {
    this.canvas.onchange = () => {
      if (!this.isCanvasReady) return
      this.hasUnsavedChanges = true
      this._editsSinceSaveStart = true
      this._updateUnsavedIndicator()
      // A property-editor operation commits its undo snapshot exactly once,
      // via the debounced canvas-sync (_performSync → updateElementProperties →
      // onchange). Managers that also mutate the canvas directly (e.g. branch
      // add/remove creates an element + connection) fire onchange too, but flag
      // it visual-only with _previewSync so it does NOT commit a second,
      // near-duplicate snapshot — otherwise undoing one add-branch took two
      // Undo presses. The sync that follows still commits the complete state.
      if (!this.canvas._previewSync) {
        this.undoRedoManager.commitPendingState()
      }
      this.canvas.clearTraceOverlay()
      this._dispatchConfigurationChange()
      if (this.minimapManager) {
        this.minimapManager.update()
      }
    }

    this.canvas.onElementDoubleClick = (element) => {
      this._handleElementSelected({ detail: { element } })
    }

    this.canvas.onSubflowToggle = (element) => {
      this.subflowManager.toggleSubflowExpansion(element)
    }

    this.canvas.onElementSelected = (_element) => {
      this._updateAlignmentToolbar()
    }

    this.canvas.onConnectionSelected = (connection) => {
      this._handleConnectionSelected(connection)
    }

    this.canvas.onCanvasClick = () => {
      this._handleCanvasClick()
    }

    this.canvas.onSelectionChanged = () => {
      this._updateAlignmentToolbar()
    }

    this.canvas.onundo = () => this.undo()
    this.canvas.onredo = () => this.redo()
    this.canvas.onZoomChange = () => {
      this._updateZoomDisplay()
      if (this.minimapManager) {
        this.minimapManager._updateViewport()
      }
    }
    this.canvas.onSearchRequested = () => this.openSearch()
    this.canvas.onSaveRequested = () => {
      if (this.readOnlyValue) this.showToast(this.readOnlySaveToastValue, "error")
      else this.save()
    }
    this.canvas.onToast = (message, type) => this.showToast(message, type)


  }

  _bindEventListeners() {
    this._boundHandleElementDrop = this._handleElementDrop.bind(this)
    this._boundHandleElementSelected = this._handleElementSelected.bind(this)

    this.element.addEventListener("elementDrop", this._boundHandleElementDrop)
    this.element.addEventListener("elementSelected", this._boundHandleElementSelected)
  }

  _onCanvasReady() {
    if (this.configurationValue) {
      this.canvas.loadConfiguration(this.configurationValue)
    }

    requestAnimationFrame(() => {
      // Restore expanded subflows tracking and fold icons after DOM is ready
      this.subflowManager.restoreExpandedSubflowsFromConfiguration()
      this._ensureElementsInView()
      this.undoRedoManager.saveInitialState()
      this.isCanvasReady = true

      if (this.minimapManager) {
        this.minimapManager.update()
      }

      if (this.autoValidateValue) {
        requestAnimationFrame(() => this.validate())
      }
    })
  }

  _ensureElementsInView() {
    const zpm = this.canvas?.zoomPanManager
    const elements = this.canvas?.elements
    if (!zpm || !elements?.length) return
    const vw = zpm.viewWidth
    const vh = zpm.viewHeight
    if (!vw || !vh) return

    const overflows = elements.some(el => (
      el.x - el.width / 2 < zpm.panX ||
      el.x + el.width / 2 > zpm.panX + vw ||
      el.y - el.height / 2 < zpm.panY ||
      el.y + el.height / 2 > zpm.panY + vh
    ))
    if (overflows) this.fitToContent()
  }

  // ===================
  // Undo/Redo Delegated
  // ===================

  undo() {
    this._leavePreviewMode({ restore: true })
    if (this.canvas?.canMutate ? !this.canvas.canMutate() : this.readOnlyValue) return false
    // Undo rebuilds every element object via loadConfiguration. An open property
    // editor would keep a stale reference to the pre-undo element and, on close,
    // sync its stale form back — silently reverting the undo. Discard it first.
    this._discardOpenPropertyEditor()
    const result = this.undoRedoManager.undo()
    if (result && this.minimapManager) {
      this.minimapManager.update()
    }
    return result
  }

  redo() {
    this._leavePreviewMode({ restore: true })
    if (this.canvas?.canMutate ? !this.canvas.canMutate() : this.readOnlyValue) return false
    this._discardOpenPropertyEditor()
    const result = this.undoRedoManager.redo()
    if (result && this.minimapManager) {
      this.minimapManager.update()
    }
    return result
  }

  // Close any open property editor without a final sync, so an undo/redo
  // restore is not clobbered by the editor's now-stale form (see
  // property-editor#discardAndClose).
  _discardOpenPropertyEditor() {
    if (!this.hasPropertySidebarTarget) return
    const propertyEditor = this.application.getControllerForElementAndIdentifier(
      this.propertySidebarTarget,
      "property-editor"
    )
    if (propertyEditor && typeof propertyEditor.discardAndClose === "function") {
      propertyEditor.discardAndClose()
    }
  }

  get canUndo() {
    return this.undoRedoManager.canUndo
  }

  get canRedo() {
    return this.undoRedoManager.canRedo
  }

  // ===================
  // Zoom Controls
  // ===================

  zoomIn() {
    this.canvas.zoomPanManager.zoomIn()
    this._updateZoomDisplay()
    if (this.minimapManager) {
      this.minimapManager._updateViewport()
    }
  }

  zoomOut() {
    this.canvas.zoomPanManager.zoomOut()
    this._updateZoomDisplay()
    if (this.minimapManager) {
      this.minimapManager._updateViewport()
    }
  }

  fitToContent() {
    this.canvas.zoomPanManager.fitToContent(this.canvas.elements)
    this._updateZoomDisplay()
    if (this.minimapManager) {
      this.minimapManager._updateViewport()
    }
  }

  _updateZoomDisplay() {
    this.element.dispatchEvent(new CustomEvent("zoomChanged", {
      detail: { percent: this.canvas.zoomPanManager.zoomPercent },
      bubbles: true
    }))
  }

  _updateUnsavedIndicator() {
    if (this.hasUnsavedIndicatorTarget) {
      this.unsavedIndicatorTarget.classList.toggle("hidden", !this.hasUnsavedChanges)
    }
  }

  // ===================
  // Alignment Tools
  // ===================

  alignLeft() {
    this.canvas.alignmentManager.alignLeft()
    this._updateAlignmentToolbar()
  }

  alignCenterH() {
    this.canvas.alignmentManager.alignCenterH()
    this._updateAlignmentToolbar()
  }

  alignRight() {
    this.canvas.alignmentManager.alignRight()
    this._updateAlignmentToolbar()
  }

  alignTop() {
    this.canvas.alignmentManager.alignTop()
    this._updateAlignmentToolbar()
  }

  alignCenterV() {
    this.canvas.alignmentManager.alignCenterV()
    this._updateAlignmentToolbar()
  }

  alignBottom() {
    this.canvas.alignmentManager.alignBottom()
    this._updateAlignmentToolbar()
  }

  distributeH() {
    this.canvas.alignmentManager.distributeH()
  }

  distributeV() {
    this.canvas.alignmentManager.distributeV()
  }

  autoLayout() {
    if (this.canvas?.canMutate ? !this.canvas.canMutate() : this.readOnlyValue) return
    this.canvas.autoLayout()
  }

  cycleConnectionRouting() {
    if (this.canvas?.canMutate ? !this.canvas.canMutate() : this.readOnlyValue) return
    this.canvas.cycleConnectionRouting()
  }

  _updateAlignmentToolbar() {
    if (!this.hasAlignmentToolbarTarget) return
    if (this.canvas?.canMutate?.() === false) {
      this.alignmentToolbarTarget.classList.add("hidden")
      return
    }
    const count = this.canvas.selectedElements.length
    if (count >= 2) {
      this.alignmentToolbarTarget.classList.remove("hidden")
      const show3 = count >= 3
      if (this.hasDistributeSeparatorTarget) this.distributeSeparatorTarget.classList.toggle("hidden", !show3)
      if (this.hasDistributeHBtnTarget) this.distributeHBtnTarget.classList.toggle("hidden", !show3)
      if (this.hasDistributeVBtnTarget) this.distributeVBtnTarget.classList.toggle("hidden", !show3)
    } else {
      this.alignmentToolbarTarget.classList.add("hidden")
    }
  }

  // ===================
  // Event Handlers
  // ===================

  _handleElementDrop(event) {
    if (this.canvas?.canMutate ? !this.canvas.canMutate() : this.readOnlyValue) return

    const { elementType, x, y, customElementData, isDoubleClick, dropTarget } = event.detail

    // A double-click append leaves placement to the canvas, which stacks the
    // element below the last one and connects it; an explicit position would
    // be treated as a free drop and left unconnected.
    const elementData = isDoubleClick ? { type: elementType } : { type: elementType, x, y }

    if (customElementData) {
      elementData.label = customElementData.name
      elementData.properties = customElementData.default_properties || {}

      if (customElementData.id) {
        elementData.customElementId = customElementData.id
      }
      if (customElementData.flowchartId != null && customElementData.flowchartId !== "") {
        const flowchartId = Number(customElementData.flowchartId)
        if (Number.isFinite(flowchartId)) elementData.properties.flowchartId = flowchartId
      }
    }

    // Use the drop target passed from drag-over (captured before clearing),
    // falling back to position-based lookup for double-click additions
    const targetElement = dropTarget || this.canvas.getElementAtPosition(x, y)

    if (targetElement) {
      // For subflow elements, auto-populate inputs from parent's outputs
      if (elementType === "subflow" && targetElement.properties?.outputs) {
        const parentOutputs = targetElement.properties.outputs
        if (parentOutputs && parentOutputs.length > 0) {
          elementData.properties = elementData.properties || {}
          elementData.properties.inputs = parentOutputs.map(output => ({ value: output.value }))
        }
      }

      this.canvas.addElementRelativeTo(elementData, targetElement, x, y)
      this.hasUnsavedChanges = true
      this._dispatchConfigurationChange()
      return
    }

    // When adding a subflow via double-click (no target element),
    // check if the last element is a Process element to auto-populate inputs
    // Only do this for double-click additions, not for drag-drop to empty space
    if (isDoubleClick && elementType === "subflow" && this.canvas.elements.length > 0) {
      const lastElement = this.canvas.elements[this.canvas.elements.length - 1]
      if (lastElement.type === "process") {
        // Auto-populate inputs from the last element's outputs
        if (lastElement.properties?.outputs) {
          const parentOutputs = lastElement.properties.outputs
          if (parentOutputs && parentOutputs.length > 0) {
            elementData.properties = elementData.properties || {}
            elementData.properties.inputs = parentOutputs.map(output => ({ value: output.value }))
          }
        }
      }
    }

    this.canvas.addElement(elementData)
    this.hasUnsavedChanges = true
    this._dispatchConfigurationChange()
  }

  _handleElementSelected(event) {
    const element = event.detail?.element || event.detail
    if (element && this.hasPropertySidebarTarget) {
      this._showPropertySidebar(element)
    }
    this._updateAlignmentToolbar()
  }

  _handleConnectionSelected(connection) {
    if (!connection || !this.hasPropertySidebarTarget) return

    this.propertySidebarTarget.classList.remove("hidden")
    this.propertySidebarTarget.classList.add("flex", "flex-col")

    const propertyEditor = this.application.getControllerForElementAndIdentifier(
      this.propertySidebarTarget,
      "property-editor"
    )

    if (propertyEditor) {
      propertyEditor.openConnectionEditor(connection, this.canvas)
    }
  }

  _handleCanvasClick() {
    if (this.hasPropertySidebarTarget) {
      this._hidePropertySidebar()
    }
    this._updateAlignmentToolbar()
  }

  // ===================
  // Property Sidebar
  // ===================

  _showPropertySidebar(element, nav = undefined) {
    if (!this.hasPropertySidebarTarget) return

    this.propertySidebarTarget.classList.remove("hidden")
    this.propertySidebarTarget.classList.add("flex", "flex-col")

    const propertyEditor = this.application.getControllerForElementAndIdentifier(
      this.propertySidebarTarget,
      "property-editor"
    )

    if (propertyEditor) {
      propertyEditor.openEditor(element, this.canvas, nav)
    }
  }

  _hidePropertySidebar() {
    if (!this.hasPropertySidebarTarget) return

    const propertyEditor = this.application.getControllerForElementAndIdentifier(
      this.propertySidebarTarget,
      "property-editor"
    )

    if (propertyEditor) {
      propertyEditor.close()
    } else {
      this.propertySidebarTarget.classList.add("hidden")
      this.propertySidebarTarget.classList.remove("flex", "flex-col")
    }
  }

  // ===================
  // Subflow preview mode
  // ===================

  _enterPreviewMode() {
    if (this.canvas.previewMode) return
    this._collapsedPreviewConfiguration = structuredClone(this.canvas.getConfiguration())
    this.canvas.previewMode = true
    this._syncPreviewChrome()
  }

  _leavePreviewMode({ restore = false } = {}) {
    const stored = this._collapsedPreviewConfiguration
    const wasPreview = !!this.canvas?.previewMode
    this._collapsedPreviewConfiguration = null
    if (this.canvas) this.canvas.previewMode = false
    if (this.subflowManager) this.subflowManager.expandedSubflows = {}
    if (restore && stored && this.canvas?.restoreGraph) this.canvas.restoreGraph(stored)
    if (wasPreview || restore) this._syncPreviewChrome()
  }

  _previewAwareConfiguration() {
    if (this.canvas?.previewMode && this._collapsedPreviewConfiguration) {
      return this._collapsedPreviewConfiguration
    }
    return this.canvas.getConfiguration()
  }

  _canvasForValidation() {
    if (!this.canvas?.previewMode || !this._collapsedPreviewConfiguration) return this.canvas
    const { elements, connections } = this._collapsedPreviewConfiguration
    const live = this.canvas
    return {
      elements,
      connections,
      iterateElements(cb) { for (const el of elements) cb(el) },
      getElementPins(id) { return live.getElementPins?.(id) || { inputs: [], outputs: [] } }
    }
  }

  _syncPreviewChrome() {
    if (this.hasPreviewNoticeTarget) {
      this.previewNoticeTarget.classList.toggle("hidden", !this.canvas?.previewMode)
    }
    const canMutate = this.canvas?.canMutate?.() !== false
    if (!canMutate) {
      this.canvas?._hideConnectionHandles?.()
      this.canvas?._hideConnectionEndpointHandles?.()
      this.canvas?.hideResizeHandles?.()
    }
    this.canvas?.elementLayer?.querySelectorAll("[data-element-id]").forEach((group) => {
      group.style.cursor = canMutate ? "move" : "pointer"
    })
    this._updateAlignmentToolbar()
    this.canvas?._removeEdgeInsertButton?.()
    if (this.hasValidationListTarget && this._validationProblems) {
      this._renderValidationList()
    }
    this.element?.dispatchEvent?.(new CustomEvent("flowchartMutabilityChanged", {
      detail: { canMutate },
      bubbles: true
    }))
    if (!this.hasPropertySidebarTarget) return
    const propertyEditor = this.application?.getControllerForElementAndIdentifier?.(
      this.propertySidebarTarget,
      "property-editor"
    )
    propertyEditor?._applyReadOnlyState?.()
  }

  // ===================
  // Save Operations
  // ===================

  save() {
    if (this.readOnlyValue) return Promise.resolve(false)
    return this._saveToServer()
  }

  async _saveToServer() {
    if (!this.idValue || !this.customerIdValue) return false
    // Ignore re-entrant clicks while a save is already in flight. Without this
    // guard, double-clicking Save fires two PATCHes and two version snapshots,
    // and each other's post-save canvas restore clobbers the other's state.
    if (this._saveInFlight) return false
    this._saveInFlight = true

    try {
      const configToSave = this._buildSaveConfiguration()

      // Any change-event that fires between here and the save response
      // completing is a genuine in-flight edit; we must not clobber it.
      this._editsSinceSaveStart = false
      const editsSinceStart = () => this._editsSinceSaveStart

      const updateUrl = flowchartUrl(this, "update")
      if (!updateUrl) return false

      const response = await fetch(updateUrl, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": getCSRFToken(),
          "Accept": "application/json"
        },
        body: JSON.stringify({
          flowchart: { configuration: JSON.stringify(configToSave) },
          expected_head_version_id: this.headVersionIdValue,
          expected_head_revision: this.headRevisionValue,
          ...(this.hasBasedOnVersionIdValue && this.basedOnVersionIdValue
              ? { based_on_version_id: this.basedOnVersionIdValue } : {})
        })
      })

      if (response.ok) {
        const data = await response.json()
        this._adoptHeadVersion(data.version_id, data.head_revision)
        this._hideSaveConflict()
        // Only clear the unsaved-changes flag if nothing changed during the
        // round-trip. Otherwise, what the user sees on screen is newer than
        // what we just persisted and it is still unsaved.
        if (!editsSinceStart()) {
          this.hasUnsavedChanges = false
          this._updateUnsavedIndicator()
        }
        // Clear redo stack after successful save, and notify the toolbar so the
        // Redo button disables — otherwise it stays enabled but does nothing.
        this.undoRedoManager.redoStack = []
        this.undoRedoManager._persistToStorage()
        this.undoRedoManager._dispatchUndoRedoUpdate()
        this._dispatchSaveSuccess(data)
        return true
      }

      // Proxies and crashes answer with HTML; only a JSON body carries messages.
      const isJson = (response.headers.get("content-type") || "").includes("json")
      const data = isJson ? await response.json() : null
      if (response.status === 409 && data) {
        this._showSaveConflict(data)
        this._dispatchSaveError({ ...data, errors: [data.message] })
        return false
      }
      const errors = data?.errors || [data?.message || this.saveFailedHttpFormatValue.replace("{status}", response.status)]
      this._dispatchSaveError({ ...data, errors })
      return false
    } catch (error) {
      this._dispatchSaveError({ errors: [this.networkErrorFormatValue.replace("{message}", error.message)] })
    } finally {
      this._saveInFlight = false
    }
    return false
  }

  // After a save or restore: the server's new line head becomes the expected
  // head, and in version-edit mode also the lineage parent of the next save.
  _adoptHeadVersion(versionId, revision) {
    if (versionId == null) return
    this.headVersionIdValue = String(versionId)
    this.headRevisionValue = String(revision ?? "")
    if (this.hasBasedOnVersionIdValue && this.basedOnVersionIdValue) {
      this.basedOnVersionIdValue = String(versionId)
    }
  }

  // ===================
  // Save Conflict Banner
  // ===================

  _showSaveConflict(data) {
    this._conflictHeadVersionId = data.head_version_id
    this._conflictHeadRevision = data.head_revision
    if (!this.hasSaveConflictBannerTarget) return
    if (data.message && this.hasSaveConflictMessageTarget) {
      this.saveConflictMessageTarget.textContent = data.message
    }
    this.saveConflictBannerTarget.classList.remove("hidden")
  }

  _hideSaveConflict() {
    if (this.hasSaveConflictBannerTarget) this.saveConflictBannerTarget.classList.add("hidden")
  }

  reloadAfterConflict() {
    this.hasUnsavedChanges = false
    window.location.reload()
  }

  overwriteAfterConflict() {
    this._hideSaveConflict()
    this.headVersionIdValue = String(this._conflictHeadVersionId ?? "")
    this.headRevisionValue = String(this._conflictHeadRevision ?? "")
    return this.save()
  }

  /**
   * Persist the collapsed graph. While a subflow is expanded the live canvas
   * is a read-only preview, so save uses the configuration stored on first expand.
   */
  _buildSaveConfiguration() {
    return this._previewAwareConfiguration()
  }

  clear() {
    this._leavePreviewMode({ restore: true })
    if (this.canvas?.canMutate ? !this.canvas.canMutate() : this.readOnlyValue) return

    if (confirm(this.clearFlowchartConfirmValue)) {
      this.canvas.clear()
      this.hasUnsavedChanges = true
      this.undoRedoManager.commitPendingState()
      // canvas.clear() resets zoom and empties the elements without firing the
      // zoom/minimap hooks, so refresh both or they show stale ghost boxes and
      // an out-of-date zoom percentage.
      this._updateZoomDisplay()
      if (this.minimapManager) this.minimapManager.update()
      this._dispatchConfigurationChange()
    }
  }

  // ===================
  // Event Dispatching
  // ===================

  _dispatchConfigurationChange() {
    this.element.dispatchEvent(new CustomEvent("flowchartChanged", {
      detail: {
        configuration: this.canvas.getConfiguration(),
        hasUnsavedChanges: this.hasUnsavedChanges
      },
      bubbles: true
    }))
  }

  _dispatchSaveSuccess(data) {
    this.element.dispatchEvent(new CustomEvent("flowchartSaved", {
      detail: { ...data, hasUnsavedChanges: this.hasUnsavedChanges },
      bubbles: true
    }))
  }

  _dispatchSaveError(error) {
    this.element.dispatchEvent(new CustomEvent("flowchartSaveError", {
      detail: error,
      bubbles: true
    }))
  }

  // ===================
  // Export
  // ===================

  exportSVG() {
    if (this.exportManager) {
      this.exportManager.exportSVG()
    }
  }

  exportPNG() {
    if (this.exportManager) {
      this.exportManager.exportPNG()
    }
  }

  // ===================
  // Documentation
  // ===================

  async generateDocs() {
    try {
      const documentUrl = flowchartUrl(this, "document")
      if (!documentUrl) throw new Error("Missing document URL")

      const response = await fetch(documentUrl, {
        method: "GET",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": getCSRFToken()
        }
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const data = await response.json()

      // Create a Blob from the markdown content
      const blob = new Blob([data.markdown], { type: "text/markdown" })
      const url = URL.createObjectURL(blob)

      // Create a temporary download link
      const link = document.createElement("a")
      link.href = url
      link.download = data.filename
      document.body.appendChild(link)
      link.click()

      // Cleanup
      document.body.removeChild(link)
      URL.revokeObjectURL(url)
    } catch (error) {
      console.error("Failed to generate documentation:", error)
      alert(this.generateDocsFailedLabelValue)
    }
  }

  // ===================
  // Properties
  // ===================

  get currentConfiguration() {
    return this.canvas ? this.canvas.getConfiguration() : null
  }
}

Object.assign(FlowchartCanvasController.prototype, ValidationMixin)
Object.assign(FlowchartCanvasController.prototype, VersionHistoryMixin)
Object.assign(FlowchartCanvasController.prototype, SearchMixin)
Object.assign(FlowchartCanvasController.prototype, BottomPanelMixin)
