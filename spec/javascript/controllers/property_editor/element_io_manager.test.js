import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"

// Keep shared request/subscription delivery real; control only HTTP and the
// asynchronous override computation boundary for focused manager tests.
vi.mock("controllers/property_editor/element_io/override_computer", () => ({
  computeElementOverrides: vi.fn().mockResolvedValue({ inputs: [], outputs: [] }),
}))

import { ElementIoManager } from "controllers/property_editor/element_io_manager"
import { NO_PRODUCER_SENTINEL } from "controllers/property_editor/element_io/renderers"
import { computeElementOverrides } from "controllers/property_editor/element_io/override_computer"
import { applyFlowchartUrls, clearFlowchartUrls } from "../../support/flowchart_urls.js"

// English defaults mirroring the Stimulus `static values` on
// PropertyEditorController — see property_editor_controller.js. This bare
// controller fake is not a real Stimulus controller, so it doesn't get Value
// defaults for free; duplicate them here (byte-identical) so _ioLabels()
// resolves to the same strings the real controller would when no
// data-*-value attribute is present.
const ELEMENT_IO_I18N_DEFAULTS = {
  elementIoInputsLabelValue: "Inputs",
  elementIoOutputsLabelValue: "Outputs",
  elementIoNoInputsLabelValue: "No inputs detected",
  elementIoNoOutputsLabelValue: "No outputs detected",
  elementIoRenamedTitleValue: "Auto-renamed to avoid a key collision",
  elementIoRenamedBadgeLabelValue: "renamed",
  elementIoConfigSourceTitleValue: "Driven by a config expression",
  elementIoConfigSourceLabelValue: "config",
  elementIoAutoSourceTitleValue: "Generator-supplied literal",
  elementIoAutoSourceLabelValue: "auto",
  elementIoNoProducerLabelValue: "— no producer —",
  elementIoProducerAriaLabelFormatValue: "Producer for {pin}",
}

const makeMgr = (canvas) => new ElementIoManager({ canvas, ...ELEMENT_IO_I18N_DEFAULTS })

describe("ElementIoManager", () => {
  beforeEach(() => {
    applyFlowchartUrls({
      elementIoParams: "/81721200/admin/maintenance/flowcharts/element_types/__TYPE__/io_params",
      implicitKeys: "/81721200/admin/maintenance/flowcharts/validation/implicit_keys.json",
    })
    window.history.replaceState({}, "", "/81721200/admin/maintenance/flowcharts/1/edit")
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(JSON.stringify({ inputs: [], outputs: [] }))))
  })
  afterEach(() => {
    clearFlowchartUrls()
    vi.unstubAllGlobals()
    window.history.replaceState({}, "", "/")
  })
  describe("updateProducer", () => {
    let el, canvas, mgr
    beforeEach(() => {
      el = { id: "x", properties: {} }
      canvas = { elements: [el], onchange: vi.fn() }
      mgr = makeMgr(canvas)
    })

    it("adds an override entry and fires canvas.onchange", () => {
      mgr.updateProducer("x", "model", "k1")
      expect(el.properties.io_overrides.inputs).toEqual([{ pin: "model", override_key: "k1" }])
      expect(canvas.onchange).toHaveBeenCalled()
    })

    it("replaces an existing entry for the same pin", () => {
      mgr.updateProducer("x", "model", "k1")
      mgr.updateProducer("x", "model", "k2")
      expect(el.properties.io_overrides.inputs).toEqual([{ pin: "model", override_key: "k2" }])
    })

    it("removes the entry when overrideKey is null", () => {
      mgr.updateProducer("x", "model", "k1")
      mgr.updateProducer("x", "model", null)
      expect(el.properties.io_overrides.inputs).toEqual([])
    })

    it("no-ops for an unknown element id", () => {
      expect(() => mgr.updateProducer("ghost", "p", "k")).not.toThrow()
      expect(canvas.onchange).not.toHaveBeenCalled()
    })

    it("initializes properties when the element has none yet", () => {
      const bareEl = { id: "y" }
      canvas.elements.push(bareEl)
      mgr.updateProducer("y", "model", "k1")
      expect(bareEl.properties.io_overrides.inputs).toEqual([{ pin: "model", override_key: "k1" }])
    })

    it("reuses an already-present io_overrides object instead of replacing it", () => {
      const existingOverrides = { inputs: [], outputs: [{ pin: "renamed" }] }
      el.properties.io_overrides = existingOverrides
      mgr.updateProducer("x", "model", "k1")
      expect(el.properties.io_overrides).toBe(existingOverrides)
      expect(el.properties.io_overrides.outputs).toEqual([{ pin: "renamed" }])
    })
  })

  describe("_merge", () => {
    it("keeps user-chosen inputs, appends computed for un-chosen pins, and takes computed outputs", () => {
      const mgr = makeMgr({})
      const merged = mgr._merge(
        { inputs: [{ pin: "a", override_key: "user" }] },
        { inputs: [{ pin: "a", override_key: "auto" }, { pin: "b", override_key: "auto2" }], outputs: [{ pin: "o" }] },
      )
      expect(merged.inputs).toEqual([
        { pin: "a", override_key: "user" },
        { pin: "b", override_key: "auto2" },
      ])
      expect(merged.outputs).toEqual([{ pin: "o" }])
    })

    it("handles a missing existing overrides object", () => {
      const mgr = makeMgr({})
      expect(mgr._merge(undefined, { inputs: [{ pin: "a" }], outputs: [] })).toEqual({
        inputs: [{ pin: "a" }],
        outputs: [],
      })
    })
  })

  describe("_candidatesFromElement", () => {
    it("matches producer outputs whose effective key equals or prefixes the input pin, honoring renames", () => {
      const producer = { id: "p", label: "Producer", type: "process", properties: { io_overrides: { outputs: [{ pin: "token", renamed_to: "token_b7e1" }] } } }
      const canvas = {
        getElementPins: (id) => (id === "p" ? { outputs: [{ pin: "user" }, { pin: "token" }] } : { outputs: [] }),
      }
      const mgr = makeMgr(canvas)
      const cands = mgr._candidatesFromElement(producer, { pin: "user" })
      expect(cands).toEqual([{ effective: "user", label: "Producer" }])
    })

    it("keeps a pin_-prefixed effective key as a candidate", () => {
      const producer = { id: "p", type: "process", properties: {} }
      const canvas = { getElementPins: () => ({ outputs: [{ pin: "user_2" }] }) }
      const mgr = makeMgr(canvas)
      expect(mgr._candidatesFromElement(producer, { pin: "user" })).toEqual([{ effective: "user_2", label: "process" }])
    })

    it("defaults outputs to [] when getElementPins returns no outputs key", () => {
      const producer = { id: "p", type: "process", properties: {} }
      const canvas = { getElementPins: () => ({}) }
      const mgr = makeMgr(canvas)
      expect(mgr._candidatesFromElement(producer, { pin: "user" })).toEqual([])
    })
  })

  describe("_externalCandidates", () => {
    it("walks reversed predecessors and collects their candidates, skipping self", () => {
      const p1 = { id: "p1", label: "P1", type: "process", properties: {} }
      const canvas = {
        elements: [p1],
        getElementPins: (id) => (id === "p1" ? { outputs: [{ pin: "user" }] } : { outputs: [] }),
      }
      const mgr = makeMgr(canvas)
      const reachability = { predecessors: () => ["p1", "self"] }
      const out = mgr._externalCandidates({ id: "self" }, { pin: "user" }, reachability)
      expect(out).toEqual([{ effective: "user", label: "P1" }])
    })

    it("skips a predecessor id that no longer resolves to a canvas element", () => {
      const canvas = { elements: [], getElementPins: () => ({ outputs: [] }) }
      const mgr = makeMgr(canvas)
      const reachability = { predecessors: () => ["ghost"] }
      expect(mgr._externalCandidates({ id: "self" }, { pin: "user" }, reachability)).toEqual([])
    })
  })

  describe("_wireInputHandlers", () => {
    it("routes a producer-select change to updateProducer (sentinel -> empty key)", () => {
      const mgr = makeMgr({ elements: [], onchange: vi.fn() })
      const spy = vi.spyOn(mgr, "updateProducer").mockImplementation(() => {})
      const pane = document.createElement("div")
      pane.innerHTML = `
        <div data-element-io-input data-pin="model">
          <select data-element-io-producer-select>
            <option value="${NO_PRODUCER_SENTINEL}">none</option>
            <option value="k1">k1</option>
          </select>
        </div>`
      mgr._wireInputHandlers({ id: "e1" }, pane)
      const sel = pane.querySelector("select")

      sel.value = NO_PRODUCER_SENTINEL
      sel.dispatchEvent(new Event("change", { bubbles: true }))
      expect(spy).toHaveBeenCalledWith("e1", "model", "")

      sel.value = "k1"
      sel.dispatchEvent(new Event("change", { bubbles: true }))
      expect(spy).toHaveBeenCalledWith("e1", "model", "k1")
    })

    it("ignores a change event whose target isn't inside a data-element-io-input row", () => {
      const mgr = makeMgr({ elements: [], onchange: vi.fn() })
      const spy = vi.spyOn(mgr, "updateProducer").mockImplementation(() => {})
      const pane = document.createElement("div")
      // No wrapping [data-element-io-input] row -> event.target.closest(...) is null.
      pane.innerHTML = `<select data-element-io-producer-select><option value="k1">k1</option></select>`
      mgr._wireInputHandlers({ id: "e1" }, pane)
      const sel = pane.querySelector("select")
      sel.value = "k1"
      sel.dispatchEvent(new Event("change", { bubbles: true }))
      expect(spy).not.toHaveBeenCalled()
    })
  })

  describe("close", () => {
    it("resets internal state without throwing", () => {
      const mgr = makeMgr({ svg: document.createElement("div") })
      mgr._currentElement = { id: "e1" }
      mgr._openEpoch = 3
      mgr.close()
      expect(mgr._openEpoch).toBe(4)
      expect(mgr._currentElement).toBeNull()
    })

    it("removes the structure-change listener from the svg when one was subscribed", () => {
      const svg = document.createElement("div")
      const mgr = makeMgr({ svg })
      const removeSpy = vi.spyOn(svg, "removeEventListener")
      mgr._subscribeToStructureChanges()
      const listener = mgr._structureListener
      mgr.close()
      expect(removeSpy).toHaveBeenCalledWith("flowchartStructureChanged", listener)
      expect(mgr._structureListener).toBeNull()
    })
  })

  describe("_subscribeToStructureChanges", () => {
    it("no-ops when the canvas has no svg", () => {
      const mgr = makeMgr({})
      expect(() => mgr._subscribeToStructureChanges()).not.toThrow()
      expect(mgr._structureListener).toBeUndefined()
    })

    it("is a no-op on a second call once already subscribed", () => {
      const svg = document.createElement("div")
      const mgr = makeMgr({ svg })
      mgr._subscribeToStructureChanges()
      const listener = mgr._structureListener
      mgr._subscribeToStructureChanges()
      expect(mgr._structureListener).toBe(listener)
    })

    it("debounces flowchartStructureChanged into a single re-open of the current element", async () => {
      vi.useFakeTimers()
      const svg = document.createElement("div")
      const element = { id: "e1", type: "process", properties: {} }
      const canvas = {
        elements: [element],
        svg,
        getElementPins: () => ({ inputs: [], outputs: [] }),
        setElementPins: vi.fn(),
        onchange: vi.fn(),
      }
      const mgr = makeMgr(canvas)
      mgr._currentElement = element
      mgr._currentPane = document.createElement("div")
      const openSpy = vi.spyOn(mgr, "openForElement").mockResolvedValue()
      mgr._subscribeToStructureChanges()

      svg.dispatchEvent(new CustomEvent("flowchartStructureChanged"))
      svg.dispatchEvent(new CustomEvent("flowchartStructureChanged")) // resets the debounce timer
      expect(openSpy).not.toHaveBeenCalled()
      await vi.advanceTimersByTimeAsync(150)
      expect(openSpy).toHaveBeenCalledTimes(1)
      expect(openSpy).toHaveBeenCalledWith(element, mgr._currentPane)
      vi.useRealTimers()
    })

    it("swallows a rejection from the debounced re-open", async () => {
      vi.useFakeTimers()
      const svg = document.createElement("div")
      const mgr = makeMgr({ svg })
      mgr._currentElement = { id: "e1" }
      mgr._currentPane = document.createElement("div")
      vi.spyOn(mgr, "openForElement").mockRejectedValue(new Error("boom"))
      mgr._subscribeToStructureChanges()
      svg.dispatchEvent(new CustomEvent("flowchartStructureChanged"))
      await vi.advanceTimersByTimeAsync(150)
      // Draining the microtask queue after the timer fires must not throw / reject.
      await Promise.resolve()
      vi.useRealTimers()
    })

    it("does not re-open when there is no current element/pane at fire time", async () => {
      vi.useFakeTimers()
      const svg = document.createElement("div")
      const mgr = makeMgr({ svg })
      const openSpy = vi.spyOn(mgr, "openForElement").mockResolvedValue()
      mgr._subscribeToStructureChanges()
      svg.dispatchEvent(new CustomEvent("flowchartStructureChanged"))
      await vi.advanceTimersByTimeAsync(150)
      expect(openSpy).not.toHaveBeenCalled()
      vi.useRealTimers()
    })
  })

  describe("openForElement", () => {
    it("ignores an accepted notification for a removed element", async () => {
      const mgr = makeMgr({ elements: [] })
      const pane = document.createElement("div")
      await mgr._renderCurrentPins({ id: "removed" }, pane)
      expect(pane.innerHTML).toBe("")
    })

    it.each(["changed", "removed"])("rejects override computation if the element is %s during its await", async mode => {
      let resolve
      computeElementOverrides.mockImplementationOnce(() => new Promise(done => { resolve = done }))
      const element = { id: "e1", properties: {} }
      const canvas = { elements: [element], getElementPins: () => ({ inputs: [], outputs: [{ pin: "old" }] }) }
      const mgr = makeMgr(canvas)
      const pane = document.createElement("div")
      const pending = mgr._renderCurrentPins(element, pane)
      if (mode === "changed") element.properties.steps = [{ action: "new_model" }]
      else canvas.elements = []
      resolve({ inputs: [], outputs: [] })
      await pending
      expect(pane.innerHTML).toBe("")
      expect(element.properties.io_overrides).toBeUndefined()
    })

    it("renders inputs/outputs into the pane using cached pins (no fetch)", async () => {
      const element = { id: "e1", type: "process", properties: {} }
      const canvas = {
        elements: [element],
        connections: [],
        svg: document.createElement("div"),
        getElementPins: () => ({ inputs: [{ pin: "model" }], outputs: [{ pin: "user" }] }),
        setElementPins: vi.fn(),
        onchange: vi.fn(),
      }
      const mgr = makeMgr(canvas)
      const pane = document.createElement("div")
      await mgr.openForElement(element, pane)
      // Something was rendered and io_overrides was initialized.
      expect(pane.innerHTML.length).toBeGreaterThan(0)
      expect(element.properties.io_overrides).toBeTruthy()
    })

    it("no-ops for a missing element or pane", async () => {
      const mgr = makeMgr({ elements: [] })
      await expect(mgr.openForElement(null, document.createElement("div"))).resolves.toBeUndefined()
    })

    it("no-ops when the controller has no canvas", async () => {
      const mgr = makeMgr(null)
      await expect(
        mgr.openForElement({ id: "e1" }, document.createElement("div"))
      ).resolves.toBeUndefined()
    })

    it("fetches pins when there is no cache, and initializes element.properties when absent", async () => {
      const element = { id: "e1", type: "process" } // no `properties` key at all
      const setElementPins = vi.fn()
      let calls = 0
      const canvas = {
        elements: [element],
        svg: null,
        // 1st call (cache check) has nothing cached; 2nd call (post-fetch snapshot)
        // sees what setElementPins just stored.
        getElementPins: () => (++calls === 1 ? null : { inputs: [], outputs: [] }),
        setElementPins,
        onchange: vi.fn(),
      }
      const mgr = makeMgr(canvas)
      const pane = document.createElement("div")
      await mgr.openForElement(element, pane)
      expect(fetch).toHaveBeenCalledTimes(1)
      expect(setElementPins).toHaveBeenCalled()
      expect(element.properties).toBeTruthy()
    })

    it("also fetches when the cache is present but has zero pins total", async () => {
      const element = { id: "e1", type: "process", properties: {} }
      const setElementPins = vi.fn()
      const canvas = {
        elements: [element],
        svg: null,
        getElementPins: () => ({ inputs: [], outputs: [] }), // cached, but empty -> needsFetch
        setElementPins,
        onchange: vi.fn(),
      }
      const mgr = makeMgr(canvas)
      await mgr.openForElement(element, document.createElement("div"))
      expect(setElementPins).toHaveBeenCalled()
    })

    it("can fill the shared cache after close without rendering the closed pane", async () => {
      let resolveFetch
      fetch.mockImplementationOnce(
        () => new Promise((resolve) => { resolveFetch = resolve })
      )
      const element = { id: "e1", type: "process", properties: {} }
      const setElementPins = vi.fn()
      const canvas = {
        elements: [element],
        svg: null,
        getElementPins: () => null,
        setElementPins,
        onchange: vi.fn(),
      }
      const mgr = makeMgr(canvas)
      const pane = document.createElement("div")
      const pending = mgr.openForElement(element, pane)
      mgr.close()
      resolveFetch(new Response(JSON.stringify({ inputs: [], outputs: [] })))
      await pending
      expect(setElementPins).toHaveBeenCalled()
      expect(pane.innerHTML).toBe("")
    })

    it("bails out via the epoch guard when a newer call started while computeElementOverrides was pending", async () => {
      let resolveCompute
      computeElementOverrides.mockImplementationOnce(
        () => new Promise((resolve) => { resolveCompute = resolve })
      )
      const element = { id: "e1", type: "process", properties: {} }
      const canvas = {
        elements: [element],
        svg: null,
        getElementPins: () => ({ inputs: [{ pin: "model" }], outputs: [{ pin: "user" }] }),
        setElementPins: vi.fn(),
        onchange: vi.fn(),
      }
      const mgr = makeMgr(canvas)
      const pane = document.createElement("div")
      const pending = mgr.openForElement(element, pane)
      mgr._openEpoch = 99
      resolveCompute({ inputs: [], outputs: [] })
      await pending
      expect(pane.innerHTML).toBe("")
      expect(element.properties.io_overrides).toBeUndefined()
    })
  })

  describe("_render", () => {
    it("defaults io_overrides.inputs and .outputs to [] when the element has none", () => {
      const mgr = makeMgr({ elements: [], connections: [], getElementPins: () => ({ outputs: [] }) })
      const element = { id: "e1", properties: {} }
      const pane = document.createElement("div")
      expect(() =>
        mgr._render(element, pane, { inputs: [{ pin: "model" }], outputs: [{ pin: "user" }] })
      ).not.toThrow()
      expect(pane.innerHTML.length).toBeGreaterThan(0)
    })

    it("defaults pins.inputs/outputs and overrides.inputs/outputs to [] when absent", () => {
      const mgr = makeMgr({ elements: [], connections: [], getElementPins: () => ({ outputs: [] }) })
      const element = { id: "e1", properties: { io_overrides: {} } } // truthy io_overrides, no inputs/outputs keys
      const pane = document.createElement("div")
      expect(() => mgr._render(element, pane, {})).not.toThrow() // pins with no inputs/outputs keys
      expect(pane.innerHTML).toContain("No inputs detected")
      expect(pane.innerHTML).toContain("No outputs detected")
    })
  })

  describe("_renderInputRow", () => {
    it("returns a read-only row when there are fewer than 2 candidates", () => {
      const mgr = makeMgr({ getElementPins: () => ({ outputs: [] }) })
      const html = mgr._renderInputRow(
        { id: "e1", properties: {} },
        { pin: "model" },
        [],
        { predecessors: () => [] }
      )
      expect(html).toContain("model")
    })

    it("returns an editable row with the selected key when an override exists and there are 2+ candidates", () => {
      // Two producers of pin "model" -> 2 external candidates -> crosses the editable threshold.
      const canvas = {
        elements: [
          { id: "p1", label: "P1", type: "process", properties: {} },
          { id: "p2", label: "P2", type: "process", properties: {} },
        ],
        getElementPins: (id) =>
          id === "p1" || id === "p2" ? { outputs: [{ pin: "model" }] } : { outputs: [] },
      }
      const mgr = makeMgr(canvas)
      const element = { id: "self", properties: {} }
      const reachability = { predecessors: () => ["p1", "p2"] }
      const html = mgr._renderInputRow(
        element,
        { pin: "model" },
        [{ pin: "model", override_key: "model" }], // matches p1/p2's effective key "model"
        reachability
      )
      expect(html).toContain('data-element-io-producer-select')
      // "wired" -> the "no producer" sentinel option is NOT selected, but the
      // matching producer option(s) are.
      expect(html).not.toContain(`"${NO_PRODUCER_SENTINEL}" selected`)
      expect(html).toContain('value="model" selected')
    })
  })

})
