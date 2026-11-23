import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"

// Mock the heavy collaborator modules so the controller's LIFECYCLE (connect,
// _initializeCanvas, _setupCanvasCallbacks, _onCanvasReady, disconnect) can be
// exercised without constructing the real geometry engine or hitting the network.
// The data-level tests below still use plain fake `this` objects and are unaffected.
const mocks = vi.hoisted(() => ({
  refreshElementPins: vi.fn(() => Promise.resolve()),
  primeAllElementPins: vi.fn(() => Promise.resolve()),
}))
const { refreshElementPins, primeAllElementPins } = mocks
vi.mock("flowchart/canvas", () => ({
  FlowchartCanvas: vi.fn(function () { this.destroy = vi.fn(); this.loadConfiguration = vi.fn() }),
}))
vi.mock("flowchart/export_manager", () => ({ ExportManager: vi.fn(() => ({ exportSVG: vi.fn(), exportPNG: vi.fn() })) }))
vi.mock("flowchart/search_manager", () => ({ SearchManager: vi.fn(() => ({})) }))
vi.mock("flowchart/minimap_manager", () => ({ MinimapManager: vi.fn(() => ({ update: vi.fn(), _updateViewport: vi.fn() })) }))
vi.mock("flowchart/test_runner_manager", () => ({ TestRunnerManager: vi.fn(() => ({ restoreSavedInput: vi.fn(), validateInput: vi.fn() })) }))
vi.mock("controllers/flowchart_canvas/undo_redo_manager", () => ({
  UndoRedoManager: vi.fn(() => ({ saveInitialState: vi.fn() })),
}))
vi.mock("controllers/flowchart_canvas/subflow_manager", () => ({
  SubflowManager: vi.fn(() => ({ restoreExpandedSubflowsFromConfiguration: vi.fn(), expandedSubflows: {} })),
}))
// Dynamic imports inside _initializeCanvas — mock so the lazy prime/refresh calls resolve.
vi.mock("controllers/property_editor/step_io/io_params_client", () => ({ primeAllStepPins: vi.fn(() => Promise.resolve()) }))
vi.mock("controllers/property_editor/element_io/io_params_client", () => ({
  refreshElementPins: mocks.refreshElementPins, primeAllElementPins: mocks.primeAllElementPins,
}))
vi.mock("controllers/property_editor/element_io/override_validator", () => ({ validateOverrides: vi.fn() }))

import Controller from "controllers/flowchart_canvas_controller"
import { I18N_VALUE_DEFAULTS } from "../support/flowchart.js"
import { getActionConfig } from "flowchart/constants/action_registry"
import { installSampleActionCatalog } from "../support/action_catalog.js"

const flush = () => new Promise((r) => setTimeout(r, 0))

// NOTE: FlowchartCanvasController orchestrates a live SVG canvas engine
// (FlowchartCanvas) whose core paths depend on real layout — getBoundingClientRect,
// pointer coords, fitToContent measurement, requestAnimationFrame-driven ready
// state. Those are Playwright-covered (spec/e2e), NOT unit-testable in happy-dom.
// Here we exercise the controller's pure/data + DOM-structural methods by invoking
// them against a minimal fake `this` (the same technique the mixin specs use),
// which avoids constructing the geometry engine.

// A fake canvas engine recording the data-level calls these methods make.
function makeCanvas(overrides = {}) {
  return {
    elements: [],
    connections: [],
    selectedElements: [],
    getConfiguration: vi.fn(() => ({ elements: [{ id: "a", x: 1, y: 2 }], connections: [] })),
    addElement: vi.fn(),
    addElementRelativeTo: vi.fn(),
    getElementAtPosition: vi.fn(() => null),
    zoomPanManager: { zoomIn: vi.fn(), zoomOut: vi.fn(), fitToContent: vi.fn(), zoomPercent: 125 },
    clear: vi.fn(),
    restoreGraph: vi.fn(),
    _removeEdgeInsertButton: vi.fn(),
    previewMode: false,
    ...overrides,
  }
}

// Minimal controller stub: Stimulus getters (hasXTarget / xTarget / xValue) are
// just plain props here. Only the members a given method reads need to be present.
function stub(overrides = {}) {
  const element = document.createElement("div")
  document.body.appendChild(element)
  const canvas = overrides.canvas || makeCanvas()
  return {
    ...I18N_VALUE_DEFAULTS,
    element,
    canvas,
    readOnlyValue: false,
    idValue: 7,
    customerIdValue: 42,
    hasUnsavedChanges: false,
    undoRedoManager: {
      undo: vi.fn(() => true), redo: vi.fn(() => true),
      redoStack: [], _persistToStorage: vi.fn(), _dispatchUndoRedoUpdate: vi.fn(),
      commitPendingState: vi.fn(),
    },
    subflowManager: {
      expandedSubflows: {},
      captureCompleteCanvasState: vi.fn(() => ({})),
      restoreCompleteCanvasState: vi.fn(),
    },
    minimapManager: { update: vi.fn(), _updateViewport: vi.fn() },
    hasPropertySidebarTarget: false,
    hasAlignmentToolbarTarget: false,
    hasUnsavedIndicatorTarget: false,
    hasMinimapContainerTarget: false,
    hasBasedOnVersionIdValue: false,
    urlsValue: {
      update: "/tenant/flowcharts/99",
      document: "/tenant/flowcharts/99/document",
      versions: "/tenant/flowcharts/99/versions"
    },
    unsavedChangesConfirmValue: "You have unsaved changes. Leave this page?",
    expandSubflowTitleValue: "Expand sub-flow",
    collapseSubflowTitleValue: "Collapse sub-flow",
    connectionIntoStartRejectedValue: "A Start element cannot have incoming connections",
    connectionOutOfEndRejectedValue: "An End element cannot have outgoing connections",
    branchFallbackNameFormatValue: "Branch {index}",
    _dispatchConfigurationChange: Controller.prototype._dispatchConfigurationChange,
    _dispatchSaveSuccess: Controller.prototype._dispatchSaveSuccess,
    _dispatchSaveError: Controller.prototype._dispatchSaveError,
    _buildSaveConfiguration: Controller.prototype._buildSaveConfiguration,
    _adoptHeadVersion: Controller.prototype._adoptHeadVersion,
    _showSaveConflict: Controller.prototype._showSaveConflict,
    _hideSaveConflict: Controller.prototype._hideSaveConflict,
    headVersionIdValue: "",
    headRevisionValue: "",
    hasSaveConflictBannerTarget: false,
    hasSaveConflictMessageTarget: false,
    _updateZoomDisplay: vi.fn(),
    _updateUnsavedIndicator: vi.fn(),
    _discardOpenPropertyEditor: vi.fn(),
    _updateAlignmentToolbar: vi.fn(),
    _collapsedPreviewConfiguration: null,
    _enterPreviewMode: Controller.prototype._enterPreviewMode,
    _leavePreviewMode: Controller.prototype._leavePreviewMode,
    _previewAwareConfiguration: Controller.prototype._previewAwareConfiguration,
    _canvasForValidation: Controller.prototype._canvasForValidation,
    _syncPreviewChrome: Controller.prototype._syncPreviewChrome,
    hasPreviewNoticeTarget: false,
    hasValidationListTarget: false,
    ...overrides,
  }
}

// Invoke a prototype method with a given `this`.
const call = (name, self, ...args) => Controller.prototype[name].call(self, ...args)
const jsonHeaders = { get: () => "application/json; charset=utf-8" }
const htmlHeaders = { get: () => "text/html" }

afterEach(() => { document.body.innerHTML = ""; vi.unstubAllGlobals() })

describe("FlowchartCanvasController — read-only guards", () => {
  it("undo/redo return false and never touch the undo manager", () => {
    const self = stub({ readOnlyValue: true })
    expect(call("undo", self)).toBe(false)
    expect(call("redo", self)).toBe(false)
    expect(self.undoRedoManager.undo).not.toHaveBeenCalled()
  })

  it("save resolves to false without hitting the network", async () => {
    const self = stub({ readOnlyValue: true })
    await expect(call("save", self)).resolves.toBe(false)
  })

  it("clear and autoLayout / cycleConnectionRouting are no-ops", () => {
    const self = stub({ readOnlyValue: true })
    const confirmSpy = vi.fn(); vi.stubGlobal("confirm", confirmSpy)
    call("clear", self)
    call("autoLayout", self)
    call("cycleConnectionRouting", self)
    expect(confirmSpy).not.toHaveBeenCalled()
    expect(self.canvas.clear).not.toHaveBeenCalled()
  })

  it("_handleElementDrop ignores drops", () => {
    const self = stub({ readOnlyValue: true })
    call("_handleElementDrop", self, { detail: { elementType: "process", x: 0, y: 0 } })
    expect(self.canvas.addElement).not.toHaveBeenCalled()
  })
})

describe("FlowchartCanvasController — undo/redo delegation", () => {
  it("undo discards the open editor, delegates and refreshes the minimap", () => {
    const self = stub()
    const result = call("undo", self)
    expect(result).toBe(true)
    expect(self._discardOpenPropertyEditor).toHaveBeenCalled()
    expect(self.undoRedoManager.undo).toHaveBeenCalled()
    expect(self.minimapManager.update).toHaveBeenCalled()
  })

  it("redo discards the open editor, delegates and refreshes the minimap", () => {
    const self = stub()
    const result = call("redo", self)
    expect(result).toBe(true)
    expect(self._discardOpenPropertyEditor).toHaveBeenCalled()
    expect(self.undoRedoManager.redo).toHaveBeenCalled()
    expect(self.minimapManager.update).toHaveBeenCalled()
  })

  it("redo skips the minimap refresh when the manager returns falsy", () => {
    const self = stub({ undoRedoManager: { redo: vi.fn(() => false), undo: vi.fn() } })
    self._discardOpenPropertyEditor = vi.fn()
    expect(call("redo", self)).toBe(false)
    expect(self.minimapManager.update).not.toHaveBeenCalled()
  })

  it("canUndo / canRedo proxy the manager", () => {
    const self = stub({ undoRedoManager: { canUndo: true, canRedo: false } })
    const gUndo = Object.getOwnPropertyDescriptor(Controller.prototype, "canUndo").get
    const gRedo = Object.getOwnPropertyDescriptor(Controller.prototype, "canRedo").get
    expect(gUndo.call(self)).toBe(true)
    expect(gRedo.call(self)).toBe(false)
  })
})

describe("FlowchartCanvasController — zoom delegation", () => {
  it("zoomIn/zoomOut/fitToContent drive the zoomPanManager + minimap + display", () => {
    const self = stub()
    call("zoomIn", self)
    call("zoomOut", self)
    call("fitToContent", self)
    expect(self.canvas.zoomPanManager.zoomIn).toHaveBeenCalled()
    expect(self.canvas.zoomPanManager.zoomOut).toHaveBeenCalled()
    expect(self.canvas.zoomPanManager.fitToContent).toHaveBeenCalledWith(self.canvas.elements)
    expect(self._updateZoomDisplay).toHaveBeenCalledTimes(3)
    expect(self.minimapManager._updateViewport).toHaveBeenCalledTimes(3)
  })

  it("_updateZoomDisplay dispatches a zoomChanged event with the percent", () => {
    const self = stub()
    const seen = []
    self.element.addEventListener("zoomChanged", (e) => seen.push(e.detail.percent))
    call("_updateZoomDisplay", self)
    expect(seen).toEqual([125])
  })
})

describe("FlowchartCanvasController — indicator & alignment toolbar", () => {
  it("_updateUnsavedIndicator toggles the hidden class from hasUnsavedChanges", () => {
    const indicator = document.createElement("div")
    const self = stub({ hasUnsavedIndicatorTarget: true, unsavedIndicatorTarget: indicator, hasUnsavedChanges: true })
    self._updateUnsavedIndicator = Controller.prototype._updateUnsavedIndicator
    call("_updateUnsavedIndicator", self)
    expect(indicator.classList.contains("hidden")).toBe(false)
    self.hasUnsavedChanges = false
    call("_updateUnsavedIndicator", self)
    expect(indicator.classList.contains("hidden")).toBe(true)
  })

  it("_updateAlignmentToolbar shows the bar for 2+ and distribute controls for 3+", () => {
    const bar = document.createElement("div"); bar.classList.add("hidden")
    const sep = document.createElement("div"), h = document.createElement("div"), v = document.createElement("div")
    const self = stub({
      canvas: makeCanvas({ selectedElements: [{}, {}] }),
      hasAlignmentToolbarTarget: true, alignmentToolbarTarget: bar,
      hasDistributeSeparatorTarget: true, distributeSeparatorTarget: sep,
      hasDistributeHBtnTarget: true, distributeHBtnTarget: h,
      hasDistributeVBtnTarget: true, distributeVBtnTarget: v,
    })
    self._updateAlignmentToolbar = Controller.prototype._updateAlignmentToolbar
    call("_updateAlignmentToolbar", self)
    expect(bar.classList.contains("hidden")).toBe(false)
    expect(sep.classList.contains("hidden")).toBe(true) // only 2 -> distribute hidden

    self.canvas.selectedElements = [{}, {}, {}]
    call("_updateAlignmentToolbar", self)
    expect(sep.classList.contains("hidden")).toBe(false) // 3 -> distribute shown

    self.canvas.selectedElements = [{}]
    call("_updateAlignmentToolbar", self)
    expect(bar.classList.contains("hidden")).toBe(true) // <2 -> hidden
  })

  it("_updateAlignmentToolbar is a no-op without the toolbar target", () => {
    const self = stub({ hasAlignmentToolbarTarget: false })
    self._updateAlignmentToolbar = Controller.prototype._updateAlignmentToolbar
    expect(() => call("_updateAlignmentToolbar", self)).not.toThrow()
  })

  it("_updateAlignmentToolbar shows the bar but leaves distribute controls when their targets are absent", () => {
    const bar = document.createElement("div"); bar.classList.add("hidden")
    const self = stub({
      canvas: makeCanvas({ selectedElements: [{}, {}, {}] }),
      hasAlignmentToolbarTarget: true, alignmentToolbarTarget: bar,
      hasDistributeSeparatorTarget: false, hasDistributeHBtnTarget: false, hasDistributeVBtnTarget: false,
    })
    self._updateAlignmentToolbar = Controller.prototype._updateAlignmentToolbar
    call("_updateAlignmentToolbar", self)
    expect(bar.classList.contains("hidden")).toBe(false)
  })
})

describe("FlowchartCanvasController — save delegation (writable)", () => {
  it("save delegates to _saveToServer when not read-only", () => {
    const self = stub()
    self._saveToServer = vi.fn(() => Promise.resolve(true))
    call("save", self)
    expect(self._saveToServer).toHaveBeenCalled()
  })
})

describe("FlowchartCanvasController — event dispatching", () => {
  it("_dispatchConfigurationChange emits flowchartChanged with config + dirty flag", () => {
    const self = stub({ hasUnsavedChanges: true })
    const seen = []
    self.element.addEventListener("flowchartChanged", (e) => seen.push(e.detail))
    call("_dispatchConfigurationChange", self)
    expect(seen[0].hasUnsavedChanges).toBe(true)
    expect(seen[0].configuration.elements[0].id).toBe("a")
  })

  it("_dispatchSaveSuccess / _dispatchSaveError emit their events", () => {
    const self = stub()
    const ok = [], err = []
    self.element.addEventListener("flowchartSaved", (e) => ok.push(e.detail))
    self.element.addEventListener("flowchartSaveError", (e) => err.push(e.detail))
    call("_dispatchSaveSuccess", self, { v: 1 })
    call("_dispatchSaveError", self, { errors: ["x"] })
    expect(ok).toEqual([{ v: 1, hasUnsavedChanges: false }])
    expect(err).toEqual([{ errors: ["x"] }])
  })

  it("currentConfiguration returns the canvas config, or null without a canvas", () => {
    const gc = Object.getOwnPropertyDescriptor(Controller.prototype, "currentConfiguration").get
    expect(gc.call(stub()).elements[0].id).toBe("a")
    expect(gc.call({ canvas: null })).toBeNull()
  })
})

describe("FlowchartCanvasController — element drop (writable)", () => {
  it("adds a plain element at empty space", () => {
    const self = stub()
    call("_handleElementDrop", self, { detail: { elementType: "process", x: 10, y: 20 } })
    expect(self.canvas.addElement).toHaveBeenCalledWith(expect.objectContaining({ type: "process", x: 10, y: 20 }))
    expect(self.hasUnsavedChanges).toBe(true)
  })

  it("adds relative to a drop target and maps custom element data", () => {
    const target = { id: "parent", properties: {} }
    const self = stub({ canvas: makeCanvas({ getElementAtPosition: vi.fn(() => target) }) })
    call("_handleElementDrop", self, {
      detail: { elementType: "subflow", x: 5, y: 5, customElementData: { name: "Sub", id: "ce1", flowchartId: "9" } },
    })
    expect(self.canvas.addElementRelativeTo).toHaveBeenCalledWith(
      expect.objectContaining({
        label: "Sub",
        customElementId: "ce1",
        properties: expect.objectContaining({ flowchartId: 9 }),
      }), target, 5, 5)
  })
})

describe("FlowchartCanvasController — _buildSaveConfiguration", () => {
  it("returns the live configuration when not previewing", () => {
    const self = stub()
    const cfg = call("_buildSaveConfiguration", self)
    expect(cfg.elements[0].id).toBe("a")
  })

  it("returns the stored collapsed configuration while previewing a subflow", () => {
    const stored = { elements: [{ id: "collapsed", x: 10, y: 20 }], connections: [{ id: "c1" }] }
    const canvas = makeCanvas({
      previewMode: true,
      getConfiguration: vi.fn(() => ({ elements: [{ id: "expanded" }], connections: [] })),
    })
    const self = stub({ canvas, _collapsedPreviewConfiguration: stored })
    expect(call("_buildSaveConfiguration", self)).toBe(stored)
    expect(canvas.getConfiguration).not.toHaveBeenCalled()
  })
})

describe("FlowchartCanvasController — _saveToServer", () => {
  it("returns false without an id or customer", async () => {
    const self = stub({ idValue: null })
    await expect(call("_saveToServer", self)).resolves.toBe(false)
  })

  it("returns false without an update URL", async () => {
    const self = stub({ urlsValue: {} })
    const fetchMock = vi.fn()
    vi.stubGlobal("fetch", fetchMock)
    await expect(call("_saveToServer", self)).resolves.toBe(false)
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it("PATCHes the config, clears dirty state and dispatches success", async () => {
    const self = stub()
    const saved = []
    self.element.addEventListener("flowchartSaved", (e) => saved.push(e.detail))
    const fetchMock = vi.fn(async () => ({ ok: true, json: async () => ({ version: 2 }) }))
    vi.stubGlobal("fetch", fetchMock)
    const ok = await call("_saveToServer", self)
    expect(ok).toBe(true)
    expect(fetchMock).toHaveBeenCalledWith(
      "/tenant/flowcharts/99",
      expect.objectContaining({ method: "PATCH" }))
    expect(self.hasUnsavedChanges).toBe(false)
    expect(saved).toEqual([{ version: 2, hasUnsavedChanges: false }])
  })

  it("dispatches a save error on a non-OK response", async () => {
    const self = stub()
    const errs = []
    self.element.addEventListener("flowchartSaveError", (e) => errs.push(e.detail))
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 422, headers: jsonHeaders, json: async () => ({ status: "error", errors: ["bad"] }) })))
    const ok = await call("_saveToServer", self)
    expect(ok).toBe(false)
    expect(errs).toEqual([{ status: "error", errors: ["bad"] }])
    expect(self._saveInFlight).toBe(false)
  })

  it("uses the JSON message when an error body has no errors array", async () => {
    const self = stub()
    const errs = []
    self.element.addEventListener("flowchartSaveError", (e) => errs.push(e.detail))
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 403, headers: jsonHeaders, json: async () => ({ message: "Denied" }) })))
    await call("_saveToServer", self)
    expect(errs).toEqual([{ message: "Denied", errors: ["Denied"] }])
  })

  it("falls back to the HTTP status for a JSON error body with neither errors nor message", async () => {
    const self = stub()
    const errs = []
    self.element.addEventListener("flowchartSaveError", (e) => errs.push(e.detail))
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 422, headers: jsonHeaders, json: async () => ({}) })))
    await call("_saveToServer", self)
    expect(errs[0].errors).toEqual(["Save failed (HTTP 422)"])
  })

  it("never parses a non-JSON error body and reports the HTTP status", async () => {
    const self = stub()
    const errs = []
    self.element.addEventListener("flowchartSaveError", (e) => errs.push(e.detail))
    const json = vi.fn(async () => { throw new SyntaxError("Unexpected token <") })
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 502, headers: htmlHeaders, json })))
    expect(await call("_saveToServer", self)).toBe(false)
    expect(json).not.toHaveBeenCalled()
    expect(errs).toEqual([{ errors: ["Save failed (HTTP 502)"] }])
  })

  it("treats a response without a content-type as non-JSON", async () => {
    const self = stub({ saveFailedHttpFormatValue: "保存失败（HTTP {status}）" })
    const errs = []
    self.element.addEventListener("flowchartSaveError", (e) => errs.push(e.detail))
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 500, headers: { get: () => null }, json: vi.fn() })))
    await call("_saveToServer", self)
    expect(errs[0].errors).toEqual(["保存失败（HTTP 500）"])
  })

  it("sends the loaded head as expected_head_version_id and expected_head_revision on every save", async () => {
    const self = stub({ headVersionIdValue: "12", headRevisionValue: "r12" })
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ version_id: 13 }) })))
    await call("_saveToServer", self)
    const body = JSON.parse(fetch.mock.calls[0][1].body)
    expect(body.expected_head_version_id).toBe("12")
    expect(body.expected_head_revision).toBe("r12")
    expect(body).not.toHaveProperty("based_on_version_id")
  })

  it("adopts the returned version id as the new head and hides a stale conflict banner", async () => {
    const banner = document.createElement("div")
    const self = stub({ headVersionIdValue: "12", headRevisionValue: "r12", hasSaveConflictBannerTarget: true, saveConflictBannerTarget: banner })
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ status: "success", version_id: 13 }) })))
    expect(await call("_saveToServer", self)).toBe(true)
    expect(self.headVersionIdValue).toBe("13")
    expect(self.headRevisionValue).toBe("")
    expect(banner.classList.contains("hidden")).toBe(true)
  })

  it("adopts the returned head revision, which changes when a draft head is revised in place", async () => {
    const self = stub({ headVersionIdValue: "12", headRevisionValue: "r1" })
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ status: "success", version_id: 12, head_revision: "r2" }) })))
    expect(await call("_saveToServer", self)).toBe(true)
    expect(self.headVersionIdValue).toBe("12")
    expect(self.headRevisionValue).toBe("r2")
  })

  it("in version-edit mode sends the lineage parent and advances it with the head after the save", async () => {
    const self = stub({ headVersionIdValue: "12", hasBasedOnVersionIdValue: true, basedOnVersionIdValue: "7" })
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ status: "success", version_id: 13 }) })))
    await call("_saveToServer", self)
    expect(JSON.parse(fetch.mock.calls[0][1].body)).toMatchObject({ expected_head_version_id: "12", based_on_version_id: "7" })
    expect(self.headVersionIdValue).toBe("13")
    expect(self.basedOnVersionIdValue).toBe("13")
  })

  it("on 409 shows the conflict banner with the server message and reports a conflict error", async () => {
    document.body.innerHTML = ""
    const banner = document.createElement("div")
    banner.className = "hidden"
    const message = document.createElement("span")
    const self = stub({
      headVersionIdValue: "12",
      hasSaveConflictBannerTarget: true, saveConflictBannerTarget: banner,
      hasSaveConflictMessageTarget: true, saveConflictMessageTarget: message,
    })
    const errs = []
    self.element.addEventListener("flowchartSaveError", (e) => errs.push(e.detail))
    const conflict = { status: "conflict", message: "Saved elsewhere", head_version_id: 20 }
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 409, headers: jsonHeaders, json: async () => conflict })))
    expect(await call("_saveToServer", self)).toBe(false)
    expect(banner.classList.contains("hidden")).toBe(false)
    expect(message.textContent).toBe("Saved elsewhere")
    expect(self._conflictHeadVersionId).toBe(20)
    expect(self.headVersionIdValue).toBe("12")
    expect(errs).toEqual([{ ...conflict, errors: ["Saved elsewhere"] }])
    expect(self._saveInFlight).toBe(false)
  })

  it("treats a non-JSON 409 as a generic HTTP failure", async () => {
    const self = stub({ _showSaveConflict: vi.fn() })
    const errs = []
    self.element.addEventListener("flowchartSaveError", (e) => errs.push(e.detail))
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 409, headers: htmlHeaders, json: vi.fn() })))
    await call("_saveToServer", self)
    expect(self._showSaveConflict).not.toHaveBeenCalled()
    expect(errs[0].errors).toEqual(["Save failed (HTTP 409)"])
  })

  it("ignores a re-entrant save while one is in flight", async () => {
    const self = stub()
    self._saveInFlight = true
    vi.stubGlobal("fetch", vi.fn())
    expect(await call("_saveToServer", self)).toBe(false)
  })
})

describe("FlowchartCanvasController — clear (writable, confirmed)", () => {
  it("clears the canvas and marks unsaved when confirmed", () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    const self = stub()
    call("clear", self)
    expect(self.canvas.clear).toHaveBeenCalled()
    expect(self.hasUnsavedChanges).toBe(true)
    expect(self.undoRedoManager.commitPendingState).toHaveBeenCalled()
  })

  it("does nothing when the confirm is declined", () => {
    vi.stubGlobal("confirm", vi.fn(() => false))
    const self = stub()
    call("clear", self)
    expect(self.canvas.clear).not.toHaveBeenCalled()
  })
})

describe("FlowchartCanvasController — generateDocs error path", () => {
  it("alerts when the document URL is missing", async () => {
    const self = stub({ urlsValue: {} })
    const alertSpy = vi.fn(); vi.stubGlobal("alert", alertSpy)
    await call("generateDocs", self)
    expect(alertSpy).toHaveBeenCalledWith(expect.stringContaining("Failed to generate documentation"))
  })

  it("alerts when documentation generation fails", async () => {
    const self = stub()
    const alertSpy = vi.fn(); vi.stubGlobal("alert", alertSpy)
    vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("net") }))
    await call("generateDocs", self)
    expect(alertSpy).toHaveBeenCalledWith(expect.stringContaining("Failed to generate documentation"))
  })

  it("downloads the generated markdown on success", async () => {
    const self = stub()
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ markdown: "# Doc", filename: "d.md" }) })))
    vi.stubGlobal("URL", { createObjectURL: vi.fn(() => "blob:x"), revokeObjectURL: vi.fn() })
    const clickSpy = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {})
    await call("generateDocs", self)
    expect(clickSpy).toHaveBeenCalled()
    clickSpy.mockRestore()
  })

  it("throws (and alerts) on a non-OK documentation response", async () => {
    const self = stub()
    const alertSpy = vi.fn(); vi.stubGlobal("alert", alertSpy)
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 500 })))
    await call("generateDocs", self)
    expect(alertSpy).toHaveBeenCalled()
  })
})

// ---------------------------------------------------------------------------
// Lifecycle: connect / _initializeCanvas / _setupCanvasCallbacks / _onCanvasReady
// / disconnect. These run the real prototype methods against a fake `this` while
// the collaborator modules are mocked (see vi.mock at the top).
// ---------------------------------------------------------------------------
function lifecycleSelf(over = {}) {
  const element = document.createElement("div")
  document.body.appendChild(element)
  return {
    ...I18N_VALUE_DEFAULTS,
    element,
    hasCanvasTarget: true,
    canvasTarget: document.createElement("div"),
    entityAttributesValue: [{ id: 1 }],
    flowchartTypeValue: "customer_specific",
    readOnlyValue: false,
    configurationValue: "",
    autoValidateValue: false,
    urlsValue: {},
    expandSubflowTitleValue: "Expand sub-flow",
    collapseSubflowTitleValue: "Collapse sub-flow",
    connectionIntoStartRejectedValue: "A Start element cannot have incoming connections",
    connectionOutOfEndRejectedValue: "An End element cannot have outgoing connections",
    branchFallbackNameFormatValue: "Branch {index}",
    unsavedChangesConfirmValue: "You have unsaved changes. Leave this page?",
    hasMinimapContainerTarget: false,
    minimapContainerTarget: document.createElement("div"),
    ...over,
  }
}

describe("FlowchartCanvasController — connect / disconnect", () => {
  it("warns and skips init when the canvas target is missing", () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {})
    const self = lifecycleSelf({ hasCanvasTarget: false })
    const init = (self._initializeCanvas = vi.fn())
    call("connect", self)
    expect(warn).toHaveBeenCalled()
    expect(init).not.toHaveBeenCalled()
    warn.mockRestore()
  })

  it("wires managers, initializes the canvas and restores the test runner", () => {
    const self = lifecycleSelf()
    self._initializeCanvas = vi.fn()
    self._bindEventListeners = vi.fn()
    call("connect", self)
    expect(self.undoRedoManager).toBeTruthy()
    expect(self.subflowManager).toBeTruthy()
    expect(self._initializeCanvas).toHaveBeenCalled()
    expect(self._bindEventListeners).toHaveBeenCalled()
    expect(self.element.flowchartCanvas).toBe(self.canvas)
    expect(self._testRunner.restoreSavedInput).toHaveBeenCalled()
    expect(self._testRunner.validateInput).toHaveBeenCalled()
  })

  it("installs the action catalog before initializing the canvas", () => {
    const catalog = {
      categories: [{ key: "model", label: "Records" }],
      actions: [{ key: "t6_probe", category: "model", label: "T6 Probe" }],
    }
    const self = lifecycleSelf({ actionCatalogValue: catalog })
    self._initializeCanvas = vi.fn()
    self._bindEventListeners = vi.fn()
    try {
      call("connect", self)
      expect(getActionConfig("t6_probe").label).toBe("T6 Probe")
      expect(self._initializeCanvas).toHaveBeenCalled()
    } finally {
      installSampleActionCatalog()
    }
  })

  it("disconnect tears down listeners and destroys the canvas", () => {
    const self = lifecycleSelf()
    self._validationNoticeTimer = null
    self._boundHandleElementDrop = vi.fn()
    self._boundHandleElementSelected = vi.fn()
    self._beforeUnload = vi.fn()
    self._beforeVisit = vi.fn()
    self.canvas = { destroy: vi.fn() }
    const remove = vi.spyOn(self.element, "removeEventListener")
    const docRemove = vi.spyOn(document, "removeEventListener")
    call("disconnect", self)
    expect(remove).toHaveBeenCalledWith("elementDrop", self._boundHandleElementDrop)
    expect(remove).toHaveBeenCalledWith("elementSelected", self._boundHandleElementSelected)
    expect(docRemove).toHaveBeenCalledWith("turbo:before-visit", self._beforeVisit)
    expect(self.canvas.destroy).toHaveBeenCalled()
  })

  it("disconnect destroys the minimap manager (disconnects its ResizeObserver)", () => {
    const self = lifecycleSelf()
    self.minimapManager = { destroy: vi.fn() }
    self.canvas = null
    call("disconnect", self)
    expect(self.minimapManager.destroy).toHaveBeenCalled()
  })

  it("declares the P5-6 readability values with English defaults", () => {
    expect(Controller.values.appLocale.default).toBe("en")
    expect(Controller.values.elementConnectionsFormat.default).toBe("{incoming} in / {outgoing} out")
    expect(Controller.values.versionLabelFormat.default).toBe("v{number}")
    expect(Controller.values.subflowSelfReferenceToast.default).toBe("Cannot expand: subflow references this flowchart (self-reference).")
    expect(Controller.values.testQueryDurationFormat.default).toBe("{duration} ms")
  })

  it("disconnect is safe when nothing was bound", () => {
    const self = lifecycleSelf()
    self.canvas = null
    expect(() => call("disconnect", self)).not.toThrow()
  })
})

describe("FlowchartCanvasController — connection rejection labels", () => {
  it("exposes English defaults for Start/End connection rejection toasts", () => {
    expect(Controller.values.connectionIntoStartRejected.default).toBe(
      "A Start element cannot have incoming connections"
    )
    expect(Controller.values.connectionOutOfEndRejected.default).toBe(
      "An End element cannot have outgoing connections"
    )
    expect(Controller.values.branchFallbackNameFormat.default).toBe("Branch {index}")
  })
})

describe("FlowchartCanvasController — test panel i18n values", () => {
  it("exposes the decision-branch format default with {step} and {branch} tokens", () => {
    expect(Controller.values.testDecisionBranchFormat.default).toBe("{step} → {branch}")
  })

  it("exposes the trace-truncated format default with a {count} token", () => {
    expect(Controller.values.testTraceTruncatedFormat.default).toBe(
      "Showing the first {count} steps; the run had more."
    )
  })
})

describe("FlowchartCanvasController — _initializeCanvas", () => {
  it("builds the canvas, managers and reacts to structure changes", async () => {
    const self = lifecycleSelf({ hasMinimapContainerTarget: true })
    self._setupCanvasCallbacks = vi.fn()
    self._setupBeforeUnloadWarning = vi.fn()
    self._onCanvasReady = vi.fn()
    refreshElementPins.mockClear(); primeAllElementPins.mockClear()
    call("_initializeCanvas", self)
    expect(self.canvas).toBeTruthy()
    expect(self.canvas.isReadOnly).toBe(false)
    // i18n seam: labels threaded onto the canvas for non-mixin flowchart/ helpers
    expect(self.canvas.labels).toEqual({
      connectionLabelPlaceholder: I18N_VALUE_DEFAULTS.connectionLabelPlaceholderValue,
      onlyOneStartAllowedToast: I18N_VALUE_DEFAULTS.onlyOneStartAllowedToastValue,
      loadConfigFailedToast: I18N_VALUE_DEFAULTS.loadConfigFailedToastValue,
      elementDefaultLabels: I18N_VALUE_DEFAULTS.elementDefaultLabelsValue,
      uniqueLabelFormat: "{label} {n}",
      expandSubflowTitle: self.expandSubflowTitleValue,
      collapseSubflowTitle: self.collapseSubflowTitleValue,
      connectionIntoStartRejected: self.connectionIntoStartRejectedValue,
      connectionOutOfEndRejected: self.connectionOutOfEndRejectedValue,
      branchFallbackNameFormat: self.branchFallbackNameFormatValue,
    })
    expect(self.exportManager).toBeTruthy()
    expect(self.searchManager).toBeTruthy()
    expect(self.minimapManager).toBeTruthy()
    expect(self._setupCanvasCallbacks).toHaveBeenCalled()
    await flush()
    // structure change with an elementId -> refreshElementPins
    self.element.dispatchEvent(new CustomEvent("flowchartStructureChanged", { detail: { elementId: "e1" } }))
    await flush(); await flush()
    expect(refreshElementPins).toHaveBeenCalled()
    // structure change without an elementId -> primeAllElementPins
    self.element.dispatchEvent(new CustomEvent("flowchartStructureChanged", { detail: {} }))
    await flush(); await flush()
    expect(primeAllElementPins).toHaveBeenCalled()
  })

  it("defaults entityAttributes/flowchartType and skips the minimap without its target", () => {
    const self = lifecycleSelf({ entityAttributesValue: null, flowchartTypeValue: "", hasMinimapContainerTarget: false })
    self._setupCanvasCallbacks = vi.fn(); self._setupBeforeUnloadWarning = vi.fn(); self._onCanvasReady = vi.fn()
    call("_initializeCanvas", self)
    expect(self.canvas.entityAttributes).toEqual([])
    expect(self.canvas.flowchartType).toBe("customer_specific")
    expect(self.minimapManager).toBeUndefined()
  })

  it("swallows errors thrown while refreshing pins on a structure change", async () => {
    const self = lifecycleSelf()
    self._setupCanvasCallbacks = vi.fn(); self._setupBeforeUnloadWarning = vi.fn(); self._onCanvasReady = vi.fn()
    refreshElementPins.mockRejectedValueOnce(new Error("boom"))
    call("_initializeCanvas", self)
    await flush()
    self.element.dispatchEvent(new CustomEvent("flowchartStructureChanged", { detail: { elementId: "e1" } }))
    await flush(); await flush()
    // no throw escapes — the handler's try/catch absorbs it
    expect(true).toBe(true)
  })
})

describe("FlowchartCanvasController — _setupBeforeUnloadWarning", () => {
  it("prompts only when there are unsaved changes", () => {
    const self = lifecycleSelf()
    call("_setupBeforeUnloadWarning", self)
    const e1 = { preventDefault: vi.fn(), returnValue: null }
    self.hasUnsavedChanges = false
    self._beforeUnload(e1)
    expect(e1.preventDefault).not.toHaveBeenCalled()
    const e2 = { preventDefault: vi.fn(), returnValue: null }
    self.hasUnsavedChanges = true
    self._beforeUnload(e2)
    expect(e2.preventDefault).toHaveBeenCalled()
    expect(e2.returnValue).toBe("")
  })

  it("turbo:before-visit confirms unsaved changes and preventDefault when declined", () => {
    const self = lifecycleSelf({
      unsavedChangesConfirmValue: "You have unsaved changes. Leave this page?",
    })
    call("_setupBeforeUnloadWarning", self)
    const confirmSpy = vi.fn(() => false)
    vi.stubGlobal("confirm", confirmSpy)

    const clean = { preventDefault: vi.fn() }
    self.hasUnsavedChanges = false
    self._beforeVisit(clean)
    expect(confirmSpy).not.toHaveBeenCalled()
    expect(clean.preventDefault).not.toHaveBeenCalled()

    const dirty = { preventDefault: vi.fn() }
    self.hasUnsavedChanges = true
    self._beforeVisit(dirty)
    expect(confirmSpy).toHaveBeenCalledWith("You have unsaved changes. Leave this page?")
    expect(dirty.preventDefault).toHaveBeenCalled()

    confirmSpy.mockReturnValue(true)
    const allowed = { preventDefault: vi.fn() }
    self._beforeVisit(allowed)
    expect(allowed.preventDefault).not.toHaveBeenCalled()
  })
})

describe("FlowchartCanvasController — _setupCanvasCallbacks", () => {
  function cbSelf(over = {}) {
    return {
      canvas: { clearTraceOverlay: vi.fn() },
      isCanvasReady: true,
      hasUnsavedChanges: false,
      undoRedoManager: { isUndoRedoOperation: false, captureCurrentState: vi.fn(() => "S"), commitPendingState: vi.fn() },
      minimapManager: { update: vi.fn(), _updateViewport: vi.fn() },
      subflowManager: { toggleSubflowExpansion: vi.fn() },
      _updateUnsavedIndicator: vi.fn(),
      _dispatchConfigurationChange: vi.fn(),
      _handleElementSelected: vi.fn(),
      _handleConnectionSelected: vi.fn(),
      _handleCanvasClick: vi.fn(),
      _updateAlignmentToolbar: vi.fn(),
      _updateZoomDisplay: vi.fn(),
      undo: vi.fn(), redo: vi.fn(), openSearch: vi.fn(), showToast: vi.fn(),
      ...over,
    }
  }

  it("onchange marks dirty, commits (unless preview) and updates the minimap", () => {
    const self = cbSelf()
    call("_setupCanvasCallbacks", self)
    self.canvas.onchange()
    expect(self.hasUnsavedChanges).toBe(true)
    expect(self.undoRedoManager.commitPendingState).toHaveBeenCalledTimes(1)
    expect(self.minimapManager.update).toHaveBeenCalled()
    // preview sync -> no second commit; and not-ready path returns early
    self.canvas._previewSync = true
    self.canvas.onchange()
    expect(self.undoRedoManager.commitPendingState).toHaveBeenCalledTimes(1)
    self.isCanvasReady = false
    self.hasUnsavedChanges = false
    self.canvas.onchange()
    expect(self.hasUnsavedChanges).toBe(false)
  })

  it("onchange clears the test-run trace overlay (P5-6), but not before the canvas is ready", () => {
    const self = cbSelf()
    call("_setupCanvasCallbacks", self)
    self.canvas.onchange()
    expect(self.canvas.clearTraceOverlay).toHaveBeenCalledTimes(1)
    self.canvas._previewSync = true
    self.canvas.onchange()
    expect(self.canvas.clearTraceOverlay).toHaveBeenCalledTimes(2)
    self.isCanvasReady = false
    self.canvas.onchange()
    expect(self.canvas.clearTraceOverlay).toHaveBeenCalledTimes(2)
  })

  it("onchange without a minimap manager still succeeds", () => {
    const self = cbSelf({ minimapManager: null })
    call("_setupCanvasCallbacks", self)
    expect(() => self.canvas.onchange()).not.toThrow()
  })

  it("onElementDoubleClick always opens the property sidebar, including for targeted subflows", () => {
    const self = cbSelf()
    call("_setupCanvasCallbacks", self)
    const sub = { type: "subflow", properties: { flowchartId: "fc1" } }
    self.canvas.onElementDoubleClick(sub)
    expect(self.subflowManager.toggleSubflowExpansion).not.toHaveBeenCalled()
    expect(self._handleElementSelected).toHaveBeenCalledWith({ detail: { element: sub } })
    const el = { type: "process" }
    self.canvas.onElementDoubleClick(el)
    expect(self._handleElementSelected).toHaveBeenCalledWith({ detail: { element: el } })
  })

  it("onSubflowToggle maps to toggleSubflowExpansion", () => {
    const self = cbSelf()
    call("_setupCanvasCallbacks", self)
    const sub = { type: "subflow", properties: { flowchartId: "fc1" } }
    self.canvas.onSubflowToggle(sub)
    expect(self.subflowManager.toggleSubflowExpansion).toHaveBeenCalledWith(sub)
  })

  it("the remaining callbacks delegate to their handlers", () => {
    const self = cbSelf()
    call("_setupCanvasCallbacks", self)
    self.canvas.onElementSelected({})
    self.canvas.onConnectionSelected({ id: "c" })
    self.canvas.onCanvasClick()
    self.canvas.onSelectionChanged()
    self.canvas.onundo()
    self.canvas.onredo()
    self.canvas.onZoomChange()
    self.canvas.onSearchRequested()
    self.canvas.onToast("hi", "info")
    expect(self._updateAlignmentToolbar).toHaveBeenCalledTimes(2)
    expect(self._handleConnectionSelected).toHaveBeenCalledWith({ id: "c" })
    expect(self._handleCanvasClick).toHaveBeenCalled()
    expect(self.undo).toHaveBeenCalled()
    expect(self.redo).toHaveBeenCalled()
    expect(self._updateZoomDisplay).toHaveBeenCalled()
    expect(self.minimapManager._updateViewport).toHaveBeenCalled()
    expect(self.openSearch).toHaveBeenCalled()
    expect(self.showToast).toHaveBeenCalledWith("hi", "info")
  })

  it("onZoomChange tolerates a missing minimap manager", () => {
    const self = cbSelf({ minimapManager: null })
    call("_setupCanvasCallbacks", self)
    expect(() => self.canvas.onZoomChange()).not.toThrow()
  })

  it("onSaveRequested (Ctrl/Cmd+S) saves a writable flowchart", () => {
    const self = cbSelf({ readOnlyValue: false, save: vi.fn() })
    call("_setupCanvasCallbacks", self)
    self.canvas.onSaveRequested()
    expect(self.save).toHaveBeenCalledOnce()
    expect(self.showToast).not.toHaveBeenCalled()
  })

  it("onSaveRequested on a read-only flowchart shows the read-only toast instead of saving", () => {
    const self = cbSelf({ readOnlyValue: true, save: vi.fn(), readOnlySaveToastValue: "Read-only" })
    call("_setupCanvasCallbacks", self)
    self.canvas.onSaveRequested()
    expect(self.save).not.toHaveBeenCalled()
    expect(self.showToast).toHaveBeenCalledWith("Read-only", "error")
  })
})

describe("FlowchartCanvasController — _bindEventListeners", () => {
  it("binds elementDrop/elementSelected listeners on the element", () => {
    const self = lifecycleSelf()
    self._handleElementDrop = vi.fn()
    self._handleElementSelected = vi.fn()
    const add = vi.spyOn(self.element, "addEventListener")
    call("_bindEventListeners", self)
    expect(add).toHaveBeenCalledWith("elementDrop", self._boundHandleElementDrop)
    expect(add).toHaveBeenCalledWith("elementSelected", self._boundHandleElementSelected)
  })
})

describe("FlowchartCanvasController — _onCanvasReady", () => {
  it("loads config, saves initial state and auto-validates after animation frames", async () => {
    const self = lifecycleSelf({ configurationValue: '{"elements":[]}', autoValidateValue: true, hasMinimapContainerTarget: true })
    self.canvas = { loadConfiguration: vi.fn() }
    self.subflowManager = { restoreExpandedSubflowsFromConfiguration: vi.fn() }
    self._ensureElementsInView = vi.fn()
    self.undoRedoManager = { saveInitialState: vi.fn() }
    self.minimapManager = { update: vi.fn() }
    self.validate = vi.fn()
    call("_onCanvasReady", self)
    await flush(); await flush()
    expect(self.canvas.loadConfiguration).toHaveBeenCalledWith('{"elements":[]}')
    expect(self.subflowManager.restoreExpandedSubflowsFromConfiguration).toHaveBeenCalled()
    expect(self.undoRedoManager.saveInitialState).toHaveBeenCalled()
    expect(self.isCanvasReady).toBe(true)
    expect(self.minimapManager.update).toHaveBeenCalled()
    expect(self.validate).toHaveBeenCalled()
  })

  it("skips config load / validation / minimap when those are absent", async () => {
    const self = lifecycleSelf({ configurationValue: "", autoValidateValue: false, hasMinimapContainerTarget: false })
    self.canvas = { loadConfiguration: vi.fn() }
    self._ensureElementsInView = vi.fn()
    self.subflowManager = { restoreExpandedSubflowsFromConfiguration: vi.fn() }
    self.undoRedoManager = { saveInitialState: vi.fn() }
    self.minimapManager = null
    self.validate = vi.fn()
    call("_onCanvasReady", self)
    await flush(); await flush()
    expect(self.canvas.loadConfiguration).not.toHaveBeenCalled()
    expect(self.validate).not.toHaveBeenCalled()
    expect(self.isCanvasReady).toBe(true)
  })
})

describe("FlowchartCanvasController — alignment + layout delegation", () => {
  function alignSelf() {
    const am = {
      alignLeft: vi.fn(), alignCenterH: vi.fn(), alignRight: vi.fn(),
      alignTop: vi.fn(), alignCenterV: vi.fn(), alignBottom: vi.fn(),
      distributeH: vi.fn(), distributeV: vi.fn(),
    }
    return {
      canvas: { alignmentManager: am, autoLayout: vi.fn(), cycleConnectionRouting: vi.fn() },
      readOnlyValue: false,
      _updateAlignmentToolbar: vi.fn(),
      _am: am,
    }
  }

  it.each(["alignLeft", "alignCenterH", "alignRight", "alignTop", "alignCenterV", "alignBottom"])(
    "%s delegates and refreshes the toolbar", (name) => {
      const self = alignSelf()
      call(name, self)
      expect(self._am[name]).toHaveBeenCalled()
      expect(self._updateAlignmentToolbar).toHaveBeenCalled()
    })

  it("distributeH / distributeV delegate to the alignment manager", () => {
    const self = alignSelf()
    call("distributeH", self); call("distributeV", self)
    expect(self._am.distributeH).toHaveBeenCalled()
    expect(self._am.distributeV).toHaveBeenCalled()
  })

  it("autoLayout / cycleConnectionRouting run when writable", () => {
    const self = alignSelf()
    call("autoLayout", self); call("cycleConnectionRouting", self)
    expect(self.canvas.autoLayout).toHaveBeenCalled()
    expect(self.canvas.cycleConnectionRouting).toHaveBeenCalled()
  })
})

describe("FlowchartCanvasController — property sidebar + selection handlers", () => {
  function pe() {
    return { openEditor: vi.fn(), openConnectionEditor: vi.fn(), close: vi.fn(), discardAndClose: vi.fn() }
  }
  function sidebarSelf(editor, over = {}) {
    const sidebar = document.createElement("div"); sidebar.classList.add("hidden")
    return {
      hasPropertySidebarTarget: true,
      propertySidebarTarget: sidebar,
      canvas: {},
      application: { getControllerForElementAndIdentifier: vi.fn(() => editor) },
      _showPropertySidebar: Controller.prototype._showPropertySidebar,
      _hidePropertySidebar: Controller.prototype._hidePropertySidebar,
      _updateAlignmentToolbar: vi.fn(),
      ...over,
    }
  }

  it("_handleElementSelected opens the sidebar for the dragged element", () => {
    const editor = pe()
    const self = sidebarSelf(editor)
    call("_handleElementSelected", self, { detail: { element: { id: "e1" } } })
    expect(editor.openEditor).toHaveBeenCalledWith({ id: "e1" }, self.canvas, undefined)
    expect(self._updateAlignmentToolbar).toHaveBeenCalled()
  })

  it("_handleElementSelected accepts a bare element in detail", () => {
    const editor = pe()
    const self = sidebarSelf(editor)
    call("_handleElementSelected", self, { detail: { id: "e2" } })
    expect(editor.openEditor).toHaveBeenCalledWith({ id: "e2" }, self.canvas, undefined)
  })

  it("_handleElementSelected only updates the toolbar when there is no sidebar target", () => {
    const self = sidebarSelf(pe(), { hasPropertySidebarTarget: false })
    call("_handleElementSelected", self, { detail: { element: { id: "x" } } })
    expect(self._updateAlignmentToolbar).toHaveBeenCalled()
  })

  it("_handleConnectionSelected opens the connection editor", () => {
    const editor = pe()
    const self = sidebarSelf(editor)
    call("_handleConnectionSelected", self, { id: "c1" })
    expect(self.propertySidebarTarget.classList.contains("hidden")).toBe(false)
    expect(editor.openConnectionEditor).toHaveBeenCalledWith({ id: "c1" }, self.canvas)
  })

  it("_handleConnectionSelected is a no-op without a connection or sidebar", () => {
    const self = sidebarSelf(pe())
    expect(() => call("_handleConnectionSelected", self, null)).not.toThrow()
    const self2 = sidebarSelf(pe(), { hasPropertySidebarTarget: false })
    expect(() => call("_handleConnectionSelected", self2, { id: "c" })).not.toThrow()
  })

  it("_handleConnectionSelected tolerates a missing property-editor controller", () => {
    const self = sidebarSelf(null)
    expect(() => call("_handleConnectionSelected", self, { id: "c" })).not.toThrow()
  })

  it("_handleCanvasClick hides the sidebar and refreshes the toolbar", () => {
    const editor = pe()
    const self = sidebarSelf(editor, { _hidePropertySidebar: vi.fn() })
    call("_handleCanvasClick", self)
    expect(self._hidePropertySidebar).toHaveBeenCalled()
    expect(self._updateAlignmentToolbar).toHaveBeenCalled()
  })

  it("_handleCanvasClick without a sidebar just refreshes the toolbar", () => {
    const self = sidebarSelf(pe(), { hasPropertySidebarTarget: false })
    call("_handleCanvasClick", self)
    expect(self._updateAlignmentToolbar).toHaveBeenCalled()
  })

  it("_showPropertySidebar reveals the sidebar and opens the editor", () => {
    const editor = pe()
    const self = sidebarSelf(editor)
    call("_showPropertySidebar", self, { id: "e1" }, "io")
    expect(editor.openEditor).toHaveBeenCalledWith({ id: "e1" }, self.canvas, "io")
    expect(self.propertySidebarTarget.classList.contains("flex")).toBe(true)
  })

  it("_showPropertySidebar is a no-op without the sidebar target", () => {
    const self = sidebarSelf(pe(), { hasPropertySidebarTarget: false })
    expect(() => call("_showPropertySidebar", self, { id: "e" })).not.toThrow()
  })

  it("_hidePropertySidebar closes an open editor when present", () => {
    const editor = pe()
    const self = sidebarSelf(editor)
    call("_hidePropertySidebar", self)
    expect(editor.close).toHaveBeenCalled()
  })

  it("_hidePropertySidebar hides via classes when no editor controller exists", () => {
    const self = sidebarSelf(null)
    self.propertySidebarTarget.classList.remove("hidden")
    call("_hidePropertySidebar", self)
    expect(self.propertySidebarTarget.classList.contains("hidden")).toBe(true)
  })

  it("_hidePropertySidebar is a no-op without the sidebar target", () => {
    const self = sidebarSelf(null, { hasPropertySidebarTarget: false })
    expect(() => call("_hidePropertySidebar", self)).not.toThrow()
  })
})

describe("FlowchartCanvasController — _discardOpenPropertyEditor", () => {
  it("calls discardAndClose on the open property editor", () => {
    const editor = { discardAndClose: vi.fn() }
    const sidebar = document.createElement("div")
    const self = {
      hasPropertySidebarTarget: true,
      propertySidebarTarget: sidebar,
      application: { getControllerForElementAndIdentifier: vi.fn(() => editor) },
    }
    call("_discardOpenPropertyEditor", self)
    expect(editor.discardAndClose).toHaveBeenCalled()
  })

  it("is a no-op without a sidebar target or a discardable editor", () => {
    const self1 = { hasPropertySidebarTarget: false }
    expect(() => call("_discardOpenPropertyEditor", self1)).not.toThrow()
    const self2 = {
      hasPropertySidebarTarget: true,
      propertySidebarTarget: document.createElement("div"),
      application: { getControllerForElementAndIdentifier: vi.fn(() => ({})) },
    }
    expect(() => call("_discardOpenPropertyEditor", self2)).not.toThrow()
  })
})

describe("FlowchartCanvasController — export delegation", () => {
  it("exportSVG / exportPNG delegate to the export manager", () => {
    const exportManager = { exportSVG: vi.fn(), exportPNG: vi.fn() }
    const self = { exportManager }
    call("exportSVG", self); call("exportPNG", self)
    expect(exportManager.exportSVG).toHaveBeenCalled()
    expect(exportManager.exportPNG).toHaveBeenCalled()
  })

  it("export methods are no-ops without an export manager", () => {
    const self = { exportManager: null }
    expect(() => { call("exportSVG", self); call("exportPNG", self) }).not.toThrow()
  })
})

describe("FlowchartCanvasController — element drop subflow branches", () => {
  it("auto-populates subflow inputs from a drop target's outputs", () => {
    const target = { id: "p", properties: { outputs: [{ value: "o1" }, { value: "o2" }] } }
    const self = stub({ canvas: makeCanvas({ getElementAtPosition: vi.fn(() => target) }) })
    call("_handleElementDrop", self, { detail: { elementType: "subflow", x: 1, y: 2, dropTarget: target } })
    const passed = self.canvas.addElementRelativeTo.mock.calls[0][0]
    expect(passed.properties.inputs).toEqual([{ value: "o1" }, { value: "o2" }])
  })

  it("double-click subflow after a process element inherits its outputs", () => {
    const last = { type: "process", properties: { outputs: [{ value: "x" }] } }
    const self = stub({ canvas: makeCanvas({ elements: [last], getElementAtPosition: vi.fn(() => null) }) })
    call("_handleElementDrop", self, { detail: { elementType: "subflow", x: 0, y: 0, isDoubleClick: true } })
    const passed = self.canvas.addElement.mock.calls[0][0]
    expect(passed.properties.inputs).toEqual([{ value: "x" }])
  })

  it("double-click append leaves placement to the canvas so it stacks and auto-connects", () => {
    const self = stub({ canvas: makeCanvas({ getElementAtPosition: vi.fn(() => null) }) })
    call("_handleElementDrop", self, { detail: { elementType: "process", x: 400, y: 175, isDoubleClick: true } })
    expect(self.canvas.addElement).toHaveBeenCalledWith({ type: "process" })
  })

  it("a palette drop onto empty canvas keeps its drop position", () => {
    const self = stub({ canvas: makeCanvas({ getElementAtPosition: vi.fn(() => null) }) })
    call("_handleElementDrop", self, { detail: { elementType: "process", x: 400, y: 175 } })
    expect(self.canvas.addElement).toHaveBeenCalledWith({ type: "process", x: 400, y: 175 })
  })

  it("maps a customElement flowchartId into the new element's properties as a number", () => {
    const self = stub()
    call("_handleElementDrop", self, {
      detail: { elementType: "process", x: 0, y: 0, customElementData: { name: "C", flowchartId: "7" } },
    })
    const passed = self.canvas.addElement.mock.calls[0][0]
    expect(passed.properties.flowchartId).toBe(7)
    expect(passed.label).toBe("C")
  })

  it("does not store a non-numeric flowchartId leftover", () => {
    const self = stub()
    call("_handleElementDrop", self, {
      detail: { elementType: "subflow", x: 0, y: 0, customElementData: { name: "Sub", flowchartId: "fc7" } },
    })
    expect(self.canvas.addElement.mock.calls[0][0].properties.flowchartId).toBeUndefined()
  })

  it("ignores a blank flowchartId on drop", () => {
    const self = stub()
    call("_handleElementDrop", self, {
      detail: { elementType: "subflow", x: 0, y: 0, customElementData: { name: "Sub", flowchartId: "" } },
    })
    expect(self.canvas.addElement.mock.calls[0][0].properties.flowchartId).toBeUndefined()
  })
})

describe("FlowchartCanvasController — _saveToServer edge branches", () => {
  it("keeps the dirty flag when edits arrive mid-save and does not rematerialize expansions", async () => {
    const self = stub({ hasBasedOnVersionIdValue: true, basedOnVersionIdValue: "v9", hasUnsavedChanges: true })
    self.subflowManager.expandedSubflows = {
      s1: { originalElement: { id: "s1", properties: {} }, startElementId: "x", endElementId: "y",
            shiftedElementPositions: {}, incomingConnections: [], outgoingConnections: [] },
    }
    self.subflowManager.captureCompleteCanvasState = vi.fn(() => ({ ok: true }))
    // fetch resolves after we flag an in-flight edit
    vi.stubGlobal("fetch", vi.fn(async () => {
      self._editsSinceSaveStart = true
      return { ok: true, json: async () => ({ version: 3, version_id: 31 }) }
    }))
    const ok = await call("_saveToServer", self)
    expect(ok).toBe(true)
    expect(self.hasUnsavedChanges).toBe(true)
    expect(self.subflowManager.restoreCompleteCanvasState).not.toHaveBeenCalled()
    const body = JSON.parse(fetch.mock.calls[0][1].body)
    expect(body.based_on_version_id).toBe("v9")
    expect(self.basedOnVersionIdValue).toBe("31")
    expect(self.headVersionIdValue).toBe("31")
  })

  it("returns false and dispatches an error on a network exception", async () => {
    const self = stub()
    const errs = []
    self.element.addEventListener("flowchartSaveError", (e) => errs.push(e.detail))
    vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("down") }))
    const ok = await call("_saveToServer", self)
    expect(ok).toBe(false)
    expect(errs[0].errors).toEqual(["Network error: down"])
    expect(self._saveInFlight).toBe(false)
  })

  it("propagates when the catch handler itself throws", async () => {
    const self = stub()
    // fetch throws -> enters catch; the catch's dispatch then throws too and the
    // error unwinds out of _saveToServer. (_dispatchSaveError only dispatches a
    // CustomEvent, so this cannot happen in the app — it just guards the path.)
    self._dispatchSaveError = vi.fn(() => { throw new Error("dispatch fail") })
    vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("net") }))
    await expect(call("_saveToServer", self)).rejects.toThrow("dispatch fail")
  })

  it("saves the stored collapsed configuration while previewing and never rematerializes expansions", async () => {
    const stored = { elements: [{ id: "collapsed" }], connections: [] }
    const canvas = makeCanvas({
      previewMode: true,
      getConfiguration: vi.fn(() => ({ elements: [{ id: "expanded" }], connections: [] })),
    })
    const self = stub({ canvas, _collapsedPreviewConfiguration: stored })
    self.subflowManager.expandedSubflows = {
      s1: { originalElement: { id: "s1", properties: {} }, startElementId: "x", endElementId: "y",
            shiftedElementPositions: {}, incomingConnections: [], outgoingConnections: [] },
    }
    self.subflowManager.captureCompleteCanvasState = vi.fn(() => ({ snap: 1 }))
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ version: 4 }) })))
    await call("_saveToServer", self)
    expect(JSON.parse(fetch.mock.calls[0][1].body).flowchart.configuration).toBe(JSON.stringify(stored))
    expect(self.subflowManager.restoreCompleteCanvasState).not.toHaveBeenCalled()
    expect(self.subflowManager.captureCompleteCanvasState).not.toHaveBeenCalled()
  })
})

describe("FlowchartCanvasController — _adoptHeadVersion", () => {
  it("ignores a missing version id", () => {
    const self = stub({ headVersionIdValue: "5" })
    call("_adoptHeadVersion", self, undefined)
    call("_adoptHeadVersion", self, null)
    expect(self.headVersionIdValue).toBe("5")
  })

  it("leaves basedOnVersionId untouched outside version-edit mode", () => {
    const self = stub({ hasBasedOnVersionIdValue: true, basedOnVersionIdValue: "" })
    call("_adoptHeadVersion", self, 8)
    expect(self.headVersionIdValue).toBe("8")
    expect(self.basedOnVersionIdValue).toBe("")
  })
})

describe("FlowchartCanvasController — save conflict banner", () => {
  it("_showSaveConflict remembers the head even without banner targets", () => {
    const self = stub()
    call("_showSaveConflict", self, { head_version_id: 4, head_revision: "r4", message: "x" })
    expect(self._conflictHeadVersionId).toBe(4)
    expect(self._conflictHeadRevision).toBe("r4")
  })

  it("_showSaveConflict keeps the rendered message when the server sends none", () => {
    const banner = document.createElement("div")
    banner.className = "hidden"
    const message = document.createElement("span")
    message.textContent = "Rendered"
    const self = stub({
      hasSaveConflictBannerTarget: true, saveConflictBannerTarget: banner,
      hasSaveConflictMessageTarget: false, saveConflictMessageTarget: message,
    })
    call("_showSaveConflict", self, { head_version_id: 4 })
    expect(banner.classList.contains("hidden")).toBe(false)
    call("_showSaveConflict", self, { head_version_id: 4, message: "ignored without target" })
    expect(message.textContent).toBe("Rendered")
  })

  it("_hideSaveConflict no-ops without a banner target", () => {
    expect(() => call("_hideSaveConflict", stub())).not.toThrow()
  })

  it("reloadAfterConflict drops the unsaved-changes guard and reloads the page", () => {
    const reload = vi.fn()
    vi.stubGlobal("location", { reload })
    const self = stub({ hasUnsavedChanges: true })
    call("reloadAfterConflict", self)
    expect(self.hasUnsavedChanges).toBe(false)
    expect(reload).toHaveBeenCalledOnce()
  })

  it("overwriteAfterConflict hides the banner and resaves against the conflicting head", async () => {
    const banner = document.createElement("div")
    const self = stub({
      hasSaveConflictBannerTarget: true, saveConflictBannerTarget: banner,
      _conflictHeadVersionId: 20, _conflictHeadRevision: "r20", headVersionIdValue: "12", headRevisionValue: "r12",
      save: vi.fn(() => Promise.resolve(true)),
    })
    await expect(call("overwriteAfterConflict", self)).resolves.toBe(true)
    expect(banner.classList.contains("hidden")).toBe(true)
    expect(self.headVersionIdValue).toBe("20")
    expect(self.headRevisionValue).toBe("r20")
    expect(self.save).toHaveBeenCalledOnce()
  })

  it("overwriteAfterConflict sends an empty expected head when the line has none", () => {
    const self = stub({ _conflictHeadVersionId: null, headVersionIdValue: "12", headRevisionValue: "r12", save: vi.fn() })
    call("overwriteAfterConflict", self)
    expect(self.headVersionIdValue).toBe("")
    expect(self.headRevisionValue).toBe("")
  })

  it("an overwrite round-trip PATCHes with the conflicting head as expected_head_version_id", async () => {
    const self = stub({ headVersionIdValue: "12", headRevisionValue: "r12" })
    self.save = () => call("_saveToServer", self)
    const responses = [
      { ok: false, status: 409, headers: jsonHeaders, json: async () => ({ status: "conflict", message: "m", head_version_id: 20, head_revision: "r20" }) },
      { ok: true, json: async () => ({ status: "success", version_id: 21, head_revision: "r21" }) },
    ]
    vi.stubGlobal("fetch", vi.fn(async () => responses.shift()))
    expect(await call("_saveToServer", self)).toBe(false)
    expect(await call("overwriteAfterConflict", self)).toBe(true)
    const bodies = fetch.mock.calls.map(([, init]) => JSON.parse(init.body))
    expect(bodies.map(b => b.expected_head_version_id)).toEqual(["12", "20"])
    expect(bodies.map(b => b.expected_head_revision)).toEqual(["r12", "r20"])
    expect(self.headVersionIdValue).toBe("21")
    expect(self.headRevisionValue).toBe("r21")
  })
})

describe("P5-8 cleanup — leaked listeners and search timer", () => {
  it("binds flowchartStructureChanged once and removes that same handler on disconnect", async () => {
    const self = lifecycleSelf()
    self._setupCanvasCallbacks = vi.fn()
    self._setupBeforeUnloadWarning = vi.fn()
    self._onCanvasReady = vi.fn()
    call("_initializeCanvas", self)
    await flush()
    const handler = self._boundStructureChanged
    expect(handler).toEqual(expect.any(Function))

    const remove = vi.spyOn(self.element, "removeEventListener")
    call("disconnect", self)
    expect(remove).toHaveBeenCalledWith("flowchartStructureChanged", handler)

    refreshElementPins.mockClear()
    primeAllElementPins.mockClear()
    self.element.dispatchEvent(new CustomEvent("flowchartStructureChanged", { detail: { elementId: "e1" } }))
    await flush()
    await flush()
    expect(refreshElementPins).not.toHaveBeenCalled()
    expect(primeAllElementPins).not.toHaveBeenCalled()
  })

  it("clears _searchDebounceTimer on disconnect so a pending search callback does not fire", () => {
    vi.useFakeTimers()
    try {
      const self = lifecycleSelf()
      let fired = false
      self._searchDebounceTimer = setTimeout(() => { fired = true }, 200)
      self.canvas = { destroy: vi.fn() }
      call("disconnect", self)
      vi.advanceTimersByTime(1000)
      expect(fired).toBe(false)
    } finally {
      vi.useRealTimers()
    }
  })
})

describe("FlowchartCanvasController — P5-4 subflow preview mode", () => {
  it("_enterPreviewMode stores a clone of the collapsed graph and shows the notice", () => {
    const notice = document.createElement("div")
    notice.classList.add("hidden")
    const live = { elements: [{ id: "a", x: 1 }], connections: [] }
    const canvas = makeCanvas({
      getConfiguration: vi.fn(() => live),
      previewMode: false,
    })
    const self = stub({
      canvas,
      hasPreviewNoticeTarget: true,
      previewNoticeTarget: notice,
    })
    call("_enterPreviewMode", self)
    expect(self.canvas.previewMode).toBe(true)
    expect(self._collapsedPreviewConfiguration).toEqual(live)
    expect(self._collapsedPreviewConfiguration).not.toBe(live)
    expect(notice.classList.contains("hidden")).toBe(false)
    expect(self.canvas._removeEdgeInsertButton).toHaveBeenCalled()
    call("_enterPreviewMode", self)
    expect(self.canvas.getConfiguration).toHaveBeenCalledTimes(1)
  })

  it("_leavePreviewMode restore:true swaps the stored graph back", () => {
    const stored = { elements: [{ id: "collapsed", x: 9, y: 8 }], connections: [] }
    const canvas = makeCanvas({ previewMode: true })
    const self = stub({
      canvas,
      _collapsedPreviewConfiguration: stored,
      subflowManager: { expandedSubflows: { s1: {} } },
    })
    call("_leavePreviewMode", self, { restore: true })
    expect(canvas.restoreGraph).toHaveBeenCalledWith(stored)
    expect(canvas.previewMode).toBe(false)
    expect(self._collapsedPreviewConfiguration).toBeNull()
    expect(self.subflowManager.expandedSubflows).toEqual({})
  })

  it("_leavePreviewMode without restore skips restoreGraph and skips chrome when not previewing", () => {
    const canvas = makeCanvas({ previewMode: false })
    const self = stub({ canvas, _collapsedPreviewConfiguration: { elements: [] } })
    self._syncPreviewChrome = vi.fn()
    call("_leavePreviewMode", self, { restore: false })
    expect(canvas.restoreGraph).not.toHaveBeenCalled()
    expect(self._syncPreviewChrome).not.toHaveBeenCalled()

    const noCanvas = stub({ canvas: null, _collapsedPreviewConfiguration: { elements: [] } })
    noCanvas._syncPreviewChrome = vi.fn()
    expect(() => call("_leavePreviewMode", noCanvas, { restore: true })).not.toThrow()
    expect(noCanvas._syncPreviewChrome).toHaveBeenCalled()
  })

  it("_canvasForValidation exposes stored elements and live pins while previewing", () => {
    const stored = { elements: [{ id: "c" }], connections: [{ id: "x" }] }
    const canvas = makeCanvas({
      previewMode: true,
      getElementPins: vi.fn(() => ({ inputs: ["in"], outputs: [] })),
    })
    const self = stub({ canvas, _collapsedPreviewConfiguration: stored })
    const view = call("_canvasForValidation", self)
    expect(view.elements).toBe(stored.elements)
    const seen = []
    view.iterateElements((el) => seen.push(el.id))
    expect(seen).toEqual(["c"])
    expect(view.getElementPins("c")).toEqual({ inputs: ["in"], outputs: [] })

    const noPins = makeCanvas({ previewMode: true })
    const emptyPins = call("_canvasForValidation", stub({
      canvas: noPins,
      _collapsedPreviewConfiguration: stored,
    }))
    expect(emptyPins.getElementPins("c")).toEqual({ inputs: [], outputs: [] })
    const live = stub()
    expect(call("_canvasForValidation", live)).toBe(live.canvas)
  })

  it("_previewAwareConfiguration falls back to the live graph when not storing a collapse", () => {
    const canvas = makeCanvas({
      previewMode: true,
      getConfiguration: vi.fn(() => ({ elements: [{ id: "live" }], connections: [] })),
    })
    const self = stub({ canvas, _collapsedPreviewConfiguration: null })
    expect(call("_previewAwareConfiguration", self).elements[0].id).toBe("live")
  })

  it("_syncPreviewChrome refreshes alignment, autofix list, and the property editor", () => {
    const notice = document.createElement("div")
    const sidebar = document.createElement("div")
    const apply = vi.fn()
    const canvas = makeCanvas({ previewMode: true })
    const self = stub({
      canvas,
      hasPreviewNoticeTarget: true,
      previewNoticeTarget: notice,
      hasValidationListTarget: true,
      _validationProblems: [{ type: "x" }],
      _renderValidationList: vi.fn(),
      hasPropertySidebarTarget: true,
      propertySidebarTarget: sidebar,
      application: { getControllerForElementAndIdentifier: vi.fn(() => ({ _applyReadOnlyState: apply })) },
    })
    call("_syncPreviewChrome", self)
    expect(notice.classList.contains("hidden")).toBe(false)
    expect(self._updateAlignmentToolbar).toHaveBeenCalled()
    expect(self._renderValidationList).toHaveBeenCalled()
    expect(apply).toHaveBeenCalled()

    canvas.previewMode = false
    self._validationProblems = null
    self.application.getControllerForElementAndIdentifier.mockReturnValue(undefined)
    call("_syncPreviewChrome", self)
    expect(notice.classList.contains("hidden")).toBe(true)
  })

  it("undo, redo, and clear leave preview before mutating", () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    const canvas = makeCanvas({
      previewMode: true,
      canMutate() { return !this.isReadOnly && !this.previewMode },
    })
    const collapsed = { elements: [{ id: "c" }], connections: [] }
    const self = stub({
      canvas,
      _collapsedPreviewConfiguration: collapsed,
      subflowManager: { expandedSubflows: { s1: {} } },
    })
    expect(call("undo", self)).toBe(true)
    expect(canvas.previewMode).toBe(false)
    expect(canvas.restoreGraph).toHaveBeenLastCalledWith(collapsed)
    expect(self.undoRedoManager.undo).toHaveBeenCalled()

    canvas.previewMode = true
    self._collapsedPreviewConfiguration = collapsed
    expect(call("redo", self)).toBe(true)
    expect(canvas.previewMode).toBe(false)
    expect(canvas.restoreGraph).toHaveBeenCalledTimes(2)

    canvas.previewMode = true
    self._collapsedPreviewConfiguration = collapsed
    call("clear", self)
    expect(canvas.previewMode).toBe(false)
    expect(canvas.restoreGraph).toHaveBeenCalledTimes(3)
    expect(canvas.clear).toHaveBeenCalled()
  })

  it("a cancelled clear in preview still brings back the collapsed graph, not the expansion", () => {
    vi.stubGlobal("confirm", vi.fn(() => false))
    const canvas = makeCanvas({
      previewMode: true,
      canMutate() { return !this.isReadOnly && !this.previewMode },
    })
    const collapsed = { elements: [{ id: "subflow" }], connections: [] }
    const self = stub({ canvas, _collapsedPreviewConfiguration: collapsed, subflowManager: { expandedSubflows: { s1: {} } } })
    call("clear", self)
    expect(canvas.restoreGraph).toHaveBeenCalledWith(collapsed)
    expect(canvas.previewMode).toBe(false)
    expect(canvas.clear).not.toHaveBeenCalled()
  })

  it("autoLayout, routing cycle, palette drop and alignment hide when canMutate is false", () => {
    const bar = document.createElement("div")
    const canvas = makeCanvas({
      selectedElements: [{}, {}],
      canMutate: () => false,
      autoLayout: vi.fn(),
      cycleConnectionRouting: vi.fn(),
    })
    const self = stub({
      canvas,
      hasAlignmentToolbarTarget: true,
      alignmentToolbarTarget: bar,
    })
    self._updateAlignmentToolbar = Controller.prototype._updateAlignmentToolbar
    call("autoLayout", self)
    call("cycleConnectionRouting", self)
    call("_handleElementDrop", self, { detail: { elementType: "process", x: 0, y: 0 } })
    call("_updateAlignmentToolbar", self)
    expect(canvas.autoLayout).not.toHaveBeenCalled()
    expect(canvas.cycleConnectionRouting).not.toHaveBeenCalled()
    expect(canvas.addElement).not.toHaveBeenCalled()
    expect(bar.classList.contains("hidden")).toBe(true)
  })

  it("_ensureElementsInView fits content only when an element overflows the current viewport", () => {
    const fitToContent = vi.fn()
    const base = { fitToContent }
    // Missing zpm or empty elements -> no-op
    call("_ensureElementsInView", { ...base, canvas: null })
    call("_ensureElementsInView", { ...base, canvas: { zoomPanManager: {}, elements: [] } })
    // Zero viewport size -> no-op
    call("_ensureElementsInView", {
      ...base,
      canvas: { zoomPanManager: { viewWidth: 0, viewHeight: 500, panX: 0, panY: 0 }, elements: [{ x: 400, y: 80, width: 100, height: 45 }] }
    })
    expect(fitToContent).not.toHaveBeenCalled()

    // Fits comfortably -> no-op
    call("_ensureElementsInView", {
      ...base,
      canvas: { zoomPanManager: { viewWidth: 1000, viewHeight: 800, panX: 0, panY: 0 }, elements: [{ x: 400, y: 80, width: 100, height: 45 }] }
    })
    expect(fitToContent).not.toHaveBeenCalled()

    // Overflows left, right, top, or bottom -> fits
    for (const el of [
      { x: 10, y: 80, width: 100, height: 45 },
      { x: 400, y: 80, width: 100, height: 45 },
      { x: 100, y: 10, width: 100, height: 45 },
      { x: 100, y: 490, width: 100, height: 45 },
    ]) {
      fitToContent.mockClear()
      call("_ensureElementsInView", {
        ...base,
        canvas: { zoomPanManager: { viewWidth: 215, viewHeight: 500, panX: 0, panY: 0 }, elements: [el] }
      })
      expect(fitToContent).toHaveBeenCalledOnce()
    }
  })

  it("_syncPreviewChrome hides handles, updates element cursors, and dispatches mutability events", () => {
    const elementLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
    const group = document.createElementNS("http://www.w3.org/2000/svg", "g")
    group.setAttribute("data-element-id", "e1")
    elementLayer.appendChild(group)
    const root = document.createElement("div")
    const events = []
    root.addEventListener("flowchartMutabilityChanged", (e) => events.push(e.detail.canMutate))

    let mutable = false
    const canvas = makeCanvas({
      previewMode: true,
      canMutate: () => mutable,
      elementLayer,
      _hideConnectionHandles: vi.fn(),
      _hideConnectionEndpointHandles: vi.fn(),
      hideResizeHandles: vi.fn(),
    })
    const self = stub({ element: root, canvas, hasPropertySidebarTarget: false })
    call("_syncPreviewChrome", self)
    expect(canvas._hideConnectionHandles).toHaveBeenCalled()
    expect(canvas._hideConnectionEndpointHandles).toHaveBeenCalled()
    expect(canvas.hideResizeHandles).toHaveBeenCalled()
    expect(group.style.cursor).toBe("pointer")

    mutable = true
    call("_syncPreviewChrome", self)
    expect(group.style.cursor).toBe("move")
    expect(events).toEqual([false, true])
  })
})
