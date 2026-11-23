import { describe, it, expect, vi, afterEach } from "vitest"
import Controller from "controllers/page_builder_controller"
import { mountController, tick } from "../support/stimulus.js"

// Force one manager's constructor to throw so connect()'s graceful-degradation
// catch (initManager) is exercised. DropMutations is otherwise unused by connect.
vi.mock("controllers/page_builder/drop_mutations", () => ({
  DropMutations: class { constructor() { throw new Error("boom") } },
}))

// A manager stub that lazily returns a stable vi.fn() for any accessed method.
function spyMgr() {
  const cache = {}
  return new Proxy({}, { get: (_t, p) => (cache[p] || (cache[p] = vi.fn())) })
}
const MANAGERS = [
  "undoRedoManager", "viewportManager", "tabManager", "dragDropManager", "fieldManager",
  "pageManager", "propertyManager", "saveManager", "keyboardManager", "selectionManager",
  "inserterManager", "rulesManager", "calculationsManager", "inlineEditManager",
  "clipboardManager", "resizeManager", "commandPaletteManager", "zoomManager",
  "contextMenuManager", "dragVisuals", "dropResolver", "dropMutations", "dragEngine",
]
function delegCtx() {
  const ctx = Object.create(Controller.prototype)
  MANAGERS.forEach((m) => { ctx[m] = spyMgr() })
  return ctx
}

// NOTE: PageBuilderController is a thin orchestrator whose connect() instantiates
// ~24 collaborating managers (drag/drop, zoom, rules, calculations, resize, etc.)
// and immediately drives keyboard/click-outside bindings + full canvas re-render.
// Most of that is geometry/pointer or manager-owned behavior — covered by Playwright
// (spec/e2e), not happy-dom. Here we characterize the controller's OWN pure logic:
// state initialization, the page/field getters, and the panel filter — exercised
// directly against the prototype without mounting the manager graph.

// Build a fake `this` bound to the real prototype so getters resolve, with the
// Stimulus value accessors it reads stubbed as plain props.
const makeCtx = (configValue, activePage = "page_1") => {
  const ctx = Object.create(Controller.prototype)
  ctx.configurationValue = configValue
  ctx.hasUpdatedAtValue = false
  ctx.activePageValue = activePage
  return ctx
}

describe("PageBuilderController — initializeState", () => {
  it("parses configuration JSON and seeds a default page + theme", () => {
    const ctx = makeCtx(JSON.stringify({ pages: [], metadata: {} }))
    ctx.initializeState()
    expect(ctx.configuration.pages).toHaveLength(1)
    expect(ctx.configuration.pages[0].id).toBe("page_1")
    expect(ctx.configuration.theme.primary_color).toBe("indigo")
    expect(ctx.isDirty).toBe(false)
    expect(ctx.undoStack).toEqual([])
    expect(ctx.maxHistorySize).toBe(50)
  })

  it("recovers from malformed JSON into an empty config", () => {
    const ctx = makeCtx("{not json")
    ctx.initializeState()
    expect(ctx.configuration.pages).toHaveLength(1) // default page injected
    expect(ctx.metadata).toEqual({})
  })

  it("keeps existing pages and a supplied theme", () => {
    const cfg = {
      pages: [{ id: "p1", name: "One", order: 1, fields: [{ id: "f1" }] }],
      theme: { primary_color: "emerald" },
      metadata: { foo: "bar" },
    }
    const ctx = makeCtx(JSON.stringify(cfg), "p1")
    ctx.initializeState()
    expect(ctx.configuration.pages).toHaveLength(1)
    expect(ctx.configuration.theme.primary_color).toBe("emerald")
    expect(ctx.metadata).toEqual({ foo: "bar" })
  })

  it("falls back activePage to the first page when the stored one is missing", () => {
    const cfg = { pages: [{ id: "pX", name: "X", order: 1, fields: [] }], metadata: {} }
    const ctx = makeCtx(JSON.stringify(cfg), "does_not_exist")
    ctx.initializeState()
    expect(ctx.activePageValue).toBe("pX")
  })
})

describe("PageBuilderController — state/getter edge branches", () => {
  it("defaults the configuration when the value is empty (`|| '{...}'`)", () => {
    const ctx = makeCtx(undefined)
    ctx.initializeState()
    expect(ctx.configuration.pages).toHaveLength(1)
    expect(ctx.metadata).toEqual({}) // configuration.metadata undefined → {}
  })

  it("defaults metadata to {} when the parsed configuration omits it", () => {
    const ctx = makeCtx(JSON.stringify({ pages: [{ id: "p1", fields: [] }] }), "p1") // no metadata key
    ctx.initializeState()
    expect(ctx.metadata).toEqual({})
  })

  it("uses updatedAtValue when hasUpdatedAtValue is true", () => {
    const ctx = makeCtx(JSON.stringify({ pages: [{ id: "p1", fields: [] }], metadata: {} }), "p1")
    ctx.hasUpdatedAtValue = true
    ctx.updatedAtValue = "2026-01-01"
    ctx.initializeState()
    expect(ctx.lastSavedAt).toBe("2026-01-01")
  })

  it("falls back the active page to 'page_1' when the first page carries no id", () => {
    const ctx = makeCtx(JSON.stringify({ pages: [{ name: "NoId", fields: [] }], metadata: {} }), "missing")
    ctx.initializeState()
    expect(ctx.activePageValue).toBe("page_1")
  })

  it("currentPageFields defaults to [] when the active page has no fields array", () => {
    const ctx = makeCtx(JSON.stringify({ pages: [{ id: "p1", name: "P1" }], metadata: {} }), "p1")
    ctx.initializeState()
    expect(ctx.currentPageFields).toEqual([])
  })

  it("allFields tolerates pages/columns/groups with missing child arrays", () => {
    const cfg = { pages: [
      { id: "p1" }, // no fields
      { id: "p2", fields: [
        { id: "cols", field_type: "columns" },          // no columns
        { id: "cols2", field_type: "columns", columns: [{}] }, // column w/o fields
        { id: "grp", type: "field_group" },             // no fields
      ] },
    ], metadata: {} }
    const ctx = makeCtx(JSON.stringify(cfg), "p1")
    ctx.initializeState()
    expect(ctx.allFields.map((f) => f.id).sort()).toEqual(["cols", "cols2", "grp"])
  })

  it("allFields / allPages default to [] when configuration.pages is undefined", () => {
    const ctx = makeCtx(JSON.stringify({ pages: [{ id: "p1", fields: [] }], metadata: {} }), "p1")
    ctx.initializeState()
    ctx.configuration.pages = undefined
    expect(ctx.allFields).toEqual([])
    expect(ctx.allPages).toEqual([])
  })
})

describe("PageBuilderController — getters", () => {
  const cfg = {
    pages: [
      { id: "p1", name: "One", order: 1, fields: [
        { id: "a", field_type: "text" },
        { id: "cols", field_type: "columns", columns: [{ fields: [{ id: "c1" }] }, { fields: [{ id: "c2" }] }] },
        { id: "grp", type: "field_group", fields: [{ id: "g1" }] },
      ] },
      { id: "p2", name: "Two", order: 2, fields: [{ id: "b" }] },
    ],
    metadata: {},
  }

  it("currentPage / currentPageFields resolve the active page", () => {
    const ctx = makeCtx(JSON.stringify(cfg), "p2")
    ctx.initializeState()
    expect(ctx.currentPage.id).toBe("p2")
    expect(ctx.currentPageFields.map(f => f.id)).toEqual(["b"])
  })

  it("currentPage falls back to the first page for an unknown active id", () => {
    const ctx = makeCtx(JSON.stringify(cfg), "p1")
    ctx.initializeState()
    ctx.activePageValue = "ghost"
    expect(ctx.currentPage.id).toBe("p1")
  })

  it("allFields flattens columns and field_groups", () => {
    const ctx = makeCtx(JSON.stringify(cfg), "p1")
    ctx.initializeState()
    const ids = ctx.allFields.map(f => f.id)
    expect(ids).toEqual(expect.arrayContaining(["a", "cols", "c1", "c2", "grp", "g1", "b"]))
  })

  it("allPages returns the configured pages", () => {
    const ctx = makeCtx(JSON.stringify(cfg), "p1")
    ctx.initializeState()
    expect(ctx.allPages.map(p => p.id)).toEqual(["p1", "p2"])
  })
})

describe("PageBuilderController — delegated actions (event forwarded)", () => {
  // [controllerMethod, managerProp, managerMethod]
  const cases = [
    ["setViewport", "viewportManager", "setViewport"],
    ["switchTab", "tabManager", "switchTab"],
    ["searchComponents", "tabManager", "searchComponents"],
    ["toggleCategory", "tabManager", "toggleCategory"],
    ["toggleSubsection", "tabManager", "toggleSubsection"],
    ["filterSidebar", "tabManager", "filterSidebar"],
    ["selectEntity", "tabManager", "selectEntity"],
    ["onEntityChange", "tabManager", "onEntityChange"],
    ["dragPointerDown", "dragEngine", "pointerDown"],
    ["addField", "fieldManager", "addField"],
    ["addAllFieldsFromSection", "fieldManager", "addAllFieldsFromSection"],
    ["removeAllFieldsFromSection", "fieldManager", "removeAllFieldsFromSection"],
    ["selectField", "fieldManager", "selectField"],
    ["selectSection", "fieldManager", "selectSection"],
    ["updateField", "fieldManager", "updateField"],
    ["removeFieldFromCard", "fieldManager", "removeFieldFromCard"],
    ["duplicateFieldFromCard", "fieldManager", "duplicateFieldFromCard"],
    ["ungroupFields", "fieldManager", "ungroupFields"],
    ["saveFieldAsTemplate", "fieldManager", "saveFieldAsTemplate"],
    ["showDependencyLines", "fieldManager", "showDependencyLines"],
    ["switchPage", "pageManager", "switchPage"],
    ["deletePage", "pageManager", "deletePage"],
    ["renamePage", "pageManager", "renamePage"],
    ["pageTabDragStart", "pageManager", "pageTabDragStart"],
    ["pageTabDragEnd", "pageManager", "pageTabDragEnd"],
    ["pageTabDragOver", "pageManager", "pageTabDragOver"],
    ["pageTabDrop", "pageManager", "pageTabDrop"],
    ["updateFieldProperty", "propertyManager", "updateFieldProperty"],
    ["updateFieldSlug", "propertyManager", "updateFieldSlug"],
    ["toggleSection", "propertyManager", "toggleSection"],
    ["updateCondition", "propertyManager", "updateCondition"],
    ["removeCondition", "propertyManager", "removeCondition"],
    ["addOption", "propertyManager", "addOption"],
    ["removeOption", "propertyManager", "removeOption"],
    ["updateOption", "propertyManager", "updateOption"],
    ["updateFormSettings", "propertyManager", "updateFormSettings"],
    ["updateWizardSettings", "propertyManager", "updateWizardSettings"],
    ["updateTheme", "propertyManager", "updateTheme"],
    ["applyThemePreset", "propertyManager", "applyThemePreset"],
    ["updateColumnLayout", "propertyManager", "updateColumnLayout"],
    ["setFieldWidth", "propertyManager", "setFieldWidth"],
    ["switchBreakpoint", "propertyManager", "switchBreakpoint"],
    ["resetBreakpointWidth", "propertyManager", "resetBreakpointWidth"],
    ["switchPropertyTab", "propertyManager", "switchPropertyTab"],
    ["breadcrumbNavigate", "propertyManager", "breadcrumbNavigate"],
    ["breadcrumbHighlight", "propertyManager", "breadcrumbHighlight"],
    ["breadcrumbUnhighlight", "propertyManager", "breadcrumbUnhighlight"],
    ["openInserterPopover", "inserterManager", "openPopover"],
    ["filterInserterPopover", "inserterManager", "filterPopover"],
    ["insertFromPopover", "inserterManager", "insertFromPopover"],
    ["insertFromToolbar", "inserterManager", "insertFromToolbar"],
    ["openFullCatalog", "inserterManager", "openFullCatalog"],
    ["closeMoveToPageModalOnBackdrop", "selectionManager", "closeMoveToPageModalOnBackdrop"],
    ["canvasMouseDown", "selectionManager", "startRubberBand"],
    ["canvasMouseMove", "selectionManager", "updateRubberBand"],
    ["canvasMouseUp", "selectionManager", "endRubberBand"],
    ["bulkSetWidth", "selectionManager", "bulkSetWidth"],
    ["openRuleEditor", "rulesManager", "openRuleEditor"],
    ["closeRuleEditorOnBackdrop", "rulesManager", "closeRuleEditorOnBackdrop"],
    ["editRule", "rulesManager", "editRule"],
    ["deleteRule", "rulesManager", "deleteRule"],
    ["toggleRule", "rulesManager", "toggleRule"],
    ["duplicateRule", "rulesManager", "duplicateRule"],
    ["removeConditionGroup", "rulesManager", "removeConditionGroup"],
    ["addConditionItem", "rulesManager", "addConditionItem"],
    ["removeConditionItem", "rulesManager", "removeConditionItem"],
    ["removeAction", "rulesManager", "removeAction"],
    ["onActionTypeChange", "rulesManager", "onActionTypeChange"],
    ["openFormulaEditor", "calculationsManager", "openFormulaEditor"],
    ["closeFormulaEditorOnBackdrop", "calculationsManager", "closeFormulaEditorOnBackdrop"],
    ["editCalculation", "calculationsManager", "editCalculation"],
    ["deleteCalculation", "calculationsManager", "deleteCalculation"],
    ["insertFieldReference", "calculationsManager", "insertFieldReference"],
    ["insertFunction", "calculationsManager", "insertFunction"],
    ["startInlineEdit", "inlineEditManager", "startEdit"],
    ["startResize", "resizeManager", "startResize"],
    ["filterCommandPalette", "commandPaletteManager", "filter"],
    ["commandPaletteKeydown", "commandPaletteManager", "handleKeydown"],
    ["executeCommandPaletteResult", "commandPaletteManager", "executeFromClick"],
    ["filterCanvasSearch", "zoomManager", "filterSearch"],
    ["canvasSearchKeydown", "zoomManager", "searchKeydown"],
    ["openFieldContextMenu", "contextMenuManager", "openForField"],
    ["openCanvasContextMenu", "contextMenuManager", "openForCanvas"],
  ]

  it.each(cases)("%s forwards the event to %s.%s", (method, mgr, target) => {
    const ctx = delegCtx()
    const evt = { sentinel: method }
    ctx[method](evt)
    expect(ctx[mgr][target]).toHaveBeenCalledWith(evt)
  })
})

describe("PageBuilderController — delegated actions (no argument)", () => {
  const cases = [
    ["undo", "undoRedoManager", "undo"],
    ["redo", "undoRedoManager", "redo"],
    ["saveState", "undoRedoManager", "saveState"],
    ["saveHistory", "undoRedoManager", "saveHistory"],
    ["closeAllTabPanels", "tabManager", "closeAllTabPanels"],
    ["deselectField", "fieldManager", "deselectField"],
    ["duplicateField", "fieldManager", "duplicateField"],
    ["deleteField", "fieldManager", "deleteField"],
    ["duplicateSelectedField", "fieldManager", "duplicateSelectedField"],
    ["deleteSelectedField", "fieldManager", "deleteSelectedField"],
    ["addPage", "pageManager", "addPage"],
    ["addCondition", "propertyManager", "addCondition"],
    ["showFormSettings", "propertyManager", "showFormSettings"],
    ["updateSubmissionModes", "propertyManager", "updateSubmissionModes"],
    ["updatePageInputs", "propertyManager", "updatePageInputs"],
    ["closeInserterPopover", "inserterManager", "closePopover"],
    ["selectAllFields", "selectionManager", "selectAll"],
    ["openMoveToPageModal", "selectionManager", "openMoveToPageModal"],
    ["closeMoveToPageModal", "selectionManager", "closeMoveToPageModal"],
    ["confirmMoveToPage", "selectionManager", "confirmMoveToPage"],
    ["bulkDuplicate", "clipboardManager", "duplicateSelected"],
    ["bulkDelete", "selectionManager", "bulkDelete"],
    ["groupIntoSection", "selectionManager", "groupIntoSection"],
    ["save", "saveManager", "save"],
    ["preview", "saveManager", "preview"],
    ["dismissSettingsError", "saveManager", "hideModalError"],
    ["showShortcuts", "keyboardManager", "showShortcuts"],
    ["hideShortcuts", "keyboardManager", "hideShortcuts"],
    ["closeRuleEditor", "rulesManager", "closeRuleEditor"],
    ["saveRule", "rulesManager", "saveRule"],
    ["addConditionGroup", "rulesManager", "addConditionGroup"],
    ["addAction", "rulesManager", "addAction"],
    ["closeFormulaEditor", "calculationsManager", "closeFormulaEditor"],
    ["saveCalculation", "calculationsManager", "saveCalculation"],
    ["copyField", "clipboardManager", "copy"],
    ["cutField", "clipboardManager", "cut"],
    ["pasteField", "clipboardManager", "paste"],
    ["openCommandPalette", "commandPaletteManager", "open"],
    ["closeCommandPalette", "commandPaletteManager", "close"],
    ["zoomIn", "zoomManager", "zoomIn"],
    ["zoomOut", "zoomManager", "zoomOut"],
    ["zoomReset", "zoomManager", "zoomReset"],
    ["toggleMiniMap", "zoomManager", "toggleMiniMap"],
    ["openCanvasSearch", "zoomManager", "openSearch"],
    ["closeCanvasSearch", "zoomManager", "closeSearch"],
    ["closeContextMenu", "contextMenuManager", "close"],
  ]

  it.each(cases)("%s delegates to %s.%s", (method, mgr, target) => {
    const ctx = delegCtx()
    ctx[method]()
    expect(ctx[mgr][target]).toHaveBeenCalled()
  })
})

describe("PageBuilderController — special delegators / modal handlers", () => {
  it("stopPropagation and stopModalClose call stopPropagation on the event", () => {
    const ctx = delegCtx()
    const e1 = { stopPropagation: vi.fn() }
    ctx.stopPropagation(e1)
    expect(e1.stopPropagation).toHaveBeenCalled()
    const e2 = { stopPropagation: vi.fn() }
    ctx.stopModalClose(e2)
    expect(e2.stopPropagation).toHaveBeenCalled()
  })

  it("onModalBackdropClick closes tabs only when the click hits the backdrop itself", () => {
    const ctx = delegCtx()
    const backdrop = document.createElement("div")
    ctx.onModalBackdropClick({ target: backdrop, currentTarget: backdrop })
    expect(ctx.tabManager.closeAllTabPanels).toHaveBeenCalledTimes(1)
    ctx.onModalBackdropClick({ target: document.createElement("div"), currentTarget: backdrop })
    expect(ctx.tabManager.closeAllTabPanels).toHaveBeenCalledTimes(1) // unchanged
  })

  it("closeModalsOnEscape closes open tab panels only on Escape", () => {
    const ctx = delegCtx()
    const open = document.createElement("div")
    const hidden = document.createElement("div"); hidden.classList.add("hidden")
    ctx.tabPanelTargets = [open, hidden]
    ctx.closeModalsOnEscape({ key: "a" }) // not escape → ignored
    expect(ctx.tabManager.closeAllTabPanels).not.toHaveBeenCalled()
    ctx.closeModalsOnEscape({ key: "Escape" }) // one panel open → close
    expect(ctx.tabManager.closeAllTabPanels).toHaveBeenCalled()
  })

  it("closeModalsOnEscape does nothing when every panel is already hidden", () => {
    const ctx = delegCtx()
    const hidden = document.createElement("div"); hidden.classList.add("hidden")
    ctx.tabPanelTargets = [hidden]
    ctx.closeModalsOnEscape({ key: "Escape" })
    expect(ctx.tabManager.closeAllTabPanels).not.toHaveBeenCalled()
  })

  it("openRulesForField switches to the rules tab", () => {
    const ctx = delegCtx()
    const rulesBtn = document.createElement("button"); rulesBtn.dataset.tab = "rules"
    ctx.tabButtonTargets = [document.createElement("button"), rulesBtn]
    ctx.openRulesForField({})
    expect(ctx.tabManager.switchTab).toHaveBeenCalledWith({ currentTarget: rulesBtn })
  })
})

describe("PageBuilderController — connect / disconnect (mounted)", () => {
  afterEach(() => { document.body.innerHTML = "" })

  it("connect instantiates managers, survives a failing manager, and initializes state", async () => {
    const errSpy = vi.spyOn(console, "error").mockImplementation(() => {})
    const html = `<div data-controller="page-builder"
      data-page-builder-configuration-value='{"pages":[],"metadata":{}}'
      data-page-builder-active-page-value="page_1"></div>`
    const { application, element } = await mountController("page-builder", Controller, html)
    const ctrl = application.getControllerForElementAndIdentifier(element, "page-builder")
    expect(ctrl.fieldManager).toBeTruthy()
    expect(ctrl.dropMutations).toBeNull() // the throwing manager degraded to null
    expect(errSpy).toHaveBeenCalledWith(expect.stringContaining("DropMutations"), expect.any(Error))
    expect(ctrl.configuration.pages).toHaveLength(1)

    // beforeunload handler honours the dirty flag
    ctrl.isDirty = true
    const evt = new Event("beforeunload", { cancelable: true })
    window.dispatchEvent(evt)
    expect(evt.defaultPrevented).toBe(true)

    // the document keydown handler (_onKeydown) routes Escape to the controller
    const spy = vi.spyOn(ctrl, "closeModalsOnEscape")
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))
    expect(spy).toHaveBeenCalled()

    // removing the element drives Stimulus disconnect()
    element.remove()
    await tick()
    application.stop()
    errSpy.mockRestore()
  })

  it("disconnect skips the keydown-listener removal when _onKeydown was never assigned", () => {
    const self = {
      fieldManager: { cleanup: vi.fn() },
      keyboardManager: { unbindKeyboardShortcuts: vi.fn(), unbindClickOutside: vi.fn() },
      selectionManager: { cleanupRubberBand: vi.fn() },
      _beforeUnload: () => {},
      // _onKeydown intentionally absent -> exercises the `if (this._onKeydown)` false side
    }
    const removeSpy = vi.spyOn(document, "removeEventListener")
    expect(() => Controller.prototype.disconnect.call(self)).not.toThrow()
    expect(removeSpy).not.toHaveBeenCalledWith("keydown", expect.anything())
    removeSpy.mockRestore()
  })

  it("disconnect removes the keydown listener when _onKeydown is set", () => {
    const onKeydown = () => {}
    const self = {
      fieldManager: { cleanup: vi.fn() },
      keyboardManager: { unbindKeyboardShortcuts: vi.fn(), unbindClickOutside: vi.fn() },
      selectionManager: { cleanupRubberBand: vi.fn() },
      _beforeUnload: () => {},
      _onKeydown: onKeydown,
    }
    const removeSpy = vi.spyOn(document, "removeEventListener")
    Controller.prototype.disconnect.call(self)
    expect(removeSpy).toHaveBeenCalledWith("keydown", onKeydown)
    removeSpy.mockRestore()
  })
})

describe("PageBuilderController — filterPanel", () => {
  const buildPanel = () => {
    document.body.innerHTML = `
      <div data-rules-panel>
        <input data-filter-panel="rules-panel" data-filter-items="rule-id" data-role="input" />
        <div data-rule-id="1">Discount rule</div>
        <div data-rule-id="2">Shipping toggle</div>
      </div>`
    return document.querySelector("[data-role='input']")
  }

  it("hides items whose text does not include the query", () => {
    const input = buildPanel()
    input.value = "discount"
    Controller.prototype.filterPanel.call({}, { currentTarget: input })
    expect(document.querySelector("[data-rule-id='1']").classList.contains("hidden")).toBe(false)
    expect(document.querySelector("[data-rule-id='2']").classList.contains("hidden")).toBe(true)
  })

  it("clears hiding when the query is emptied", () => {
    const input = buildPanel()
    input.value = ""
    Controller.prototype.filterPanel.call({}, { currentTarget: input })
    expect(document.querySelector("[data-rule-id='2']").classList.contains("hidden")).toBe(false)
  })

  it("no-ops when the filter data attributes are missing", () => {
    document.body.innerHTML = `<input data-role="x" />`
    const input = document.querySelector("[data-role='x']")
    expect(() => Controller.prototype.filterPanel.call({}, { currentTarget: input })).not.toThrow()
  })

  it("no-ops when no matching panel ancestor is found", () => {
    document.body.innerHTML = `<input data-filter-panel="rules-panel" data-filter-items="rule-id" data-role="y" />`
    const input = document.querySelector("[data-role='y']")
    input.value = "q"
    expect(() => Controller.prototype.filterPanel.call({}, { currentTarget: input })).not.toThrow()
  })
})
