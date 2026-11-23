// NOTE: happy-dom fully supports window.Selection/Range on text nodes inside a
// contenteditable (verified empirically) — it just returns zeroed
// getBoundingClientRect()/empty getClientRects() for real ranges (no layout engine).
// So caret-driven autocomplete insertion (queryContext / insertFieldFromQuery /
// insertFunctionFromQuery / insertPillAtCaret) IS unit-testable here by constructing
// real Ranges. Only the *visual positioning* branches that need a non-zero rect are
// exercised via a fully-faked window.getSelection() (documented at each call site).
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/formula_editor_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const fields = [
  { id: "a", label: "Alpha", type: "number" },
  { id: "b", label: "Beta", type: "string" },
  { id: "c" }, // deliberately no label/type -> exercises the `field?.label || id` and `f.type || ""` fallbacks
]

const html = (formula = "") => `
  <div data-controller="formula-editor"
       data-formula-editor-fields-value='${JSON.stringify(fields)}'
       data-formula-editor-formula-value="${formula}">
    <div data-formula-editor-target="surface" contenteditable="true"></div>
    <div data-formula-editor-target="autocomplete" class="hidden"></div>
    <span data-formula-editor-target="status"></span>
    <div data-formula-editor-target="preview"></div>
    <div data-formula-editor-target="errors" class="hidden"></div>
    <input data-formula-editor-target="fnSearch">
    <div data-formula-editor-target="fnGrid" data-fn-tabs>
      <button data-category="Math" data-action="click->formula-editor#switchFunctionTab">Math</button>
      <button data-category="Logic" data-action="click->formula-editor#switchFunctionTab">Logic</button>
      <button data-fn-insert data-function="SUM" data-category="Math">SUM</button>
      <button data-fn-insert data-function="IF" data-category="Logic">IF</button>
      <button data-fn-insert data-function="ABS">ABS</button>
      <button data-fn-insert data-category="Math">NoFn</button>
    </div>
    <div data-formula-editor-target="sampleInputs"></div>
  </div>`

// Variants that omit one target, to exercise the `hasXTarget` false branches.
const htmlNoSampleInputs = (formula = "") => `
  <div data-controller="formula-editor"
       data-formula-editor-fields-value='${JSON.stringify(fields)}'
       data-formula-editor-formula-value="${formula}">
    <div data-formula-editor-target="surface" contenteditable="true"></div>
    <div data-formula-editor-target="autocomplete" class="hidden"></div>
    <span data-formula-editor-target="status"></span>
  </div>`

const htmlNoFnGrid = (formula = "") => `
  <div data-controller="formula-editor"
       data-formula-editor-fields-value='${JSON.stringify(fields)}'
       data-formula-editor-formula-value="${formula}">
    <div data-formula-editor-target="surface" contenteditable="true"></div>
    <div data-formula-editor-target="autocomplete" class="hidden"></div>
    <input data-formula-editor-target="fnSearch">
  </div>`

const htmlNoFnSearch = (formula = "") => `
  <div data-controller="formula-editor"
       data-formula-editor-fields-value='${JSON.stringify(fields)}'
       data-formula-editor-formula-value="${formula}">
    <div data-formula-editor-target="surface" contenteditable="true"></div>
    <div data-formula-editor-target="autocomplete" class="hidden"></div>
    <div data-formula-editor-target="fnGrid" data-fn-tabs>
      <button data-category="Math" data-action="click->formula-editor#switchFunctionTab">Math</button>
      <button data-category="Logic" data-action="click->formula-editor#switchFunctionTab">Logic</button>
      <button data-fn-insert data-function="SUM" data-category="Math">SUM</button>
      <button data-fn-insert data-function="IF" data-category="Logic">IF</button>
    </div>
  </div>`

const surface = (el) => el.querySelector("[data-formula-editor-target='surface']")
const status = (el) => el.querySelector("[data-formula-editor-target='status']")
const autocomplete = (el) => el.querySelector("[data-formula-editor-target='autocomplete']")
const chip = (el, fn) => el.querySelector(`[data-fn-insert][data-function='${fn}']`)

// Places a collapsed caret at `offset` inside `node` (text node, or an element for
// "caret between children") and returns the live Selection.
const setCaret = (node, offset) => {
  const sel = window.getSelection()
  const range = document.createRange()
  range.setStart(node, offset)
  range.collapse(true)
  sel.removeAllRanges()
  sel.addRange(range)
  return sel
}

// Places a non-collapsed selection spanning [startNode,startOffset) .. (endNode,endOffset).
const setRange = (startNode, startOffset, endNode, endOffset) => {
  const sel = window.getSelection()
  const range = document.createRange()
  range.setStart(startNode, startOffset)
  range.setEnd(endNode, endOffset)
  sel.removeAllRanges()
  sel.addRange(range)
  return sel
}

describe("formula-editor controller", () => {
  let application, element, ctrl
  const mount = async (formula) => {
    ;({ application, element } = await mountController("formula-editor", Controller, html(formula)))
    ctrl = controllerFor(application, element, "formula-editor")
  }
  beforeEach(() => mount(""))
  afterEach(() => vi.restoreAllMocks())

  // Mount `formula`, then drop a collapsed caret at the end of the surface's text.
  const caretAtEnd = async (formula) => {
    await mount(formula)
    const tn = surface(element).firstChild
    setCaret(tn, tn.length)
    return tn
  }

  // Remount the controller against one of the target-omitting HTML variants.
  const remount = async (htmlFn, formula = "") => {
    ;({ application, element } = await mountController("formula-editor", Controller, htmlFn(formula)))
    ctrl = controllerFor(application, element, "formula-editor")
  }

  // Fake window.getSelection() so a single active range reports the given caret rects.
  const stubCaretRects = (rects, bounding = { left: 0, top: 0, bottom: 0, right: 0 }) =>
    vi.spyOn(window, "getSelection").mockReturnValue({
      rangeCount: 1,
      getRangeAt: () => ({ getClientRects: () => rects, getBoundingClientRect: () => bounding }),
    })

  describe("hydrate / serialize", () => {
    it("renders a field pill labeled by the field map and round-trips to {id}", async () => {
      await mount("{a} + 2")
      const pill = surface(element).querySelector("[data-pill]")
      expect(pill).not.toBeNull()
      expect(pill.dataset.fieldId).toBe("a")
      expect(pill.textContent).toContain("Alpha")
      expect(ctrl.serialize()).toBe("{a} + 2")
      expect(ctrl.getFormula()).toBe("{a} + 2")
    })

    it("uses the raw id as the pill label for unknown fields", () => {
      const pill = ctrl.buildPill("unknown_id")
      expect(pill.textContent).toContain("unknown_id")
    })

    it("clicking a pill's × removes it and revalidates", async () => {
      await mount("{a}")
      const x = surface(element).querySelector("[data-pill] span:last-child")
      x.dispatchEvent(new Event("click", { bubbles: true }))
      expect(surface(element).querySelector("[data-pill]")).toBeNull()
      expect(ctrl.serialize()).toBe("")
    })
  })

  describe("validation", () => {
    it("marks a valid formula and fires a changed event", async () => {
      await mount("{a} + 2")
      // connect() validates once; assert the current status reflects validity.
      expect(status(element).textContent).toContain("Valid")
      const spy = vi.fn()
      element.addEventListener("formula-editor:changed", spy)
      ctrl.validate()
      expect(spy).toHaveBeenCalled()
      expect(spy.mock.calls.at(-1)[0].detail.valid).toBe(true)
    })

    it("flags an unknown field reference as an error", async () => {
      await mount("{z}")
      expect(status(element).textContent).toContain("✗")
      expect(element.querySelector("[data-formula-editor-target='errors']").textContent).toContain("Unknown field: z")
    })
  })

  describe("function chip filter", () => {
    it("shows only the active category (Math) on connect", () => {
      expect(chip(element, "SUM").style.display).toBe("")
      expect(chip(element, "IF").style.display).toBe("none")
    })

    it("switchFunctionTab reveals the chosen category", () => {
      ctrl.switchFunctionTab({ currentTarget: element.querySelector("[data-category='Logic']") })
      expect(chip(element, "IF").style.display).toBe("")
      expect(chip(element, "SUM").style.display).toBe("none")
    })

    it("filterFunctions searches across all categories by name", () => {
      element.querySelector("[data-formula-editor-target='fnSearch']").value = "if"
      ctrl.filterFunctions()
      expect(chip(element, "IF").style.display).toBe("")
      expect(chip(element, "SUM").style.display).toBe("none")
    })
  })

  describe("insertion fallbacks (no caret in surface)", () => {
    it("insertFieldChip appends a pill for the chosen field", () => {
      ctrl.insertFieldChip({ currentTarget: { dataset: { fieldId: "b" }, tagName: "BUTTON" } })
      const pills = surface(element).querySelectorAll("[data-pill]")
      expect(pills.length).toBe(1)
      expect(ctrl.serialize()).toBe("{b}")
    })

    it("insertFunctionToken appends 'FN()' to the surface", () => {
      ctrl.insertFunctionToken({ currentTarget: { dataset: { function: "SUM" } } })
      expect(surface(element).textContent).toContain("SUM()")
    })

    it("insertFunctionToken ignores a chip with no function name", () => {
      const before = surface(element).textContent
      ctrl.insertFunctionToken({ currentTarget: { dataset: {} } })
      expect(surface(element).textContent).toBe(before)
    })
  })

  describe("autocomplete teardown", () => {
    it("closeAutocomplete hides and empties the dropdown", () => {
      const dd = element.querySelector("[data-formula-editor-target='autocomplete']")
      dd.classList.remove("hidden")
      dd.innerHTML = "<div>x</div>"
      ctrl.closeAutocomplete()
      expect(dd.classList.contains("hidden")).toBe(true)
      expect(dd.innerHTML).toBe("")
    })
  })

  describe("sample values", () => {
    it("setSampleValues stores values and revalidates", async () => {
      await mount("{a} + 1")
      ctrl.setSampleValues({ a: 5 })
      expect(ctrl.sampleValues()).toEqual({ a: 5 })
    })
  })

  describe("hydrate leading text before a pill (line 65 branch)", () => {
    it("preserves text that precedes the first field reference", async () => {
      await mount("x+{a}")
      const nodes = surface(element).childNodes
      expect(nodes[0].nodeType).toBe(Node.TEXT_NODE)
      expect(nodes[0].textContent).toBe("x+")
      expect(nodes[1].dataset.fieldId).toBe("a")
      expect(ctrl.serialize()).toBe("x+{a}")
    })
  })

  describe("validation pluralization", () => {
    it("uses the plural 'errors' suffix for 2+ errors", async () => {
      await mount("{y}+{z}")
      expect(status(element).textContent).toBe("✗ 2 errors")
    })

    it("uses the singular 'error' suffix for exactly 1 error", async () => {
      await mount("{z}")
      expect(status(element).textContent).toBe("✗ 1 error")
    })
  })

  describe("onInput / onBlur debounce", () => {
    it("onInput refreshes the autocomplete synchronously and debounces validate by 150ms", () => {
      vi.useFakeTimers()
      const updSpy = vi.spyOn(ctrl, "updateAutocomplete")
      const valSpy = vi.spyOn(ctrl, "validate")
      ctrl.onInput()
      expect(updSpy).toHaveBeenCalledTimes(1)
      expect(valSpy).not.toHaveBeenCalled()
      vi.advanceTimersByTime(149)
      expect(valSpy).not.toHaveBeenCalled()
      vi.advanceTimersByTime(1)
      expect(valSpy).toHaveBeenCalledTimes(1)
      vi.useRealTimers()
    })

    it("a second onInput within the debounce window cancels the first timer", () => {
      vi.useFakeTimers()
      const valSpy = vi.spyOn(ctrl, "validate")
      ctrl.onInput()
      vi.advanceTimersByTime(100)
      ctrl.onInput()
      vi.advanceTimersByTime(100)
      expect(valSpy).not.toHaveBeenCalled()
      vi.advanceTimersByTime(50)
      expect(valSpy).toHaveBeenCalledTimes(1)
      vi.useRealTimers()
    })

    it("onBlur closes the autocomplete after a 150ms delay", () => {
      vi.useFakeTimers()
      const closeSpy = vi.spyOn(ctrl, "closeAutocomplete")
      ctrl.onBlur()
      expect(closeSpy).not.toHaveBeenCalled()
      vi.advanceTimersByTime(150)
      expect(closeSpy).toHaveBeenCalledTimes(1)
      vi.useRealTimers()
    })
  })

  describe("onKeydown — autocomplete navigation", () => {
    beforeEach(() => {
      ctrl._autocompleteMode = "field"
      ctrl._acItems = [
        { label: "Alpha", sub: "number", value: "a", type: "field" },
        { label: "Beta", sub: "string", value: "b", type: "field" },
      ]
      ctrl._acIndex = -1
      autocomplete(element).innerHTML = "<div></div><div></div>"
    })

    it("ArrowDown moves the index forward, highlights it, and prevents default", () => {
      const evt = { key: "ArrowDown", preventDefault: vi.fn() }
      ctrl.onKeydown(evt)
      expect(evt.preventDefault).toHaveBeenCalled()
      expect(ctrl._acIndex).toBe(0)
      expect(autocomplete(element).children[0].classList.contains("bg-purple-100")).toBe(true)
      expect(autocomplete(element).children[1].classList.contains("bg-purple-100")).toBe(false)
    })

    it("ArrowDown wraps from the last item back to the first", () => {
      ctrl._acIndex = 1
      ctrl.onKeydown({ key: "ArrowDown", preventDefault: vi.fn() })
      expect(ctrl._acIndex).toBe(0)
    })

    it("ArrowUp moves the index backward and prevents default", () => {
      ctrl._acIndex = 1
      const evt = { key: "ArrowUp", preventDefault: vi.fn() }
      ctrl.onKeydown(evt)
      expect(evt.preventDefault).toHaveBeenCalled()
      expect(ctrl._acIndex).toBe(0)
    })

    it("ArrowUp wraps from the first item back to the last", () => {
      ctrl._acIndex = 0
      ctrl.onKeydown({ key: "ArrowUp", preventDefault: vi.fn() })
      expect(ctrl._acIndex).toBe(1)
    })

    it("Enter accepts the highlighted suggestion when one is highlighted", () => {
      ctrl._acIndex = 1
      const selSpy = vi.spyOn(ctrl, "selectAcItem").mockImplementation(() => {})
      const evt = { key: "Enter", preventDefault: vi.fn() }
      ctrl.onKeydown(evt)
      expect(evt.preventDefault).toHaveBeenCalled()
      expect(selSpy).toHaveBeenCalledWith(1)
    })

    it("Tab accepts the highlighted suggestion when one is highlighted", () => {
      ctrl._acIndex = 0
      const selSpy = vi.spyOn(ctrl, "selectAcItem").mockImplementation(() => {})
      ctrl.onKeydown({ key: "Tab", preventDefault: vi.fn() })
      expect(selSpy).toHaveBeenCalledWith(0)
    })

    it("Enter does nothing special when no item is highlighted (index -1)", () => {
      ctrl._acIndex = -1
      const selSpy = vi.spyOn(ctrl, "selectAcItem")
      const evt = { key: "Enter", preventDefault: vi.fn() }
      ctrl.onKeydown(evt)
      expect(selSpy).not.toHaveBeenCalled()
      // falls through to the Backspace branch (no-op for this key) without throwing
      expect(evt.preventDefault).not.toHaveBeenCalled()
    })

    it("Escape closes the autocomplete and prevents default", () => {
      const closeSpy = vi.spyOn(ctrl, "closeAutocomplete")
      const evt = { key: "Escape", preventDefault: vi.fn() }
      ctrl.onKeydown(evt)
      expect(evt.preventDefault).toHaveBeenCalled()
      expect(closeSpy).toHaveBeenCalled()
    })

    it("an unrelated key while autocomplete is open does not throw or preventDefault", () => {
      const evt = { key: "a", preventDefault: vi.fn() }
      expect(() => ctrl.onKeydown(evt)).not.toThrow()
      expect(evt.preventDefault).not.toHaveBeenCalled()
    })

    it("arrow keys are ignored when the autocomplete list is empty", () => {
      ctrl._acItems = []
      const evt = { key: "ArrowDown", preventDefault: vi.fn() }
      ctrl.onKeydown(evt)
      expect(evt.preventDefault).not.toHaveBeenCalled()
    })
  })

  describe("onKeydown — Backspace pill deletion", () => {
    it("deletes the preceding pill when the caret sits at offset 0 of a text node", async () => {
      await mount("{a}xyz")
      const textNode = surface(element).childNodes[1]
      setCaret(textNode, 0)
      const evt = { key: "Backspace", preventDefault: vi.fn() }
      ctrl.onKeydown(evt)
      expect(evt.preventDefault).toHaveBeenCalled()
      expect(surface(element).querySelector("[data-pill]")).toBeNull()
      expect(ctrl.serialize()).toBe("xyz")
    })

    it("deletes the preceding pill when the caret sits directly in the surface after it", async () => {
      await mount("{a}")
      const surf = surface(element)
      setCaret(surf, surf.childNodes.length)
      const evt = { key: "Backspace", preventDefault: vi.fn() }
      ctrl.onKeydown(evt)
      expect(evt.preventDefault).toHaveBeenCalled()
      expect(surf.querySelector("[data-pill]")).toBeNull()
      expect(ctrl.serialize()).toBe("")
    })

    it("does nothing when Backspace is pressed mid-text (not adjacent to a pill)", async () => {
      await mount("{a}xyz")
      const textNode = surface(element).childNodes[1]
      setCaret(textNode, 2) // offset > 0, no adjacency check applies
      const evt = { key: "Backspace", preventDefault: vi.fn() }
      ctrl.onKeydown(evt)
      expect(evt.preventDefault).not.toHaveBeenCalled()
      expect(surface(element).querySelector("[data-pill]")).not.toBeNull()
    })

    it("does nothing when the text node at offset 0 has no previous pill sibling", async () => {
      await mount("xyz")
      const textNode = surface(element).childNodes[0]
      setCaret(textNode, 0)
      const evt = { key: "Backspace", preventDefault: vi.fn() }
      expect(() => ctrl.onKeydown(evt)).not.toThrow()
      expect(evt.preventDefault).not.toHaveBeenCalled()
    })

    it("does nothing when the caret is in the surface at offset 0 (no previous sibling)", async () => {
      await mount("{a}")
      const surf = surface(element)
      setCaret(surf, 0)
      const evt = { key: "Backspace", preventDefault: vi.fn() }
      ctrl.onKeydown(evt)
      expect(evt.preventDefault).not.toHaveBeenCalled()
      expect(surf.querySelector("[data-pill]")).not.toBeNull()
    })

    it("does nothing when the selection is not collapsed", async () => {
      await mount("{a}xyz")
      const textNode = surface(element).childNodes[1]
      setRange(textNode, 0, textNode, 2)
      const evt = { key: "Backspace", preventDefault: vi.fn() }
      ctrl.onKeydown(evt)
      expect(evt.preventDefault).not.toHaveBeenCalled()
      expect(surface(element).querySelector("[data-pill]")).not.toBeNull()
    })
  })

  describe("queryContext", () => {
    it("returns null when there is no selection", () => {
      vi.spyOn(window, "getSelection").mockReturnValue(null)
      expect(ctrl.queryContext()).toBeNull()
    })

    it("returns null when the selection is not collapsed", async () => {
      await mount("hello")
      const tn = surface(element).firstChild
      setRange(tn, 0, tn, 2)
      expect(ctrl.queryContext()).toBeNull()
    })

    it("returns null when rangeCount is 0 (no active range)", () => {
      expect(ctrl.queryContext()).toBeNull()
    })

    it("returns null when the caret is not inside a text node", async () => {
      await mount("{a}")
      const surf = surface(element)
      setCaret(surf, 1)
      expect(ctrl.queryContext()).toBeNull()
    })

    it("returns a field context for an unterminated '{partial'", async () => {
      await mount("hi {al")
      const tn = surface(element).firstChild
      setCaret(tn, tn.length)
      expect(ctrl.queryContext()).toEqual({ mode: "field", query: "al" })
    })

    it("returns a function context for a trailing run of letters", async () => {
      await mount("1 + su")
      const tn = surface(element).firstChild
      setCaret(tn, tn.length)
      expect(ctrl.queryContext()).toEqual({ mode: "function", query: "su" })
    })

    it("returns null when the caret follows neither an open brace nor letters", async () => {
      await mount("1 + 2 ")
      const tn = surface(element).firstChild
      setCaret(tn, tn.length)
      expect(ctrl.queryContext()).toBeNull()
    })
  })

  describe("updateAutocomplete", () => {
    it("closes the autocomplete when queryContext yields no context", () => {
      const closeSpy = vi.spyOn(ctrl, "closeAutocomplete")
      ctrl.updateAutocomplete() // fresh mount, no caret -> queryContext() is null
      expect(closeSpy).toHaveBeenCalled()
    })

    it("shows matching field suggestions filtered by label", async () => {
      await mount("hi {al")
      const tn = surface(element).firstChild
      setCaret(tn, tn.length)
      ctrl.updateAutocomplete()
      expect(autocomplete(element).classList.contains("hidden")).toBe(false)
      const labels = Array.from(autocomplete(element).children).map(c => c.textContent)
      expect(labels.join(",")).toContain("Alpha")
      expect(labels.join(",")).not.toContain("Beta")
    })

    it("shows all fields when the field query is empty", async () => {
      await mount("hi {")
      const tn = surface(element).firstChild
      setCaret(tn, tn.length)
      ctrl.updateAutocomplete()
      expect(autocomplete(element).children.length).toBe(fields.length)
    })

    it("closes the autocomplete when no field matches the query", async () => {
      await mount("hi {zzzzz")
      const tn = surface(element).firstChild
      setCaret(tn, tn.length)
      const closeSpy = vi.spyOn(ctrl, "closeAutocomplete")
      ctrl.updateAutocomplete()
      expect(closeSpy).toHaveBeenCalled()
    })

    it("shows matching function suggestions filtered by prefix", async () => {
      await mount("1 + su")
      const tn = surface(element).firstChild
      setCaret(tn, tn.length)
      ctrl.updateAutocomplete()
      expect(autocomplete(element).classList.contains("hidden")).toBe(false)
      const labels = Array.from(autocomplete(element).children).map(c => c.textContent)
      expect(labels.some(l => l.includes("SUM"))).toBe(true)
      expect(labels.some(l => l.includes("SUBTRACT"))).toBe(true)
    })

    it("closes the autocomplete when no function matches the prefix", async () => {
      await mount("1 + zzzzz")
      const tn = surface(element).firstChild
      setCaret(tn, tn.length)
      const closeSpy = vi.spyOn(ctrl, "closeAutocomplete")
      ctrl.updateAutocomplete()
      expect(closeSpy).toHaveBeenCalled()
    })
  })

  describe("showAutocomplete", () => {
    it("renders a label and a sub line when item.sub is present", () => {
      ctrl.showAutocomplete([{ label: "SUM", sub: "SUM(n1, n2, ...)", value: "SUM", type: "function" }], "function")
      const item = autocomplete(element).children[0]
      expect(item.children.length).toBe(2)
      expect(item.textContent).toContain("SUM")
      expect(item.textContent).toContain("SUM(n1, n2, ...)")
    })

    it("renders only the label span when item.sub is falsy", () => {
      ctrl.showAutocomplete([{ label: "Alpha", sub: "", value: "a", type: "field" }], "field")
      const item = autocomplete(element).children[0]
      expect(item.children.length).toBe(1)
    })

    it("clicking (mousedown on) a suggestion selects it", () => {
      const selSpy = vi.spyOn(ctrl, "selectAcItem").mockImplementation(() => {})
      ctrl.showAutocomplete([{ label: "Alpha", sub: "", value: "a", type: "field" }], "field")
      const item = autocomplete(element).children[0]
      const evt = new Event("mousedown", { bubbles: true, cancelable: true })
      item.dispatchEvent(evt)
      expect(selSpy).toHaveBeenCalledWith(0)
      expect(evt.defaultPrevented).toBe(true)
    })

    it("resets the highlighted index to 0 when the previous index is out of range", () => {
      ctrl._acIndex = 99
      ctrl.showAutocomplete([{ label: "A", value: "a", type: "field" }], "field")
      expect(ctrl._acIndex).toBe(0)
    })

    it("keeps the highlighted index when still in range", () => {
      ctrl._acIndex = 1
      ctrl.showAutocomplete(
        [{ label: "A", value: "a", type: "field" }, { label: "B", value: "b", type: "field" }],
        "field"
      )
      expect(ctrl._acIndex).toBe(1)
    })
  })

  describe("positionAutocomplete", () => {
    it("falls back to the surface rect when there is no active selection range", () => {
      // fresh mount: window.getSelection() has rangeCount === 0
      ctrl.showAutocomplete([{ label: "A", value: "a", type: "field" }], "field")
      const dd = autocomplete(element)
      expect(dd.style.position).toBe("fixed")
      expect(dd.style.left).toBe("0px")
      expect(dd.style.top).toBe("4px") // surfaceTarget rect is all zeros in happy-dom
    })

    it("falls back to the surface rect when window.getSelection() returns null", () => {
      vi.spyOn(window, "getSelection").mockReturnValue(null)
      ctrl.positionAutocomplete()
      const dd = autocomplete(element)
      expect(dd.style.left).toBe("0px")
      expect(dd.style.top).toBe("4px")
    })

    it("falls back to the surface rect when a real (zero) Range is active", async () => {
      await mount("hi {al")
      const tn = surface(element).firstChild
      setCaret(tn, tn.length)
      ctrl.positionAutocomplete()
      const dd = autocomplete(element)
      expect(dd.style.left).toBe("0px")
      expect(dd.style.top).toBe("4px")
    })

    it("uses the caret's client rect when getClientRects() returns a non-zero rect", () => {
      vi.spyOn(window, "getSelection").mockReturnValue({
        rangeCount: 1,
        getRangeAt: () => ({
          getClientRects: () => [{ left: 15, top: 20, bottom: 40, right: 100 }],
          getBoundingClientRect: () => ({ left: 0, top: 0, bottom: 0, right: 0 }),
        }),
      })
      ctrl.positionAutocomplete()
      const dd = autocomplete(element)
      expect(dd.style.left).toBe("15px")
      expect(dd.style.top).toBe("44px")
    })

    it("falls back to getBoundingClientRect() when getClientRects() is empty but the rect is non-zero", () => {
      vi.spyOn(window, "getSelection").mockReturnValue({
        rangeCount: 1,
        getRangeAt: () => ({
          getClientRects: () => [],
          getBoundingClientRect: () => ({ left: 8, top: 9, bottom: 12, right: 50 }),
        }),
      })
      ctrl.positionAutocomplete()
      const dd = autocomplete(element)
      expect(dd.style.left).toBe("8px")
      expect(dd.style.top).toBe("16px")
    })

    it("falls back to the surface rect when the caret rect is zero (left:0, top:0)", () => {
      vi.spyOn(window, "getSelection").mockReturnValue({
        rangeCount: 1,
        getRangeAt: () => ({
          getClientRects: () => [{ left: 0, top: 0, bottom: 5, right: 5 }],
          getBoundingClientRect: () => ({ left: 0, top: 0, bottom: 0, right: 0 }),
        }),
      })
      ctrl.positionAutocomplete()
      const dd = autocomplete(element)
      expect(dd.style.left).toBe("0px")
      expect(dd.style.top).toBe("4px")
    })

    it("keeps a rect whose left is 0 but top is non-zero (does not fall back)", () => {
      vi.spyOn(window, "getSelection").mockReturnValue({
        rangeCount: 1,
        getRangeAt: () => ({
          getClientRects: () => [{ left: 0, top: 20, bottom: 25, right: 5 }],
          getBoundingClientRect: () => ({ left: 0, top: 0, bottom: 0, right: 0 }),
        }),
      })
      ctrl.positionAutocomplete()
      const dd = autocomplete(element)
      expect(dd.style.left).toBe("0px")
      expect(dd.style.top).toBe("29px")
    })
  })

  describe("highlightAcItem", () => {
    it("toggles bg-purple-100 only on the active item and does not throw calling scrollIntoView", () => {
      autocomplete(element).innerHTML = "<div></div><div></div><div></div>"
      ctrl._acIndex = 2
      expect(() => ctrl.highlightAcItem()).not.toThrow()
      const children = autocomplete(element).children
      expect(children[0].classList.contains("bg-purple-100")).toBe(false)
      expect(children[1].classList.contains("bg-purple-100")).toBe(false)
      expect(children[2].classList.contains("bg-purple-100")).toBe(true)
    })
  })

  describe("selectAcItem", () => {
    it("does nothing when the index has no matching item", () => {
      ctrl._acItems = []
      const focusSpy = vi.spyOn(surface(element), "focus")
      expect(() => ctrl.selectAcItem(0)).not.toThrow()
      expect(focusSpy).not.toHaveBeenCalled()
    })

    it("inserts a field pill, closes the autocomplete, focuses, and revalidates for a field item", () => {
      ctrl._acItems = [{ label: "Alpha", value: "a", type: "field" }]
      const insertSpy = vi.spyOn(ctrl, "insertFieldFromQuery").mockImplementation(() => {})
      const closeSpy = vi.spyOn(ctrl, "closeAutocomplete")
      const valSpy = vi.spyOn(ctrl, "validate")
      ctrl.selectAcItem(0)
      expect(insertSpy).toHaveBeenCalledWith("a")
      expect(closeSpy).toHaveBeenCalled()
      expect(valSpy).toHaveBeenCalled()
    })

    it("inserts a function token for a function item", () => {
      ctrl._acItems = [{ label: "SUM", value: "SUM", type: "function" }]
      const insertSpy = vi.spyOn(ctrl, "insertFunctionFromQuery").mockImplementation(() => {})
      ctrl.selectAcItem(0)
      expect(insertSpy).toHaveBeenCalledWith("SUM")
    })
  })

  describe("insertPillAtCaret", () => {
    it("appends to the end when there is no selection", () => {
      vi.spyOn(window, "getSelection").mockReturnValue(null)
      ctrl.insertPillAtCaret("a")
      expect(surface(element).querySelector("[data-pill]").dataset.fieldId).toBe("a")
    })

    it("appends to the end when the selection is not collapsed", async () => {
      await mount("xyz")
      const tn = surface(element).firstChild
      setRange(tn, 0, tn, 2)
      ctrl.insertPillAtCaret("b")
      const pill = surface(element).querySelector("[data-pill]")
      expect(pill).not.toBeNull()
      expect(pill).toBe(surface(element).lastChild)
    })

    it("inserts the pill at the caret position and deletes any selected content", async () => {
      await mount("xyz")
      const tn = surface(element).firstChild
      setCaret(tn, 1) // between "x" and "yz"
      ctrl.insertPillAtCaret("b")
      expect(ctrl.serialize()).toBe("x{b}yz")
      // caret should now sit right after the pill
      const sel = window.getSelection()
      expect(sel.isCollapsed).toBe(true)
    })
  })

  describe("insertFieldFromQuery", () => {
    it("removes the typed '{partial' text and inserts the field pill in its place", async () => {
      await mount("hello {al")
      const tn = surface(element).firstChild
      setCaret(tn, tn.length)
      ctrl.insertFieldFromQuery("a")
      expect(ctrl.serialize()).toBe("hello {a}")
    })

    it("inserts a pill without removing text when the caret is not in a text node", async () => {
      await mount("{a}")
      const surf = surface(element)
      setCaret(surf, 1) // caret between/after elements, not inside a text node
      ctrl.insertFieldFromQuery("b")
      expect(ctrl.serialize()).toBe("{a}{b}")
    })
  })

  describe("insertFunctionFromQuery", () => {
    it("falls back to appending 'FUNC()' when there is no selection", () => {
      vi.spyOn(window, "getSelection").mockReturnValue(null)
      ctrl.insertFunctionFromQuery("SUM")
      expect(surface(element).textContent).toBe("SUM()")
    })

    it("falls back to appending 'FUNC()' when the selection is not collapsed", async () => {
      await mount("xyz")
      const tn = surface(element).firstChild
      setRange(tn, 0, tn, 2)
      ctrl.insertFunctionFromQuery("SUM")
      expect(surface(element).textContent).toBe("xyzSUM()")
    })

    it("falls back to appending 'FUNC()' when the caret is not inside a text node", async () => {
      await mount("{a}")
      const surf = surface(element)
      setCaret(surf, 1)
      ctrl.insertFunctionFromQuery("SUM")
      expect(surface(element).textContent).toContain("SUM()")
    })

    it("replaces the typed prefix with 'FUNC()' and parks the caret inside the parens", async () => {
      await mount("1 + su")
      const tn = surface(element).firstChild
      setCaret(tn, tn.length)
      ctrl.insertFunctionFromQuery("SUM")
      expect(surface(element).textContent).toBe("1 + SUM()")
      const sel = window.getSelection()
      expect(sel.anchorOffset).toBe("1 + SUM(".length)
    })

    it("inserts 'FUNC()' at the caret when there is no letter run to replace", async () => {
      await mount("1 + ")
      const tn = surface(element).firstChild
      setCaret(tn, tn.length)
      ctrl.insertFunctionFromQuery("SUM")
      expect(surface(element).textContent).toBe("1 + SUM()")
    })
  })

  describe("insertFunctionToken — caret-aware branches", () => {
    it("falls back to appending when the caret is outside the surface", async () => {
      await mount("")
      const outside = document.createElement("div")
      outside.textContent = "elsewhere"
      document.body.appendChild(outside)
      setCaret(outside.firstChild, 0)
      ctrl.insertFunctionToken({ currentTarget: { dataset: { function: "SUM" } } })
      expect(surface(element).textContent).toBe("SUM()")
    })

    it("inserts at a collapsed caret inside the surface without collapsing a range", async () => {
      await mount("xy")
      const tn = surface(element).firstChild
      setCaret(tn, 1)
      ctrl.insertFunctionToken({ currentTarget: { dataset: { function: "SUM" } } })
      expect(surface(element).textContent).toBe("xSUM()y")
    })

    it("collapses a non-collapsed selection to its end before inserting", async () => {
      await mount("xyz")
      const tn = surface(element).firstChild
      setRange(tn, 0, tn, 2) // select "xy", collapses to end (offset 2) before insert
      ctrl.insertFunctionToken({ currentTarget: { dataset: { function: "SUM" } } })
      expect(surface(element).textContent).toBe("xySUM()z")
    })
  })

  describe("_placeCaretInsideParens", () => {
    it("does nothing when there is no selection", () => {
      vi.spyOn(window, "getSelection").mockReturnValue(null)
      const node = document.createTextNode("SUM()")
      expect(() => ctrl._placeCaretInsideParens(node, "SUM")).not.toThrow()
    })
  })

  describe("switchFunctionTab — extra branches", () => {
    it("does nothing when the clicked element has no data-category", () => {
      const before = chip(element, "SUM").style.display
      ctrl.switchFunctionTab({ currentTarget: { dataset: {} } })
      expect(chip(element, "SUM").style.display).toBe(before)
    })

    it("updates the active category even when no [data-fn-tabs] ancestor is found", () => {
      ctrl.switchFunctionTab({ currentTarget: { dataset: { category: "Logic" }, closest: () => null } })
      ctrl._applyFnFilter()
      expect(chip(element, "IF").style.display).toBe("")
      expect(chip(element, "SUM").style.display).toBe("none")
    })

    it("clears the fnSearch value on tab switch when the target is present", () => {
      element.querySelector("[data-formula-editor-target='fnSearch']").value = "abc"
      ctrl.switchFunctionTab({ currentTarget: element.querySelector("[data-category='Math']") })
      expect(element.querySelector("[data-formula-editor-target='fnSearch']").value).toBe("")
    })

    it("skips clearing fnSearch when the target is absent", async () => {
      ;({ application, element } = await mountController("formula-editor", Controller, htmlNoFnSearch("")))
      ctrl = controllerFor(application, element, "formula-editor")
      expect(() =>
        ctrl.switchFunctionTab({ currentTarget: element.querySelector("[data-category='Logic']") })
      ).not.toThrow()
      expect(chip(element, "IF").style.display).toBe("")
    })
  })

  describe("_applyFnFilter — extra branches", () => {
    it("is a no-op when the fnGrid target is absent", async () => {
      ;({ application, element } = await mountController("formula-editor", Controller, htmlNoFnGrid("")))
      ctrl = controllerFor(application, element, "formula-editor")
      expect(() => ctrl.filterFunctions()).not.toThrow()
    })

    it("treats a missing fnSearch target as an empty search term", async () => {
      ;({ application, element } = await mountController("formula-editor", Controller, htmlNoFnSearch("")))
      ctrl = controllerFor(application, element, "formula-editor")
      // No search target -> term defaults to "" -> falls back to category-based filtering.
      expect(chip(element, "SUM").style.display).toBe("")
      expect(chip(element, "IF").style.display).toBe("none")
    })

    it("falls back to 'Math' when _activeFnCategory is falsy", () => {
      ctrl._activeFnCategory = null
      ctrl._applyFnFilter()
      expect(chip(element, "SUM").style.display).toBe("")
      expect(chip(element, "IF").style.display).toBe("none")
    })

    it("treats a chip with no data-category as belonging to no category (hidden by default tab)", () => {
      ctrl._applyFnFilter()
      expect(chip(element, "ABS").style.display).toBe("none")
    })

    it("a search term matches a chip with no data-category by name", () => {
      element.querySelector("[data-formula-editor-target='fnSearch']").value = "ab"
      ctrl.filterFunctions()
      expect(chip(element, "ABS").style.display).toBe("")
    })
  })

  describe("insertFieldChip — extra branches", () => {
    it("falls back to el.value when dataset.fieldId is absent (e.g. a <select>)", () => {
      const fakeSelect = { dataset: {}, value: "b", tagName: "SELECT" }
      ctrl.insertFieldChip({ currentTarget: fakeSelect })
      expect(ctrl.serialize()).toBe("{b}")
      expect(fakeSelect.value).toBe("")
    })

    it("does nothing when neither dataset.fieldId nor value is present", () => {
      const fake = { dataset: {}, value: "", tagName: "BUTTON" }
      ctrl.insertFieldChip({ currentTarget: fake })
      expect(surface(element).querySelector("[data-pill]")).toBeNull()
    })

    it("inserts the pill at the caret when a valid selection exists inside the surface", async () => {
      await mount("xyz")
      const tn = surface(element).firstChild
      setCaret(tn, 1)
      ctrl.insertFieldChip({ currentTarget: { dataset: { fieldId: "a" }, tagName: "BUTTON" } })
      expect(ctrl.serialize()).toBe("x{a}yz")
    })

    it("does not reset value when the source element is not a SELECT", () => {
      const fakeBtn = { dataset: { fieldId: "a" }, value: "should-not-clear", tagName: "BUTTON" }
      ctrl.insertFieldChip({ currentTarget: fakeBtn })
      expect(fakeBtn.value).toBe("should-not-clear")
    })
  })

  describe("_syncSampleInputs", () => {
    it("is a no-op when the sampleInputs target is absent", async () => {
      ;({ application, element } = await mountController("formula-editor", Controller, htmlNoSampleInputs("{a}")))
      ctrl = controllerFor(application, element, "formula-editor")
      expect(() => ctrl.validate()).not.toThrow()
    })

    it("falls back to the raw id when the field has no label", async () => {
      await mount("{c}")
      const label = element.querySelector("[data-formula-editor-target='sampleInputs'] span")
      expect(label.textContent).toBe("c")
    })

    it("defaults a fresh sample input to an empty string when no sample values are set", async () => {
      await mount("{a}")
      const input = element.querySelector("[data-formula-editor-target='sampleInputs'] input")
      expect(input.value).toBe("")
    })

    it("uses the stored sample value once the referenced-field set changes and rebuilds", () => {
      ctrl.setSampleValues({ a: 5 }) // formula still empty -> no rebuild yet
      ctrl.insertFieldChip({ currentTarget: { dataset: { fieldId: "a" }, tagName: "BUTTON" } })
      const input = element.querySelector("[data-formula-editor-target='sampleInputs'] input")
      expect(input.value).toBe("5")
    })

    it("falls back to an empty string for a field present in the set but absent from sampleValues", () => {
      ctrl.setSampleValues({ a: 5 })
      ctrl.insertFieldChip({ currentTarget: { dataset: { fieldId: "a" }, tagName: "BUTTON" } })
      ctrl.insertFieldChip({ currentTarget: { dataset: { fieldId: "b" }, tagName: "BUTTON" } })
      const inputs = element.querySelectorAll("[data-formula-editor-target='sampleInputs'] input")
      expect(inputs[0].value).toBe("5")
      expect(inputs[1].value).toBe("")
    })

    it("does not rebuild the inputs when the referenced-field set is unchanged", async () => {
      await mount("{a}")
      const inputsBefore = element.querySelector("[data-formula-editor-target='sampleInputs'] input")
      ctrl.validate() // same formula -> same key -> _syncSampleInputs should bail out early
      const inputsAfter = element.querySelector("[data-formula-editor-target='sampleInputs'] input")
      expect(inputsAfter).toBe(inputsBefore) // same DOM node, not rebuilt
    })

    it("updates the stored sample value and revalidates when the input fires", async () => {
      await mount("{a}")
      const input = element.querySelector("[data-formula-editor-target='sampleInputs'] input")
      input.value = "7"
      input.dispatchEvent(new Event("input", { bubbles: true }))
      expect(ctrl.sampleValues()).toEqual({ a: 7 })
    })

    it("keeps a non-numeric sample value as a string", async () => {
      await mount("{b}")
      const input = element.querySelector("[data-formula-editor-target='sampleInputs'] input")
      input.value = "hello"
      input.dispatchEvent(new Event("input", { bubbles: true }))
      expect(ctrl.sampleValues()).toEqual({ b: "hello" })
    })
  })
})
