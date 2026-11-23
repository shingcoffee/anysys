import { describe, it, expect, vi } from "vitest"
import { FormBuilder } from "controllers/property_editor/form_builder"
import { installSampleElementCatalog } from "../../support/element_catalog.js"

installSampleElementCatalog()

const svgIcon = () => {
  const d = document.createElement("div")
  d.innerHTML = "<svg><path d=''></path></svg>"
  return d
}

const CONTROL_LABELS = {
  noneOptionLabelValue: "None",
  addRowLabelValue: "Add row",
  removeRowTitleValue: "Remove",
  searchPlaceholderValue: "Search…",
  localeEnLabelValue: "English",
  localeZhCnLabelValue: "Chinese",
  referenceLoadingLabelValue: "Loading…",
  referenceEmptyLabelValue: "No matches",
  referenceErrorLabelValue: "Could not load options",
  referencePlaceholderValue: "Select…",
  joinAndLabelValue: "AND",
  joinOrLabelValue: "OR",
  valuePlaceholderValue: "value",
  defaultPlaceholderFormatValue: "Default: {value}",
  insertVariableTitleValue: "Insert variable",
  noVariablesAvailableValue: "No variables available",
  usedInThisElementLabelValue: "Used in this element",
  noMatchingVariablesLabelValue: "No matching variables",
  branchOperatorLabelsValue: {},
}

function makePanes() {
  return {
    general: document.createElement("div"),
    steps: document.createElement("div"),
    io: document.createElement("div"),
    advanced: document.createElement("div"),
  }
}

function makeController(over = {}) {
  const panes = over.panes || makePanes()
  return {
    currentElement: over.currentElement ?? { id: "e1", type: "process", label: "", properties: {} },
    canvas: over.canvas ?? {},
    hasTitleTarget: true,
    titleTarget: document.createElement("div"),
    hasTypeIndicatorTarget: true,
    typeIndicatorTarget: document.createElement("div"),
    hasTypeIconTarget: true,
    typeIconTarget: svgIcon(),
    hasHeaderWrapperTarget: true,
    headerWrapperTarget: document.createElement("div"),
    formTarget: over.formTarget || document.createElement("form"),
    tabManager: { activeTab: "general" },
    getFormFieldsForTab: (tab) => panes[tab] || panes.general,
    _collectFormData: over._collectFormData || (() => ({})),
    _deriveLabelFromProperties: over._deriveLabelFromProperties || (() => ""),
    _performSync: over._performSync || vi.fn(),
    ...CONTROL_LABELS,
    ...over.controllerOverrides,
    panes,
  }
}

describe("FormBuilder", () => {
  describe("buildForm guards", () => {
    it("no-ops without a current element or canvas", () => {
      expect(() => new FormBuilder(makeController({ currentElement: null })).buildForm()).not.toThrow()
    })

    it("no-ops without a canvas even when there is a current element", () => {
      const fb = new FormBuilder(makeController({ controllerOverrides: { canvas: null } }))
      expect(() => fb.buildForm()).not.toThrow()
    })
  })

  describe("_updateTitle", () => {
    it("sets the catalog type label and tints indicator/icon/header", () => {
      const ctrl = makeController({ currentElement: { id: "e1", type: "decision", label: "My Gate", properties: {} } })
      new FormBuilder(ctrl)._updateTitle()
      expect(ctrl.titleTarget.textContent).toBe("Decision")
      expect(ctrl.typeIndicatorTarget.style.backgroundColor).toBeTruthy()
      expect(ctrl.typeIconTarget.querySelector("path").getAttribute("d")).toContain("M12 3l9 9")
    })

    it("falls back to the raw type when the catalog has no entry", () => {
      const ctrl = makeController({ currentElement: { id: "e1", type: "mystery_type", label: "", properties: {} } })
      new FormBuilder(ctrl)._updateTitle()
      expect(ctrl.titleTarget.textContent).toBe("mystery_type")
    })

    it("no-ops entirely when there is no title target", () => {
      const ctrl = makeController({ controllerOverrides: { hasTitleTarget: false } })
      expect(() => new FormBuilder(ctrl)._updateTitle()).not.toThrow()
      expect(ctrl.titleTarget.textContent).toBe("")
    })

    it("falls back to the process icon path for an unmapped element type", () => {
      const ctrl = makeController({ currentElement: { id: "e1", type: "mystery_type", label: "X", properties: {} } })
      new FormBuilder(ctrl)._updateTitle()
      expect(ctrl.typeIconTarget.querySelector("path").getAttribute("d")).toContain("M4 6h16M4 12h16M4 18h16")
    })
  })

  describe("catalog-driven form", () => {
    it("defaults missing properties, element id, and placeholder format", () => {
      const ctrl = makeController({
        currentElement: { type: "start", label: null },
        controllerOverrides: { defaultPlaceholderFormatValue: "" },
      })
      delete ctrl.currentElement.id
      new FormBuilder(ctrl).buildForm()
      expect(ctrl.panes.general.querySelector('input[name="label"]').value).toBe("")
    })

    it("renders chrome label + notes on General and no tiny type sizes", () => {
      const ctrl = makeController({
        currentElement: { id: "e1", type: "start", label: "Go", properties: {} },
      })
      new FormBuilder(ctrl).buildForm()
      const general = ctrl.panes.general
      expect(general.querySelector('input[name="label"]').value).toBe("Go")
      const notes = general.querySelector("[data-notes-disclosure]")
      expect(notes).not.toBeNull()
      expect(notes.open).toBe(false)
      expect(general.innerHTML).not.toMatch(/text-\[(?:9|10|11)px\]/)
    })

    it("opens Notes when description is non-empty", () => {
      const ctrl = makeController({
        currentElement: { id: "e1", type: "start", label: "Go", properties: { description: "hello" } },
      })
      new FormBuilder(ctrl).buildForm()
      expect(ctrl.panes.general.querySelector("[data-notes-disclosure]").open).toBe(true)
      expect(ctrl.panes.general.querySelector('textarea[name="description"]').value).toBe("hello")
    })

    it("renders End fields on General and hides returnValue when responseType is none", () => {
      const ctrl = makeController({
        currentElement: { id: "e1", type: "end", label: "End", properties: { responseType: "none" } },
      })
      new FormBuilder(ctrl).buildForm()
      const general = ctrl.panes.general
      expect(general.querySelector('[data-element-field="responseType"]')).not.toBeNull()
      expect(general.querySelector('[data-element-field="returnValue"]').classList.contains("hidden")).toBe(true)
      expect(ctrl.panes.advanced.innerHTML).toBe("")
    })

    it("keeps a missing number empty and shows the catalog default in the placeholder", () => {
      const ctrl = makeController({
        currentElement: { id: "e1", type: "loop", label: "Loop", properties: { loopType: "while" } },
      })
      new FormBuilder(ctrl).buildForm()
      const input = ctrl.panes.general.querySelector('input[name="maxIterations"]')
      expect(input.value).toBe("")
      expect(input.placeholder).toBe("Default: 100")
    })

    it("renders a stored number and loop advanced fields in one column", () => {
      const ctrl = makeController({
        currentElement: {
          id: "e1",
          type: "loop",
          label: "Loop",
          properties: { loopType: "while", maxIterations: 25 },
        },
      })
      new FormBuilder(ctrl).buildForm()
      expect(ctrl.panes.general.querySelector('input[name="maxIterations"]').value).toBe("25")
      expect(ctrl.panes.advanced.querySelector('[data-element-field="stopWhen"]')).not.toBeNull()
      expect(ctrl.panes.advanced.classList.contains("grid-cols-2")).toBe(false)
      expect(ctrl.panes.advanced.classList.contains("space-y-2")).toBe(true)
    })

    it("delegates Process steps and Decision branches to their managers", () => {
      const ctrl = makeController({
        currentElement: { id: "e1", type: "process", label: "P", properties: { steps: [] } },
        controllerOverrides: {
          stepManager: { buildStepsFieldHTML: () => '<div data-steps-container></div>' },
        },
      })
      new FormBuilder(ctrl).buildForm()
      expect(ctrl.panes.steps.querySelector("[data-steps-container]")).not.toBeNull()

      const decision = makeController({
        currentElement: { id: "d1", type: "decision", label: "D", properties: { routeBy: "condition" } },
        controllerOverrides: {
          branchManager: { buildBranchesFieldHTML: () => '<div data-branches-container></div>' },
        },
      })
      new FormBuilder(decision).buildForm()
      expect(decision.panes.steps.querySelector("[data-branches-container]")).not.toBeNull()
      expect(decision.panes.general.querySelector('[data-element-field="routeBy"]')).not.toBeNull()
    })
  })

  describe("_buildNotes fallbacks and focus", () => {
    it("uses Notes / description when chrome is empty", () => {
      const fb = new FormBuilder(makeController())
      expect(fb._buildNotes({}, "")).toContain("Notes")
      expect(fb._buildNotes({}, "")).toContain('name="description"')
      expect(fb._buildLabelField({}, null)).toContain("Label")
    })

    it("focuses the first input of the active tab, defaulting the tab to general", () => {
      vi.useFakeTimers()
      const panes = makePanes()
      panes.general.innerHTML = '<input name="label">'
      const focus = vi.spyOn(panes.general.querySelector("input"), "focus")
      const ctrl = makeController({
        currentElement: { id: "e1", type: "start", label: "", properties: {} },
        panes,
        controllerOverrides: { tabManager: null },
      })
      new FormBuilder(ctrl)._focusFirstInput()
      vi.advanceTimersByTime(100)
      expect(focus).toHaveBeenCalled()
      vi.useRealTimers()
    })
  })

  describe("_fieldValue", () => {
    it("prefers a stored property, leaves missing numbers empty, and uses other defaults", () => {
      const fb = new FormBuilder(makeController())
      expect(fb._fieldValue({ name: "maxIterations", role: "integer" }, { maxIterations: 3 })).toBe(3)
      expect(fb._fieldValue({ name: "maxIterations", role: "integer", default: 100 }, {})).toBeUndefined()
      expect(fb._fieldValue({ name: "rate", role: "decimal", default: 1 }, {})).toBeUndefined()
      expect(fb._fieldValue({ name: "loopType", default: "while" }, {})).toBe("while")
      expect(fb._fieldValue({ name: "x" }, {})).toBe("")
    })
  })

  describe("_autoDeriveLabelOnOpen", () => {
    it("marks a blank or catalog defaultLabel as automatic without rewriting the input", () => {
      const form = document.createElement("form")
      form.innerHTML = '<input name="label" value="Start">'
      const ctrl = makeController({
        currentElement: { id: "e1", type: "start", label: "Start", properties: {} },
        formTarget: form,
      })
      const fb = new FormBuilder(ctrl)
      fb._autoDeriveLabelOnOpen()
      expect(ctrl._labelAutoDerived).toBe(true)
      expect(form.querySelector('input[name="label"]').value).toBe("Start")
    })

    it("marks a label automatic when it matches the previous derived label", () => {
      const form = document.createElement("form")
      form.innerHTML = '<input name="label" value="While x > 1">'
      const ctrl = makeController({
        currentElement: { id: "e1", type: "loop", label: "While x > 1", properties: {} },
        formTarget: form,
        _collectFormData: () => ({ loopType: "while" }),
        _deriveLabelFromProperties: () => "While x > 1",
      })
      new FormBuilder(ctrl)._autoDeriveLabelOnOpen()
      expect(ctrl._labelAutoDerived).toBe(true)
    })

    it("treats a custom label as manual", () => {
      const form = document.createElement("form")
      form.innerHTML = '<input name="label" value="My Loop">'
      const ctrl = makeController({
        currentElement: { id: "e1", type: "loop", label: "My Loop", properties: {} },
        formTarget: form,
        _deriveLabelFromProperties: () => "While",
      })
      new FormBuilder(ctrl)._autoDeriveLabelOnOpen()
      expect(ctrl._labelAutoDerived).toBe(false)
    })

    it("treats a missing element type as a blank catalog defaultLabel", () => {
      const form = document.createElement("form")
      form.innerHTML = '<input name="label" value="Custom">'
      const ctrl = makeController({
        currentElement: { id: "e1", properties: {} },
        formTarget: form,
        _deriveLabelFromProperties: () => "",
      })
      new FormBuilder(ctrl)._autoDeriveLabelOnOpen()
      expect(ctrl._labelAutoDerived).toBe(false)
    })

    it("no-ops without a label input and re-attaches the listener on a later open", () => {
      const fb = new FormBuilder(makeController({ formTarget: document.createElement("form") }))
      expect(() => fb._autoDeriveLabelOnOpen()).not.toThrow()

      const form = document.createElement("form")
      const input = document.createElement("input")
      input.name = "label"
      input.value = ""
      form.appendChild(input)
      const sync = vi.fn()
      const ctrl = makeController({
        currentElement: { id: "e1", type: "start", label: "", properties: {} },
        formTarget: form,
        _performSync: sync,
      })
      const again = new FormBuilder(ctrl)
      again._autoDeriveLabelOnOpen()
      again._autoDeriveLabelOnOpen()
      input.value = "typed"
      input.dispatchEvent(new Event("input"))
      expect(ctrl._labelAutoDerived).toBe(false)
      input.value = ""
      input.dispatchEvent(new Event("input"))
      expect(ctrl._labelAutoDerived).toBe(true)
      expect(sync).toHaveBeenCalled()
    })
  })
})
