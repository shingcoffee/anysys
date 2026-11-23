// NOTE: scrollIntoView is a real-layout no-op in happy-dom, so it is stubbed on
// every target rather than asserted against real scroll positions. The
// _navigateToProblem retry loop itself is pure setTimeout + querySelector (no
// layout involved) and IS exercised here with fake timers.
import { describe, it, expect, beforeEach, vi } from "vitest"
import { UiFeedbackMixin } from "controllers/property_editor/ui_feedback"

const withMixin = (host) => {
  Object.assign(host, UiFeedbackMixin)
  return host
}

beforeEach(() => {
  document.body.innerHTML = ""
  vi.useRealTimers()
})

describe("paintFieldError", () => {
  const makeHost = () => {
    const form = document.createElement("form")
    form.innerHTML = `
      <div data-tab-pane="general">
        <div data-element-field="returnValue">
          <input name="returnValue">
        </div>
      </div>
    `
    document.body.appendChild(form)
    const general = form.querySelector("[data-tab-pane]")
    return withMixin({
      hasFormTarget: true,
      formTarget: form,
      getFormFieldsForTab: (tab) => (tab === "general" ? general : null),
      tabManager: { switchTo: vi.fn() },
    })
  }

  it("reveals the Branches tab for a Decision field error, not Steps", () => {
    const form = document.createElement("form")
    form.innerHTML = `
      <div data-pane="steps">
        <div data-element-field="branches"><input name="branches"></div>
      </div>
    `
    document.body.appendChild(form)
    const steps = form.querySelector("[data-pane]")
    const host = withMixin({
      hasFormTarget: true,
      formTarget: form,
      currentElement: { type: "decision" },
      getFormFieldsForTab: (tab) => (tab === "steps" || tab === "branches" ? steps : null),
      tabManager: { switchTo: vi.fn() },
    })
    host.paintFieldError("branches", "Match values must be unique")
    expect(host.tabManager.switchTo).toHaveBeenCalledWith("branches")
    expect(host.tabManager.switchTo).not.toHaveBeenCalledWith("steps")
  })

  it("paints data-field-error + aria-invalid and reveals the holding tab", () => {
    const host = makeHost()
    host.paintFieldError("returnValue", "Required")
    const wrap = host.formTarget.querySelector('[data-element-field="returnValue"]')
    const input = wrap.querySelector("input")
    expect(input.getAttribute("aria-invalid")).toBe("true")
    const err = wrap.querySelector("[data-field-error]")
    expect(err).not.toBeNull()
    expect(err.textContent).toBe("Required")
    expect(host.tabManager.switchTo).toHaveBeenCalledWith("general")
  })

  it("paints without switching tabs or opening disclosures when reveal is false", () => {
    const form = document.createElement("form")
    form.innerHTML = `
      <div data-tab-pane="general">
        <details data-element-field="description"><textarea name="description"></textarea></details>
      </div>
    `
    document.body.appendChild(form)
    const general = form.querySelector("[data-tab-pane]")
    const host = withMixin({
      hasFormTarget: true,
      formTarget: form,
      getFormFieldsForTab: (tab) => (tab === "general" ? general : null),
      tabManager: { switchTo: vi.fn() },
    })
    host.applyElementFieldProblems([{ field: "description", severity: "error", message: "Too long" }], { reveal: false })
    expect(form.querySelector("[data-field-error]").textContent).toBe("Too long")
    expect(form.querySelector("details").open).toBe(false)
    expect(host.tabManager.switchTo).not.toHaveBeenCalled()
  })

  it("reuses an existing error node instead of stacking", () => {
    const host = makeHost()
    host.paintFieldError("returnValue", "one")
    host.paintFieldError("returnValue", "two")
    expect(host.formTarget.querySelectorAll("[data-field-error]").length).toBe(1)
    expect(host.formTarget.querySelector("[data-field-error]").textContent).toBe("two")
  })

  it("clears on input and ignores results without a field", () => {
    const host = makeHost()
    host.applyElementFieldProblems([
      { field: "returnValue", severity: "error", message: "Need a value" },
      { severity: "error", message: "panel only" },
    ])
    expect(host.formTarget.querySelector("[data-field-error]").textContent).toBe("Need a value")
    host._clearFieldErrorOnInput({ target: host.formTarget.querySelector("[name='returnValue']") })
    expect(host.formTarget.querySelector("[data-field-error]")).toBeNull()
    expect(host.formTarget.querySelector("[aria-invalid]")).toBeNull()
  })

  it("no-ops paint/clear without a name or form", () => {
    const host = withMixin({ hasFormTarget: false })
    expect(() => {
      host.paintFieldError("x", "msg")
      host.clearFieldError("x")
      host.applyElementFieldProblems([{ field: "x", message: "m" }])
    }).not.toThrow()
  })

  it("opens a hidden step disclosure that holds the field", () => {
    const form = document.createElement("form")
    form.innerHTML = `
      <div data-tab-pane="general">
        <div data-disclosure>
          <div data-disclosure-body class="hidden">
            <div data-element-field="returnValue"><input name="returnValue"></div>
          </div>
        </div>
      </div>
    `
    document.body.appendChild(form)
    const general = form.querySelector("[data-tab-pane]")
    const toggle = vi.fn((event) => event.preventDefault())
    const host = withMixin({
      hasFormTarget: true,
      formTarget: form,
      getFormFieldsForTab: (tab) => (tab === "general" ? general : null),
      tabManager: { switchTo: vi.fn() },
      toggleDisclosure: toggle,
    })
    host.paintFieldError("returnValue", "Required")
    expect(toggle).toHaveBeenCalled()
  })

  it("opens a closed notes disclosure when painting an error on description", () => {
    const form = document.createElement("form")
    form.innerHTML = `
      <div data-tab-pane="general">
        <details data-element-field="description">
          <textarea name="description"></textarea>
        </details>
      </div>
    `
    document.body.appendChild(form)
    const general = form.querySelector("[data-tab-pane]")
    const host = withMixin({
      hasFormTarget: true,
      formTarget: form,
      getFormFieldsForTab: (tab) => (tab === "general" ? general : null),
      tabManager: { switchTo: vi.fn() },
    })
    host.paintFieldError("description", "Too long")
    expect(form.querySelector("details").open).toBe(true)
    expect(form.querySelector("[data-field-error]").textContent).toBe("Too long")
  })

  it("falls back to a data-config-input when the wrap has no matching name", () => {
    const form = document.createElement("form")
    form.innerHTML = `<div data-element-field="flowchartId"><input data-config-input="flowchartId" value="9"></div>`
    const host = withMixin({
      hasFormTarget: true,
      formTarget: form,
      getFormFieldsForTab: () => form,
      tabManager: { switchTo: vi.fn() },
    })
    host.paintFieldError("flowchartId", "Required")
    expect(form.querySelector("[data-config-input]").getAttribute("aria-invalid")).toBe("true")
  })

  it("falls back to a named input wrap and paints an empty message", () => {
    const form = document.createElement("form")
    form.innerHTML = `<div class="wrap"><input name="orphan"></div>`
    const host = withMixin({
      hasFormTarget: true,
      formTarget: form,
      getFormFieldsForTab: () => null,
      tabManager: { switchTo: vi.fn() },
    })
    host.paintFieldError("orphan")
    expect(form.querySelector("[data-field-error]").textContent).toBe("")
    expect(form.querySelector("input").getAttribute("aria-invalid")).toBe("true")
    host.applyElementFieldProblems(null)
  })

  it("clears a missing wrap and paints nothing without a matching field", () => {
    const form = document.createElement("form")
    form.innerHTML = `<input name="other">`
    const host = withMixin({ hasFormTarget: true, formTarget: form, tabManager: { switchTo: vi.fn() } })
    expect(() => {
      host.paintFieldError("missing", "x")
      host.clearFieldError("missing")
      host.clearFieldError("")
      host.paintFieldError("", "x")
    }).not.toThrow()
  })
})

describe("save button state transitions", () => {
  const makeHost = () => {
    const btn = document.createElement("button")
    btn.classList.add("bg-indigo-600", "hover:bg-indigo-700")
    return withMixin({
      hasSaveButtonTarget: true,
      saveButtonTarget: btn,
      // English defaults mirroring PropertyEditorController's static values
      // (see property_editor_controller.js) — this bare host is not a real
      // Stimulus controller, so it doesn't get Value defaults for free.
      savedLabelValue: "Saved!",
      errorLabelValue: "Error!",
      saveButtonLabelValue: "Save",
    })
  }

  it("_showSaveSuccess swaps to green + 'Saved!', then resets after 1500ms", () => {
    vi.useFakeTimers()
    const host = makeHost()
    host._showSaveSuccess()
    expect(host.saveButtonTarget.textContent).toContain("Saved!")
    expect(host.saveButtonTarget.classList.contains("bg-green-600")).toBe(true)
    vi.advanceTimersByTime(1500)
    expect(host.saveButtonTarget.classList.contains("bg-indigo-600")).toBe(true)
    expect(host.saveButtonTarget.textContent).toContain("Save")
  })

  it("_showSaveError swaps to red + 'Error!', then resets after 2000ms", () => {
    vi.useFakeTimers()
    const host = makeHost()
    host._showSaveError()
    expect(host.saveButtonTarget.textContent).toContain("Error!")
    expect(host.saveButtonTarget.classList.contains("bg-red-600")).toBe(true)
    vi.advanceTimersByTime(2000)
    expect(host.saveButtonTarget.classList.contains("bg-indigo-600")).toBe(true)
    expect(host.saveButtonTarget.textContent).toContain("Save")
  })

  it("_resetSaveButton restores indigo 'Save'", () => {
    const host = makeHost()
    host.saveButtonTarget.classList.add("bg-green-600")
    host._resetSaveButton()
    expect(host.saveButtonTarget.classList.contains("bg-indigo-600")).toBe(true)
    expect(host.saveButtonTarget.classList.contains("bg-green-600")).toBe(false)
  })

  it("clears a pending save-button timer before scheduling another", () => {
    vi.useFakeTimers()
    const host = makeHost()
    host._showSaveSuccess()
    expect(host._saveButtonTimer).toBeTruthy()
    host._showSaveError()
    expect(host.saveButtonTarget.textContent).toContain("Error!")
    host._resetSaveButton()
    expect(host._saveButtonTimer).toBeNull()
  })

  it("clears a pending save-button timer before scheduling another", () => {
    vi.useFakeTimers()
    const host = makeHost()
    host._showSaveSuccess()
    expect(host._saveButtonTimer).toBeTruthy()
    host._showSaveError()
    expect(host.saveButtonTarget.textContent).toContain("Error!")
    host._resetSaveButton()
    expect(host._saveButtonTimer).toBeNull()
  })

  it("all three no-op safely when there is no save-button target", () => {
    const host = withMixin({ hasSaveButtonTarget: false })
    expect(() => {
      host._showSaveSuccess()
      host._showSaveError()
      host._resetSaveButton()
    }).not.toThrow()
  })
})

describe("_highlightProblemField", () => {
  const target = () => {
    const el = document.createElement("div")
    el.scrollIntoView = vi.fn() // happy-dom lacks a real impl
    document.body.appendChild(el)
    return el
  }

  it("applies a red ring by default, clearing after 2s", () => {
    vi.useFakeTimers()
    const host = withMixin({})
    const el = target()
    host._highlightProblemField(el, undefined)
    expect(el.classList.contains("ring-red-400")).toBe(true)
    expect(el.scrollIntoView).toHaveBeenCalled()
    vi.advanceTimersByTime(2000)
    expect(el.classList.contains("ring-red-400")).toBe(false)
    expect(host._problemHighlightTarget).toBeNull()
  })

  it("applies a yellow ring for warnings", () => {
    vi.useFakeTimers()
    const host = withMixin({})
    const el = target()
    host._highlightProblemField(el, "warning")
    expect(el.classList.contains("ring-yellow-400")).toBe(true)
  })

  it("clears the previous target's ring when a second highlight arrives", () => {
    vi.useFakeTimers()
    const host = withMixin({})
    const a = target()
    const b = target()
    host._highlightProblemField(a, undefined)
    host._highlightProblemField(b, undefined)
    expect(a.classList.contains("ring-red-400")).toBe(false)
    expect(b.classList.contains("ring-red-400")).toBe(true)
    expect(host._problemHighlightTarget).toBe(b)
  })
})

describe("_navigateToProblem", () => {
  it("switches to the target tab only when a matching visible button exists", () => {
    const switchTo = vi.fn()
    const container = document.createElement("div")
    container.innerHTML = `<button data-tab="io"></button>`
    const host = withMixin({
      tabManager: { tabBarContainer: container, switchTo, getPane: () => null, activeTab: "io" },
      formTarget: document.createElement("div"),
    })
    host._navigateToProblem({ tab: "io" })
    expect(switchTo).toHaveBeenCalledWith("io")
  })

  it("does not switch when the tab has no visible button", () => {
    const switchTo = vi.fn()
    const container = document.createElement("div") // empty → no button
    const host = withMixin({
      tabManager: { tabBarContainer: container, switchTo, getPane: () => null },
      formTarget: document.createElement("div"),
    })
    host._navigateToProblem({ tab: "io" })
    expect(switchTo).not.toHaveBeenCalled()
  })

  it("highlights the anchor immediately when the pane already contains it", () => {
    vi.useFakeTimers()
    const pane = document.createElement("div")
    const field = document.createElement("input")
    field.scrollIntoView = vi.fn()
    field.setAttribute("data-anchor", "")
    pane.appendChild(field)
    const container = document.createElement("div")
    container.innerHTML = `<button data-tab="general"></button>`
    const host = withMixin({
      tabManager: {
        tabBarContainer: container,
        switchTo: vi.fn(),
        getPane: () => pane,
        activeTab: "general",
      },
      formTarget: document.createElement("div"),
    })
    host._navigateToProblem({ tab: "general", anchor: "[data-anchor]", severity: "warning" })
    expect(field.classList.contains("ring-yellow-400")).toBe(true)
  })

  it("opens the collapsed disclosure that holds the anchor before highlighting it", () => {
    vi.useFakeTimers()
    const form = document.createElement("form")
    form.innerHTML = `
      <div data-tab-pane="general">
        <details data-element-field="description"><textarea name="description"></textarea></details>
      </div>
    `
    document.body.appendChild(form)
    const general = form.querySelector("[data-tab-pane]")
    const target = form.querySelector("details")
    target.scrollIntoView = vi.fn()
    const container = document.createElement("div")
    container.innerHTML = `<button data-tab="general"></button>`
    const host = withMixin({
      formTarget: form,
      getFormFieldsForTab: (tab) => (tab === "general" ? general : null),
      tabManager: { tabBarContainer: container, switchTo: vi.fn(), getPane: () => general, activeTab: "general" },
    })
    host._navigateToProblem({ tab: "general", anchor: '[data-element-field="description"]' })
    expect(target.open).toBe(true)
    expect(target.classList.contains("ring-red-400")).toBe(true)
  })

  it("falls back to formTarget when the active pane is unavailable", () => {
    vi.useFakeTimers()
    const field = document.createElement("input")
    field.scrollIntoView = vi.fn()
    field.setAttribute("data-anchor", "")
    const form = document.createElement("div")
    form.appendChild(field)
    const container = document.createElement("div")
    container.innerHTML = `<button data-tab="io"></button>`
    const host = withMixin({
      tabManager: { tabBarContainer: container, switchTo: vi.fn(), getPane: () => null, activeTab: "io" },
      formTarget: form,
    })
    host._navigateToProblem({ tab: "io", anchor: "[data-anchor]" })
    expect(field.classList.contains("ring-red-400")).toBe(true)
  })

  it("retries anchor resolution at 100ms intervals until the pane renders it", () => {
    vi.useFakeTimers()
    const field = document.createElement("input")
    field.scrollIntoView = vi.fn()
    field.setAttribute("data-anchor", "")
    let calls = 0
    const getPane = vi.fn(() => {
      calls += 1
      if (calls < 3) return document.createElement("div") // anchor not yet rendered
      const pane = document.createElement("div")
      pane.appendChild(field)
      return pane
    })
    const container = document.createElement("div")
    container.innerHTML = `<button data-tab="io"></button>`
    const host = withMixin({
      tabManager: { tabBarContainer: container, switchTo: vi.fn(), getPane, activeTab: "io" },
      formTarget: document.createElement("div"),
    })
    host._navigateToProblem({ tab: "io", anchor: "[data-anchor]" })
    expect(field.classList.contains("ring-red-400")).toBe(false)
    vi.advanceTimersByTime(100)
    expect(field.classList.contains("ring-red-400")).toBe(false)
    vi.advanceTimersByTime(100)
    expect(field.classList.contains("ring-red-400")).toBe(true)
  })

  it("gives up silently after 15 failed retries", () => {
    vi.useFakeTimers()
    const getPane = vi.fn(() => document.createElement("div")) // anchor never appears
    const container = document.createElement("div")
    container.innerHTML = `<button data-tab="io"></button>`
    const host = withMixin({
      tabManager: { tabBarContainer: container, switchTo: vi.fn(), getPane, activeTab: "io" },
      formTarget: document.createElement("div"),
    })
    host._navigateToProblem({ tab: "io", anchor: "[data-anchor]" })
    vi.advanceTimersByTime(100 * 15)
    // 1 synchronous call, then retries scheduled while attempts < 15 (14 more
    // retries) = 15 calls total; the 15th sets attempts to 15 and stops.
    expect(getPane.mock.calls.length).toBe(15)
  })
})

describe("_updateTabBadges", () => {
  it("no-ops without a tab manager", () => {
    expect(() => withMixin({})._updateTabBadges()).not.toThrow()
  })

  it("counts steps for a process element and forwards inputs/outputs from pins", () => {
    const updateBadges = vi.fn()
    const form = document.createElement("div")
    form.innerHTML = `<div data-steps-container><div data-step-item></div><div data-step-item></div></div>`
    const host = withMixin({
      tabManager: { updateBadges },
      currentElement: { type: "process", id: "e1" },
      formTarget: form,
      canvas: { getElementPins: () => ({ inputs: ["a"], outputs: ["b", "c"] }) },
    })
    host._updateTabBadges()
    expect(updateBadges).toHaveBeenCalledWith({ steps: 2, inputs: 1, outputs: 2 })
  })

  it("counts branches for a decision element", () => {
    const updateBadges = vi.fn()
    const form = document.createElement("div")
    form.innerHTML = `<div data-branches-container><div data-branch-item></div></div>`
    const host = withMixin({
      tabManager: { updateBadges },
      currentElement: { type: "decision", id: "e1" },
      formTarget: form,
      canvas: null,
    })
    host._updateTabBadges()
    expect(updateBadges).toHaveBeenCalledWith({ branches: 1, inputs: 0, outputs: 0 })
  })

  it("counts 0 steps when the process form has no steps container yet", () => {
    const updateBadges = vi.fn()
    const host = withMixin({
      tabManager: { updateBadges },
      currentElement: { type: "process", id: "e1" },
      formTarget: document.createElement("div"),
      canvas: null,
    })
    host._updateTabBadges()
    expect(updateBadges).toHaveBeenCalledWith({ steps: 0, inputs: 0, outputs: 0 })
  })

  it("counts 0 branches when the decision form has no branches container yet", () => {
    const updateBadges = vi.fn()
    const host = withMixin({
      tabManager: { updateBadges },
      currentElement: { type: "decision", id: "e1" },
      formTarget: document.createElement("div"),
      canvas: null,
    })
    host._updateTabBadges()
    expect(updateBadges).toHaveBeenCalledWith({ branches: 0, inputs: 0, outputs: 0 })
  })
})
