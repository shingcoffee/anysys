// PropertyEditorController is a Stimulus controller composing several plain-class
// managers + mixins. Heavy flows (openEditor→buildForm, save→collect→persist)
// depend on a full FlowchartCanvas and on collectBranches/collectSteps, whose
// input[name*='[...]'] selectors happy-dom mis-parses — those are Playwright-
// covered. Here we mount the controller and exercise the DOM-structural surface:
// escaping, tab-pane routing, connection editing, sidebar visibility, read-only
// detection, keyboard handling, and pre-save validation.
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/property_editor_controller"
import { mountController, controllerFor } from "../support/stimulus.js"
import { mountEditor } from "./property_editor/behavior/_support.js"
import { clearElementCatalog, installSampleElementCatalog } from "../support/element_catalog.js"

const HTML = `
  <div data-controller="property-editor">
    <div data-property-editor-target="sidebar" class="hidden">
      <div data-property-editor-target="headerWrapper">
        <span data-property-editor-target="title"></span>
        <span data-property-editor-target="typeIndicator"></span>
        <span data-property-editor-target="typeIcon"><svg><path d=""></path></svg></span>
      </div>
      <form data-property-editor-target="form">
        <div data-property-editor-target="tabPaneGeneral">
          <div data-property-editor-target="formFieldsGeneral"></div>
        </div>
        <div data-property-editor-target="tabPaneSteps">
          <div data-property-editor-target="formFieldsSteps"></div>
        </div>
        <div data-property-editor-target="tabPaneIo">
          <div data-property-editor-target="formFieldsIo"></div>
        </div>
        <div data-property-editor-target="tabPaneAdvanced">
          <div data-property-editor-target="formFieldsAdvanced"></div>
        </div>
      </form>
    </div>
  </div>`

async function mount() {
  const { application, element } = await mountController("property-editor", Controller, HTML)
  const ctrl = controllerFor(application, element, "property-editor")
  return { application, element, ctrl }
}

describe("PropertyEditorController", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element, ctrl } = await mount())
  })
  afterEach(() => {
    vi.useRealTimers()
    document.querySelectorAll('[data-controller*="flowchart-canvas"]').forEach((n) => n.remove())
    application?.stop()
  })

  describe("connect", () => {
    it("initializes managers and per-session state", () => {
      expect(ctrl.stepManager).toBeTruthy()
      expect(ctrl.branchManager).toBeTruthy()
      expect(ctrl.joinManager).toBeUndefined()
      expect(ctrl.elementIoManager).toBeTruthy()
      expect(ctrl.formBuilder).toBeTruthy()
      expect(ctrl.currentElement).toBeNull()
      expect(ctrl.unsavedChangesCache).toBeUndefined()
      expect(ctrl._openSnapshot).toBeNull()
      expect(ctrl.disclosureState instanceof Map).toBe(true)
    })

    it("formFieldsTarget getter aliases the form target", () => {
      expect(ctrl.formFieldsTarget).toBe(ctrl.formTarget)
      expect(ctrl.hasFormFieldsTarget).toBe(true)
    })
  })

  describe("_escapeAttr", () => {
    it("escapes the five HTML-significant characters", () => {
      expect(ctrl._escapeAttr(`a&b"c'd<e>f`)).toBe("a&amp;b&quot;c&#39;d&lt;e&gt;f")
      expect(ctrl._escapeAttr(42)).toBe("42")
    })
  })

  describe("getFormFieldsForTab", () => {
    it("returns the pane-specific container, falling back to the form for unknown tabs", () => {
      expect(ctrl.getFormFieldsForTab("general")).toBe(ctrl.formFieldsGeneralTarget)
      expect(ctrl.getFormFieldsForTab("advanced")).toBe(ctrl.formFieldsAdvancedTarget)
      expect(ctrl.getFormFieldsForTab("bogus")).toBe(ctrl.formTarget)
    })
  })

  describe("_isCanvasReadOnly", () => {
    it("is false when no canvas element is present", () => {
      expect(ctrl._isCanvasReadOnly()).toBe(false)
    })

    it("is true when the canvas element declares read-only", () => {
      const canvasEl = document.createElement("div")
      canvasEl.setAttribute("data-controller", "flowchart-canvas")
      canvasEl.dataset.flowchartCanvasReadOnlyValue = "true"
      document.body.appendChild(canvasEl)
      expect(ctrl._isCanvasReadOnly()).toBe(true)
    })

    it("prefers canvas.canMutate over the data-attribute fallback", () => {
      ctrl.canvas = { canMutate: () => false }
      expect(ctrl._isCanvasReadOnly()).toBe(true)
      ctrl.canvas = { canMutate: () => true }
      expect(ctrl._isCanvasReadOnly()).toBe(false)
    })

    it("reads canMutate from the live flowchartCanvas facade when this.canvas has none", () => {
      const canvasEl = document.createElement("div")
      canvasEl.setAttribute("data-controller", "flowchart-canvas")
      canvasEl.flowchartCanvas = { canMutate: () => false }
      document.body.appendChild(canvasEl)
      expect(ctrl._isCanvasReadOnly()).toBe(true)
    })
  })

  describe("_formOutOfSync", () => {
    it("is false for a non-decision element", () => {
      expect(ctrl._formOutOfSync({ type: "process" })).toBe(false)
    })

    it("is true when the canvas element has outgoing connections the (empty) form lacks", () => {
      ctrl.currentElement = { id: "d", type: "decision" }
      const el = { id: "d", type: "decision", properties: {} }
      ctrl.canvas = { connections: [{ from: "d", to: "e1", fromPort: "port_0", label: "Yes", matchValue: "true" }] }
      expect(ctrl._formOutOfSync(el)).toBe(true)
    })

    it("is false when both sides agree (no branches)", () => {
      const el = { type: "decision", properties: { branches: [] } }
      expect(ctrl._formOutOfSync(el)).toBe(false)
    })
  })

  describe("_buildConnectionForm", () => {
    it("renders catalog label and Notes fields from the connection into the general pane", () => {
      ctrl._buildConnectionForm({ label: "Yes", properties: { description: "d", priority: 5 } })
      const pane = ctrl.formFieldsGeneralTarget
      expect(pane.querySelector('input[name="label"]').value).toBe("Yes")
      expect(pane.querySelector('textarea[name="description"]').textContent).toContain("d")
      expect(pane.querySelector('input[name="connectionPriority"]')).toBeNull()
    })

    it("does not expose match values for Decision connections", () => {
      ctrl.canvas = { elements: [{ id: "d1", type: "decision" }] }
      ctrl._buildConnectionForm({ from: "d1", matchValue: "true", properties: {} })
      expect(ctrl.formFieldsGeneralTarget.querySelector('input[name="connectionMatchValue"]')).toBeNull()
    })
  })

  describe("openConnectionEditor", () => {
    it("shows the sidebar, sets the connection title, and builds the connection form", () => {
      const canvas = { updateConnectionProperties: vi.fn() }
      ctrl.openConnectionEditor({ id: "c1", label: "Approved", properties: {} }, canvas)
      expect(ctrl.currentConnection).toEqual(expect.objectContaining({ id: "c1" }))
      expect(ctrl.currentElement).toBeNull()
      expect(ctrl.titleTarget.textContent).toBe("Connection Properties")
      expect(ctrl.sidebarTarget.classList.contains("hidden")).toBe(false)
      expect(ctrl.formFieldsGeneralTarget.querySelector('input[name="label"]').value).toBe("Approved")
    })
  })

  describe("undo coalesce key", () => {
    const focus = (field, type) => field.dispatchEvent(new FocusEvent(type, { bubbles: true }))

    it("keys a focused connection field and commits its last debounced edit under that key on blur", () => {
      vi.useFakeTimers()
      const keysAtUpdate = []
      const canvas = { updateConnectionProperties: vi.fn(() => keysAtUpdate.push(canvas.undoCoalesceKey)) }
      ctrl.openConnectionEditor({ id: "c1", label: "Old", properties: {} }, canvas)
      const label = ctrl.formTarget.querySelector('input[name="label"]')

      focus(label, "focusin")
      const key = canvas.undoCoalesceKey
      expect(key).toMatch(/^c1:label#\d+$/)
      label.value = "New"
      label.dispatchEvent(new Event("input", { bubbles: true }))
      focus(label, "focusout")

      expect(keysAtUpdate).toEqual([key])
      expect(canvas.updateConnectionProperties).toHaveBeenCalledWith("c1", "New", { description: "" })
      expect(canvas.undoCoalesceKey).toBeNull()
      vi.advanceTimersByTime(200)
      expect(canvas.updateConnectionProperties).toHaveBeenCalledTimes(1)
    })

    it("opening another selection clears a key left on the previous canvas", () => {
      const canvas = { updateConnectionProperties: vi.fn() }
      ctrl.openConnectionEditor({ id: "c1", properties: {} }, canvas)
      canvas.undoCoalesceKey = "c1:label"
      ctrl.openConnectionEditor({ id: "c2", properties: {} }, canvas)
      expect(canvas.undoCoalesceKey).toBeNull()

      canvas.undoCoalesceKey = "c2:label"
      vi.spyOn(ctrl.formBuilder, "buildForm").mockImplementation(() => {})
      vi.spyOn(ctrl.formBuilder, "_autoDeriveLabelOnOpen").mockImplementation(() => {})
      ctrl.openEditor({ id: "p1", type: "process", properties: {} }, canvas)
      expect(canvas.undoCoalesceKey).toBeNull()
    })

    it("closing clears the key before the cancel-restore commits", () => {
      const canvas = { updateConnectionProperties: vi.fn() }
      ctrl.openConnectionEditor({ id: "c1", properties: {} }, canvas)
      canvas.undoCoalesceKey = "c1:label"
      let keyAtRestore
      vi.spyOn(ctrl, "_restoreOpenSnapshotIfChanged").mockImplementation(() => { keyAtRestore = canvas.undoCoalesceKey })
      ctrl.close()
      expect(keyAtRestore).toBeNull()
      expect(canvas.undoCoalesceKey).toBeNull()
    })
  })

  describe("sidebar visibility", () => {
    it("cancel hides the sidebar and prevents default", () => {
      ctrl._showSidebar()
      const preventDefault = vi.fn()
      ctrl.cancel({ preventDefault })
      expect(preventDefault).toHaveBeenCalled()
      expect(ctrl.sidebarTarget.classList.contains("hidden")).toBe(true)
    })

    it("close hides the sidebar", () => {
      ctrl._showSidebar()
      ctrl.close({ preventDefault() {} })
      expect(ctrl.sidebarTarget.classList.contains("hidden")).toBe(true)
    })

    it("Escape keydown hides a visible sidebar unless defaultPrevented", () => {
      ctrl._showSidebar()
      ctrl._handleKeydown({ key: "Escape", defaultPrevented: true })
      expect(ctrl._isSidebarVisible()).toBe(true)
      ctrl._handleKeydown({ key: "Escape" })
      expect(ctrl._isSidebarVisible()).toBe(false)
    })

    it("Escape is a no-op when the sidebar is already hidden", () => {
      expect(ctrl._isSidebarVisible()).toBe(false)
      expect(() => ctrl._handleKeydown({ key: "Escape" })).not.toThrow()
    })

    it("discardAndClose hides the sidebar without a final sync", () => {
      ctrl._showSidebar()
      const sync = vi.spyOn(ctrl, "_performSync")
      ctrl.discardAndClose()
      expect(ctrl._isSidebarVisible()).toBe(false)
      expect(sync).not.toHaveBeenCalled()
    })
  })

  describe("open/cancel snapshot (C3)", () => {
    function stubFormBuilder() {
      vi.spyOn(ctrl.formBuilder, "buildForm").mockImplementation(() => {})
      vi.spyOn(ctrl.formBuilder, "_autoDeriveLabelOnOpen").mockImplementation(() => {})
    }

    function editableCanvas(element) {
      const undoEntries = []
      const onchange = vi.fn(() => {
        undoEntries.push(structuredClone({ label: element.label, properties: element.properties }))
      })
      return {
        updateElementProperties: vi.fn((id, label, properties) => {
          element.label = label
          element.properties = properties
          onchange()
        }),
        onchange,
        undoEntries,
      }
    }

    it("open then Cancel without edits does not update the canvas, fire onchange, or record undo", () => {
      stubFormBuilder()
      const element = { id: "e1", type: "process", label: "Start", properties: { description: "a" } }
      const canvas = editableCanvas(element)
      ctrl.openEditor(element, canvas)
      ctrl.cancel({ preventDefault() {} })
      expect(canvas.updateElementProperties).not.toHaveBeenCalled()
      expect(canvas.onchange).not.toHaveBeenCalled()
      expect(canvas.undoEntries).toEqual([])
    })

    it("open then close (X) without edits does not update the canvas", () => {
      stubFormBuilder()
      const element = { id: "e1", type: "process", label: "Start", properties: { description: "a" } }
      const canvas = editableCanvas(element)
      ctrl.openEditor(element, canvas)
      ctrl.close({ preventDefault() {} })
      expect(canvas.updateElementProperties).not.toHaveBeenCalled()
      expect(canvas.onchange).not.toHaveBeenCalled()
      expect(canvas.undoEntries).toEqual([])
    })

    it("open, edit label, Cancel restores the snapshot with one canvas update", () => {
      stubFormBuilder()
      const element = { id: "e1", type: "process", label: "Start", properties: { description: "a" } }
      const canvas = editableCanvas(element)
      ctrl.openEditor(element, canvas)
      element.label = "Edited"
      element.properties = { description: "b" }
      ctrl.cancel({ preventDefault() {} })
      expect(element.label).toBe("Start")
      expect(element.properties).toEqual({ description: "a" })
      expect(canvas.updateElementProperties).toHaveBeenCalledTimes(1)
      expect(canvas.updateElementProperties).toHaveBeenCalledWith("e1", "Start", { description: "a" }, true)
    })

    it("open, edit, Save keeps the changes and auto-hide does not re-sync", async () => {
      stubFormBuilder()
      const element = { id: "e1", type: "process", label: "Start", properties: { description: "a" } }
      const canvas = editableCanvas(element)
      ctrl.openEditor(element, canvas)
      vi.spyOn(ctrl, "_validateBeforeSave").mockReturnValue(true)
      vi.spyOn(ctrl, "_collectFormData").mockReturnValue({ label: "Saved", description: "kept" })
      vi.spyOn(ctrl, "_deriveLabelFromProperties").mockReturnValue("Saved")
      vi.spyOn(ctrl, "_saveToDatabase").mockResolvedValue(true)
      vi.spyOn(ctrl, "_showSaveSuccess")
      vi.spyOn(ctrl, "_dispatchChange")
      vi.useFakeTimers()
      await ctrl.save({ preventDefault() {} })
      expect(element.label).toBe("Saved")
      expect(element.properties).toEqual({ description: "kept" })
      canvas.updateElementProperties.mockClear()
      ctrl._dispatchChange.mockClear()
      const performSync = vi.spyOn(ctrl, "_performSync")
      vi.advanceTimersByTime(500)
      expect(element.label).toBe("Saved")
      expect(element.properties).toEqual({ description: "kept" })
      expect(performSync).not.toHaveBeenCalled()
      expect(canvas.updateElementProperties).not.toHaveBeenCalled()
      expect(ctrl._dispatchChange).not.toHaveBeenCalled()
    })

    it("reopening after an undo shows the undone state (no unsavedChangesCache)", () => {
      stubFormBuilder()
      const element = { id: "e1", type: "process", label: "Orig", properties: { description: "a" } }
      const canvas = { updateElementProperties: vi.fn() }
      ctrl.openEditor(element, canvas)
      element.label = "Edited"
      element.properties = { description: "stale" }
      ctrl._performSync()
      element.label = "Orig"
      element.properties = { description: "a" }
      ctrl.discardAndClose()
      ctrl.openEditor(element, canvas)
      expect(ctrl.currentElement.label).toBe("Orig")
      expect(ctrl.currentElement.properties).toEqual({ description: "a" })
      expect(ctrl.unsavedChangesCache).toBeUndefined()
    })

    it("cancel drops a pending debounced sync so it cannot rewrite the snapshot", () => {
      vi.useFakeTimers()
      stubFormBuilder()
      const element = { id: "e1", type: "process", label: "Start", properties: { description: "a" } }
      const canvas = editableCanvas(element)
      ctrl.openEditor(element, canvas)
      ctrl._syncChangesToCanvas()
      ctrl.cancel({ preventDefault() {} })
      vi.advanceTimersByTime(100)
      expect(canvas.updateElementProperties).not.toHaveBeenCalled()
    })
  })

  describe("open/cancel with the real derive path (C3)", () => {
    let editor

    afterEach(async () => {
      await editor?.dispose()
      editor = null
    })

    it("open a default-labeled process with a step then Cancel does not update the canvas or record undo", async () => {
      editor = await mountEditor("process", {
        steps: [{ id: "s1", action: "new_model", config: { resultVar: "order" } }],
      })
      editor.controller.discardAndClose()
      editor.node.label = "Process"
      const update = vi.spyOn(editor.canvas, "updateElementProperties")
      const onchange = vi.fn()
      editor.canvas.onchange = onchange
      editor.controller.openEditor(editor.node, editor.canvas)
      expect(editor.node.label).toBe("Process")
      editor.controller.cancel({ preventDefault() {} })
      expect(editor.node.label).toBe("Process")
      expect(update).not.toHaveBeenCalled()
      expect(onchange).not.toHaveBeenCalled()
    })

    it("Cancel after adding a branch restores the graph and leaves zoom/pan unchanged", async () => {
      editor = await mountEditor("decision", { branches: [] })
      const zpm = editor.canvas.zoomPanManager
      zpm.panX = 40
      zpm.panY = 50
      const zoom = zpm.zoom
      const snapshotBranches = structuredClone(editor.node.properties.branches || [])
      const idsBefore = editor.canvas.elements.map((el) => el.id)
      editor.controller.addBranch({ preventDefault() {} })
      const created = editor.canvas.elements.find((el) => !idsBefore.includes(el.id))
      expect(created).toBeTruthy()
      editor.controller.cancel({ preventDefault() {} })
      expect(editor.canvas.elements.map((el) => el.id)).toEqual(idsBefore)
      expect(editor.canvas.elements.some((el) => el.id === created.id)).toBe(false)
      expect(editor.canvas.connections.some((c) => c.to === created.id)).toBe(false)
      expect(editor.node.properties.branches).toEqual(snapshotBranches)
      expect(zpm.panX).toBe(40)
      expect(zpm.panY).toBe(50)
      expect(zpm.zoom).toBe(zoom)
    })

    it("Cancel after a dropped connection restores the snapshot graph", async () => {
      editor = await mountEditor("process", {})
      const child = {
        id: "child-1",
        type: "process",
        label: "Yes",
        x: 200,
        y: 240,
        width: 160,
        height: 60,
        properties: {},
      }
      editor.canvas.elements.push(child)
      editor.canvas.renderElement(child)
      editor.canvas.createConnection(editor.node, child, "bottom", "top")
      editor.controller.discardAndClose()
      editor.controller.openEditor(editor.node, editor.canvas)
      const beforeIds = editor.canvas.connections.map((c) => c.id)
      editor.canvas.connections = editor.canvas.connections.filter((c) => c.to !== "child-1")
      editor.controller.cancel({ preventDefault() {} })
      expect(editor.canvas.elements.some((el) => el.id === "child-1")).toBe(true)
      expect(editor.canvas.connections.map((c) => c.id)).toEqual(beforeIds)
    })
  })

  describe("save guards", () => {
    it("prevents default and bails when the canvas is read-only", async () => {
      const canvasEl = document.createElement("div")
      canvasEl.setAttribute("data-controller", "flowchart-canvas")
      canvasEl.dataset.flowchartCanvasReadOnlyValue = "true"
      document.body.appendChild(canvasEl)
      const preventDefault = vi.fn()
      const collect = vi.spyOn(ctrl, "_collectFormData")
      await ctrl.save({ preventDefault })
      expect(preventDefault).toHaveBeenCalled()
      expect(collect).not.toHaveBeenCalled()
    })

    it("bails when there is no current element or connection", async () => {
      const collect = vi.spyOn(ctrl, "_collectFormData")
      await ctrl.save({ preventDefault() {} })
      expect(collect).not.toHaveBeenCalled()
    })
  })

  describe("_validateBeforeSave", () => {
    it("allows save when there are no field-addressed errors", () => {
      ctrl.currentElement = { type: "process", id: "p1" }
      expect(ctrl._validateBeforeSave()).toBe(true)
      ctrl.currentElement = { type: "start", id: "s1" }
      expect(ctrl._validateBeforeSave()).toBe(true)
    })

    it("live rules are empty without a current element", () => {
      ctrl.currentElement = null
      expect(ctrl._liveElementRuleProblems()).toEqual([])
    })

    it("reads properties from the element when the form target is missing", () => {
      ctrl.currentElement = { type: "end", id: "e1" }
      Object.defineProperty(ctrl, "hasFormTarget", { configurable: true, get: () => false })
      ctrl._getCanvasController = () => null
      expect(ctrl._liveElementRuleProblems()).toEqual([])
    })

    it("passes the canvas flowchart id into live subflow rules", () => {
      ctrl.currentElement = { type: "subflow", id: "sf", properties: { flowchartId: "1" } }
      Object.defineProperty(ctrl, "hasFormTarget", { configurable: true, get: () => false })
      ctrl._getCanvasController = () => ({ idValue: "1", _validationMessages: () => ({}) })
      expect(ctrl._liveElementRuleProblems().some((problem) => problem.type === "subflow_self_reference")).toBe(true)
    })

    it("words live rule problems with the canvas's translated validation messages", () => {
      ctrl.currentElement = { type: "end", id: "e1", label: "Done", properties: { responseType: "value" } }
      Object.defineProperty(ctrl, "hasFormTarget", { configurable: true, get: () => false })
      ctrl._getCanvasController = () => ({ idValue: "9", _validationMessages: () => ({ missingReturnValue: "请填写{field}", unused: "" }) })
      const [problem] = ctrl._liveElementRuleProblems()
      expect(problem).toMatchObject({ type: "end_no_return_value", field: "returnValue" })
      expect(problem.message).toBe("请填写{field}")
    })

    it("blocks save from live element rules when a while loop has no condition", () => {
      ctrl.currentElement = { type: "loop", id: "l1", properties: { loopType: "while" } }
      ctrl.formTarget.innerHTML = `<div data-element-field="condition"><textarea name="condition"></textarea></div>`
      expect(ctrl._validateBeforeSave()).toBe(false)
      expect(ctrl.formTarget.querySelector("[data-field-error]")).not.toBeNull()
      expect(ctrl.formTarget.querySelector('[name="condition"]').getAttribute("aria-invalid")).toBe("true")
    })

    it("ignores problems for another element and accepts element_id keys", () => {
      ctrl.currentElement = { type: "end", id: "e1" }
      ctrl.formTarget.innerHTML = `<div data-element-field="returnValue"><input name="returnValue"></div>`
      vi.spyOn(ctrl, "_canvasValidationProblems").mockReturnValue([
        { field: "returnValue", severity: "error", message: "other", element_id: "e2" },
        { field: "returnValue", severity: "warning", message: "mine", elementId: "e1" },
        { field: "returnValue", severity: "error", message: "also mine" },
        null,
        { message: "panel" },
      ])
      expect(ctrl._validateBeforeSave()).toBe(false)
      expect(ctrl.formTarget.querySelector("[data-field-error]").textContent).toBe("also mine")
    })

    it("blocks save on severity error but not on warnings or panel-only rows", () => {
      ctrl.currentElement = { type: "end", id: "e1" }
      ctrl.formTarget.innerHTML = `<div data-element-field="returnValue"><input name="returnValue"></div>`
      vi.spyOn(ctrl, "_canvasValidationProblems").mockReturnValue([
        { field: "returnValue", severity: "error", message: "Required", elementId: "e1" },
      ])
      expect(ctrl._validateBeforeSave()).toBe(false)
      expect(ctrl.formTarget.querySelector("[data-field-error]").textContent).toBe("Required")

      ctrl._canvasValidationProblems.mockReturnValue([
        { field: "returnValue", severity: "warning", message: "Check this", elementId: "e1" },
        { severity: "error", message: "panel only" },
      ])
      expect(ctrl._validateBeforeSave()).toBe(true)
    })

    it("reads canvas validation problems and treats a missing list as empty", () => {
      const canvas = document.createElement("div")
      canvas.setAttribute("data-controller", "flowchart-canvas")
      canvas.appendChild(element)
      document.body.appendChild(canvas)
      vi.spyOn(ctrl.application, "getControllerForElementAndIdentifier").mockReturnValue({})
      expect(ctrl._canvasValidationProblems()).toEqual([])
      ctrl.application.getControllerForElementAndIdentifier.mockReturnValue({ _validationProblems: [{ field: "x" }] })
      expect(ctrl._canvasValidationProblems()).toEqual([{ field: "x" }])
    })
  })

  describe("getFormFieldsForTab (steps/io)", () => {
    it("returns the steps and io panes", () => {
      expect(ctrl.getFormFieldsForTab("steps")).toBe(ctrl.formFieldsStepsTarget)
      expect(ctrl.getFormFieldsForTab("io")).toBe(ctrl.formFieldsIoTarget)
    })
  })

  describe("_buildConnectionForm defaults", () => {
    it("falls back to empty label and Notes when absent", () => {
      ctrl._buildConnectionForm({})
      const pane = ctrl.formFieldsGeneralTarget
      expect(pane.querySelector('input[name="label"]').value).toBe("")
      expect(pane.querySelector('textarea[name="description"]').textContent).toBe("")
      expect(pane.querySelector('input[name="connectionPriority"]')).toBeNull()
    })

    it("falls back to chrome label/Notes when the catalog has no connection fields", () => {
      clearElementCatalog()
      try {
        ctrl._buildConnectionForm({ label: "No", properties: { description: "note" } })
        const pane = ctrl.formFieldsGeneralTarget
        expect(pane.querySelector('input[name="label"]').value).toBe("No")
        expect(pane.querySelector('textarea[name="description"]').textContent).toContain("note")
      } finally {
        installSampleElementCatalog()
      }
    })

    it("uses empty control labels when the form builder has none", () => {
      ctrl.formBuilder = null
      ctrl._buildConnectionForm({ label: "X", properties: {} })
      expect(ctrl.formFieldsGeneralTarget.querySelector('input[name="label"]').value).toBe("X")
    })
  })

  describe("disconnect", () => {
    it("clears pending timers, removes document listeners, and closes the io manager", () => {
      ctrl._syncTimeout = setTimeout(() => {}, 1000)
      ctrl._problemHighlightTimer = setTimeout(() => {}, 1000)
      ctrl._structureRefreshTimer = setTimeout(() => {}, 1000)
      const removeFormChangeListeners = vi.spyOn(ctrl, "_removeFormChangeListeners")
      const closeIo = vi.spyOn(ctrl.elementIoManager, "close")
      const removeEventListener = vi.spyOn(document, "removeEventListener")
      ctrl.disconnect()
      expect(removeFormChangeListeners).toHaveBeenCalled()
      expect(closeIo).toHaveBeenCalled()
      expect(removeEventListener).toHaveBeenCalledWith("keydown", ctrl._boundHandleKeydown)
      expect(removeEventListener).toHaveBeenCalledWith("flowchartStructureChanged", ctrl._boundStructureChanged)
    })

    it("tolerates missing timers and a missing io manager", () => {
      ctrl._syncTimeout = null
      ctrl._problemHighlightTimer = null
      ctrl._structureRefreshTimer = null
      ctrl.elementIoManager = null
      expect(() => ctrl.disconnect()).not.toThrow()
    })
  })

  describe("tabBarTargetConnected", () => {
    it("creates a tab manager on demand and initializes it with the tab bar and panes", () => {
      ctrl.sidebarTarget.insertAdjacentHTML("afterbegin", '<div data-property-editor-target="tabBar"></div>')
      ctrl.tabManager = null
      ctrl.tabBarTargetConnected()
      expect(ctrl.tabManager).toBeTruthy()
      expect(ctrl.tabManager.tabBarContainer).toBe(ctrl.tabBarTarget)
      expect(ctrl.tabManager.tabPanes).toEqual({
        general: ctrl.tabPaneGeneralTarget,
        steps: ctrl.tabPaneStepsTarget,
        branches: ctrl.tabPaneStepsTarget,
        io: ctrl.tabPaneIoTarget,
        advanced: ctrl.tabPaneAdvancedTarget
      })
    })

    it("reuses an already-initialized tab manager", () => {
      ctrl.sidebarTarget.insertAdjacentHTML("afterbegin", '<div data-property-editor-target="tabBar"></div>')
      const existing = ctrl.tabManager
      ctrl.tabBarTargetConnected()
      expect(ctrl.tabManager).toBe(existing)
    })

    it("passes null panes when a tab pane target is absent", () => {
      ctrl.tabPaneGeneralTarget.remove()
      ctrl.tabPaneStepsTarget.remove()
      ctrl.tabPaneIoTarget.remove()
      ctrl.tabPaneAdvancedTarget.remove()
      ctrl.sidebarTarget.insertAdjacentHTML("afterbegin", '<div data-property-editor-target="tabBar"></div>')
      ctrl.tabBarTargetConnected()
      expect(ctrl.tabManager.tabPanes).toEqual({ general: null, steps: null, branches: null, io: null, advanced: null })
    })
  })

  describe("_formOutOfSync additional branches", () => {
    it("treats a decision element with no properties object as having no branches", () => {
      ctrl.currentElement = { id: "d1", type: "decision" }
      expect(ctrl._formOutOfSync({ id: "d1", type: "decision" })).toBe(false)
    })

    it("compares branch identity field-by-field once lengths match", () => {
      ctrl.currentElement = { id: "d1", type: "decision" }
      vi.spyOn(ctrl.branchManager, "collectBranches").mockReturnValue([
        { elementId: "e1", matchValue: "yes", name: "Yes" }
      ])
      const el = { id: "d1", type: "decision", properties: {} }

      ctrl.canvas = { connections: [{ from: "d1", to: "e1", matchValue: "yes", label: "Yes", fromPort: "port_0" }] }
      expect(ctrl._formOutOfSync(el)).toBe(false)

      ctrl.canvas = { connections: [{ from: "d1", to: "e2", matchValue: "yes", label: "Yes", fromPort: "port_0" }] }
      expect(ctrl._formOutOfSync(el)).toBe(true)

      ctrl.canvas = { connections: [{ from: "d1", to: "e1", matchValue: "no", label: "Yes", fromPort: "port_0" }] }
      expect(ctrl._formOutOfSync(el)).toBe(true)

      ctrl.canvas = { connections: [{ from: "d1", to: "e1", matchValue: "yes", label: "No", fromPort: "port_0" }] }
      expect(ctrl._formOutOfSync(el)).toBe(true)
    })

    it("orders outgoing connections by fromPort before comparing identity", () => {
      ctrl.currentElement = { id: "d1", type: "decision" }
      vi.spyOn(ctrl.branchManager, "collectBranches").mockReturnValue([
        { elementId: "e0", matchValue: "a", name: "A" },
        { elementId: "e1", matchValue: "b", name: "B" }
      ])
      const el = { id: "d1", type: "decision" }
      ctrl.canvas = {
        connections: [
          { from: "d1", to: "e1", matchValue: "b", label: "B", fromPort: "port_1" },
          { from: "d1", to: "e0", matchValue: "a", label: "A", fromPort: "port_0" }
        ]
      }
      expect(ctrl._formOutOfSync(el)).toBe(false)
    })

    it("treats a missing fromPort as last when ordering outgoing connections", () => {
      ctrl.currentElement = { id: "d1", type: "decision" }
      vi.spyOn(ctrl.branchManager, "collectBranches").mockReturnValue([
        { elementId: "e0", name: "A" },
        { elementId: "e1", name: "B" }
      ])
      const el = { id: "d1", type: "decision" }
      ctrl.canvas = {
        connections: [
          { from: "d1", to: "e1", label: "B" },
          { from: "d1", to: "e0", label: "A", fromPort: "port_0" }
        ]
      }
      expect(ctrl._formOutOfSync(el)).toBe(false)
    })

    it("treats a blank or non-port fromPort as unordered when it is the sort left-hand side", () => {
      ctrl.currentElement = { id: "d1", type: "decision" }
      vi.spyOn(ctrl.branchManager, "collectBranches").mockReturnValue([
        { elementId: "e0", name: "A" },
        { elementId: "e1", name: "B" },
        { elementId: "e2", name: "C" }
      ])
      const el = { id: "d1", type: "decision" }
      ctrl.canvas = {
        connections: [
          { from: "d1", to: "e0", label: "A", fromPort: "port_0" },
          { from: "d1", to: "e1", label: "B", fromPort: "port_1" },
          { from: "d1", to: "e2", label: "C", fromPort: "" }
        ]
      }
      expect(ctrl._formOutOfSync(el)).toBe(false)

      ctrl.canvas = {
        connections: [
          { from: "d1", to: "e0", label: "A", fromPort: "port_0" },
          { from: "d1", to: "e1", label: "B", fromPort: "port_1" },
          { from: "d1", to: "e2", label: "C", fromPort: "side" }
        ]
      }
      expect(ctrl._formOutOfSync(el)).toBe(false)
    })

    it("treats a missing outgoing slot as an empty object", () => {
      ctrl.currentElement = { id: "d1", type: "decision" }
      vi.spyOn(ctrl.branchManager, "collectBranches").mockReturnValue([{}])
      const connections = [{ from: "d1" }]
      connections.filter = () => [undefined]
      ctrl.canvas = { connections }
      expect(ctrl._formOutOfSync({ id: "d1", type: "decision" })).toBe(false)
    })
  })

  describe("_onCanvasStructureChanged", () => {
    it("no-ops without a current element, canvas, or form target", () => {
      expect(() => ctrl._onCanvasStructureChanged()).not.toThrow()
    })

    it("no-ops when there is no form target", () => {
      ctrl.currentElement = { id: "d1", type: "decision" }
      ctrl.canvas = { elements: [] }
      ctrl.formTarget.parentNode.removeChild(ctrl.formTarget) // happy-dom .remove() bug on <form>
      expect(() => ctrl._onCanvasStructureChanged()).not.toThrow()
    })

    it("skips while the user is focused on a form field", () => {
      ctrl.currentElement = { id: "e1", type: "process" }
      ctrl.canvas = { elements: [{ id: "e1", type: "process" }] }
      const input = document.createElement("input")
      ctrl.element.appendChild(input)
      input.focus()
      const openEditorSpy = vi.spyOn(ctrl, "openEditor")
      ctrl._onCanvasStructureChanged()
      expect(openEditorSpy).not.toHaveBeenCalled()
    })

    it("no-ops when the element is missing from the canvas", () => {
      ctrl.currentElement = { id: "missing", type: "process" }
      ctrl.canvas = { elements: [] }
      expect(() => ctrl._onCanvasStructureChanged()).not.toThrow()
    })

    it("does not schedule a refresh when canvas and form already agree", () => {
      ctrl.currentElement = { id: "d1", type: "decision" }
      const el = { id: "d1", type: "decision", properties: { branches: [] } }
      ctrl.canvas = { elements: [el] }
      const openEditorSpy = vi.spyOn(ctrl, "openEditor")
      ctrl._onCanvasStructureChanged()
      expect(openEditorSpy).not.toHaveBeenCalled()
    })

    it("schedules a refresh, drops a pending sync, reopens the editor, and restores the active tab", () => {
      vi.useFakeTimers()
      ctrl.currentElement = { id: "d1", type: "decision" }
      const freshEl = { id: "d1", type: "decision", properties: {} }
      ctrl.canvas = {
        elements: [freshEl],
        connections: [{ from: "d1", to: "e2", fromPort: "port_0", label: "Yes", matchValue: "true" }]
      }
      ctrl._syncTimeout = setTimeout(() => {}, 1000)
      ctrl.tabManager.activeTab = "steps"
      const openEditorSpy = vi.spyOn(ctrl, "openEditor").mockImplementation(() => {})
      const switchToSpy = vi.spyOn(ctrl.tabManager, "switchTo").mockImplementation(() => {})
      ctrl._onCanvasStructureChanged()
      expect(ctrl._structureRefreshTimer).toBeTruthy()
      vi.advanceTimersByTime(30)
      expect(ctrl._syncTimeout).toBeNull()
      expect(openEditorSpy).toHaveBeenCalledWith(freshEl, ctrl.canvas)
      expect(switchToSpy).toHaveBeenCalledWith("steps")
      vi.useRealTimers()
    })

    it("skips tab restoration when there is no active tab to restore", () => {
      vi.useFakeTimers()
      ctrl.currentElement = { id: "d1", type: "decision" }
      const freshEl = { id: "d1", type: "decision", properties: {} }
      ctrl.canvas = {
        elements: [freshEl],
        connections: [{ from: "d1", to: "e2", fromPort: "port_0", label: "Yes", matchValue: "true" }]
      }
      ctrl.tabManager.activeTab = null
      const openEditorSpy = vi.spyOn(ctrl, "openEditor").mockImplementation(() => {})
      const switchToSpy = vi.spyOn(ctrl.tabManager, "switchTo")
      ctrl._onCanvasStructureChanged()
      vi.advanceTimersByTime(30)
      expect(openEditorSpy).toHaveBeenCalled()
      expect(switchToSpy).not.toHaveBeenCalled()
      vi.useRealTimers()
    })

    it("bails inside the deferred refresh if the canvas disappeared", () => {
      vi.useFakeTimers()
      ctrl.currentElement = { id: "d1", type: "decision" }
      const el = { id: "d1", type: "decision", properties: {} }
      ctrl.canvas = {
        elements: [el],
        connections: [{ from: "d1", to: "e2", fromPort: "port_0", label: "Yes", matchValue: "true" }]
      }
      const openEditorSpy = vi.spyOn(ctrl, "openEditor")
      ctrl._onCanvasStructureChanged()
      ctrl.canvas = null
      vi.advanceTimersByTime(30)
      expect(openEditorSpy).not.toHaveBeenCalled()
      vi.useRealTimers()
    })

    it("bails inside the deferred refresh if the fresh element vanished", () => {
      vi.useFakeTimers()
      ctrl.currentElement = { id: "d1", type: "decision" }
      const el = { id: "d1", type: "decision", properties: {} }
      const canvas = {
        elements: [el],
        connections: [{ from: "d1", to: "e2", fromPort: "port_0", label: "Yes", matchValue: "true" }]
      }
      ctrl.canvas = canvas
      const openEditorSpy = vi.spyOn(ctrl, "openEditor")
      ctrl._onCanvasStructureChanged()
      canvas.elements = []
      vi.advanceTimersByTime(30)
      expect(openEditorSpy).not.toHaveBeenCalled()
      vi.useRealTimers()
    })
  })

  describe("openEditor", () => {
    function stubFormBuilder() {
      vi.spyOn(ctrl.formBuilder, "buildForm").mockImplementation(() => {})
      vi.spyOn(ctrl.formBuilder, "_autoDeriveLabelOnOpen").mockImplementation(() => {})
    }

    it("opens a process element: resets managers, builds the form, shows the tab bar, updates badges", () => {
      stubFormBuilder()
      const resetStep = vi.spyOn(ctrl.stepManager, "reset")
      const resetBranch = vi.spyOn(ctrl.branchManager, "reset")
      ctrl.sidebarTarget.insertAdjacentHTML("afterbegin", '<div data-property-editor-target="tabBar" class="hidden"></div>')
      const canvas = { elementSchemas: {} }
      const element = { id: "p1", type: "process", properties: {} }
      ctrl.openEditor(element, canvas)
      expect(ctrl.currentElement).toBe(element)
      expect(ctrl.currentConnection).toBeNull()
      expect(ctrl.canvas).toBe(canvas)
      expect(ctrl.elementIdValue).toBe("p1")
      expect(ctrl.elementTypeValue).toBe("process")
      expect(ctrl._labelAutoDerived).toBe(false)
      expect(resetStep).toHaveBeenCalled()
      expect(resetBranch).toHaveBeenCalled()
      expect(ctrl.formBuilder.buildForm).toHaveBeenCalled()
      expect(ctrl.tabBarTarget.classList.contains("hidden")).toBe(false)
    })

    it("snapshots label and properties on open and ignores a leftover cache object", () => {
      stubFormBuilder()
      ctrl.unsavedChangesCache = { e1: { foo: "bar" } }
      const element = { id: "e1", type: "process", label: "Orig", properties: { existing: true } }
      ctrl.openEditor(element, {})
      expect(ctrl.currentElement.properties).toEqual({ existing: true })
      expect(ctrl._openSnapshot).toEqual({
        label: "Orig",
        properties: { existing: true },
        elements: [],
        connections: [],
      })
    })

    it("flushes a pending debounced sync for the previously-open selection before switching", () => {
      stubFormBuilder()
      const prevElement = { id: "prev", type: "process", properties: {} }
      ctrl.currentElement = prevElement
      ctrl.canvas = {}
      ctrl._syncTimeout = setTimeout(() => {}, 1000)
      const performSync = vi.spyOn(ctrl, "_performSync").mockImplementation(() => {})
      ctrl.openEditor({ id: "next", type: "process", properties: {} }, {})
      expect(performSync).toHaveBeenCalled()
      expect(ctrl._syncTimeout).toBeNull()
    })

    it("does not open the property editor for unsupported structural elements", () => {
      const buildForm = vi.spyOn(ctrl.formBuilder, "buildForm")
      ctrl.openEditor({ id: "j1", type: "join", properties: {} }, { elementSchemas: {} })
      expect(buildForm).not.toHaveBeenCalled()
      expect(ctrl.currentElement).toBeNull()
    })

    it("navigates to a validation problem when nav.tab is provided", () => {
      stubFormBuilder()
      const navigate = vi.spyOn(ctrl, "_navigateToProblem").mockImplementation(() => {})
      const nav = { tab: "steps", anchor: "[name=foo]" }
      ctrl.openEditor({ id: "p1", type: "process", properties: {} }, {}, nav)
      expect(navigate).toHaveBeenCalledWith(nav)
    })

    it("paints field problems on open without revealing their tab", () => {
      stubFormBuilder()
      const apply = vi.spyOn(ctrl, "applyElementFieldProblems")
      ctrl.openEditor({ id: "p1", type: "process", properties: {} }, {})
      expect(apply).toHaveBeenCalledWith(expect.any(Array), { reveal: false })
    })

    it("does not navigate when nav is omitted", () => {
      stubFormBuilder()
      const navigate = vi.spyOn(ctrl, "_navigateToProblem")
      ctrl.openEditor({ id: "p1", type: "process", properties: {} }, {})
      expect(navigate).not.toHaveBeenCalled()
    })
  })

  describe("openConnectionEditor additional branches", () => {
    it("hides the tab bar when present", () => {
      ctrl.sidebarTarget.insertAdjacentHTML("afterbegin", '<div data-property-editor-target="tabBar"></div>')
      ctrl.openConnectionEditor({ id: "c1", label: "X", properties: {} }, {})
      expect(ctrl.tabBarTarget.classList.contains("hidden")).toBe(true)
    })

    it("flushes a pending debounced sync for the previously-open selection before switching", () => {
      ctrl.currentElement = { id: "e1", type: "process", properties: {} }
      ctrl.canvas = {}
      ctrl._syncTimeout = setTimeout(() => {}, 1000)
      const performSync = vi.spyOn(ctrl, "_performSync").mockImplementation(() => {})
      ctrl.openConnectionEditor({ id: "c1", properties: {} }, {})
      expect(performSync).toHaveBeenCalled()
      expect(ctrl._syncTimeout).toBeNull()
    })
  })

  describe("onTabActivated", () => {
    it("is a no-op for non-io tabs", () => {
      const spy = vi.spyOn(ctrl.elementIoManager, "openForElement")
      ctrl.onTabActivated("general")
      expect(spy).not.toHaveBeenCalled()
    })

    it("is a no-op without a current element", () => {
      ctrl.currentElement = null
      const spy = vi.spyOn(ctrl.elementIoManager, "openForElement")
      ctrl.onTabActivated("io")
      expect(spy).not.toHaveBeenCalled()
    })

    it("is a no-op without an elementIoManager", () => {
      ctrl.currentElement = { id: "e1", type: "process" }
      ctrl.elementIoManager = null
      expect(() => ctrl.onTabActivated("io")).not.toThrow()
    })

    it("is a no-op without an io pane", () => {
      ctrl.currentElement = { id: "e1", type: "process" }
      ctrl.formFieldsIoTarget.remove()
      const spy = vi.spyOn(ctrl.elementIoManager, "openForElement")
      ctrl.onTabActivated("io")
      expect(spy).not.toHaveBeenCalled()
    })

    it("opens the io manager for the current element and swallows rejection", async () => {
      ctrl.currentElement = { id: "e1", type: "process" }
      const openForElement = vi.spyOn(ctrl.elementIoManager, "openForElement").mockRejectedValue(new Error("boom"))
      ctrl.onTabActivated("io")
      expect(openForElement).toHaveBeenCalledWith(ctrl.currentElement, ctrl.formFieldsIoTarget)
      await new Promise((resolve) => setTimeout(resolve, 0))
    })
  })

  describe("_applyReadOnlyState", () => {
    it("no-ops without a form target", () => {
      ctrl.formTarget.parentNode.removeChild(ctrl.formTarget) // happy-dom .remove() bug on <form>
      expect(() => ctrl._applyReadOnlyState()).not.toThrow()
    })

    it("no-ops when the canvas is not read-only", () => {
      ctrl.formTarget.innerHTML = "<input>"
      ctrl._applyReadOnlyState()
      expect(ctrl.formTarget.querySelector("input").disabled).toBe(false)
    })

    it("disables form controls but leaves the close action enabled when read-only", () => {
      const canvasEl = document.createElement("div")
      canvasEl.setAttribute("data-controller", "flowchart-canvas")
      canvasEl.dataset.flowchartCanvasReadOnlyValue = "true"
      document.body.appendChild(canvasEl)
      ctrl.formTarget.innerHTML = `
        <input name="label">
        <button data-action="click->property-editor#close">Close</button>
      `
      ctrl._applyReadOnlyState()
      const input = ctrl.formTarget.querySelector("input")
      const button = ctrl.formTarget.querySelector("button")
      expect(input.disabled).toBe(true)
      expect(input.classList.contains("opacity-60")).toBe(true)
      expect(button.disabled).toBe(false)
    })

    it("re-enables controls this guard previously disabled when read-only is cleared", () => {
      const canvasEl = document.createElement("div")
      canvasEl.setAttribute("data-controller", "flowchart-canvas")
      canvasEl.dataset.flowchartCanvasReadOnlyValue = "true"
      document.body.appendChild(canvasEl)
      ctrl.formTarget.innerHTML = '<input name="label">'
      ctrl._applyReadOnlyState()
      delete canvasEl.dataset.flowchartCanvasReadOnlyValue
      ctrl._applyReadOnlyState()
      const input = ctrl.formTarget.querySelector("input")
      expect(input.disabled).toBe(false)
      expect(input.dataset.propertyEditorDisabled).toBeUndefined()
      expect(input.classList.contains("opacity-60")).toBe(false)
      expect(input.classList.contains("cursor-not-allowed")).toBe(false)
    })
  })

  describe("save (element flow)", () => {
    beforeEach(() => {
      ctrl.currentElement = { id: "e1", type: "process", properties: {} }
      ctrl.canvas = {}
      vi.spyOn(ctrl, "_validateBeforeSave").mockReturnValue(true)
      vi.spyOn(ctrl, "_collectFormData").mockReturnValue({ label: "Typed Label" })
      vi.spyOn(ctrl, "_deriveLabelFromProperties").mockReturnValue("Derived Label")
    })

    it("delegates to _saveConnection when a connection is open", async () => {
      ctrl.currentElement = null
      ctrl.currentConnection = { id: "c1" }
      const spy = vi.spyOn(ctrl, "_saveConnection").mockResolvedValue(undefined)
      await ctrl.save({ preventDefault() {} })
      expect(spy).toHaveBeenCalled()
    })

    it("bails validation before collecting form data", async () => {
      ctrl._validateBeforeSave.mockReturnValue(false)
      await ctrl.save({ preventDefault() {} })
      expect(ctrl._collectFormData).not.toHaveBeenCalled()
    })

    it("uses canvas.updateElementProperties when available and shows success", async () => {
      const updateElementProperties = vi.fn()
      ctrl.canvas.updateElementProperties = updateElementProperties
      vi.spyOn(ctrl, "_saveToDatabase").mockResolvedValue(true)
      const successSpy = vi.spyOn(ctrl, "_showSaveSuccess")
      vi.useFakeTimers()
      ctrl._syncTimeout = setTimeout(() => {}, 1000)
      await ctrl.save({ preventDefault() {} })
      expect(updateElementProperties).toHaveBeenCalledWith("e1", "Derived Label", {}, true)
      expect(successSpy).toHaveBeenCalled()
      expect(ctrl._syncTimeout).toBeNull()
      vi.advanceTimersByTime(500)
      vi.useRealTimers()
    })

    it("falls back to _updateElementFallback and shows an error on failed save", async () => {
      const fallbackSpy = vi.spyOn(ctrl, "_updateElementFallback").mockImplementation(() => {})
      vi.spyOn(ctrl, "_saveToDatabase").mockResolvedValue(false)
      const errorSpy = vi.spyOn(ctrl, "_showSaveError")
      await ctrl.save({ preventDefault() {} })
      expect(fallbackSpy).toHaveBeenCalledWith({}, "Derived Label")
      expect(errorSpy).toHaveBeenCalled()
    })

    it("uses an empty explicit label when the label was auto-derived", async () => {
      ctrl._labelAutoDerived = true
      ctrl.canvas.updateElementProperties = vi.fn()
      vi.spyOn(ctrl, "_saveToDatabase").mockResolvedValue(true)
      await ctrl.save({ preventDefault() {} })
      expect(ctrl._deriveLabelFromProperties).toHaveBeenCalledWith({}, "")
    })

    it("uses the typed label as the explicit label when not auto-derived", async () => {
      ctrl._labelAutoDerived = false
      ctrl.canvas.updateElementProperties = vi.fn()
      vi.spyOn(ctrl, "_saveToDatabase").mockResolvedValue(true)
      await ctrl.save({ preventDefault() {} })
      expect(ctrl._deriveLabelFromProperties).toHaveBeenCalledWith({}, "Typed Label")
    })
  })

  describe("_saveConnection", () => {
    it("no-ops without a current connection, canvas, or form target", async () => {
      await expect(ctrl._saveConnection()).resolves.toBeUndefined()
    })

    it("updates via canvas.updateConnectionProperties, saves, and shows success", async () => {
      ctrl.currentConnection = { id: "c1", from: "d1", label: null, matchValue: "true", properties: {} }
      const updateConnectionProperties = vi.fn()
      ctrl.canvas = { elements: [{ id: "d1", type: "decision" }], updateConnectionProperties }
      ctrl.formTarget.innerHTML = `
        <input name="label" value=" Yes ">
        <textarea name="description"> desc </textarea>
      `
      vi.spyOn(ctrl, "_saveToDatabase").mockResolvedValue(true)
      const successSpy = vi.spyOn(ctrl, "_showSaveSuccess")
      vi.useFakeTimers()
      ctrl._syncTimeout = setTimeout(() => {}, 1000)
      await ctrl._saveConnection()
      expect(updateConnectionProperties).toHaveBeenCalledWith("c1", "Yes", { description: "desc" })
      expect(ctrl.currentConnection.matchValue).toBe("true")
      expect(successSpy).toHaveBeenCalled()
      expect(ctrl._syncTimeout).toBeNull()
      vi.advanceTimersByTime(500)
      vi.useRealTimers()
    })

    it("falls back to setting connection fields directly and shows an error on failed save", async () => {
      ctrl.currentConnection = { id: "c1", label: null, properties: { foo: "bar" } }
      ctrl.canvas = {}
      ctrl.formTarget.innerHTML = `
        <input name="label" value="">
        <textarea name="description"></textarea>
      `
      vi.spyOn(ctrl, "_saveToDatabase").mockResolvedValue(false)
      const errorSpy = vi.spyOn(ctrl, "_showSaveError")
      await ctrl._saveConnection()
      expect(ctrl.currentConnection.label).toBeNull()
      expect(ctrl.currentConnection.properties).toEqual({ foo: "bar", description: "" })
      expect(errorSpy).toHaveBeenCalled()
    })
  })

  describe("_collectFormData", () => {
    it("returns an empty object without a form target", () => {
      ctrl.formTarget.parentNode.removeChild(ctrl.formTarget) // happy-dom .remove() bug on <form>
      expect(ctrl._collectFormData()).toEqual({})
    })

    it("collects plain fields and steps, skipping bracketed array prefixes", () => {
      ctrl.formTarget.innerHTML = `
        <input name="label" value="My Label">
        <input name="steps[0][foo]" value="ignored">
        <input name="condition[left]" value="ignored">
        <input name="branches[0][name]" value="ignored">
      `
      ctrl.currentElement = { type: "process" }
      vi.spyOn(ctrl.stepManager, "collectSteps").mockReturnValue([{ action: "email" }])
      vi.spyOn(ctrl.branchManager, "collectBranches").mockReturnValue(null)
      const result = ctrl._collectFormData()
      expect(result.label).toBe("My Label")
      expect(result.steps).toEqual([{ action: "email" }])
      expect(result.condition).toBeUndefined()
      expect(result.branches).toBeUndefined()
      expect(result.joinedBranches).toBeUndefined()
    })

    it("does not collect editor-managed branches (identity lives on connections)", () => {
      ctrl.currentElement = { type: "decision" }
      vi.spyOn(ctrl.stepManager, "collectSteps").mockReturnValue(null)
      vi.spyOn(ctrl.branchManager, "collectBranches").mockReturnValue([{ name: "Yes" }])

      expect(ctrl._collectFormData().branches).toBeUndefined()
    })

    it("collects named checkbox fields as booleans", () => {
      ctrl.formTarget.innerHTML = `<input type="checkbox" name="enabled" checked>`
      ctrl.currentElement = { type: "process" }
      vi.spyOn(ctrl.stepManager, "collectSteps").mockReturnValue(null)
      expect(ctrl._collectFormData().enabled).toBe(true)
    })

    it("collects an element's key/value field as rows with a key", () => {
      ctrl.formTarget.innerHTML = `
        <div data-element-field="inputVariables">
          <div data-key-value-list>
            <div data-kv-row><input data-kv-key value="order"><input data-kv-value value="ctx[:model]"></div>
            <div data-kv-row><input data-kv-key value=""><input data-kv-value value="dropped"></div>
          </div>
        </div>`
      ctrl.currentElement = { type: "subflow" }
      vi.spyOn(ctrl.stepManager, "collectSteps").mockReturnValue(null)

      expect(ctrl._collectFormData().inputVariables).toEqual([{ key: "order", value: "ctx[:model]" }])
    })

  })

  describe("sidebar target fallback (no sidebar target present)", () => {
    it("_showSidebar falls back to the controller element", () => {
      ctrl.sidebarTarget.remove()
      ctrl._showSidebar()
      expect(element.classList.contains("hidden")).toBe(false)
      expect(element.classList.contains("flex")).toBe(true)
      expect(element.classList.contains("flex-col")).toBe(true)
    })

    it("_hideSidebar falls back to the controller element", () => {
      ctrl.sidebarTarget.remove()
      ctrl._hideSidebar(false)
      expect(element.classList.contains("hidden")).toBe(true)
    })

    it("_isSidebarVisible falls back to the controller element", () => {
      ctrl.sidebarTarget.remove()
      expect(ctrl._isSidebarVisible()).toBe(true)
    })
  })

  describe("discardAndClose additional branches", () => {
    it("is a no-op when the sidebar is already hidden", () => {
      const sync = vi.spyOn(ctrl, "_performSync")
      expect(() => ctrl.discardAndClose()).not.toThrow()
      expect(sync).not.toHaveBeenCalled()
    })

    it("clears a pending sync timeout when discarding a visible sidebar", () => {
      ctrl._showSidebar()
      ctrl._syncTimeout = setTimeout(() => {}, 1000)
      ctrl.discardAndClose()
      expect(ctrl._syncTimeout).toBeNull()
    })
  })

  describe("step manager delegated actions", () => {
    const methods = [
      "toggleStep", "removeStep", "handleStepDragStart", "handleStepDragEnd", "handleStepDragOver",
      "handleStepDrop", "handleConfigFieldChange", "addConfigKvRow", "removeConfigKvRow",
      "addConfigListRow", "removeConfigListRow", "addConfigConditionRow", "removeConfigConditionRow",
      "toggleStepConditionJoin", "switchLocalizedLocale",
      "handleEntityColumnSelectChange", "swapEntityColumnToManual", "swapEntityColumnToSelect",
      "syncEntityColumnManual", "stepPickerCommit", "stepPickerEscape",
      "stepPickerFilter", "stepPickerKeydown", "stepPickerSelect", "stepPickerCategory", "changeStep"
    ]

    it.each(methods)("%s delegates to stepManager.%s with the event", (method) => {
      const spy = vi.spyOn(ctrl.stepManager, method).mockImplementation(() => {})
      const event = { type: "test-event" }
      ctrl[method](event)
      expect(spy).toHaveBeenCalledWith(event)
    })
  })

  describe("branch manager delegated actions", () => {
    const methods = [
      "addBranch", "removeBranch", "undoRouteByChange"
    ]

    it.each(methods)("%s delegates to branchManager.%s with the event", (method) => {
      const spy = vi.spyOn(ctrl.branchManager, method).mockImplementation(() => {})
      const event = { type: "test-event" }
      ctrl[method](event)
      expect(spy).toHaveBeenCalledWith(event)
    })
  })

  // Remaining branch-only gaps found via coverage_gaps.mjs after the above.
  describe("remaining branch coverage", () => {
    it("_formOutOfSync defaults missing individual branch fields to empty strings", () => {
      ctrl.currentElement = { id: "d1", type: "decision" }
      vi.spyOn(ctrl.branchManager, "collectBranches").mockReturnValue([{}])
      const el = { id: "d1", type: "decision", properties: {} }
      ctrl.canvas = { connections: [{ from: "d1", fromPort: "port_0" }] }
      expect(ctrl._formOutOfSync(el)).toBe(false)
    })

    it("_formOutOfSync defaults an undefined branch slot to an empty object on both sides", () => {
      ctrl.currentElement = { id: "d1", type: "decision" }
      vi.spyOn(ctrl.branchManager, "collectBranches").mockReturnValue([undefined])
      const el = { id: "d1", type: "decision", properties: {} }
      ctrl.canvas = { connections: [{ from: "d1", fromPort: "port_0" }] }
      expect(ctrl._formOutOfSync(el)).toBe(false)
    })

    it("getFormFieldsForTab falls back to the form when tab-specific containers are absent", () => {
      ctrl.formFieldsGeneralTarget.remove()
      ctrl.formFieldsStepsTarget.remove()
      ctrl.formFieldsIoTarget.remove()
      ctrl.formFieldsAdvancedTarget.remove()
      expect(ctrl.getFormFieldsForTab("general")).toBe(ctrl.formTarget)
      expect(ctrl.getFormFieldsForTab("steps")).toBe(ctrl.formTarget)
      expect(ctrl.getFormFieldsForTab("io")).toBe(ctrl.formTarget)
      expect(ctrl.getFormFieldsForTab("advanced")).toBe(ctrl.formTarget)
    })

    it("openEditor clears a pending sync timeout without flushing when there was no prior selection", () => {
      vi.spyOn(ctrl.formBuilder, "buildForm").mockImplementation(() => {})
      vi.spyOn(ctrl.formBuilder, "_autoDeriveLabelOnOpen").mockImplementation(() => {})
      ctrl.currentElement = null
      ctrl.currentConnection = null
      ctrl.canvas = null
      ctrl._syncTimeout = setTimeout(() => {}, 1000)
      const performSync = vi.spyOn(ctrl, "_performSync")
      ctrl.openEditor({ id: "next", type: "process", properties: {} }, {})
      expect(performSync).not.toHaveBeenCalled()
      expect(ctrl._syncTimeout).toBeNull()
    })

    it("openEditor snapshots empty properties when the element has none", () => {
      vi.spyOn(ctrl.formBuilder, "buildForm").mockImplementation(() => {})
      vi.spyOn(ctrl.formBuilder, "_autoDeriveLabelOnOpen").mockImplementation(() => {})
      const element = { id: "e2", type: "process", label: "Bare" }
      ctrl.openEditor(element, {})
      expect(ctrl.currentElement.properties).toBeUndefined()
      expect(ctrl._openSnapshot).toEqual({ label: "Bare", properties: {}, elements: [], connections: [] })
    })

    it("openConnectionEditor clears a pending sync timeout without flushing when there was no prior selection", () => {
      ctrl.currentElement = null
      ctrl.currentConnection = null
      ctrl.canvas = null
      ctrl._syncTimeout = setTimeout(() => {}, 1000)
      const performSync = vi.spyOn(ctrl, "_performSync")
      ctrl.openConnectionEditor({ id: "c1", properties: {} }, {})
      expect(performSync).not.toHaveBeenCalled()
      expect(ctrl._syncTimeout).toBeNull()
    })

    it("_buildConnectionForm falls back to the form target when the general pane is absent", () => {
      ctrl.formFieldsGeneralTarget.remove()
      ctrl._buildConnectionForm({ label: "X", properties: {} })
      expect(ctrl.formTarget.querySelector('input[name="label"]').value).toBe("X")
    })

    it("save falls back to an empty explicit label when the form provided none and label was not auto-derived", async () => {
      ctrl.currentElement = { id: "e1", type: "process", properties: {} }
      ctrl.canvas = { updateElementProperties: vi.fn() }
      ctrl._labelAutoDerived = false
      vi.spyOn(ctrl, "_validateBeforeSave").mockReturnValue(true)
      vi.spyOn(ctrl, "_collectFormData").mockReturnValue({})
      const derive = vi.spyOn(ctrl, "_deriveLabelFromProperties").mockReturnValue("Derived")
      vi.spyOn(ctrl, "_saveToDatabase").mockResolvedValue(true)
      await ctrl.save({ preventDefault() {} })
      expect(derive).toHaveBeenCalledWith({}, "")
    })

  })
})

describe("P5-8 cleanup — sidebar hide timer and unused params", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element, ctrl } = await mount())
  })
  afterEach(() => {
    vi.useRealTimers()
    document.querySelectorAll('[data-controller*="flowchart-canvas"]').forEach((n) => n.remove())
    application?.stop()
  })

  it("_saveConnection does not take an event parameter", () => {
    expect(ctrl._saveConnection.length).toBe(0)
  })

  it("clears the sidebar-hide timer on disconnect so advancing fake timers does not hide", () => {
    vi.useFakeTimers()
    const hide = vi.spyOn(ctrl, "_hideSidebar")
    ctrl._hideSidebarTimer = setTimeout(() => ctrl._hideSidebar(false), 500)
    ctrl.disconnect()
    vi.advanceTimersByTime(500)
    expect(hide).not.toHaveBeenCalled()
  })

  it("clears a pending sidebar-hide timer before scheduling another", async () => {
    ctrl.currentElement = { id: "e1", type: "process", properties: {} }
    ctrl.canvas = { updateElementProperties: vi.fn() }
    vi.spyOn(ctrl, "_validateBeforeSave").mockReturnValue(true)
    vi.spyOn(ctrl, "_collectFormData").mockReturnValue({ label: "L" })
    vi.spyOn(ctrl, "_deriveLabelFromProperties").mockReturnValue("L")
    vi.spyOn(ctrl, "_saveToDatabase").mockResolvedValue(true)
    vi.spyOn(ctrl, "_showSaveSuccess").mockImplementation(() => {})
    vi.useFakeTimers()
    await ctrl.save({ preventDefault() {} })
    const first = ctrl._hideSidebarTimer
    expect(first).toBeTruthy()
    await ctrl.save({ preventDefault() {} })
    expect(ctrl._hideSidebarTimer).toBeTruthy()
    expect(ctrl._hideSidebarTimer).not.toBe(first)
    const hide = vi.spyOn(ctrl, "_hideSidebar")
    vi.advanceTimersByTime(500)
    expect(hide).toHaveBeenCalledOnce()
  })

  it("does not hide the sidebar after disconnect when a successful save had scheduled hide", async () => {
    ctrl.currentElement = { id: "e1", type: "process", properties: {} }
    ctrl.canvas = { updateElementProperties: vi.fn() }
    vi.spyOn(ctrl, "_validateBeforeSave").mockReturnValue(true)
    vi.spyOn(ctrl, "_collectFormData").mockReturnValue({ label: "L" })
    vi.spyOn(ctrl, "_deriveLabelFromProperties").mockReturnValue("L")
    vi.spyOn(ctrl, "_saveToDatabase").mockResolvedValue(true)
    vi.spyOn(ctrl, "_showSaveSuccess").mockImplementation(() => {})
    vi.useFakeTimers()
    await ctrl.save({ preventDefault() {} })
    const hide = vi.spyOn(ctrl, "_hideSidebar")
    ctrl.disconnect()
    vi.advanceTimersByTime(500)
    expect(hide).not.toHaveBeenCalled()
  })
})
