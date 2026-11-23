import { describe, it, expect, beforeEach, vi } from "vitest"
import { FieldVisibilityMixin } from "controllers/property_editor/field_visibility"

// Host mirrors the controller state the mixin reads: a formTarget element, a
// syncChangesToCanvas hook, an _escapeAttr helper, and a disclosureState Map.
const makeHost = (formHtml) => {
  const form = document.createElement("div")
  form.innerHTML = formHtml
  const host = {
    formTarget: form,
    hasFormTarget: true,
    disclosureState: new Map(),
    _syncChangesToCanvas: vi.fn(),
    _escapeAttr: (s) => String(s),
  }
  Object.assign(host, FieldVisibilityMixin)
  return host
}

describe("_applyFieldVisibility", () => {
  it("hides fields whose visible-values exclude the selected value, shows others", () => {
    const host = makeHost(`
      <div data-visible-when="mode" data-visible-values="a,b" id="f1"></div>
      <div data-visible-when="mode" data-visible-values="c" id="f2" class="hidden"></div>
      <div data-visible-when="other" data-visible-values="a" id="f3"></div>
    `)
    host._applyFieldVisibility("mode", "a")
    expect(host.formTarget.querySelector("#f1").classList.contains("hidden")).toBe(false)
    expect(host.formTarget.querySelector("#f2").classList.contains("hidden")).toBe(true)
    // every visibleWhen clause is re-evaluated against the value bag
    expect(host.formTarget.querySelector("#f3").classList.contains("hidden")).toBe(true)
  })

  it("evaluates catalog object-form visibleWhen JSON", () => {
    const host = makeHost(`
      <input name="loopType" value="while">
      <div data-visible-when='{"loopType":"for_each"}' id="collection"></div>
    `)
    host._applyFieldVisibility()
    expect(host.formTarget.querySelector("#collection").classList.contains("hidden")).toBe(true)
    host.formTarget.querySelector("[name='loopType']").value = "for_each"
    host._applyFieldVisibility()
    expect(host.formTarget.querySelector("#collection").classList.contains("hidden")).toBe(false)
  })

  it("treats broken visibleWhen JSON as visible", () => {
    const host = makeHost(`<div data-visible-when="{nope" id="f1"></div>`)
    host._applyFieldVisibility()
    expect(host.formTarget.querySelector("#f1").classList.contains("hidden")).toBe(false)
  })

  it("falls back to an empty visible-values list when the dataset attribute is absent", () => {
    // No data-visible-values at all → (undefined || "").split(",") === [""], so
    // the field is hidden unless the selected value is itself the empty string.
    const host = makeHost(`<div data-visible-when="mode" id="f1"></div>`)
    host._applyFieldVisibility("mode", "a")
    expect(host.formTarget.querySelector("#f1").classList.contains("hidden")).toBe(true)
  })
})

describe("_revealInvalidField", () => {
  const hostFor = (type, html) => {
    const form = document.createElement("form")
    form.innerHTML = html
    const panes = {
      general: form.querySelector("[data-pane-general]"),
      steps: form.querySelector("[data-pane-steps]"),
      io: form.querySelector("[data-pane-io]"),
      advanced: form.querySelector("[data-pane-advanced]"),
    }
    return Object.assign(makeHost(""), {
      formTarget: form,
      currentElement: { type },
      tabManager: { switchTo: vi.fn() },
      stepManager: { _setStepExpanded: vi.fn() },
      getFormFieldsForTab: (tab) => (tab === "branches" ? panes.steps : panes[tab]),
    })
  }

  it("switches a process invalid control to the steps tab and expands the step", () => {
    const host = hostFor("process", `
      <div data-pane-general></div>
      <div data-pane-steps>
        <div data-step-item>
          <input name="connectTimeout">
        </div>
      </div>
    `)
    const input = host.formTarget.querySelector("input")
    host._revealInvalidField({ target: input })
    expect(host.tabManager.switchTo).toHaveBeenCalledWith("steps")
    expect(host.stepManager._setStepExpanded).toHaveBeenCalled()
  })

  it("switches a decision invalid control to the branches tab, not steps", () => {
    const host = hostFor("decision", `
      <div data-pane-general></div>
      <div data-pane-steps>
        <input name="matchValue">
      </div>
    `)
    host._revealInvalidField({ target: host.formTarget.querySelector("input") })
    expect(host.tabManager.switchTo).toHaveBeenCalledWith("branches")
    expect(host.tabManager.switchTo).not.toHaveBeenCalledWith("steps")
  })

  it("opens a closed details and a hidden disclosure around the invalid control", () => {
    const host = hostFor("end", `
      <div data-pane-general>
        <details>
          <div data-disclosure>
            <div data-disclosure-body class="hidden">
              <input name="returnValue">
            </div>
          </div>
        </details>
      </div>
    `)
    const input = host.formTarget.querySelector("input")
    const details = host.formTarget.querySelector("details")
    host._revealInvalidField({ target: input })
    expect(details.open).toBe(true)
    expect(host.formTarget.querySelector("[data-disclosure-body]").classList.contains("hidden")).toBe(false)
  })
})

describe("visibility bag and empty clauses", () => {
  it("skips unnamed and indexed inputs, and treats an empty visibleWhen as visible", () => {
    const host = makeHost(`
      <input name="" value="x">
      <input name="steps[0][action]" value="a">
      <input name="flag" type="checkbox" checked>
      <div data-visible-when="" id="empty-when"></div>
    `)
    expect(host._visibilityValueBag()).toEqual({ flag: true })
    expect(host._isVisibleFromDataset(host.formTarget.querySelector("#empty-when"), {})).toBe(true)
  })
})

describe("conditionally-required children", () => {
  it("toggles required on nested data-conditionally-required controls", () => {
    const host = makeHost(`
      <input name="mode" value="off">
      <div data-visible-when='{"mode":"on"}'>
        <input data-conditionally-required name="child">
      </div>
    `)
    host._applyFieldVisibility()
    expect(host.formTarget.querySelector("[data-conditionally-required]").required).toBe(false)
    host.formTarget.querySelector("[name='mode']").value = "on"
    host._applyFieldVisibility()
    expect(host.formTarget.querySelector("[data-conditionally-required]").required).toBe(true)
  })

  it("does not mark checkbox or hidden inputs required on a conditionally-required wrap", () => {
    const host = makeHost(`
      <input name="mode" value="on">
      <div data-visible-when='{"mode":"on"}' data-conditionally-required>
        <input type="checkbox" name="flag">
        <input type="hidden" name="keep">
        <input type="text" name="shown">
      </div>
    `)
    host._applyFieldVisibility()
    expect(host.formTarget.querySelector("[name='flag']").required).toBe(false)
    expect(host.formTarget.querySelector("[name='keep']").required).toBe(false)
    expect(host.formTarget.querySelector("[name='shown']").required).toBe(true)
  })

  it("does not require a unary right-operand that lives in a hidden wrap", () => {
    const host = makeHost(`
      <input name="loopType" value="while">
      <div data-visible-when='{"loopType":"while"}' data-conditionally-required>
        <input data-condition-left name="left" value="keep_going">
        <select data-condition-op name="op"><option value="is_true" selected>is true</option></select>
        <div data-condition-right-wrap class="hidden">
          <input data-condition-right name="right" value="">
        </div>
      </div>
    `)
    host._applyFieldVisibility()
    expect(host.formTarget.querySelector("[data-condition-left]").required).toBe(true)
    expect(host.formTarget.querySelector("[data-condition-op]").required).toBe(true)
    expect(host.formTarget.querySelector("[data-condition-right]").required).toBe(false)
  })
})

describe("handleVisibilityFieldChange", () => {
  it("no-ops without a field name", () => {
    const host = makeHost("")
    host.handleVisibilityFieldChange({ target: { name: "", value: "x" } })
    expect(host._syncChangesToCanvas).not.toHaveBeenCalled()
  })

  it("applies visibility and syncs to canvas", () => {
    const host = makeHost(`<div data-visible-when="mode" data-visible-values="a"></div>`)
    const field = host.formTarget.querySelector("div")
    host.handleVisibilityFieldChange({ target: { name: "mode", value: "b" } })
    expect(field.classList.contains("hidden")).toBe(true)
    expect(host._syncChangesToCanvas).toHaveBeenCalledOnce()
  })

  it("does not apply legacy Loop editor behavior to an unsupported loopType field", () => {
    const host = makeHost(`
      <input name="itemVariable" value="">
      <input name="indexVariable" value="">
    `)
    host.handleVisibilityFieldChange({ target: { name: "loopType", value: "for_each" } })
    expect(host.formTarget.querySelector('input[name="itemVariable"]').value).toBe("")
    expect(host.formTarget.querySelector('input[name="indexVariable"]').value).toBe("")
  })
})

describe("toggleDisclosure", () => {
  const build = (disclosureId, inStep = true) => {
    const wrap = document.createElement("div")
    wrap.innerHTML = `
      ${inStep ? '<div data-step-item data-step-id="step-1">' : "<div>"}
        <div data-disclosure data-disclosure-id="${disclosureId}">
          <button data-toggle></button>
          <div data-disclosure-body class="hidden"></div>
          <svg data-disclosure-chevron></svg>
        </div>
      </div>
    `
    document.body.appendChild(wrap)
    return wrap
  }

  it("toggles the body hidden class and chevron rotation", () => {
    const host = makeHost("")
    const wrap = build("step-more-0")
    const btn = wrap.querySelector("[data-toggle]")
    host.toggleDisclosure({ preventDefault() {}, currentTarget: btn })
    expect(wrap.querySelector("[data-disclosure-body]").classList.contains("hidden")).toBe(false)
    expect(wrap.querySelector("[data-disclosure-chevron]").classList.contains("rotate-180")).toBe(
      true
    )
  })

  it("records disclosure state keyed by stepId:kind for step-more", () => {
    const host = makeHost("")
    const wrap = build("step-more-0")
    const btn = wrap.querySelector("[data-toggle]")
    host.toggleDisclosure({ preventDefault() {}, currentTarget: btn })
    // body opened → true recorded
    expect(host.disclosureState.get("step-1:more")).toBe(true)
  })

  it("does not record state for non-step disclosures", () => {
    const host = makeHost("")
    const wrap = build("step-more-0", false)
    const btn = wrap.querySelector("[data-toggle]")
    host.toggleDisclosure({ preventDefault() {}, currentTarget: btn })
    expect(host.disclosureState.size).toBe(0)
  })

  it("no-ops when the click target is not inside a [data-disclosure]", () => {
    const host = makeHost("")
    const btn = document.createElement("button")
    document.body.appendChild(btn)
    expect(() =>
      host.toggleDisclosure({ preventDefault() {}, currentTarget: btn })
    ).not.toThrow()
  })

  it("falls back to an empty disclosure id when data-disclosure-id is absent", () => {
    const host = makeHost("")
    const wrap = document.createElement("div")
    wrap.innerHTML = `
      <div data-step-item data-step-id="step-1">
        <div data-disclosure>
          <button data-toggle></button>
          <div data-disclosure-body class="hidden"></div>
        </div>
      </div>
    `
    document.body.appendChild(wrap)
    const btn = wrap.querySelector("[data-toggle]")
    host.toggleDisclosure({ preventDefault() {}, currentTarget: btn })
    expect(host.disclosureState.size).toBe(0)
  })

  it("does not record state for a disclosure id that is not step-more", () => {
    const host = makeHost("")
    const wrap = build("something-else")
    const btn = wrap.querySelector("[data-toggle]")
    host.toggleDisclosure({ preventDefault() {}, currentTarget: btn })
    expect(host.disclosureState.size).toBe(0)
  })

  it("does not record state when the host has no disclosureState map", () => {
    const host = makeHost("")
    delete host.disclosureState
    const wrap = build("step-more-0")
    const btn = wrap.querySelector("[data-toggle]")
    expect(() =>
      host.toggleDisclosure({ preventDefault() {}, currentTarget: btn })
    ).not.toThrow()
  })

  it("no-ops in _recordDisclosureState when there is no body element", () => {
    const host = makeHost("")
    const wrap = document.createElement("div")
    wrap.innerHTML = `
      <div data-step-item data-step-id="step-1">
        <div data-disclosure data-disclosure-id="step-more-0">
          <button data-toggle></button>
        </div>
      </div>
    `
    document.body.appendChild(wrap)
    const btn = wrap.querySelector("[data-toggle]")
    host.toggleDisclosure({ preventDefault() {}, currentTarget: btn })
    expect(host.disclosureState.size).toBe(0)
  })
})
