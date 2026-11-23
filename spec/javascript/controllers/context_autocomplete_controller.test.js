// NOTE: _positionDropdown() places the dropdown from getBoundingClientRect() +
// window.innerHeight — that geometry is meaningless in happy-dom (zeroed rects),
// so exact placement is a Playwright concern (spec/e2e). Everything else — word
// extraction, option flattening, picker group assembly, sibling-step scanning,
// dropdown structure and text replacement — is pure DOM and tested here.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"

vi.mock("flowchart/context_variable_provider", () => ({
  getAvailableVariables: vi.fn(),
  filterVariables: vi.fn(),
}))
vi.mock("controllers/property_editor/templates", () => ({
  OUTPUT_VAR_KEYS: ["resultVar", "outputKey", "targetVariable"],
}))

import { getAvailableVariables, filterVariables } from "flowchart/context_variable_provider"
import Controller from "controllers/context_autocomplete_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = `
  <div data-controller="context-autocomplete" data-context-autocomplete-element-id-value="el-1">
    <input data-context-autocomplete-target="input" type="text">
  </div>`

const getCtrl = async () => {
  const { application, element } = await mountController("context-autocomplete", Controller, html)
  const ctrl = controllerFor(application, element, "context-autocomplete")
  return { element, ctrl, input: element.querySelector("input") }
}

describe("context-autocomplete controller", () => {
  beforeEach(() => {
    // _updateSelection calls scrollIntoView on the selected option.
    Element.prototype.scrollIntoView = vi.fn()
    getAvailableVariables.mockReset()
    filterVariables.mockReset()
  })
  afterEach(() => {
    document.querySelectorAll(".context-autocomplete-dropdown").forEach((n) => n.remove())
    vi.restoreAllMocks()
  })

  it("_input resolves the target input (round-2 wrapper markup)", async () => {
    const { ctrl, input } = await getCtrl()
    expect(ctrl._input).toBe(input)
  })

  it("_getWordAtCursor extracts the word around the caret", async () => {
    const { ctrl, input } = await getCtrl()
    input.value = "hello world"
    input.setSelectionRange(3, 3)
    expect(ctrl._getWordAtCursor()).toBe("hello")
    input.setSelectionRange(8, 8)
    expect(ctrl._getWordAtCursor()).toBe("world")
  })

  it("_flattenOptions flattens groups into {variable, groupLabel} pairs", async () => {
    const { ctrl } = await getCtrl()
    const flat = ctrl._flattenOptions([
      { label: "G1", variables: ["a", "b"] },
      { label: "G2", variables: ["c"] },
    ])
    expect(flat).toEqual([
      { variable: "a", groupLabel: "G1" },
      { variable: "b", groupLabel: "G1" },
      { variable: "c", groupLabel: "G2" },
    ])
  })

  it("_buildPickerGroups prepends a sibling-vars group when present", async () => {
    const { ctrl } = await getCtrl()
    const base = [{ label: "Existing", variables: ["x"] }]
    expect(ctrl._buildPickerGroups(base, [])).toBe(base)
    const withSibling = ctrl._buildPickerGroups(base, ["sv"])
    expect(withSibling[0]).toMatchObject({ label: "Used in this element", variables: ["sv"] })
    expect(withSibling[1]).toBe(base[0])
  })

  it("_collectSiblingStepVars reads output vars from sibling step configs", async () => {
    const markup = `
      <div data-controller="context-autocomplete">
        <div data-steps-container>
          <div data-step-item id="own">
            <input data-context-autocomplete-target="input" type="text">
          </div>
          <div data-step-item>
            <input data-step-config value='${JSON.stringify({ resultVar: "total", outputKey: "code" })}'>
          </div>
        </div>
      </div>`
    const { application, element } = await mountController("context-autocomplete", Controller, markup)
    const ctrl = controllerFor(application, element, "context-autocomplete")
    expect(ctrl._collectSiblingStepVars().sort()).toEqual(["code", "total"])
  })

  it("_selectOption replaces the word at the caret and fires an input event", async () => {
    const { ctrl, input } = await getCtrl()
    input.value = "pre foo"
    input.setSelectionRange(7, 7)
    const spy = vi.fn()
    input.addEventListener("input", spy)
    ctrl._selectOption("chosen_var")
    expect(input.value).toBe("pre chosen_var")
    expect(spy).toHaveBeenCalled()
  })

  it("keepFocus prevents default to preserve input focus", async () => {
    const { ctrl } = await getCtrl()
    const ev = { preventDefault: vi.fn() }
    ctrl.keepFocus(ev)
    expect(ev.preventDefault).toHaveBeenCalled()
  })

  it("picker() renders a dropdown of the available variables", async () => {
    getAvailableVariables.mockResolvedValue({ groups: [{ label: "Group A", variables: ["v1", "v2"] }] })
    const { ctrl } = await getCtrl()
    await ctrl.picker({ preventDefault: vi.fn() })
    const dropdown = document.querySelector(".context-autocomplete-dropdown")
    expect(dropdown).not.toBeNull()
    expect(dropdown.querySelectorAll(".context-autocomplete-option").length).toBe(2)
    expect(dropdown.textContent).toContain("v1")
    expect(dropdown.textContent).toContain("Group A")
  })

  it("picker() renders an empty-state dropdown when there are no variables", async () => {
    getAvailableVariables.mockResolvedValue({ groups: [] })
    const { ctrl } = await getCtrl()
    await ctrl.picker({ preventDefault: vi.fn() })
    const dropdown = document.querySelector(".context-autocomplete-dropdown")
    expect(dropdown.textContent).toContain("No variables available")
  })

  it("_destroyDropdown removes the dropdown and resets state", async () => {
    getAvailableVariables.mockResolvedValue({ groups: [{ label: "G", variables: ["v1"] }] })
    const { ctrl } = await getCtrl()
    await ctrl.picker({ preventDefault: vi.fn() })
    expect(document.querySelector(".context-autocomplete-dropdown")).not.toBeNull()
    ctrl._destroyDropdown()
    expect(document.querySelector(".context-autocomplete-dropdown")).toBeNull()
    expect(ctrl._allOptions).toEqual([])
  })

  it("_input falls back to this.element on legacy markup (mounted directly on the input)", async () => {
    const legacyHtml = `<input data-controller="context-autocomplete" type="text">`
    const { application, element } = await mountController("context-autocomplete", Controller, legacyHtml)
    const ctrl = controllerFor(application, element, "context-autocomplete")
    expect(ctrl._input).toBe(element)
  })

  it("disconnect removes listeners, clears a pending debounce timer, and destroys the dropdown", async () => {
    const { ctrl, input } = await getCtrl()
    ctrl._debounceTimer = setTimeout(() => {}, 5000)
    ctrl._dropdown = document.createElement("div")
    document.body.appendChild(ctrl._dropdown)
    const removeSpy = vi.spyOn(input, "removeEventListener")
    ctrl.disconnect()
    expect(removeSpy).toHaveBeenCalledWith("input", ctrl._boundOnInput)
    expect(removeSpy).toHaveBeenCalledWith("keydown", ctrl._boundOnKeydown)
    expect(removeSpy).toHaveBeenCalledWith("blur", ctrl._boundOnBlur)
    expect(ctrl._dropdown).toBeNull()
  })

  it("_resolveCanvas reads .flowchartCanvas off the matched element, or stays null when absent/unset", async () => {
    // Insert the canvas element AFTER mounting: mountController resets
    // document.body.innerHTML, so anything appended before mount is wiped.
    const { ctrl } = await getCtrl()
    expect(ctrl._canvas).toBeNull()
    document.body.insertAdjacentHTML("beforeend", '<div data-controller="flowchart-canvas"></div>')
    const canvasEl = document.querySelector('[data-controller="flowchart-canvas"]')
    try {
      canvasEl.flowchartCanvas = { id: "c1" }
      ctrl._resolveCanvas()
      expect(ctrl._canvas).toEqual({ id: "c1" })
    } finally {
      canvasEl.remove()
    }
  })

  it("_getWordAtCursor handles an empty input (falsy value/selectionStart branches)", async () => {
    const { ctrl } = await getCtrl()
    expect(ctrl._getWordAtCursor()).toBe("")
  })

  it("_ensureDropdown is idempotent once a dropdown already exists", async () => {
    const { ctrl } = await getCtrl()
    ctrl._ensureDropdown()
    const dd = ctrl._dropdown
    ctrl._ensureDropdown()
    expect(ctrl._dropdown).toBe(dd)
  })

  it("picker() falls back to an empty group list when the result has no .groups", async () => {
    getAvailableVariables.mockResolvedValue({})
    const { ctrl } = await getCtrl()
    await ctrl.picker({ preventDefault: vi.fn() })
    const dropdown = document.querySelector(".context-autocomplete-dropdown")
    expect(dropdown.textContent).toContain("No variables available")
  })

  it("picker() swallows errors from getAvailableVariables and shows the empty state", async () => {
    getAvailableVariables.mockRejectedValue(new Error("boom"))
    const { ctrl } = await getCtrl()
    await ctrl.picker({ preventDefault: vi.fn() })
    const dropdown = document.querySelector(".context-autocomplete-dropdown")
    expect(dropdown.textContent).toContain("No variables available")
  })

  it("picker() ignores a stale resolution superseded by a newer picker() call", async () => {
    const { ctrl } = await getCtrl()
    let resolveFirst
    getAvailableVariables
      .mockImplementationOnce(() => new Promise((resolve) => { resolveFirst = resolve }))
      .mockResolvedValueOnce({ groups: [{ label: "Second", variables: ["v2"] }] })
    const p1 = ctrl.picker({ preventDefault: vi.fn() })
    const p2 = ctrl.picker({ preventDefault: vi.fn() })
    await p2
    resolveFirst({ groups: [{ label: "First", variables: ["v1"] }] })
    await p1
    const dropdown = document.querySelector(".context-autocomplete-dropdown")
    expect(dropdown.textContent).toContain("v2")
    expect(dropdown.textContent).not.toContain("v1")
  })

  it("_collectSiblingStepVars skips items with no config, empty config, and malformed JSON", async () => {
    const markup = `
      <div data-controller="context-autocomplete">
        <div data-steps-container>
          <div data-step-item id="own">
            <input data-context-autocomplete-target="input" type="text">
          </div>
          <div data-step-item>
            <input data-step-config value='${JSON.stringify({ resultVar: "total" })}'>
          </div>
          <div data-step-item></div>
          <div data-step-item>
            <input data-step-config value="">
          </div>
          <div data-step-item>
            <input data-step-config value="not-json{">
          </div>
        </div>
      </div>`
    const { application, element } = await mountController("context-autocomplete", Controller, markup)
    const ctrl = controllerFor(application, element, "context-autocomplete")
    expect(ctrl._collectSiblingStepVars()).toEqual(["total"])
  })

  it("_positionDropdown flips above the input when there isn't enough space below", async () => {
    const { ctrl, input } = await getCtrl()
    Object.defineProperty(input, "getBoundingClientRect", {
      value: () => ({ top: 500, bottom: 520, left: 10, right: 100 }),
      configurable: true,
    })
    Object.defineProperty(window, "innerHeight", { value: 600, configurable: true })
    try {
      ctrl._ensureDropdown()
      ctrl._positionDropdown()
      expect(ctrl._dropdown.style.top).toBe(`${500 - 256}px`)
    } finally {
      delete window.innerHeight
    }
  })

  it("_buildDropdownHTML shows a no-matches message when there are no filtered groups", async () => {
    const { ctrl } = await getCtrl()
    ctrl._filteredGroups = []
    expect(ctrl._buildDropdownHTML()).toContain("No matching variables")
  })

  it("clicking a rendered dropdown option selects it via _wireOptionClicks", async () => {
    getAvailableVariables.mockResolvedValue({ groups: [{ label: "G", variables: ["chosen"] }] })
    const { ctrl, input } = await getCtrl()
    input.value = "abc"
    input.setSelectionRange(3, 3)
    await ctrl.picker({ preventDefault: vi.fn() })
    const opt = document.querySelector(".context-autocomplete-option")
    opt.dispatchEvent(new Event("mousedown", { bubbles: true, cancelable: true }))
    expect(input.value).toContain("chosen")
    expect(document.querySelector(".context-autocomplete-dropdown")).toBeNull()
  })

  it("_onInput clears a previously pending debounce timer on rapid successive keystrokes", async () => {
    getAvailableVariables.mockResolvedValue({ groups: [] })
    filterVariables.mockReturnValue({ groups: [] })
    const { input } = await getCtrl()
    input.dispatchEvent(new Event("input", { bubbles: true }))
    input.dispatchEvent(new Event("input", { bubbles: true })) // hits the truthy _debounceTimer branch
    await new Promise((resolve) => setTimeout(resolve, 150))
  })

  it("_onInput debounces and closes the dropdown when no canvas can be resolved", async () => {
    const { ctrl, input } = await getCtrl()
    ctrl._dropdown = document.createElement("div")
    input.dispatchEvent(new Event("input", { bubbles: true }))
    await new Promise((resolve) => setTimeout(resolve, 150))
    expect(ctrl._dropdown).toBeNull()
    expect(getAvailableVariables).not.toHaveBeenCalled()
  })

  it("_onInput fetches, filters and renders matching variables after the debounce delay", async () => {
    getAvailableVariables.mockResolvedValue({ groups: [{ label: "G", variables: ["foo", "bar"] }] })
    filterVariables.mockReturnValue({ groups: [{ label: "G", variables: ["foo"] }] })
    const { input } = await getCtrl()
    // Insert the canvas AFTER mounting (mount wipes body.innerHTML); this
    // exercises _onInput's own re-resolve-canvas retry at debounce time.
    document.body.insertAdjacentHTML("beforeend", '<div data-controller="flowchart-canvas"></div>')
    const canvasEl = document.querySelector('[data-controller="flowchart-canvas"]')
    canvasEl.flowchartCanvas = {}
    try {
      input.value = "fo"
      input.setSelectionRange(2, 2)
      input.dispatchEvent(new Event("input", { bubbles: true }))
      await new Promise((resolve) => setTimeout(resolve, 150))
      const dropdown = document.querySelector(".context-autocomplete-dropdown")
      expect(dropdown.textContent).toContain("foo")
    } finally {
      canvasEl.remove()
    }
  })

  it("_onInput closes the dropdown when the filtered result has no options", async () => {
    getAvailableVariables.mockResolvedValue({ groups: [] })
    filterVariables.mockReturnValue({ groups: [] })
    const { ctrl, input } = await getCtrl()
    document.body.insertAdjacentHTML("beforeend", '<div data-controller="flowchart-canvas"></div>')
    const canvasEl = document.querySelector('[data-controller="flowchart-canvas"]')
    canvasEl.flowchartCanvas = {}
    try {
      ctrl._dropdown = document.createElement("div")
      input.dispatchEvent(new Event("input", { bubbles: true }))
      await new Promise((resolve) => setTimeout(resolve, 150))
      expect(ctrl._dropdown).toBeNull()
    } finally {
      canvasEl.remove()
    }
  })

  describe("_onKeydown", () => {
    it("is a no-op when no dropdown is open", async () => {
      const { input } = await getCtrl()
      const ev = new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true })
      input.dispatchEvent(ev)
      expect(ev.defaultPrevented).toBe(false)
    })

    it("ArrowDown/ArrowUp move the selection within bounds and highlight the option", async () => {
      getAvailableVariables.mockResolvedValue({ groups: [{ label: "G", variables: ["a", "b", "c"] }] })
      const { ctrl } = await getCtrl()
      await ctrl.picker({ preventDefault: vi.fn() })
      expect(ctrl._selectedIndex).toBe(0)
      ctrl._onKeydown({ key: "ArrowDown", preventDefault: vi.fn() })
      expect(ctrl._selectedIndex).toBe(1)
      ctrl._onKeydown({ key: "ArrowDown", preventDefault: vi.fn() })
      ctrl._onKeydown({ key: "ArrowDown", preventDefault: vi.fn() }) // clamps at length-1
      expect(ctrl._selectedIndex).toBe(2)
      ctrl._onKeydown({ key: "ArrowUp", preventDefault: vi.fn() })
      expect(ctrl._selectedIndex).toBe(1)
      ctrl._onKeydown({ key: "ArrowUp", preventDefault: vi.fn() })
      ctrl._onKeydown({ key: "ArrowUp", preventDefault: vi.fn() }) // clamps at 0
      expect(ctrl._selectedIndex).toBe(0)
      const selectedOpt = document.querySelectorAll(".context-autocomplete-option")[0]
      expect(selectedOpt.classList.contains("bg-indigo-100")).toBe(true)
    })

    it("Enter selects the highlighted option", async () => {
      getAvailableVariables.mockResolvedValue({ groups: [{ label: "G", variables: ["a", "b"] }] })
      const { ctrl, input } = await getCtrl()
      input.value = "x "
      input.setSelectionRange(2, 2)
      await ctrl.picker({ preventDefault: vi.fn() })
      ctrl._onKeydown({ key: "Enter", preventDefault: vi.fn() })
      expect(input.value).toContain("a")
      expect(document.querySelector(".context-autocomplete-dropdown")).toBeNull()
    })

    it("Tab also selects the highlighted option", async () => {
      getAvailableVariables.mockResolvedValue({ groups: [{ label: "G", variables: ["a"] }] })
      const { ctrl } = await getCtrl()
      await ctrl.picker({ preventDefault: vi.fn() })
      ctrl._onKeydown({ key: "Tab", preventDefault: vi.fn() })
      expect(document.querySelector(".context-autocomplete-dropdown")).toBeNull()
    })

    it("Enter/Tab no-op when there are no options in the dropdown", async () => {
      const { ctrl } = await getCtrl()
      ctrl._dropdown = document.createElement("div")
      const ev = { key: "Enter", preventDefault: vi.fn() }
      ctrl._onKeydown(ev)
      expect(ev.preventDefault).not.toHaveBeenCalled()
    })

    it("Enter with a stale out-of-range selectedIndex selects nothing", async () => {
      getAvailableVariables.mockResolvedValue({ groups: [{ label: "G", variables: ["a"] }] })
      const { ctrl } = await getCtrl()
      await ctrl.picker({ preventDefault: vi.fn() })
      ctrl._selectedIndex = 99
      const spy = vi.spyOn(ctrl, "_selectOption")
      ctrl._onKeydown({ key: "Enter", preventDefault: vi.fn() })
      expect(spy).not.toHaveBeenCalled()
    })

    it("Escape closes the dropdown", async () => {
      getAvailableVariables.mockResolvedValue({ groups: [{ label: "G", variables: ["a"] }] })
      const { ctrl } = await getCtrl()
      await ctrl.picker({ preventDefault: vi.fn() })
      ctrl._onKeydown({ key: "Escape", preventDefault: vi.fn() })
      expect(document.querySelector(".context-autocomplete-dropdown")).toBeNull()
    })
  })

  it("_updateSelection is a no-op when there is no dropdown", async () => {
    const { ctrl } = await getCtrl()
    expect(() => ctrl._updateSelection()).not.toThrow()
  })

  it("_selectOption handles an empty input (falsy value/selectionStart branches)", async () => {
    const { ctrl, input } = await getCtrl()
    ctrl._selectOption("foo")
    expect(input.value).toBe("foo")
  })

  it("_selectOption replaces a mid-string word, exercising both boundary-scan loops fully", async () => {
    const { ctrl, input } = await getCtrl()
    input.value = "pre foo bar"
    input.setSelectionRange(5, 5) // caret inside "foo"
    ctrl._selectOption("XXX")
    expect(input.value).toBe("pre XXX bar")
  })

  describe("_onBlur", () => {
    it("closes the dropdown after the delay when focus moves elsewhere", async () => {
      getAvailableVariables.mockResolvedValue({ groups: [{ label: "G", variables: ["a"] }] })
      const { ctrl, input } = await getCtrl()
      await ctrl.picker({ preventDefault: vi.fn() })
      input.blur() // happy-dom moves activeElement to <body>
      await new Promise((resolve) => setTimeout(resolve, 200))
      expect(document.querySelector(".context-autocomplete-dropdown")).toBeNull()
    })

    it("keeps the dropdown open when focus has returned to the input by the time the timer fires", async () => {
      getAvailableVariables.mockResolvedValue({ groups: [{ label: "G", variables: ["a"] }] })
      const { ctrl, input } = await getCtrl()
      await ctrl.picker({ preventDefault: vi.fn() })
      input.blur()
      input.focus() // simulate picker() having refocused it before the timer fires
      await new Promise((resolve) => setTimeout(resolve, 200))
      expect(document.querySelector(".context-autocomplete-dropdown")).not.toBeNull()
    })

    it("keeps the dropdown open when focus moved inside the dropdown itself", async () => {
      getAvailableVariables.mockResolvedValue({ groups: [{ label: "G", variables: ["a"] }] })
      const { ctrl, input } = await getCtrl()
      await ctrl.picker({ preventDefault: vi.fn() })
      const optionEl = document.querySelector(".context-autocomplete-option")
      optionEl.tabIndex = -1
      input.blur()
      optionEl.focus()
      await new Promise((resolve) => setTimeout(resolve, 200))
      expect(document.querySelector(".context-autocomplete-dropdown")).not.toBeNull()
    })
  })

  describe("_onClickOutside", () => {
    it("closes the dropdown when the mousedown target is outside both the dropdown and the controller element", async () => {
      getAvailableVariables.mockResolvedValue({ groups: [{ label: "G", variables: ["a"] }] })
      const { ctrl } = await getCtrl()
      await ctrl.picker({ preventDefault: vi.fn() })
      document.body.dispatchEvent(new Event("mousedown", { bubbles: true }))
      expect(document.querySelector(".context-autocomplete-dropdown")).toBeNull()
    })

    it("keeps the dropdown open when the mousedown target is inside the controller element", async () => {
      getAvailableVariables.mockResolvedValue({ groups: [{ label: "G", variables: ["a"] }] })
      const { ctrl, input } = await getCtrl()
      await ctrl.picker({ preventDefault: vi.fn() })
      input.dispatchEvent(new Event("mousedown", { bubbles: true }))
      expect(document.querySelector(".context-autocomplete-dropdown")).not.toBeNull()
    })

    it("keeps the dropdown open when the mousedown target is inside the dropdown itself", async () => {
      getAvailableVariables.mockResolvedValue({ groups: [{ label: "G", variables: ["a"] }] })
      const { ctrl } = await getCtrl()
      await ctrl.picker({ preventDefault: vi.fn() })
      const dropdown = document.querySelector(".context-autocomplete-dropdown")
      dropdown.dispatchEvent(new Event("mousedown", { bubbles: true }))
      expect(document.querySelector(".context-autocomplete-dropdown")).not.toBeNull()
    })
  })
})
