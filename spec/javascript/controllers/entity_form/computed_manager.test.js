import { describe, it, expect, vi } from "vitest"
import { ComputedManager } from "controllers/entity_form/computed_manager"
import { buildController, fakeEvent } from "./support.js"

const SAMPLE_OPTIONS = [
  {
    bridge_entity_id: 15,
    bridge_role: "source",
    related_entity_label: "Class",
    bridge_label: "assoc_student_class",
    attributes: [
      { slug: "score", label: "Score", numeric: true },
      { slug: "status", label: "Status", numeric: false },
    ],
  },
  {
    bridge_entity_id: 22,
    bridge_role: "target",
    related_entity_label: "Student",
    bridge_label: "assoc_student_class",
    attributes: [{ slug: "credits", label: "Credits", numeric: true }],
  },
]

const COMPUTED_HTML = `
  <button data-entity-form-target="modeInputBtn" class="text-accent-text bg-accent-subtle border-accent shadow-sm"></button>
  <button data-entity-form-target="modeComputedBtn" class="text-text-muted bg-transparent border-transparent"></button>
  <div data-entity-form-target="valueSourceSection" class="hidden"></div>
  <div data-entity-form-target="computedSection" class="hidden"></div>
  <div data-entity-form-target="htmlTypeField"></div>
  <div data-entity-form-target="validatorsSection"></div>
  <div data-entity-form-target="optionsSection"></div>
  <select data-entity-form-target="computedRelation"></select>
  <select data-entity-form-target="computedAttribute"></select>
  <select data-entity-form-target="computedFunction">
    <option value="avg">Average</option>
    <option value="sum">Sum</option>
    <option value="count">Count</option>
    <option value="min">Min</option>
    <option value="max">Max</option>
  </select>
  <input type="number" data-entity-form-target="computedPrecision" value="2">
  <select data-entity-form-target="computedFilterAttribute"></select>
  <select data-entity-form-target="computedFilterOp" disabled>
    <option value="">Select an operator</option>
    <option value="=">=</option>
    <option value="!=">!=</option>
    <option value=">">&gt;</option>
    <option value=">=">&gt;=</option>
    <option value="<">&lt;</option>
    <option value="<=">&lt;=</option>
  </select>
  <input type="text" data-entity-form-target="computedFilterValue" disabled>
`

function computedController({ html = COMPUTED_HTML, values = {}, typeManager } = {}) {
  const { controller } = buildController(html, {
    values: { attributeMode: "input", computedOptionsValue: SAMPLE_OPTIONS, ...values },
  })
  controller.typeManager = typeManager || { htmlTypeChanged: vi.fn() }
  controller.computedManager = new ComputedManager(controller)
  return controller
}

describe("ComputedManager#parsedOptions", () => {
  it("returns an array as-is", () => {
    const c = computedController()
    expect(c.computedManager.parsedOptions()).toEqual(SAMPLE_OPTIONS)
  })

  it("wraps a single object", () => {
    const c = computedController({ values: { computedOptionsValue: SAMPLE_OPTIONS[0] } })
    expect(c.computedManager.parsedOptions()).toEqual([SAMPLE_OPTIONS[0]])
  })

  it("parses a JSON array string", () => {
    const c = computedController({ values: { computedOptionsValue: JSON.stringify(SAMPLE_OPTIONS) } })
    expect(c.computedManager.parsedOptions()).toHaveLength(2)
  })

  it("parses a JSON object string as a one-item array", () => {
    const c = computedController({ values: { computedOptionsValue: JSON.stringify(SAMPLE_OPTIONS[0]) } })
    expect(c.computedManager.parsedOptions()).toEqual([SAMPLE_OPTIONS[0]])
  })

  it("returns [] for malformed JSON, empty, or non-object values", () => {
    expect(computedController({ values: { computedOptionsValue: "not-json" } }).computedManager.parsedOptions()).toEqual([])
    expect(computedController({ values: { computedOptionsValue: null } }).computedManager.parsedOptions()).toEqual([])
    expect(computedController({ values: { computedOptionsValue: 12 } }).computedManager.parsedOptions()).toEqual([])
    expect(computedController({ values: { computedOptionsValue: "" } }).computedManager.parsedOptions()).toEqual([])
  })
})

describe("ComputedManager#selectInputMode / selectComputedMode", () => {
  it("selectInputMode sets data mode, restyles buttons, and restores html-type visibility", () => {
    const c = computedController()
    c.attributeMode = "computed"
    c.computedManager.selectInputMode(fakeEvent())
    expect(c.attributeMode).toBe("input")
    expect(c.modeInputBtnTarget.className).toContain("bg-accent-subtle")
    expect(c.modeComputedBtnTarget.className).toContain("text-text-muted")
    expect(c.computedSectionTarget.classList.contains("hidden")).toBe(true)
    expect(c.htmlTypeFieldTarget.classList.contains("hidden")).toBe(false)
    expect(c.validatorsSectionTarget.classList.contains("hidden")).toBe(false)
    expect(c.typeManager.htmlTypeChanged).toHaveBeenCalled()
  })

  it("selectComputedMode populates relations and hides data-only sections", () => {
    const c = computedController()
    c.computedManager.selectComputedMode(fakeEvent())
    expect(c.attributeMode).toBe("computed")
    expect(c.computedSectionTarget.classList.contains("hidden")).toBe(false)
    expect(c.htmlTypeFieldTarget.classList.contains("hidden")).toBe(true)
    expect(c.validatorsSectionTarget.classList.contains("hidden")).toBe(true)
    expect(c.optionsSectionTarget.classList.contains("hidden")).toBe(true)
    expect(c.valueSourceSectionTarget.classList.contains("hidden")).toBe(false)
    expect(c.computedRelationTarget.options.length).toBe(3) // placeholder + 2
    expect(c.computedRelationTarget.options[1].textContent).toBe("Class (assoc_student_class)")
    expect(c.typeManager.htmlTypeChanged).not.toHaveBeenCalled()
  })

  it("tolerates being called without an event and without mode-button targets", () => {
    const { controller } = buildController(`<div data-entity-form-target="computedSection" class="hidden"></div>`, {
      values: { attributeMode: "input", computedOptionsValue: [] },
    })
    controller.typeManager = { htmlTypeChanged: vi.fn() }
    const mgr = new ComputedManager(controller)
    expect(() => mgr.selectComputedMode()).not.toThrow()
    expect(() => mgr.selectInputMode()).not.toThrow()
    expect(controller.attributeMode).toBe("input")
    expect(controller.typeManager.htmlTypeChanged).toHaveBeenCalled()
  })

  it("reveals Value source when the entity has computed relations", () => {
    const c = computedController()
    c.computedManager.updateModeUI()
    expect(c.valueSourceSectionTarget.classList.contains("hidden")).toBe(false)
  })

  it("keeps Value source hidden when the entity has no associations", () => {
    const c = computedController({ values: { computedOptionsValue: [] } })
    c.computedManager.updateModeUI()
    expect(c.valueSourceSectionTarget.classList.contains("hidden")).toBe(true)
  })

  it("hides Value source in association-attribute context even when relations exist", () => {
    const c = computedController()
    c.computedManager.selectComputedMode(fakeEvent())
    expect(c.attributeMode).toBe("computed")
    c.attributeModalContext = "association"
    c.computedManager.updateModeUI()
    expect(c.valueSourceSectionTarget.classList.contains("hidden")).toBe(true)
    expect(c.attributeMode).toBe("input")
  })

  it("falls back to input mode when Computed is selected without relations", () => {
    const c = computedController({ values: { computedOptionsValue: [] } })
    c.attributeMode = "computed"
    c.computedManager.selectComputedMode(fakeEvent())
    expect(c.attributeMode).toBe("input")
    expect(c.computedSectionTarget.classList.contains("hidden")).toBe(true)
    expect(c.htmlTypeFieldTarget.classList.contains("hidden")).toBe(false)
    expect(c.valueSourceSectionTarget.classList.contains("hidden")).toBe(true)
  })

  it("selectInputMode skips htmlTypeChanged when typeManager is absent", () => {
    const c = computedController({ typeManager: null })
    c.typeManager = undefined
    expect(() => c.computedManager.selectInputMode()).not.toThrow()
  })
})

describe("ComputedManager#populateRelations", () => {
  it("no-ops without a relation select", () => {
    const { controller } = buildController("", { values: { computedOptionsValue: SAMPLE_OPTIONS } })
    expect(() => new ComputedManager(controller).populateRelations()).not.toThrow()
  })

  it("shows the empty hint as the only option when there are no relations", () => {
    const c = computedController({ values: { computedOptionsValue: [] } })
    c.computedManager.populateRelations()
    expect(c.computedRelationTarget.options.length).toBe(1)
    expect(c.computedRelationTarget.options[0].textContent).toBe("No related associations")
  })

  it("preserves the current relation when it is still present after a refill", () => {
    const c = computedController()
    c.computedManager.populateRelations()
    c.computedRelationTarget.value = "1"
    c.computedManager.populateRelations()
    expect(c.computedRelationTarget.value).toBe("1")
  })

  it("falls back to blank related/bridge labels in the format string", () => {
    const c = computedController({
      values: {
        computedOptionsValue: [{ bridge_entity_id: 1, bridge_role: "source", attributes: [] }],
      },
    })
    c.computedManager.populateRelations()
    expect(c.computedRelationTarget.options[1].textContent).toBe(" ()")
  })
})

describe("ComputedManager#populateAttributes / functionChanged", () => {
  it("no-ops without an attribute select", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="computedRelation"><option value="0">R</option></select>`,
      { values: { computedOptionsValue: SAMPLE_OPTIONS } }
    )
    expect(() => new ComputedManager(controller).populateAttributes()).not.toThrow()
  })

  it("leaves only the placeholder when no relation is selected", () => {
    const c = computedController()
    c.computedManager.populateRelations()
    expect(c.computedAttributeTarget.options.length).toBe(1)
    expect(c.computedAttributeTarget.options[0].textContent).toBe("Select an attribute")
  })

  it("filters to numeric attributes unless the function is count", () => {
    const c = computedController()
    c.computedManager.populateRelations()
    c.computedRelationTarget.value = "0"
    c.computedFunctionTarget.value = "avg"
    c.computedManager.relationChanged()
    expect([...c.computedAttributeTarget.options].map((o) => o.value)).toEqual(["", "score"])

    c.computedFunctionTarget.value = "count"
    c.computedManager.functionChanged()
    expect([...c.computedAttributeTarget.options].map((o) => o.value)).toEqual(["", "score", "status"])
    expect(c.computedPrecisionTarget.disabled).toBe(true)
    expect(c.computedPrecisionTarget.value).toBe("")
  })

  it("re-enables precision and restores the default when leaving count", () => {
    const c = computedController()
    c.computedFunctionTarget.value = "count"
    c.computedManager.functionChanged()
    c.computedFunctionTarget.value = "sum"
    c.computedManager.functionChanged()
    expect(c.computedPrecisionTarget.disabled).toBe(false)
    expect(c.computedPrecisionTarget.value).toBe("2")
  })

  it("keeps a still-valid previously selected attribute", () => {
    const c = computedController()
    c.computedManager.populateRelations()
    c.computedRelationTarget.value = "0"
    c.computedManager.relationChanged()
    c.computedAttributeTarget.value = "score"
    c.computedManager.relationChanged()
    expect(c.computedAttributeTarget.value).toBe("score")
  })

  it("uses the slug as the option label when label is missing", () => {
    const c = computedController({
      values: {
        computedOptionsValue: [{
          bridge_entity_id: 1, bridge_role: "source", related_entity_label: "X", bridge_label: "b",
          attributes: [{ slug: "raw", numeric: true }],
        }],
      },
    })
    c.computedManager.populateRelations()
    c.computedRelationTarget.value = "0"
    c.computedManager.relationChanged()
    expect(c.computedAttributeTarget.options[1].textContent).toBe("raw")
  })

  it("treats a missing attributes array as empty", () => {
    const c = computedController({
      values: {
        computedOptionsValue: [{ bridge_entity_id: 1, bridge_role: "source", related_entity_label: "X", bridge_label: "b" }],
      },
    })
    c.computedManager.populateRelations()
    c.computedRelationTarget.value = "0"
    c.computedManager.relationChanged()
    expect(c.computedAttributeTarget.options.length).toBe(1)
  })

  it("functionChanged no-ops precision updates without the precision target", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="computedFunction"><option value="count" selected>count</option></select>` +
      `<select data-entity-form-target="computedAttribute"></select>`,
      { values: { computedOptionsValue: [] } }
    )
    expect(() => new ComputedManager(controller).functionChanged()).not.toThrow()
  })
})

describe("ComputedManager#getComputedConfig / validate", () => {
  function filled(c) {
    c.computedManager.populateRelations()
    c.computedRelationTarget.value = "0"
    c.computedFunctionTarget.value = "avg"
    c.computedManager.relationChanged()
    c.computedAttributeTarget.value = "score"
    c.computedPrecisionTarget.value = "3"
  }

  it("returns null when relation or function is missing", () => {
    const c = computedController()
    c.computedManager.populateRelations()
    expect(c.computedManager.getComputedConfig()).toBeNull()
    expect(c.computedManager.validate()).toBe("Please complete the computed field configuration")
    c.computedRelationTarget.value = "0"
    c.computedFunctionTarget.value = ""
    expect(c.computedManager.getComputedConfig()).toBeNull()
  })

  it("returns null when a non-count function has no source attribute", () => {
    const c = computedController()
    c.computedManager.populateRelations()
    c.computedRelationTarget.value = "0"
    c.computedFunctionTarget.value = "avg"
    expect(c.computedManager.getComputedConfig()).toBeNull()
  })

  it("allows a blank source slug for count", () => {
    const c = computedController()
    filled(c)
    c.computedFunctionTarget.value = "count"
    c.computedAttributeTarget.value = ""
    expect(c.computedManager.getComputedConfig()).toMatchObject({
      bridge_entity_id: 15,
      bridge_role: "source",
      source_slug: "",
      function: "count",
    })
    expect(c.computedManager.validate()).toBeNull()
  })

  it("returns the complete config and clamps precision", () => {
    const c = computedController()
    filled(c)
    expect(c.computedManager.getComputedConfig()).toEqual({
      bridge_entity_id: 15,
      bridge_role: "source",
      source_slug: "score",
      function: "avg",
      precision: 3,
    })
    expect(c.computedManager.validate()).toBeNull()

    c.computedPrecisionTarget.value = "99"
    expect(c.computedManager.getComputedConfig().precision).toBe(6)
    c.computedPrecisionTarget.value = "-4"
    expect(c.computedManager.getComputedConfig().precision).toBe(0)
    c.computedPrecisionTarget.value = "nope"
    expect(c.computedManager.getComputedConfig().precision).toBe(2)
  })

  it("defaults precision when the input is missing and when the function is count", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="computedRelation"><option value="0" selected>R</option></select>` +
      `<select data-entity-form-target="computedFunction"><option value="count" selected>count</option></select>` +
      `<select data-entity-form-target="computedAttribute"><option value=""></option></select>`,
      { values: { computedOptionsValue: SAMPLE_OPTIONS } }
    )
    const mgr = new ComputedManager(controller)
    expect(mgr.getComputedConfig().precision).toBe(2)
  })

  it("defaults precision when the precision target is missing for a non-count function", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="computedRelation"><option value="0" selected>R</option></select>` +
      `<select data-entity-form-target="computedFunction"><option value="avg" selected>avg</option></select>` +
      `<select data-entity-form-target="computedAttribute"><option value="score" selected>score</option></select>`,
      { values: { computedOptionsValue: SAMPLE_OPTIONS } }
    )
    expect(new ComputedManager(controller).getComputedConfig().precision).toBe(2)
  })

  it("treats a missing function select as an empty function", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="computedRelation"><option value="0" selected>R</option></select>` +
      `<select data-entity-form-target="computedAttribute"></select>`,
      { values: { computedOptionsValue: SAMPLE_OPTIONS } }
    )
    const mgr = new ComputedManager(controller)
    expect(mgr.getComputedConfig()).toBeNull()
    expect(() => mgr.populateAttributes()).not.toThrow()
  })

  it("returns null without a relation select or when the index is out of range", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="computedFunction"><option value="avg" selected>avg</option></select>`,
      { values: { computedOptionsValue: SAMPLE_OPTIONS } }
    )
    expect(new ComputedManager(controller).getComputedConfig()).toBeNull()

    const c = computedController()
    c.computedManager.populateRelations()
    c.computedRelationTarget.innerHTML = `<option value="99">gone</option>`
    c.computedRelationTarget.value = "99"
    c.computedFunctionTarget.value = "avg"
    expect(c.computedManager.getComputedConfig()).toBeNull()
  })

  it("treats a missing attribute select as a blank slug", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="computedRelation"><option value="0" selected>R</option></select>` +
      `<select data-entity-form-target="computedFunction"><option value="avg" selected>avg</option></select>`,
      { values: { computedOptionsValue: SAMPLE_OPTIONS } }
    )
    expect(new ComputedManager(controller).getComputedConfig()).toBeNull()
  })
})

describe("ComputedManager#applyComputedConfig / reset", () => {
  it("no-ops for a missing or non-object config", () => {
    const c = computedController()
    expect(() => c.computedManager.applyComputedConfig(null)).not.toThrow()
    expect(() => c.computedManager.applyComputedConfig("x")).not.toThrow()
  })

  it("selects the matching relation, function, attribute, and precision", () => {
    const c = computedController()
    c.computedManager.applyComputedConfig({
      bridge_entity_id: 22,
      bridge_role: "target",
      source_slug: "credits",
      function: "sum",
      precision: 4,
    })
    expect(c.computedRelationTarget.value).toBe("1")
    expect(c.computedFunctionTarget.value).toBe("sum")
    expect(c.computedAttributeTarget.value).toBe("credits")
    expect(c.computedPrecisionTarget.value).toBe("4")
  })

  it("matches bridge_entity_id as a string and skips unknown relations", () => {
    const c = computedController()
    c.computedManager.applyComputedConfig({
      bridge_entity_id: "15",
      bridge_role: "source",
      source_slug: "score",
      function: "avg",
    })
    expect(c.computedRelationTarget.value).toBe("0")
    expect(c.computedAttributeTarget.value).toBe("score")

    c.computedManager.applyComputedConfig({
      bridge_entity_id: 999,
      bridge_role: "source",
      function: "min",
    })
    expect(c.computedFunctionTarget.value).toBe("min")
  })

  it("does not write precision when the function is count", () => {
    const c = computedController()
    c.computedManager.applyComputedConfig({
      bridge_entity_id: 15,
      bridge_role: "source",
      function: "count",
      precision: 5,
    })
    expect(c.computedPrecisionTarget.disabled).toBe(true)
    expect(c.computedPrecisionTarget.value).toBe("")
  })

  it("skips writing fields when the matching targets are absent", () => {
    const { controller } = buildController("", { values: { computedOptionsValue: SAMPLE_OPTIONS } })
    expect(() => new ComputedManager(controller).applyComputedConfig({
      bridge_entity_id: 15, bridge_role: "source", source_slug: "score", function: "avg", precision: 1,
    })).not.toThrow()
  })

  it("reset clears selects, restores precision, and returns to data mode", () => {
    const c = computedController()
    c.computedManager.selectComputedMode()
    c.computedRelationTarget.value = "0"
    c.computedFunctionTarget.value = "count"
    c.computedManager.functionChanged()
    c.computedManager.reset()
    expect(c.attributeMode).toBe("input")
    expect(c.computedRelationTarget.innerHTML).toBe("")
    expect(c.computedAttributeTarget.innerHTML).toBe("")
    expect(c.computedFunctionTarget.selectedIndex).toBe(0)
    expect(c.computedPrecisionTarget.value).toBe("2")
    expect(c.computedPrecisionTarget.disabled).toBe(false)
  })

  it("reset no-ops missing targets", () => {
    const { controller } = buildController("", { values: { attributeMode: "computed", computedOptionsValue: [] } })
    controller.typeManager = { htmlTypeChanged: vi.fn() }
    expect(() => new ComputedManager(controller).reset()).not.toThrow()
    expect(controller.attributeMode).toBe("input")
  })
})

describe("ComputedManager filter", () => {
  function filled(c) {
    c.computedManager.populateRelations()
    c.computedRelationTarget.value = "0"
    c.computedFunctionTarget.value = "avg"
    c.computedManager.relationChanged()
    c.computedAttributeTarget.value = "score"
    c.computedPrecisionTarget.value = "2"
  }

  function setFilter(c, { slug = "status", op = "=", value = "completed" } = {}) {
    c.computedFilterAttributeTarget.value = slug
    c.computedManager.filterChanged()
    c.computedFilterOpTarget.value = op
    c.computedFilterValueTarget.value = value
  }

  it("populateFilterAttributes no-ops without the filter attribute select", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="computedRelation"><option value="0">R</option></select>`,
      { values: { computedOptionsValue: SAMPLE_OPTIONS } }
    )
    expect(() => new ComputedManager(controller).populateFilterAttributes()).not.toThrow()
  })

  it("lists every bridge attribute plus the no-filter placeholder", () => {
    const c = computedController()
    c.computedManager.populateRelations()
    c.computedRelationTarget.value = "0"
    c.computedManager.relationChanged()
    expect([...c.computedFilterAttributeTarget.options].map((o) => o.value)).toEqual(["", "score", "status"])
    expect(c.computedFilterAttributeTarget.options[0].textContent).toBe("No filter")
    expect(c.computedFilterOpTarget.disabled).toBe(true)
    expect(c.computedFilterValueTarget.disabled).toBe(true)
  })

  it("leaves only the no-filter placeholder when no relation is selected", () => {
    const c = computedController()
    c.computedManager.populateRelations()
    expect(c.computedFilterAttributeTarget.options.length).toBe(1)
    expect(c.computedFilterAttributeTarget.options[0].textContent).toBe("No filter")
  })

  it("preserves a still-valid filter attribute across relation refills", () => {
    const c = computedController()
    filled(c)
    c.computedFilterAttributeTarget.value = "status"
    c.computedManager.relationChanged()
    expect(c.computedFilterAttributeTarget.value).toBe("status")
    expect(c.computedFilterOpTarget.disabled).toBe(false)
  })

  it("drops a filter attribute that is no longer on the selected relation", () => {
    const c = computedController()
    filled(c)
    setFilter(c)
    c.computedRelationTarget.value = "1"
    c.computedManager.relationChanged()
    expect(c.computedFilterAttributeTarget.value).toBe("")
    expect([...c.computedFilterAttributeTarget.options].map((o) => o.value)).toEqual(["", "credits"])
    expect(c.computedFilterOpTarget.disabled).toBe(true)
    expect(c.computedFilterValueTarget.value).toBe("")
  })

  it("uses the slug as the filter option label when label is missing", () => {
    const c = computedController({
      values: {
        computedOptionsValue: [{
          bridge_entity_id: 1, bridge_role: "source", related_entity_label: "X", bridge_label: "b",
          attributes: [{ slug: "raw", numeric: false }],
        }],
      },
    })
    c.computedManager.populateRelations()
    c.computedRelationTarget.value = "0"
    c.computedManager.relationChanged()
    expect(c.computedFilterAttributeTarget.options[1].textContent).toBe("raw")
  })

  it("treats a missing attributes array as empty for the filter list", () => {
    const c = computedController({
      values: {
        computedOptionsValue: [{ bridge_entity_id: 1, bridge_role: "source", related_entity_label: "X", bridge_label: "b" }],
      },
    })
    c.computedManager.populateRelations()
    c.computedRelationTarget.value = "0"
    c.computedManager.relationChanged()
    expect(c.computedFilterAttributeTarget.options.length).toBe(1)
  })

  it("omits the filter key when no filter attribute is selected", () => {
    const c = computedController()
    filled(c)
    expect(c.computedManager.getComputedConfig()).toEqual({
      bridge_entity_id: 15,
      bridge_role: "source",
      source_slug: "score",
      function: "avg",
      precision: 2,
    })
    expect(c.computedManager.getComputedConfig()).not.toHaveProperty("filter")
    expect(c.computedManager.validate()).toBeNull()
  })

  it("omits the filter key when a filter attribute is selected without an operator", () => {
    const c = computedController()
    filled(c)
    c.computedFilterAttributeTarget.value = "status"
    c.computedManager.filterChanged()
    expect(c.computedManager.getComputedConfig()).not.toHaveProperty("filter")
    expect(c.computedManager.validate()).toBe("Please complete the computed field configuration")
  })

  it("rejects a filter attribute with a blank or whitespace-only value", () => {
    const c = computedController()
    filled(c)
    setFilter(c, { value: "" })
    expect(c.computedManager.getComputedConfig().filter).toEqual({ slug: "status", op: "=", value: "" })
    expect(c.computedManager.validate()).toBe("Please complete the computed field configuration")

    c.computedFilterValueTarget.value = "   "
    expect(c.computedManager.validate()).toBe("Please complete the computed field configuration")
  })

  it("includes filter when slug and operator are set", () => {
    const c = computedController()
    filled(c)
    setFilter(c)
    expect(c.computedManager.getComputedConfig()).toEqual({
      bridge_entity_id: 15,
      bridge_role: "source",
      source_slug: "score",
      function: "avg",
      precision: 2,
      filter: { slug: "status", op: "=", value: "completed" },
    })
    expect(c.computedManager.validate()).toBeNull()
  })

  it("restores filter controls from a saved config and clears them when absent", () => {
    const c = computedController()
    c.computedManager.applyComputedConfig({
      bridge_entity_id: 15,
      bridge_role: "source",
      source_slug: "score",
      function: "avg",
      precision: 2,
      filter: { slug: "status", op: "!=", value: "completed" },
    })
    expect(c.computedFilterAttributeTarget.value).toBe("status")
    expect(c.computedFilterOpTarget.value).toBe("!=")
    expect(c.computedFilterValueTarget.value).toBe("completed")
    expect(c.computedFilterOpTarget.disabled).toBe(false)
    expect(c.computedFilterValueTarget.disabled).toBe(false)

    c.computedManager.applyComputedConfig({
      bridge_entity_id: 15,
      bridge_role: "source",
      source_slug: "score",
      function: "avg",
    })
    expect(c.computedFilterAttributeTarget.value).toBe("")
    expect(c.computedFilterOpTarget.disabled).toBe(true)
    expect(c.computedFilterValueTarget.value).toBe("")
  })

  it("clears filter controls when the saved filter has no slug", () => {
    const c = computedController()
    filled(c)
    setFilter(c)
    c.computedManager.applyComputedConfig({
      bridge_entity_id: 15,
      bridge_role: "source",
      source_slug: "score",
      function: "avg",
      filter: {},
    })
    expect(c.computedFilterAttributeTarget.value).toBe("")
    expect(c.computedFilterOpTarget.disabled).toBe(true)
  })

  it("restores a filter slug without an operator or value", () => {
    const c = computedController()
    c.computedManager.applyComputedConfig({
      bridge_entity_id: 15,
      bridge_role: "source",
      source_slug: "score",
      function: "avg",
      filter: { slug: "status" },
    })
    expect(c.computedFilterAttributeTarget.value).toBe("status")
    expect(c.computedFilterOpTarget.value).toBe("")
    expect(c.computedFilterValueTarget.value).toBe("")
    expect(c.computedManager.validate()).toBe("Please complete the computed field configuration")
  })

  it("clears filter controls when the saved filter is not an object", () => {
    const c = computedController()
    filled(c)
    setFilter(c)
    c.computedManager.applyComputedConfig({
      bridge_entity_id: 15,
      bridge_role: "source",
      source_slug: "score",
      function: "avg",
      filter: "status",
    })
    expect(c.computedFilterAttributeTarget.value).toBe("")
    expect(c.computedFilterOpTarget.disabled).toBe(true)
  })

  it("clears filter controls when the saved slug is not on the relation", () => {
    const c = computedController()
    c.computedManager.applyComputedConfig({
      bridge_entity_id: 15,
      bridge_role: "source",
      source_slug: "score",
      function: "avg",
      filter: { slug: "missing", op: "=", value: "x" },
    })
    expect(c.computedFilterAttributeTarget.value).toBe("")
    expect(c.computedFilterOpTarget.disabled).toBe(true)
    expect(c.computedFilterValueTarget.value).toBe("")
  })

  it("skips writing op or value when those targets or fields are absent", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="computedRelation"></select>` +
      `<select data-entity-form-target="computedFunction"><option value="avg" selected>avg</option></select>` +
      `<select data-entity-form-target="computedAttribute"></select>` +
      `<select data-entity-form-target="computedFilterAttribute"></select>`,
      { values: { computedOptionsValue: SAMPLE_OPTIONS } }
    )
    const mgr = new ComputedManager(controller)
    expect(() => mgr.applyComputedConfig({
      bridge_entity_id: 15,
      bridge_role: "source",
      source_slug: "score",
      function: "avg",
      filter: { slug: "status", op: "=", value: "completed" },
    })).not.toThrow()
    expect(controller.computedFilterAttributeTarget.value).toBe("status")
  })

  it("applyComputedConfig no-ops the filter when the filter attribute target is missing", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="computedRelation"></select>` +
      `<select data-entity-form-target="computedFunction"><option value="avg">avg</option></select>` +
      `<select data-entity-form-target="computedAttribute"></select>`,
      { values: { computedOptionsValue: SAMPLE_OPTIONS } }
    )
    expect(() => new ComputedManager(controller).applyComputedConfig({
      bridge_entity_id: 15,
      bridge_role: "source",
      source_slug: "score",
      function: "avg",
      filter: { slug: "status", op: "=", value: "completed" },
    })).not.toThrow()
  })

  it("writes a numeric filter value as a string and skips a null value", () => {
    const c = computedController()
    c.computedManager.applyComputedConfig({
      bridge_entity_id: 15,
      bridge_role: "source",
      source_slug: "score",
      function: "avg",
      filter: { slug: "score", op: ">=", value: 0 },
    })
    expect(c.computedFilterValueTarget.value).toBe("0")

    c.computedManager.applyComputedConfig({
      bridge_entity_id: 15,
      bridge_role: "source",
      source_slug: "score",
      function: "avg",
      filter: { slug: "score", op: ">=" },
    })
    expect(c.computedFilterValueTarget.value).toBe("")
    expect(c.computedFilterOpTarget.value).toBe(">=")
  })

  it("reset clears the filter back to no filter and disables operator/value", () => {
    const c = computedController()
    filled(c)
    setFilter(c)
    c.computedManager.reset()
    expect(c.computedFilterAttributeTarget.innerHTML).toBe("")
    expect(c.computedFilterOpTarget.selectedIndex).toBe(0)
    expect(c.computedFilterOpTarget.disabled).toBe(true)
    expect(c.computedFilterValueTarget.value).toBe("")
    expect(c.computedFilterValueTarget.disabled).toBe(true)
  })

  it("treats a missing filter value input as a blank value", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="computedRelation"><option value="0" selected>R</option></select>` +
      `<select data-entity-form-target="computedFunction"><option value="avg" selected>avg</option></select>` +
      `<select data-entity-form-target="computedAttribute"><option value="score" selected>score</option></select>` +
      `<select data-entity-form-target="computedFilterAttribute"><option value="status" selected>Status</option></select>` +
      `<select data-entity-form-target="computedFilterOp"><option value="=" selected>=</option></select>`,
      { values: { computedOptionsValue: SAMPLE_OPTIONS } }
    )
    const mgr = new ComputedManager(controller)
    expect(mgr.getComputedConfig().filter).toEqual({ slug: "status", op: "=", value: "" })
    expect(mgr.validate()).toBe("Please complete the computed field configuration")
  })

  it("syncs filter controls when the operator or value target is missing", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="computedRelation"><option value="0" selected>R</option></select>` +
      `<select data-entity-form-target="computedFilterAttribute"><option value="status" selected>Status</option></select>`,
      { values: { computedOptionsValue: SAMPLE_OPTIONS } }
    )
    expect(() => new ComputedManager(controller).filterChanged()).not.toThrow()
  })
})
