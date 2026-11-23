// Shared fakes for flowchart_canvas mixin/manager unit tests.
//
// The real FlowchartCanvasController wires a live SVG canvas engine. The mixins
// and managers under test only manipulate DATA (element/connection arrays,
// serialized state) and light DOM structure, so we hand them a minimal fake
// canvas + controller that record calls. Geometry (getBoundingClientRect,
// pointer coords, fitToContent measurement) is NOT faked — those paths are
// Tier C / Playwright, per the guide.
import { vi } from "vitest"

// A fake canvas engine. `elementLayer` is a real (SVG-ish) container so
// data-element-id groups can be queried/removed like the real engine does.
export function makeCanvas(overrides = {}) {
  const elementLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
  const connectionLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
  document.body.appendChild(elementLayer)
  document.body.appendChild(connectionLayer)

  const canvas = {
    elements: [],
    connections: [],
    selectedElements: [],
    elementLayer,
    connectionLayer,
    // renderElement mirrors the engine by dropping a <g data-element-id> so that
    // querySelector([data-element-id]) works for fold-icon / removal logic.
    renderElement: vi.fn((el) => {
      const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
      g.setAttribute("data-element-id", el.id)
      elementLayer.appendChild(g)
      return g
    }),
    updateConnections: vi.fn(),
    updateElementPosition: vi.fn(),
    loadConfiguration: vi.fn(),
    restoreGraph: vi.fn(),
    onToast: vi.fn(),
    _getSubTreeElements: vi.fn(() => []),
    _setElementSelected: vi.fn(),
    showConnectionHandles: vi.fn(),
    clearValidationStates: vi.fn(),
    setValidationState: vi.fn(),
    zoomPanManager: { fitToContent: vi.fn() },
    previewMode: false,
    isReadOnly: false,
    canMutate() { return !this.isReadOnly && !this.previewMode },
    getConfiguration: vi.fn(function () {
      return { elements: this.elements, connections: this.connections }
    }),
    _removeEdgeInsertButton: vi.fn(),
    ...overrides,
  }
  return canvas
}

// Mirrors the English `default:` values declared on flowchart_canvas_controller.js's
// `static values` block (the i18n seam: production overrides these via
// data-flowchart-canvas-<name>-value="<%= t(...) %>", tests get the same English
// text a real Stimulus-mounted controller would fall back to). Keep in sync
// with app/javascript/controllers/flowchart_canvas_controller.js.
export const I18N_VALUE_DEFAULTS = {
  actionCatalogValue: {},

  appLocaleValue: "en",

  // BottomPanelMixin
  unnamedElementLabelValue: "(unnamed)",
  elementConnectionsFormatValue: "{incoming} in / {outgoing} out",

  // SearchMixin
  searchCountZeroValue: "0 of 0",
  searchCountFormatValue: "{current} of {total}",

  // ValidationMixin
  validationSummaryFormatValue: "{errors} errors, {warnings} warnings",
  noProblemsFoundLabelValue: "No problems found",
  filterAllLabelValue: "All",
  filterErrorsLabelValue: "Errors",
  filterWarningsLabelValue: "Warnings",
  noProblemsMatchFilterLabelValue: "No problems match this filter",
  problemNotTiedNoticeValue: "This problem isn't tied to a specific element — fix it on the canvas",
  serverCheckUnavailableMsgValue: "Server-side checks (subflow validity, code generation) could not run — showing local results only",

  // ValidationMixin -> flowchart/validation_service.js
  validationMissingStartMsgValue: "Flowchart must have a Start element",
  validationDuplicateStartMsgValue: "Only one Start element is allowed",
  validationMissingEndMsgValue: "Flowchart should have at least one End element",
  validationOrphanStartFormatValue: 'Start element "{label}" has no outgoing connections',
  validationOrphanEndFormatValue: 'End element "{label}" has no incoming connections',
  validationOrphanElementFormatValue: '"{label}" is not connected to any other element',
  validationUnreachableFormatValue: '"{label}" is not reachable from Start',
  validationDuplicateLabelFormatValue: '{count} elements share the label "{label}" — generated step names derive from labels, so duplicates are renamed unpredictably',
  validationElementProblemFormatValue: "{label} ({type}): {message}",
  validationEmptyProcessValue: "Add at least one step",
  validationTooFewBranchesValue: "Decision requires at least two outgoing connections",
  validationDuplicateMatchValueValue: "Match values must be unique",
  validationMultipleOtherwiseValue: "Only one Otherwise branch is allowed",
  validationInvalidConditionMatchValue: "Condition branches must match Yes (true), No (false), or Otherwise",
  validationMissingYesBranchValue: "Condition routing needs a Yes branch and either No or Otherwise",
  validationEmptyLoopConditionValue: "Add at least one condition",
  validationMissingCollectionValue: "Collection is required",
  validationMissingReturnValueValue: "Return Value is required",
  validationMissingFlowchartValue: "Flowchart is required",
  validationSubflowSelfReferenceValue: "Flowchart cannot target itself",
  validationInvalidCollectionPathValue: "collection must be a valid identifier path",
  validationReservedLoopVariableValue: "{field} cannot be {name} because that name is reserved for the loop header",
  validationCollidingLoopVariablesValue: "itemVariable and indexVariable must be different",
  validationConditionErrorsValue: {},
  validationDanglingConnectionFromFormatValue: "Connection references missing element (from: {id})",
  validationDanglingConnectionToFormatValue: "Connection references missing element (to: {id})",
  validationSelfConnectionMsgValue: "Element cannot connect to itself",
  validationDuplicateConnectionMsgValue: "Duplicate connection between elements",
  validationCycleMsgValue: "Cycle detected in flowchart",
  validationUnsupportedStructuralFormatValue: 'Element "{label}" uses unsupported structural type "{type}"',

  // ValidationMixin -> flowchart/input_output_validation_service.js
  validationMissingInputFormatValue: 'Input "{key}" has no upstream output',

  // ValidationMixin -> flowchart/validation_navigation.js fixHint overrides
  fixHintDeleteExtraStartValue: "Delete the extra Start element",
  fixHintRenameUniqueLabelValue: "Rename this element to a unique label",
  fixHintAddOneStepValue: "Add at least one step",
  fixHintFixStepConfigValue: "Fix this step's configuration",
  fixHintFixElementConfigValue: "Fix this element's configuration",
  fixHintSetRequiredCountPositiveValue: "Set Required Count to a positive whole number",
  fixHintLowerRequiredCountValue: "Lower Required Count to at most the incoming branch count",
  fixHintSpecifyCollectionValue: "Specify the collection to iterate",
  fixHintDefineLoopConditionValue: "Define the loop condition",
  fixHintSelectTargetFlowchartValue: "Select a target flowchart",
  fixHintSelectAccessibleFlowchartValue: "Select a flowchart that belongs to this customer or is shared",
  fixHintRemoveCircularSubflowValue: "Remove the circular subflow reference",
  fixHintProvideReturnValueValue: "Provide the Return Value expression",
  fixHintPickInputProducerValue: "Pick a producer for this input or add an upstream step that emits it",
  fixHintChangeStepOrElementTypeValue: "This step/element has no code generator — change the action or element type",
  fixHintRepointSubflowValue: "Point this Subflow at a different flowchart",

  // ValidationMixin -> flowchart/validation_autofix.js button captions
  autoFixAllLabelFormatValue: "Fix all ({count})",
  autoFixAppliedFormatValue: "Applied {count} fixes",
  autoFixNothingToDoNoticeValue: "Nothing left to fix automatically",
  autoFixDeleteExtraStartValue: "Delete this Start",
  autoFixRenameUniqueValue: "Rename uniquely",
  autoFixRemoveConnectionValue: "Remove connection",
  autoFixSetRequiredCountFormatValue: "Set to {count}",
  autoFixSetIterationCapFormatValue: "Cap at {value}",
  autoFixAddEndValue: "Add an End element",
  autoFixConnectToEndValue: "Connect from the last step",
  autoFixSetReturnValueFormatValue: "Use {value}",
  autoFixSetCollectionFormatValue: "Use {value}",
  autoFixClearSubflowTargetValue: "Clear the target",

  // VersionHistoryMixin
  versionsLoadFailedLabelValue: "Failed to load versions",
  networkErrorFormatValue: "Network error: {message}",
  versionCountSingularFormatValue: "{count} version",
  versionCountPluralFormatValue: "{count} versions",
  noVersionsSavedLabelValue: "No versions saved yet. Save the flowchart to create the first version.",
  noDescriptionFallbackValue: "No description",
  restoreButtonLabelValue: "Restore",
  versionLabelFormatValue: "v{number}",
  restoreVersionConfirmFormatValue: "Restore version {version}? This creates a new head version with its content; the current head stays in the version history.",
  restoreVersionFailedFormatValue: "Failed to restore version: {errors}",
  restoreFailedHttpFormatValue: "Restore failed (HTTP {status})",

  // Save path (_saveToServer / Ctrl+S)
  saveFailedHttpFormatValue: "Save failed (HTTP {status})",
  readOnlySaveToastValue: "Cannot save a launched flowchart. Take it offline first.",

  // FlowchartCanvasController (clear / generateDocs)
  clearFlowchartConfirmValue: "Are you sure you want to clear the entire flowchart?",
  generateDocsFailedLabelValue: "Failed to generate documentation. Please try again.",
  subflowSelfReferenceToastValue: "Cannot expand: subflow references this flowchart (self-reference).",

  // flowchart/connection_manager.js (threaded onto canvas.labels)
  connectionLabelPlaceholderValue: "Label...",

  // flowchart/canvas/element_management.js, canvas/external_drop.js,
  // canvas/serialization.js (threaded onto canvas.labels)
  onlyOneStartAllowedToastValue: "Only one Start element allowed per flowchart",
  loadConfigFailedToastValue: "Failed to load flowchart configuration. Please reload the page.",
  elementDefaultLabelsValue: {
    start: "Start", end: "End", process: "Process", decision: "Decision",
    loop: "Loop", subflow: "Subflow",
  },
  uniqueLabelFormatValue: "{label} {n}",

  // flowchart/test_runner_manager.js (reads via this.controller.xValue)
  testRunningLabelValue: "Running...",
  testInvalidJsonInputFormatValue: "Invalid JSON input: {message}",
  testInvalidJsonFormatValue: "Invalid JSON: {message}",
  testSaveFailedLabelValue: "Save failed — run aborted; fix validation/save errors first",
  testServerErrorFormatValue: "Server error ({status})",
  testClientTimeoutFormatValue: "Request timed out after {seconds} seconds — the server did not respond",
  testHistoryViewTitleValue: "View this run's results",
  testHistoryUseInputTitleValue: "Copy this run's input back into the editor",
  testUseInputLabelValue: "use input",
  testTimedOutLabelValue: "Timed out",
  testSuccessFormatValue: "Success ({signal})",
  testCompletedFallbackValue: "completed",
  testExecutionFailedLabelValue: "Execution failed",
  testContextLabelValue: "Context:",
  testTraceOutputLabelValue: "Trace Output",
  testDefaultTimeoutBannerValue: "Timed out after 10 seconds — execution aborted",
  testExecutionSucceededLabelValue: "Execution succeeded",
  testNoTracedStepsLabelValue: "Run completed without traced steps",
  testContextNotCapturedLabelValue: "context not captured",
  testContextToggleLabelValue: "context",
  testStepsLabelValue: "Steps:",
  testUnnamedStepFallbackValue: "(unnamed step)",
  testNoQueriesLabelValue: "No SQL queries executed",
  testQuerySummarySingularFormatValue: "{count} query · {duration} ms total",
  testQuerySummaryPluralFormatValue: "{count} queries · {duration} ms total",
  testQueryDurationFormatValue: "{duration} ms",
  testSqlQueriesLabelFormatValue: "SQL Queries — {summary}",
  testErrorLabelValue: "Error",
  testDecisionBranchFormatValue: "{step} → {branch}",
  testTraceTruncatedFormatValue: "Showing the first {count} steps; the run had more.",
}

export function makeController(canvas, overrides = {}) {
  const element = document.createElement("div")
  document.body.appendChild(element)
  return {
    ...I18N_VALUE_DEFAULTS,
    canvas,
    element,
    idValue: "root-fc",
    customerIdValue: "cust-1",
    hasUnsavedChanges: false,
    _editsSinceSaveStart: false,
    _dispatchConfigurationChange: vi.fn(),
    _updateUnsavedIndicator: vi.fn(),
    _collapsedPreviewConfiguration: null,
    _enterPreviewMode() {
      if (this.canvas.previewMode) return
      this._collapsedPreviewConfiguration = this.canvas.getConfiguration?.()
        ?? { elements: this.canvas.elements, connections: this.canvas.connections }
      this.canvas.previewMode = true
      this._syncPreviewChrome?.()
    },
    _leavePreviewMode({ restore = false } = {}) {
      const stored = this._collapsedPreviewConfiguration
      this._collapsedPreviewConfiguration = null
      if (this.canvas) this.canvas.previewMode = false
      if (restore && stored) this.canvas?.restoreGraph(stored)
      this._syncPreviewChrome?.()
    },
    _previewAwareConfiguration() {
      if (this.canvas.previewMode && this._collapsedPreviewConfiguration) {
        return this._collapsedPreviewConfiguration
      }
      return this.canvas.getConfiguration?.()
        ?? { elements: this.canvas.elements, connections: this.canvas.connections }
    },
    _canvasForValidation() {
      if (!this.canvas.previewMode || !this._collapsedPreviewConfiguration) return this.canvas
      const { elements, connections } = this._collapsedPreviewConfiguration
      const live = this.canvas
      return {
        elements,
        connections,
        iterateElements(cb) { for (const el of elements) cb(el) },
        getElementPins(id) { return live.getElementPins?.(id) || { inputs: [], outputs: [] } }
      }
    },
    _syncPreviewChrome: vi.fn(),
    ...overrides,
  }
}

// Attach a mixin (or several) onto a bare host object so its methods can be
// invoked with `this` bound to the host. Extra props (targets, stubs) merge in.
// Seeded with I18N_VALUE_DEFAULTS first so `this.xxxValue` reads inside the
// mixin resolve to the same English default a real Stimulus-mounted
// controller would fall back to; `props` can still override any of them.
export function mixinHost(mixins, props = {}) {
  const host = { ...I18N_VALUE_DEFAULTS }
  for (const m of [].concat(mixins)) Object.assign(host, m)
  return Object.assign(host, props)
}
