import { describe, it, expect, vi, beforeEach } from "vitest"
import { CalculationsManager, FORMULA_FUNCTIONS } from "controllers/page_builder/calculations_manager"
import { makeCtrl, field } from "../../support/page_builder.js"

describe("FORMULA_FUNCTIONS catalogue", () => {
  it("groups functions by category with the expected members", () => {
    expect(Object.keys(FORMULA_FUNCTIONS)).toEqual(["Math", "Logic", "Text", "Date"])
    expect(FORMULA_FUNCTIONS.Math).toContain("SUM")
    expect(FORMULA_FUNCTIONS.Logic).toContain("SWITCH")
    expect(FORMULA_FUNCTIONS.Date).toContain("DATE_DIFF")
  })
})

describe("CalculationsManager.openFormulaEditor", () => {
  let ctrl, cm
  beforeEach(() => {
    ctrl = makeCtrl({ configuration: { calculations: [{ id: "c1", target_field_id: "f1", formula: "{a}", format: {} }], rules: [], pages: [], theme: {} } })
    ctrl.hasFormulaEditorModalTarget = false // skip DOM render path
    cm = new CalculationsManager(ctrl)
  })

  it("seeds a blank editing calculation for a new calc", () => {
    cm.openFormulaEditor({ currentTarget: { dataset: {} } })
    expect(ctrl.editingCalculationIdValue).toBe("")
    expect(ctrl.currentEditingCalculation).toMatchObject({ id: null, formula: "" })
  })

  it("deep-clones an existing calculation for editing", () => {
    cm.openFormulaEditor({ currentTarget: { dataset: { calculationId: "c1" } } })
    expect(ctrl.editingCalculationIdValue).toBe("c1")
    expect(ctrl.currentEditingCalculation).toEqual({ id: "c1", target_field_id: "f1", formula: "{a}", format: {} })
    expect(ctrl.currentEditingCalculation).not.toBe(ctrl.configuration.calculations[0])
  })
})

describe("CalculationsManager.renderFormulaEditorModal", () => {
  const buildTemplate = () => {
    const template = document.createElement("template")
    template.innerHTML = `
      <select data-page-builder-target="calculationTargetField"><option value="">--</option><option value="f1">F1</option></select>
      <h3 data-calc-editor-title></h3>
      <div data-controller="formula-editor"></div>
      <select data-calc-format="type"><option value="plain">plain</option><option value="currency">currency</option></select>
      <input data-calc-format="decimals">
      <input data-calc-format="prefix">
      <input data-calc-format="suffix">
    `
    return template
  }

  const setup = (calc) => {
    const ctrl = makeCtrl()
    ctrl.hasFormulaEditorModalTarget = true
    ctrl.formulaEditorModalTarget = document.createElement("div")
    ctrl.hasCalculationEditorTemplateTarget = true
    ctrl.calculationEditorTemplateTarget = buildTemplate()
    ctrl.currentEditingCalculation = calc
    const cm = new CalculationsManager(ctrl)
    return { ctrl, cm }
  }

  it("returns early when there is no modal target", () => {
    const ctrl = makeCtrl()
    ctrl.hasFormulaEditorModalTarget = false
    const cm = new CalculationsManager(ctrl)
    expect(() => cm.renderFormulaEditorModal()).not.toThrow()
  })

  it("clears the modal when there is no calculation-editor template", () => {
    const ctrl = makeCtrl()
    ctrl.hasFormulaEditorModalTarget = true
    ctrl.formulaEditorModalTarget = document.createElement("div")
    ctrl.formulaEditorModalTarget.innerHTML = "stale"
    ctrl.hasCalculationEditorTemplateTarget = false
    const cm = new CalculationsManager(ctrl)
    cm.renderFormulaEditorModal()
    expect(ctrl.formulaEditorModalTarget.innerHTML).toBe("")
  })

  it("defaults to an empty format object when the calculation has none", () => {
    const { ctrl, cm } = setup({ id: "c1", target_field_id: "f1", formula: "{a}" })
    expect(() => cm.renderFormulaEditorModal()).not.toThrow()
    expect(ctrl.formulaEditorModalTarget.querySelector('[data-calc-format="type"]').value).toBe("plain")
  })

  it("hydrates a new (blank) calculation with the 'New Calculation' title and no field selection", () => {
    const { ctrl, cm } = setup({ id: null, target_field_id: "", formula: "", format: {} })
    cm.renderFormulaEditorModal()
    const modal = ctrl.formulaEditorModalTarget
    expect(modal.querySelector("[data-calc-editor-title]").textContent).toBe("New Calculation")
    expect(modal.querySelector('[data-page-builder-target="calculationTargetField"] option[value="f1"]').selected).toBe(false)
    expect(ctrl.tabManager.showDrawerEditor).toHaveBeenCalledWith("calculations")
  })

  it("hydrates an existing calculation: target field, title, formula, and full format", () => {
    const { ctrl, cm } = setup({
      id: "c1", target_field_id: "f1", formula: "{a}+{b}",
      format: { type: "currency", decimals: 2, prefix: "$", suffix: " USD" },
    })
    cm.renderFormulaEditorModal()
    const modal = ctrl.formulaEditorModalTarget
    expect(modal.querySelector("[data-calc-editor-title]").textContent).toBe("Edit Calculation")
    expect(modal.querySelector('[data-page-builder-target="calculationTargetField"] option[value="f1"]').selected).toBe(true)
    expect(modal.querySelector('[data-controller~="formula-editor"]').dataset.formulaEditorFormulaValue).toBe("{a}+{b}")
    expect(modal.querySelector('[data-calc-format="type"]').value).toBe("currency")
    expect(modal.querySelector('[data-calc-format="decimals"]').value).toBe("2")
    expect(modal.querySelector('[data-calc-format="prefix"]').value).toBe("$")
    expect(modal.querySelector('[data-calc-format="suffix"]').value).toBe(" USD")
  })

  it("skips option selection when the target field id has no matching option", () => {
    const { ctrl, cm } = setup({ id: "c1", target_field_id: "unknown", formula: "{a}", format: {} })
    expect(() => cm.renderFormulaEditorModal()).not.toThrow()
    const f1Option = ctrl.formulaEditorModalTarget.querySelector(
      '[data-page-builder-target="calculationTargetField"] option[value="f1"]'
    )
    expect(f1Option.selected).toBe(false)
  })

  it("skips decimals hydration when format.decimals is nullish but writes when it is 0", () => {
    const { ctrl, cm } = setup({ id: "c1", target_field_id: "f1", formula: "{a}", format: { decimals: 0 } })
    cm.renderFormulaEditorModal()
    expect(ctrl.formulaEditorModalTarget.querySelector('[data-calc-format="decimals"]').value).toBe("0")
  })
})

describe("CalculationsManager.editCalculation", () => {
  it("delegates to openFormulaEditor", () => {
    const ctrl = makeCtrl()
    ctrl.hasFormulaEditorModalTarget = false
    const cm = new CalculationsManager(ctrl)
    const spy = vi.spyOn(cm, "openFormulaEditor")
    const event = { currentTarget: { dataset: { calculationId: "c1" } } }
    cm.editCalculation(event)
    expect(spy).toHaveBeenCalledWith(event)
  })
})

describe("CalculationsManager.closeFormulaEditor", () => {
  it("clears editing state and switches the drawer back to the list", () => {
    const ctrl = makeCtrl()
    ctrl.hasFormulaEditorModalTarget = true
    ctrl.formulaEditorModalTarget = document.createElement("div")
    ctrl.formulaEditorModalTarget.innerHTML = "stuff"
    const cm = new CalculationsManager(ctrl)
    cm.closeFormulaEditor()
    expect(ctrl.editingCalculationIdValue).toBe("")
    expect(ctrl.currentEditingCalculation).toBeNull()
    expect(ctrl.formulaEditorModalTarget.innerHTML).toBe("")
    expect(ctrl.tabManager.showDrawerList).toHaveBeenCalledWith("calculations")
  })

  it("closeFormulaEditorOnBackdrop only closes on a backdrop (self) click", () => {
    const ctrl = makeCtrl()
    ctrl.hasFormulaEditorModalTarget = false
    const cm = new CalculationsManager(ctrl)
    const spy = vi.spyOn(cm, "closeFormulaEditor")
    const el = document.createElement("div")
    cm.closeFormulaEditorOnBackdrop({ target: el, currentTarget: el })
    expect(spy).toHaveBeenCalledOnce()
    cm.closeFormulaEditorOnBackdrop({ target: document.createElement("span"), currentTarget: el })
    expect(spy).toHaveBeenCalledOnce() // not called again
  })
})

describe("CalculationsManager.saveCalculation", () => {
  const buildModal = (formula) => {
    const modal = document.createElement("div")
    modal.innerHTML = `
      <select data-page-builder-target="calculationTargetField"><option value="">--</option><option value="f1">F1</option></select>
      <div data-controller="formula-editor"></div>
      <select data-calc-format="type"><option value="plain">plain</option><option value="currency">currency</option></select>
      <input data-calc-format="decimals" value="">
      <input data-calc-format="prefix" value="">
      <input data-calc-format="suffix" value="">
    `
    modal.querySelector('[data-page-builder-target="calculationTargetField"]').value = "f1"
    return modal
  }

  it("returns early when there is no modal target", () => {
    const ctrl = makeCtrl()
    ctrl.hasFormulaEditorModalTarget = false
    const cm = new CalculationsManager(ctrl)
    expect(() => cm.saveCalculation()).not.toThrow()
  })

  it("alerts and does not save when the formula is empty", () => {
    const ctrl = makeCtrl({ configuration: { calculations: [], rules: [], pages: [], theme: {} } })
    ctrl.hasFormulaEditorModalTarget = true
    ctrl.formulaEditorModalTarget = buildModal()
    ctrl.application = { getControllerForElementAndIdentifier: () => ({ getFormula: () => "" }) }
    const alertSpy = vi.spyOn(globalThis, "alert").mockImplementation(() => {})
    const cm = new CalculationsManager(ctrl)
    // Avoid the DOM re-render path
    cm.renderCalculationsPanel = vi.fn()
    cm.saveCalculation()
    expect(alertSpy).toHaveBeenCalled()
    expect(ctrl.configuration.calculations).toHaveLength(0)
    alertSpy.mockRestore()
  })

  it("pushes a new calculation, saves history, and marks dirty", () => {
    const ctrl = makeCtrl({ configuration: { calculations: [], rules: [], pages: [], theme: {} } })
    ctrl.hasFormulaEditorModalTarget = true
    ctrl.formulaEditorModalTarget = buildModal()
    ctrl.formulaEditorModalTarget.querySelector('[data-calc-format="type"]').value = "currency"
    ctrl.application = { getControllerForElementAndIdentifier: () => ({ getFormula: () => "{a} + 1" }) }
    const cm = new CalculationsManager(ctrl)
    cm.renderCalculationsPanel = vi.fn()
    cm.saveCalculation()
    expect(ctrl.configuration.calculations).toHaveLength(1)
    expect(ctrl.configuration.calculations[0]).toMatchObject({ target_field_id: "f1", formula: "{a} + 1", format: { type: "currency" } })
    expect(ctrl.undoRedoManager.saveHistory).toHaveBeenCalled()
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
  })

  it("treats a missing target-select or formula-editor-controller as empty and alerts", () => {
    const ctrl = makeCtrl({ configuration: { calculations: [], rules: [], pages: [], theme: {} } })
    ctrl.hasFormulaEditorModalTarget = true
    ctrl.formulaEditorModalTarget = document.createElement("div") // no select, no formula-editor root
    const alertSpy = vi.spyOn(globalThis, "alert").mockImplementation(() => {})
    const cm = new CalculationsManager(ctrl)
    cm.saveCalculation()
    expect(alertSpy).toHaveBeenCalled()
    alertSpy.mockRestore()
  })

  it("treats a formula-editor root with no resolvable controller as an empty formula", () => {
    const ctrl = makeCtrl({ configuration: { calculations: [], rules: [], pages: [], theme: {} } })
    ctrl.hasFormulaEditorModalTarget = true
    ctrl.formulaEditorModalTarget = buildModal()
    ctrl.application = { getControllerForElementAndIdentifier: () => null }
    const alertSpy = vi.spyOn(globalThis, "alert").mockImplementation(() => {})
    const cm = new CalculationsManager(ctrl)
    cm.saveCalculation()
    expect(alertSpy).toHaveBeenCalled()
    expect(ctrl.configuration.calculations).toHaveLength(0)
    alertSpy.mockRestore()
  })

  it("falls back to window.Stimulus when the controller has no application reference", () => {
    const ctrl = makeCtrl({ configuration: { calculations: [], rules: [], pages: [], theme: {} } })
    ctrl.hasFormulaEditorModalTarget = true
    ctrl.formulaEditorModalTarget = buildModal()
    ctrl.application = undefined
    const alertSpy = vi.spyOn(globalThis, "alert").mockImplementation(() => {})
    const cm = new CalculationsManager(ctrl)
    expect(() => cm.saveCalculation()).not.toThrow()
    expect(alertSpy).toHaveBeenCalled() // no formula resolvable -> alert
    alertSpy.mockRestore()
  })

  it("writes decimals (including a zero fallback), prefix, and suffix when present", () => {
    const ctrl = makeCtrl({ configuration: { calculations: [], rules: [], pages: [], theme: {} } })
    ctrl.hasFormulaEditorModalTarget = true
    const modal = buildModal()
    modal.querySelector('[data-calc-format="decimals"]').value = "abc" // parseInt -> NaN -> falls back to 0
    modal.querySelector('[data-calc-format="prefix"]').value = "$"
    modal.querySelector('[data-calc-format="suffix"]').value = " USD"
    ctrl.formulaEditorModalTarget = modal
    ctrl.application = { getControllerForElementAndIdentifier: () => ({ getFormula: () => "{a}" }) }
    const cm = new CalculationsManager(ctrl)
    cm.renderCalculationsPanel = vi.fn()
    cm.saveCalculation()
    expect(ctrl.configuration.calculations[0].format).toMatchObject({ decimals: 0, prefix: "$", suffix: " USD" })
  })

  it("initializes configuration.calculations when it is missing", () => {
    const ctrl = makeCtrl({ configuration: { rules: [], pages: [], theme: {} } })
    delete ctrl.configuration.calculations
    ctrl.hasFormulaEditorModalTarget = true
    ctrl.formulaEditorModalTarget = buildModal()
    ctrl.application = { getControllerForElementAndIdentifier: () => ({ getFormula: () => "{a}" }) }
    const cm = new CalculationsManager(ctrl)
    cm.renderCalculationsPanel = vi.fn()
    cm.saveCalculation()
    expect(ctrl.configuration.calculations).toHaveLength(1)
  })

  it("updates an existing calculation in place when editing", () => {
    const ctrl = makeCtrl({ configuration: { calculations: [{ id: "c1", target_field_id: "old", formula: "old", format: {} }], rules: [], pages: [], theme: {} } })
    ctrl.editingCalculationIdValue = "c1"
    ctrl.hasFormulaEditorModalTarget = true
    ctrl.formulaEditorModalTarget = buildModal()
    ctrl.application = { getControllerForElementAndIdentifier: () => ({ getFormula: () => "{new}" }) }
    const cm = new CalculationsManager(ctrl)
    cm.renderCalculationsPanel = vi.fn()
    cm.saveCalculation()
    expect(ctrl.configuration.calculations).toHaveLength(1)
    expect(ctrl.configuration.calculations[0]).toMatchObject({ id: "c1", formula: "{new}", target_field_id: "f1" })
  })
})

describe("CalculationsManager.deleteCalculation", () => {
  it("removes the calc after confirmation and marks dirty", () => {
    const ctrl = makeCtrl({ configuration: { calculations: [{ id: "c1" }, { id: "c2" }], rules: [], pages: [], theme: {} } })
    const cm = new CalculationsManager(ctrl)
    cm.renderCalculationsPanel = vi.fn()
    const confirmSpy = vi.spyOn(globalThis, "confirm").mockReturnValue(true)
    cm.deleteCalculation({ currentTarget: { dataset: { calculationId: "c1" } } })
    expect(ctrl.configuration.calculations.map((c) => c.id)).toEqual(["c2"])
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
    confirmSpy.mockRestore()
  })

  it("defaults to an empty list when configuration.calculations is missing", () => {
    const ctrl = makeCtrl({ configuration: { rules: [], pages: [], theme: {} } })
    delete ctrl.configuration.calculations
    const cm = new CalculationsManager(ctrl)
    cm.renderCalculationsPanel = vi.fn()
    const confirmSpy = vi.spyOn(globalThis, "confirm").mockReturnValue(true)
    expect(() => cm.deleteCalculation({ currentTarget: { dataset: { calculationId: "c1" } } })).not.toThrow()
    expect(ctrl.configuration.calculations).toEqual([])
    confirmSpy.mockRestore()
  })

  it("does nothing when the confirm is declined", () => {
    const ctrl = makeCtrl({ configuration: { calculations: [{ id: "c1" }], rules: [], pages: [], theme: {} } })
    const cm = new CalculationsManager(ctrl)
    const confirmSpy = vi.spyOn(globalThis, "confirm").mockReturnValue(false)
    cm.deleteCalculation({ currentTarget: { dataset: { calculationId: "c1" } } })
    expect(ctrl.configuration.calculations).toHaveLength(1)
    confirmSpy.mockRestore()
  })
})

describe("CalculationsManager.renderCalculationsPanel", () => {
  let ctrl, cm
  beforeEach(() => {
    ctrl = makeCtrl({
      currentPage: { id: "p1", fields: [field({ id: "f1", label: "Total" })] },
      configuration: { calculations: [], rules: [], pages: [], theme: {} },
    })
    ctrl.hasCalculationsPanelTarget = true
    ctrl.calculationsPanelTarget = document.createElement("div")
    cm = new CalculationsManager(ctrl)
  })

  it("returns early when there is no panel target", () => {
    ctrl.hasCalculationsPanelTarget = false
    expect(() => cm.renderCalculationsPanel()).not.toThrow()
  })

  it("renders an empty state with a call to action", () => {
    cm.renderCalculationsPanel()
    expect(ctrl.calculationsPanelTarget.innerHTML).toContain("No calculated fields")
    expect(ctrl.calculationsPanelTarget.innerHTML).toContain("0 calculations configured")
  })

  it("renders each calculation with its target field label and truncated formula", () => {
    ctrl.configuration.calculations = [{ id: "c1", target_field_id: "f1", formula: "{a}+{b}", format: { type: "currency" } }]
    cm.renderCalculationsPanel()
    const html = ctrl.calculationsPanelTarget.innerHTML
    expect(html).toContain("1 calculation configured")
    expect(html).toContain("Total")
    expect(html).toContain('data-calculation-id="c1"')
    expect(html).toContain("currency")
  })

  it("shows a search box once there are more than 6 calculations", () => {
    ctrl.configuration.calculations = Array.from({ length: 7 }, (_, i) => ({
      id: `c${i}`, target_field_id: "f1", formula: `{a${i}}`, format: {},
    }))
    cm.renderCalculationsPanel()
    const html = ctrl.calculationsPanelTarget.innerHTML
    expect(html).toContain("7 calculations configured")
    expect(html).toContain("Search calculations")
  })

  it("truncates a formula longer than 40 characters and falls back to the field id when the field is unknown", () => {
    ctrl.configuration.calculations = [
      { id: "c1", target_field_id: "unknown_field", formula: "a".repeat(50), format: {} },
    ]
    cm.renderCalculationsPanel()
    const html = ctrl.calculationsPanelTarget.innerHTML
    expect(html).toContain("unknown_field")
    expect(html).toContain("a".repeat(40) + "…")
  })

  it("defaults calculations to an empty list when configuration.calculations is missing", () => {
    delete ctrl.configuration.calculations
    expect(() => cm.renderCalculationsPanel()).not.toThrow()
    expect(ctrl.calculationsPanelTarget.innerHTML).toContain("No calculated fields")
  })

  it("renders a blank formula summary and default format badge when a calc has neither", () => {
    ctrl.configuration.calculations = [{ id: "c1", target_field_id: "f1" }] // no formula, no format
    cm.renderCalculationsPanel()
    const html = ctrl.calculationsPanelTarget.innerHTML
    expect(html).toContain('data-calculation-id="c1"')
    expect(html).toContain('= </span>') // empty formula summary right after "= "
  })
})
