import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { CanvasSyncMixin } from "controllers/property_editor/canvas_sync"

// CanvasSyncMixin is a bag of methods Object.assign'd onto the controller
// prototype. We build a minimal host object with the state each method reads and
// mix the methods in, then call them directly.
function makeCtx(over = {}) {
  const form = over.formTarget || document.createElement("form")
  const ctx = Object.assign(
    {
      hasFormTarget: "hasFormTarget" in over ? over.hasFormTarget : true,
      formTarget: form,
      currentElement: "currentElement" in over ? over.currentElement : { id: "e1", type: "process", properties: {} },
      currentConnection: "currentConnection" in over ? over.currentConnection : null,
      canvas: "canvas" in over ? over.canvas : { updateElementProperties: vi.fn() },
      _openSnapshot: over._openSnapshot ?? null,
      _collectFormData: over._collectFormData || (() => ({})),
      _deriveLabelFromProperties: over._deriveLabelFromProperties || ((_p, l) => l || "Derived"),
      _labelAutoDerived: false,
      _isCanvasReadOnly: () => false,
      _updateTabBadges: vi.fn(),
      stepManager: { refreshMoreOptionsBadges: vi.fn(), refreshAllCapabilityChrome: vi.fn() },
      hasTitleTarget: false,
      application: over.application || { getControllerForElementAndIdentifier: () => null },
    },
    CanvasSyncMixin,
    over.extra || {},
  )
  return ctx
}

describe("CanvasSyncMixin", () => {
  afterEach(() => {
    document.body.innerHTML = ""
    vi.useRealTimers()
  })

  describe("form change listeners", () => {
    it("wires the bound handler to input/change and the manager custom events", () => {
      const ctx = makeCtx()
      ctx._boundSyncChanges = vi.fn()
      ctx._setupFormChangeListeners()

      ;["input", "change", "stepAdded", "branchRemoved", "branchUpdated"].forEach((type) => {
        ctx.formTarget.dispatchEvent(new CustomEvent(type))
      })
      expect(ctx._boundSyncChanges).toHaveBeenCalledTimes(5)
    })

    it("removeFormChangeListeners detaches the handler", () => {
      const ctx = makeCtx()
      ctx._boundSyncChanges = vi.fn()
      ctx._setupFormChangeListeners()
      ctx._removeFormChangeListeners()
      ctx.formTarget.dispatchEvent(new CustomEvent("input"))
      expect(ctx._boundSyncChanges).not.toHaveBeenCalled()
    })

    it("no-ops without a form target", () => {
      const ctx = makeCtx({ hasFormTarget: false })
      expect(() => ctx._setupFormChangeListeners()).not.toThrow()
    })

    it("removeFormChangeListeners no-ops without a form target", () => {
      const ctx = makeCtx({ hasFormTarget: false })
      expect(() => ctx._removeFormChangeListeners()).not.toThrow()
    })

    it("wires and detaches the focusin/focusout coalesce hooks", () => {
      const ctx = makeCtx()
      ctx._boundFieldFocusIn = vi.fn()
      ctx._boundFieldFocusOut = vi.fn()
      ctx._setupFormChangeListeners()
      ctx.formTarget.dispatchEvent(new FocusEvent("focusin"))
      ctx.formTarget.dispatchEvent(new FocusEvent("focusout"))
      expect(ctx._boundFieldFocusIn).toHaveBeenCalledTimes(1)
      expect(ctx._boundFieldFocusOut).toHaveBeenCalledTimes(1)

      ctx._removeFormChangeListeners()
      ctx.formTarget.dispatchEvent(new FocusEvent("focusin"))
      ctx.formTarget.dispatchEvent(new FocusEvent("focusout"))
      expect(ctx._boundFieldFocusIn).toHaveBeenCalledTimes(1)
      expect(ctx._boundFieldFocusOut).toHaveBeenCalledTimes(1)
    })
  })

  describe("undo coalesce key", () => {
    const field = (html) => {
      const holder = document.createElement("div")
      holder.innerHTML = html
      return holder.firstElementChild
    }

    it("focusin on a named control sets <elementId>:<name>#<focus>", () => {
      const ctx = makeCtx()
      ctx._onFieldFocusIn({ target: field('<input name="label">') })
      expect(ctx.canvas.undoCoalesceKey).toMatch(/^e1:label#\d+$/)
      ctx._onFieldFocusIn({ target: field('<textarea name="steps[0][config][body]"></textarea>') })
      expect(ctx.canvas.undoCoalesceKey).toMatch(/^e1:steps\[0\]\[config\]\[body\]#\d+$/)
    })

    it("refocusing the same field starts a new key so separate edits stay separate undo entries", () => {
      const ctx = makeCtx()
      const label = field('<input name="label">')
      ctx._onFieldFocusIn({ target: label })
      const first = ctx.canvas.undoCoalesceKey
      ctx._onFieldFocusIn({ target: label })
      expect(ctx.canvas.undoCoalesceKey).toMatch(/^e1:label#\d+$/)
      expect(ctx.canvas.undoCoalesceKey).not.toBe(first)
    })

    it("falls back to the control id and keys connection forms by connection id", () => {
      const ctx = makeCtx({ currentElement: null, currentConnection: { id: "c9" } })
      ctx._onFieldFocusIn({ target: field('<select id="route-select"></select>') })
      expect(ctx.canvas.undoCoalesceKey).toMatch(/^c9:route-select#\d+$/)
    })

    it("clears the key for buttons and anonymous controls", () => {
      const ctx = makeCtx()
      ctx.canvas.undoCoalesceKey = "e1:label"
      ctx._onFieldFocusIn({ target: field('<button name="add">Add</button>') })
      expect(ctx.canvas.undoCoalesceKey).toBeNull()
      ctx.canvas.undoCoalesceKey = "e1:label"
      ctx._onFieldFocusIn({ target: field("<input>") })
      expect(ctx.canvas.undoCoalesceKey).toBeNull()
    })

    it("focusin no-ops without a canvas", () => {
      const ctx = makeCtx({ canvas: null })
      expect(() => ctx._onFieldFocusIn({ target: field('<input name="label">') })).not.toThrow()
    })

    it("clears the key when no element or connection is open", () => {
      const ctx = makeCtx({ currentElement: null, currentConnection: null })
      ctx.canvas.undoCoalesceKey = "stale"
      ctx._onFieldFocusIn({ target: field('<input name="label">') })
      expect(ctx.canvas.undoCoalesceKey).toBeNull()
    })

    it("focusout flushes the pending sync under the field key, then clears the key", () => {
      vi.useFakeTimers()
      const ctx = makeCtx()
      const keysAtSync = []
      ctx._performSync = vi.fn(() => keysAtSync.push(ctx.canvas.undoCoalesceKey))
      ctx.canvas.undoCoalesceKey = "e1:label"
      ctx._syncChangesToCanvas()
      ctx._onFieldFocusOut()
      expect(keysAtSync).toEqual(["e1:label"])
      expect(ctx.canvas.undoCoalesceKey).toBeNull()
      expect(ctx._syncTimeout).toBeNull()
      vi.advanceTimersByTime(200)
      expect(ctx._performSync).toHaveBeenCalledTimes(1)
    })

    it("focusout without a pending sync just clears the key", () => {
      const ctx = makeCtx()
      ctx._performSync = vi.fn()
      ctx.canvas.undoCoalesceKey = "e1:label"
      ctx._onFieldFocusOut()
      expect(ctx._performSync).not.toHaveBeenCalled()
      expect(ctx.canvas.undoCoalesceKey).toBeNull()
    })

    it("_clearUndoCoalesceKey no-ops without a canvas", () => {
      const ctx = makeCtx({ canvas: null })
      expect(() => ctx._clearUndoCoalesceKey()).not.toThrow()
    })

    it.each([
      ["no element or connection", { currentElement: null }],
      ["no canvas", { canvas: null }],
      ["no form target", { hasFormTarget: false }],
    ])("_flushPendingSync drops the timer without syncing when there is %s", (_label, over) => {
      vi.useFakeTimers()
      const ctx = makeCtx(over)
      ctx._performSync = vi.fn()
      ctx._syncTimeout = setTimeout(() => {}, 100)
      ctx._flushPendingSync()
      expect(ctx._syncTimeout).toBeNull()
      expect(ctx._performSync).not.toHaveBeenCalled()
    })

    it("_flushPendingSync syncs an open connection", () => {
      vi.useFakeTimers()
      const ctx = makeCtx({ currentElement: null, currentConnection: { id: "c1" } })
      ctx._performSync = vi.fn()
      ctx._syncTimeout = setTimeout(() => {}, 100)
      ctx._flushPendingSync()
      expect(ctx._performSync).toHaveBeenCalledTimes(1)
    })
  })

  describe("_syncChangesToCanvas", () => {
    it("debounces into a single _performSync after 100ms", () => {
      vi.useFakeTimers()
      const ctx = makeCtx()
      ctx._performSync = vi.fn()
      ctx._syncChangesToCanvas()
      ctx._syncChangesToCanvas() // resets the timer
      expect(ctx._performSync).not.toHaveBeenCalled()
      vi.advanceTimersByTime(100)
      expect(ctx._performSync).toHaveBeenCalledTimes(1)
    })

    it("no-ops when there is no current element or canvas", () => {
      const ctx = makeCtx({ currentElement: null })
      ctx._performSync = vi.fn()
      ctx._syncChangesToCanvas()
      expect(ctx._syncTimeout).toBeUndefined()
    })
  })

  describe("_performSync", () => {
    it("collects data, updates the canvas element, and refreshes badges without a cache write", () => {
      const updateElementProperties = vi.fn()
      const ctx = makeCtx({
        canvas: { updateElementProperties },
        _collectFormData: () => ({ label: "Typed", foo: "bar" }),
      })
      ctx._performSync()
      expect(updateElementProperties).toHaveBeenCalledWith("e1", "Typed", { foo: "bar" }, true)
      expect(ctx.unsavedChangesCache).toBeUndefined()
      expect(ctx._updateTabBadges).toHaveBeenCalled()
      expect(ctx.stepManager.refreshMoreOptionsBadges).toHaveBeenCalled()
      expect(ctx.stepManager.refreshAllCapabilityChrome).toHaveBeenCalled()
    })

    it("refreshes the retry chrome before collecting, so a self-unchecked retry is stored as off", () => {
      const order = []
      const ctx = makeCtx({ _collectFormData: () => { order.push("collect"); return {} } })
      ctx.stepManager.refreshAllCapabilityChrome.mockImplementation(() => order.push("refresh"))
      ctx._performSync()
      expect(order).toEqual(["refresh", "collect"])
    })

    it("no-ops without a current element", () => {
      const ctx = makeCtx({ currentElement: null })
      expect(() => ctx._performSync()).not.toThrow()
    })

    it("delegates to _performConnectionSync when a connection is active", () => {
      const ctx = makeCtx({ currentConnection: { id: "c1" } })
      ctx._performConnectionSync = vi.fn()
      ctx._performSync()
      expect(ctx._performConnectionSync).toHaveBeenCalled()
    })

    it("defaults explicitLabel to '' when the form data has no label and it wasn't auto-derived", () => {
      const updateElementProperties = vi.fn()
      const ctx = makeCtx({
        canvas: { updateElementProperties },
        _collectFormData: () => ({ foo: "bar" }),
        _deriveLabelFromProperties: (_p, explicit) => `Derived(${explicit === "" ? "empty" : explicit})`,
      })
      ctx._performSync()
      expect(updateElementProperties).toHaveBeenCalledWith("e1", "Derived(empty)", { foo: "bar" }, true)
    })

    it("falls back to _updateElementFallback when the canvas has no updateElementProperties", () => {
      const ctx = makeCtx({
        canvas: {},
        _collectFormData: () => ({ label: "Typed", foo: "bar" }),
      })
      ctx._updateElementFallback = vi.fn()
      ctx._performSync()
      expect(ctx._updateElementFallback).toHaveBeenCalledWith({ foo: "bar" }, "Typed")
    })

    it("re-derives the label from properties when it was auto-derived, ignoring a stale form label", () => {
      const updateElementProperties = vi.fn()
      const ctx = makeCtx({
        canvas: { updateElementProperties },
        _collectFormData: () => ({ label: "Stale Typed Label" }),
        _deriveLabelFromProperties: (_p, explicit) => `Derived(${explicit || "none"})`,
      })
      ctx._labelAutoDerived = true
      ctx._performSync()
      expect(updateElementProperties).toHaveBeenCalledWith("e1", "Derived(none)", {}, true)
    })

    it("auto-fills the label input and header title when the label was auto-derived", () => {
      const form = document.createElement("form")
      form.innerHTML = '<input name="label" value="Old">'
      const titleTarget = document.createElement("h1")
      const ctx = makeCtx({
        formTarget: form,
        canvas: { updateElementProperties: vi.fn() },
        _collectFormData: () => ({}),
        _deriveLabelFromProperties: () => "Fresh Label",
      })
      ctx._labelAutoDerived = true
      ctx.hasTitleTarget = true
      ctx.titleTarget = titleTarget
      ctx._performSync()
      expect(form.querySelector('input[name="label"]').value).toBe("Fresh Label")
      expect(titleTarget.textContent).toBe("Fresh Label")
    })

    it("leaves the label input untouched when it already matches the derived label", () => {
      const form = document.createElement("form")
      form.innerHTML = '<input name="label" value="Fresh Label">'
      const ctx = makeCtx({
        formTarget: form,
        canvas: { updateElementProperties: vi.fn() },
        _collectFormData: () => ({}),
        _deriveLabelFromProperties: () => "Fresh Label",
      })
      ctx._labelAutoDerived = true
      const input = form.querySelector('input[name="label"]')
      expect(() => ctx._performSync()).not.toThrow()
      expect(input.value).toBe("Fresh Label")
    })
  })

  describe("_updateElementFallback", () => {
    it("mutates the element in place, re-renders, and dispatches a change", () => {
      const render = vi.fn()
      const ctx = makeCtx({ canvas: { render } })
      ctx._dispatchChange = vi.fn()
      ctx._updateElementFallback({ foo: 1 }, "New Label")
      expect(ctx.currentElement.label).toBe("New Label")
      expect(ctx.currentElement.properties.foo).toBe(1)
      expect(render).toHaveBeenCalled()
      expect(ctx._dispatchChange).toHaveBeenCalled()
    })
  })

  describe("open snapshot restore", () => {
    it("_performSync no-ops when the canvas is read-only", () => {
      const updateElementProperties = vi.fn()
      const ctx = makeCtx({
        canvas: { updateElementProperties },
        extra: { _isCanvasReadOnly: () => true },
      })
      ctx._performSync()
      expect(updateElementProperties).not.toHaveBeenCalled()
    })

    it("_captureOpenSnapshot clones label and properties", () => {
      const ctx = makeCtx()
      expect(typeof ctx._captureOpenSnapshot).toBe("function")
      const source = { label: "A", properties: { n: 1 } }
      ctx._captureOpenSnapshot(source)
      source.label = "B"
      source.properties.n = 2
      expect(ctx._openSnapshot).toEqual({ label: "A", properties: { n: 1 }, elements: [], connections: [] })
    })

    it("_restoreOpenSnapshotIfChanged skips when the current state matches the snapshot", () => {
      const updateElementProperties = vi.fn()
      const ctx = makeCtx({
        currentElement: { id: "e1", label: "A", properties: { n: 1 } },
        canvas: { updateElementProperties, elements: [], connections: [] },
        _openSnapshot: { label: "A", properties: { n: 1 }, elements: [], connections: [] },
      })
      ctx._restoreOpenSnapshotIfChanged()
      expect(updateElementProperties).not.toHaveBeenCalled()
    })

    it("_restoreOpenSnapshotIfChanged restores a changed element once", () => {
      const element = { id: "e1", label: "Edited", properties: { n: 2 } }
      const updateElementProperties = vi.fn((id, label, properties) => {
        element.label = label
        element.properties = properties
      })
      const ctx = makeCtx({
        currentElement: element,
        canvas: { updateElementProperties, elements: [], connections: [] },
        _openSnapshot: { label: "A", properties: { n: 1 }, elements: [], connections: [] },
      })
      ctx._restoreOpenSnapshotIfChanged()
      expect(updateElementProperties).toHaveBeenCalledTimes(1)
      expect(updateElementProperties).toHaveBeenCalledWith("e1", "A", { n: 1 }, true)
      expect(element.label).toBe("A")
      expect(element.properties).toEqual({ n: 1 })
    })

    it("_captureOpenSnapshot defaults a missing label and properties", () => {
      const ctx = makeCtx()
      ctx._captureOpenSnapshot({})
      expect(ctx._openSnapshot).toEqual({ label: "", properties: {}, elements: [], connections: [] })
      ctx._captureOpenSnapshot(undefined)
      expect(ctx._openSnapshot).toEqual({ label: "", properties: {}, elements: [], connections: [] })
    })

    it("_restoreOpenSnapshotIfChanged no-ops when read-only, snapshot-less, canvas-less, or unselected", () => {
      const updateElementProperties = vi.fn()
      const snapshot = { label: "A", properties: { n: 1 } }
      makeCtx({
        currentElement: { id: "e1", label: "B", properties: { n: 2 } },
        canvas: { updateElementProperties },
        _openSnapshot: snapshot,
        extra: { _isCanvasReadOnly: () => true },
      })._restoreOpenSnapshotIfChanged()
      makeCtx({
        currentElement: { id: "e1", label: "B", properties: { n: 2 } },
        canvas: { updateElementProperties },
        _openSnapshot: null,
      })._restoreOpenSnapshotIfChanged()
      makeCtx({
        currentElement: { id: "e1", label: "B", properties: { n: 2 } },
        canvas: null,
        _openSnapshot: snapshot,
      })._restoreOpenSnapshotIfChanged()
      makeCtx({
        currentElement: null,
        currentConnection: null,
        canvas: { updateElementProperties },
        _openSnapshot: snapshot,
      })._restoreOpenSnapshotIfChanged()
      expect(updateElementProperties).not.toHaveBeenCalled()
    })

    it("_restoreOpenSnapshotIfChanged falls back when the canvas has no updateElementProperties", () => {
      const ctx = makeCtx({
        currentElement: { id: "e1", label: "Edited", properties: { n: 2 } },
        canvas: { elements: [], connections: [] },
        _openSnapshot: { label: "A", properties: { n: 1 }, elements: [], connections: [] },
      })
      ctx._updateElementFallback = vi.fn()
      ctx._restoreOpenSnapshotIfChanged()
      expect(ctx._updateElementFallback).toHaveBeenCalledWith({ n: 1 }, "A")
    })

    it("_restoreOpenSnapshotIfChanged restores a changed connection", () => {
      const updateConnectionProperties = vi.fn()
      const ctx = makeCtx({
        currentElement: null,
        currentConnection: { id: "c1", label: "Yes", properties: { description: "new" } },
        canvas: { updateConnectionProperties, elements: [], connections: [] },
        _openSnapshot: { label: "", properties: { description: "" }, elements: [], connections: [] },
      })
      ctx._restoreOpenSnapshotIfChanged()
      expect(updateConnectionProperties).toHaveBeenCalledWith("c1", null, { description: "" })
    })

    it("_restoreOpenSnapshotIfChanged mutates a connection when the canvas has no updater", () => {
      const connection = { id: "c1", label: "Yes", properties: { description: "new", foo: "keep" } }
      const ctx = makeCtx({
        currentElement: null,
        currentConnection: connection,
        canvas: { elements: [], connections: [] },
        _openSnapshot: { label: "", properties: { description: "old" }, elements: [], connections: [] },
      })
      ctx._restoreOpenSnapshotIfChanged()
      expect(connection.label).toBeNull()
      expect(connection.properties).toEqual({ description: "old", foo: "keep" })
    })

    it("_currentOpenState reads a connection when no element is selected", () => {
      const ctx = makeCtx({
        currentElement: null,
        currentConnection: { label: "Yes", properties: { description: "d" } },
      })
      expect(ctx._currentOpenState()).toEqual({
        label: "Yes",
        properties: { description: "d" },
        elements: [],
        connections: [],
      })
    })

    it("_currentOpenState defaults when nothing is selected", () => {
      const ctx = makeCtx({ currentElement: null, currentConnection: null })
      expect(ctx._currentOpenState()).toEqual({ label: "", properties: {}, elements: [], connections: [] })
    })

    it("_captureOpenSnapshot deep-clones canvas elements and connections", () => {
      const elements = [{ id: "d1", type: "decision", properties: { branches: [] } }]
      const connections = [{ id: "c1", from: "d1", to: "p1" }]
      const ctx = makeCtx({ canvas: { elements, connections } })
      ctx._captureOpenSnapshot({ label: "D", properties: { branches: [] } })
      elements.push({ id: "p1" })
      connections.push({ id: "c2" })
      expect(ctx._openSnapshot.elements).toEqual([{ id: "d1", type: "decision", properties: { branches: [] } }])
      expect(ctx._openSnapshot.connections).toEqual([{ id: "c1", from: "d1", to: "p1" }])
    })

    it("_graphChanged treats missing elements and connections as empty arrays", () => {
      const ctx = makeCtx()
      expect(ctx._graphChanged({}, { elements: [], connections: [] })).toBe(false)
      expect(ctx._graphChanged({ elements: [{ id: "x" }] }, {})).toBe(true)
      expect(ctx._graphChanged({ elements: [] }, { elements: [] })).toBe(false)
      expect(ctx._graphChanged({ elements: [], connections: [{ id: "c" }] }, { elements: [] })).toBe(true)
    })

    it("_restoreOpenSnapshotIfChanged replaceGraphs when elements or connections drifted", () => {
      const replaceGraph = vi.fn()
      const updateElementProperties = vi.fn()
      const snapshotElements = [{ id: "d1", properties: { branches: [] } }]
      const snapshotConnections = []
      const ctx = makeCtx({
        currentElement: { id: "d1", label: "D", properties: { branches: [{ name: "Yes" }] } },
        canvas: {
          updateElementProperties,
          replaceGraph,
          elements: [{ id: "d1" }, { id: "p-new" }],
          connections: [{ id: "c-new", from: "d1", to: "p-new" }],
        },
        _openSnapshot: {
          label: "D",
          properties: { branches: [] },
          elements: snapshotElements,
          connections: snapshotConnections,
        },
      })
      ctx._restoreOpenSnapshotIfChanged()
      expect(replaceGraph).toHaveBeenCalledTimes(1)
      expect(replaceGraph).toHaveBeenCalledWith(snapshotElements, snapshotConnections)
      expect(updateElementProperties).not.toHaveBeenCalled()
      expect(ctx.currentElement.properties).toEqual({ branches: [] })
    })

    it("_restoreOpenSnapshotIfChanged restores a connection when the graph drifted", () => {
      const connection = { id: "c1", label: "Yes", properties: { description: "new" } }
      const replaceGraph = vi.fn()
      const ctx = makeCtx({
        currentElement: null,
        currentConnection: connection,
        canvas: {
          replaceGraph,
          elements: [{ id: "a" }],
          connections: [{ id: "c1" }, { id: "extra" }],
        },
        _openSnapshot: {
          label: "",
          properties: { description: "old" },
          elements: [{ id: "a" }],
          connections: [{ id: "c1" }],
        },
      })
      ctx._restoreOpenSnapshotIfChanged()
      expect(replaceGraph).toHaveBeenCalledTimes(1)
      expect(connection.label).toBeNull()
      expect(connection.properties).toEqual({ description: "old" })
    })

    it("_restoreOpenSnapshotIfChanged skips updateElementProperties when the graph drifted but replaceGraph is missing", () => {
      const updateElementProperties = vi.fn()
      const ctx = makeCtx({
        currentElement: { id: "d1", label: "D", properties: { branches: [] } },
        canvas: {
          updateElementProperties,
          elements: [{ id: "d1" }, { id: "p-new" }],
          connections: [],
        },
        _openSnapshot: {
          label: "D",
          properties: { branches: [] },
          elements: [{ id: "d1" }],
          connections: [],
        },
      })
      ctx._restoreOpenSnapshotIfChanged()
      expect(updateElementProperties).not.toHaveBeenCalled()
    })
  })

  describe("canvas controller bridge", () => {
    const mountCanvasController = (controllerImpl) => {
      const el = document.createElement("div")
      el.setAttribute("data-controller", "flowchart-canvas")
      document.body.appendChild(el)
      const controller = { element: el, ...controllerImpl }
      return {
        el,
        application: { getControllerForElementAndIdentifier: () => controller },
        controller,
      }
    }

    it("_getCanvasController returns null when no canvas element is present", () => {
      const ctx = makeCtx()
      expect(ctx._getCanvasController()).toBeNull()
    })

    it("_dispatchChange fires flowchartChanged on the canvas controller element", () => {
      const { el, application } = mountCanvasController({})
      const ctx = makeCtx({ application })
      const handler = vi.fn()
      el.addEventListener("flowchartChanged", handler)
      ctx._dispatchChange()
      expect(handler).toHaveBeenCalledOnce()
      expect(handler.mock.calls[0][0].detail.action).toBe("elementPropertiesUpdated")
      expect(handler.mock.calls[0][0].detail.elementId).toBe("e1")
      expect(handler.mock.calls[0][0].detail.connectionId).toBeNull()
    })

    it("_dispatchChange reports a connection update with null elementId when a connection is active", () => {
      const { el, application } = mountCanvasController({})
      const ctx = makeCtx({ application, currentElement: null, currentConnection: { id: "c1" } })
      const handler = vi.fn()
      el.addEventListener("flowchartChanged", handler)
      ctx._dispatchChange()
      expect(handler.mock.calls[0][0].detail.action).toBe("connectionPropertiesUpdated")
      expect(handler.mock.calls[0][0].detail.elementId).toBeNull()
      expect(handler.mock.calls[0][0].detail.connectionId).toBe("c1")
    })

    it("_saveToDatabase delegates to the canvas controller's save()", async () => {
      const { application } = mountCanvasController({ save: vi.fn().mockResolvedValue(true) })
      const ctx = makeCtx({ application })
      expect(await ctx._saveToDatabase()).toBe(true)
    })

    it("_saveToDatabase returns false when the canvas controller throws", async () => {
      const { application } = mountCanvasController({ save: vi.fn().mockRejectedValue(new Error("x")) })
      const ctx = makeCtx({ application })
      expect(await ctx._saveToDatabase()).toBe(false)
    })

    it("_saveToDatabase returns false with no canvas controller", async () => {
      const ctx = makeCtx()
      expect(await ctx._saveToDatabase()).toBe(false)
    })
  })

  describe("_performConnectionSync", () => {
    it("reads connection fields and updates connection properties", () => {
      const form = document.createElement("form")
      form.innerHTML = `
        <input name="label" value="  Yes  ">
        <textarea name="description">  hi  </textarea>`
      const updateConnectionProperties = vi.fn()
      const ctx = makeCtx({
        formTarget: form,
        currentElement: null,
        currentConnection: { id: "c1" },
        canvas: { updateConnectionProperties },
      })
      ctx._dispatchChange = vi.fn()
      ctx._performConnectionSync()
      expect(updateConnectionProperties).toHaveBeenCalledWith("c1", "Yes", { description: "hi" })
      expect(ctx._dispatchChange).toHaveBeenCalled()
    })

    it("defaults label to null and description to '' when fields are absent", () => {
      const form = document.createElement("form")
      const updateConnectionProperties = vi.fn()
      const ctx = makeCtx({
        formTarget: form,
        currentElement: null,
        currentConnection: { id: "c1" },
        canvas: { updateConnectionProperties },
      })
      ctx._dispatchChange = vi.fn()
      ctx._performConnectionSync()
      expect(updateConnectionProperties).toHaveBeenCalledWith("c1", null, { description: "" })
    })

    it("leaves Decision match metadata unchanged", () => {
      const form = document.createElement("form")
      form.innerHTML = '<input name="connectionMatchValue" value="changed">'
      const connection = { id: "c1", from: "d1", matchValue: "true" }
      const ctx = makeCtx({
        formTarget: form,
        currentElement: null,
        currentConnection: connection,
        canvas: {
          elements: [{ id: "d1", type: "decision" }],
          updateConnectionProperties: vi.fn(),
        },
      })
      ctx._dispatchChange = vi.fn()

      ctx._performConnectionSync()

      expect(connection.matchValue).toBe("true")
    })

    it("debounces connection input changes even though no element is selected", () => {
      vi.useFakeTimers()
      const ctx = makeCtx({
        currentElement: null,
        currentConnection: { id: "c1" },
        canvas: {},
      })
      ctx._performSync = vi.fn()

      try {
        ctx._syncChangesToCanvas()
        vi.advanceTimersByTime(100)

        expect(ctx._performSync).toHaveBeenCalledOnce()
      } finally {
        vi.useRealTimers()
      }
    })

    it("no-ops without a current connection, canvas, or form target", () => {
      expect(() =>
        makeCtx({ currentConnection: null })._performConnectionSync()
      ).not.toThrow()
      expect(() =>
        makeCtx({ currentConnection: { id: "c1" }, canvas: null })._performConnectionSync()
      ).not.toThrow()
      expect(() =>
        makeCtx({ currentConnection: { id: "c1" }, hasFormTarget: false })._performConnectionSync()
      ).not.toThrow()
    })
  })
})
