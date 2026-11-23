import { describe, it, expect, vi } from "vitest"
import { TypeManager, SELECTION_TYPES, CONFIG_TYPE_MAP } from "controllers/entity_form/type_manager"
import { ValidatorManager } from "controllers/entity_form/validator_manager"
import { buildController } from "./support.js"

const optionRow = (label, value, isDefault = false) =>
  `<div data-option-item>` +
  `<input data-option-label value="${label}">` +
  `<input data-option-value value="${value}">` +
  `<input type="checkbox" data-option-default${isDefault ? " checked" : ""}>` +
  `</div>`

describe("type_manager — constant exports", () => {
  it("exposes selection types and the config-type map", () => {
    expect(SELECTION_TYPES).toEqual(["select", "radio", "checkbox"])
    expect(CONFIG_TYPE_MAP).toMatchObject({
      select: "selection", radio: "selection", checkbox: "selection",
      file: "file", image: "file",
    })
    expect(CONFIG_TYPE_MAP.text).toBeUndefined()
  })
})

describe("TypeManager#formatHtmlTypeName", () => {
  const tm = () => new TypeManager({})
  it.each([
    ["text", "Text Input"],
    ["select", "Dropdown"],
    ["datetime-local", "DateTime"],
    ["tel", "Phone"],
    ["image", "Image"],
  ])("maps %s -> %s", (input, expected) => {
    expect(tm().formatHtmlTypeName(input)).toBe(expected)
  })

  it("returns N/A for empty/nullish and echoes unknown types", () => {
    expect(tm().formatHtmlTypeName("")).toBe("N/A")
    expect(tm().formatHtmlTypeName(null)).toBe("N/A")
    expect(tm().formatHtmlTypeName("weird")).toBe("weird")
  })
})

describe("TypeManager#getSelectedOptions", () => {
  it("returns [] without an options container", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="modalHtmlType"><option value="select" selected>select</option></select>`
    )
    expect(new TypeManager(controller).getSelectedOptions()).toEqual([])
  })

  it("treats a missing modalHtmlType target as an empty type ([] result)", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="optionsContainer">${optionRow("A", "a")}</div>`
    )
    expect(new TypeManager(controller).getSelectedOptions()).toEqual([])
  })

  it("returns [] when the html type is not a selection type", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="modalHtmlType"><option value="text" selected>text</option></select>` +
      `<div data-entity-form-target="optionsContainer">${optionRow("A", "a")}</div>`
    )
    expect(new TypeManager(controller).getSelectedOptions()).toEqual([])
  })

  it("collects trimmed label/value/default and drops fully-empty rows", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="modalHtmlType"><option value="select" selected>select</option></select>` +
      `<div data-entity-form-target="optionsContainer">` +
      optionRow(" One ", " uno ", true) + optionRow("Two", "dos") + optionRow("", "") +
      `</div>`
    )
    expect(new TypeManager(controller).getSelectedOptions()).toEqual([
      { label: "One", value: "uno", default: true },
      { label: "Two", value: "dos", default: false },
    ])
  })
})

describe("TypeManager#getFileConfig", () => {
  it("returns null when neither accept nor multiple is set", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="configAccept" value="">` +
      `<input type="checkbox" data-entity-form-target="configMultiple">`
    )
    expect(new TypeManager(controller).getFileConfig()).toBeNull()
  })

  it("returns accept/multiple when present", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="configAccept" value=" image/* ">` +
      `<input type="checkbox" data-entity-form-target="configMultiple" checked>`
    )
    expect(new TypeManager(controller).getFileConfig()).toEqual({ accept: "image/*", multiple: true })
  })

  it("treats a missing accept/multiple target as absent (empty string / false)", () => {
    const { controller } = buildController("")
    expect(new TypeManager(controller).getFileConfig()).toBeNull()
  })

  it("normalizes a blank accept to null when multiple is set", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="configAccept" value="">` +
      `<input type="checkbox" data-entity-form-target="configMultiple" checked>`
    )
    expect(new TypeManager(controller).getFileConfig()).toEqual({ accept: null, multiple: true })
  })
})

describe("TypeManager#getConfigForType", () => {
  it("manual selection -> { source: 'manual', options }", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="modalHtmlType"><option value="select" selected>select</option></select>` +
      `<div data-entity-form-target="optionsContainer">${optionRow("A", "a")}</div>`,
      { values: { optionsSourceMode: "manual" } }
    )
    controller.validatorManager = new ValidatorManager(controller)
    controller.typeManager = new TypeManager(controller)
    expect(controller.typeManager.getConfigForType("select")).toEqual({
      source: "manual",
      options: [{ label: "A", value: "a", default: false }],
    })
  })

  it("manual selection with no options -> null", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="modalHtmlType"><option value="select" selected>select</option></select>` +
      `<div data-entity-form-target="optionsContainer"></div>`,
      { values: { optionsSourceMode: "manual" } }
    )
    controller.validatorManager = new ValidatorManager(controller)
    controller.typeManager = new TypeManager(controller)
    expect(controller.typeManager.getConfigForType("select")).toBeNull()
  })

  it("constant selection resolves the chosen constant by id", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="constantSelect"><option value="">--</option><option value="3" selected>C</option></select>`,
      {
        values: {
          optionsSourceMode: "constant",
          constants: [{ id: 3, name: "Colors", options: ["red", "blue"] }],
        },
      }
    )
    expect(new TypeManager(controller).getConfigForType("select")).toEqual({
      source: "constant",
      constant_id: 3,
      constant_name: "Colors",
      options: ["red", "blue"],
    })
  })

  it("constant selection with no selected id -> null", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="constantSelect"><option value="" selected>--</option></select>`,
      { values: { optionsSourceMode: "constant", constants: [] } }
    )
    expect(new TypeManager(controller).getConfigForType("select")).toBeNull()
  })

  it("constant selection without a constantSelect target -> null (empty id)", () => {
    const { controller } = buildController("", { values: { optionsSourceMode: "constant", constants: [] } })
    expect(new TypeManager(controller).getConfigForType("select")).toBeNull()
  })

  it("constant selection with an id that matches no known constant -> null", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="constantSelect"><option value="9" selected>C</option></select>`,
      { values: { optionsSourceMode: "constant", constants: [{ id: 3, name: "Colors", options: [] }] } }
    )
    expect(new TypeManager(controller).getConfigForType("select")).toBeNull()
  })

  it("constant selection defaults options to [] when the constant has none", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="constantSelect"><option value="3" selected>C</option></select>`,
      { values: { optionsSourceMode: "constant", constants: [{ id: 3, name: "Colors" }] } }
    )
    expect(new TypeManager(controller).getConfigForType("select")).toEqual({
      source: "constant", constant_id: 3, constant_name: "Colors", options: [],
    })
  })

  it("file type delegates to getFileConfig", () => {
    const { controller } = buildController(
      `<input data-entity-form-target="configAccept" value=".pdf">` +
      `<input type="checkbox" data-entity-form-target="configMultiple">`
    )
    expect(new TypeManager(controller).getConfigForType("file")).toEqual({ accept: ".pdf", multiple: false })
  })

  it("non-config type -> null", () => {
    expect(new TypeManager({}).getConfigForType("text")).toBeNull()
  })

  it("entity_entries selection returns referenceManager.getConfig()", () => {
    const { controller } = buildController("", { values: { optionsSourceMode: "entity_entries" } })
    controller.referenceManager = {
      getConfig: vi.fn(() => ({ options_source: "entity_entries", entity_id: "7", label_field: "title" })),
    }
    expect(new TypeManager(controller).getConfigForType("select")).toEqual({
      options_source: "entity_entries", entity_id: "7", label_field: "title",
    })
  })

  it("entity_entries selection returns null when getConfig is incomplete", () => {
    const { controller } = buildController("", { values: { optionsSourceMode: "entity_entries" } })
    controller.referenceManager = { getConfig: vi.fn(() => null) }
    expect(new TypeManager(controller).getConfigForType("select")).toBeNull()
  })
})

describe("TypeManager — config section visibility", () => {
  it("showConfigSection reveals the options section + the matching container and hides others", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="optionsSection" class="hidden"></div>` +
      `<div data-entity-form-target="selectionConfig" class="hidden"></div>` +
      `<div data-entity-form-target="fileConfig"></div>` +
      `<div data-entity-form-target="optionsContainer"><div data-option-item></div></div>` +
      `<select data-entity-form-target="modalHtmlType"></select>`
    )
    const tm = new TypeManager(controller)
    tm.showConfigSection("selection")
    expect(controller.optionsSectionTarget.classList.contains("hidden")).toBe(false)
    expect(controller.selectionConfigTarget.classList.contains("hidden")).toBe(false)
    expect(controller.fileConfigTarget.classList.contains("hidden")).toBe(true)
  })

  it("showConfigSection('selection') seeds one option row when the container is empty", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="optionsSection"></div>` +
      `<div data-entity-form-target="selectionConfig"></div>` +
      `<div data-entity-form-target="optionsContainer"></div>`
    )
    let added = 0
    controller.addOption = () => { added++ }
    new TypeManager(controller).showConfigSection("selection")
    expect(added).toBe(1)
  })

  it("hideConfigSection hides the options section", () => {
    const { controller } = buildController(
      `<div data-entity-form-target="optionsSection"></div>` +
      `<div data-entity-form-target="selectionConfig"></div>`
    )
    const tm = new TypeManager(controller)
    tm.hideConfigSection()
    expect(controller.optionsSectionTarget.classList.contains("hidden")).toBe(true)
  })

  it("htmlTypeChanged does nothing without the modalHtmlType or optionsSection targets", () => {
    const { controller } = buildController("")
    controller.validatorManager = { filterValidatorsByHtmlType: () => { throw new Error("should not be called") } }
    expect(() => new TypeManager(controller).htmlTypeChanged()).not.toThrow()
  })

  it("htmlTypeChanged hides the config section for a non-config html type", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="modalHtmlType"><option value="text" selected>text</option></select>` +
      `<div data-entity-form-target="optionsSection"></div>` +
      `<div data-entity-form-target="selectionConfig"></div>`
    )
    const calls = []
    controller.validatorManager = {
      filterValidatorsByHtmlType: (t) => calls.push(["filter", t]),
      syncInclusionValidator: () => calls.push(["sync"]),
    }
    new TypeManager(controller).htmlTypeChanged()
    expect(controller.optionsSectionTarget.classList.contains("hidden")).toBe(true)
    expect(calls).toEqual([["filter", "text"], ["sync"]])
  })

  it("htmlTypeChanged shows/hides config + drives the validator manager", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="modalHtmlType"><option value="select" selected>select</option></select>` +
      `<div data-entity-form-target="optionsSection" class="hidden"></div>` +
      `<div data-entity-form-target="selectionConfig" class="hidden"></div>` +
      `<div data-entity-form-target="optionsContainer"><div data-option-item></div></div>`,
      { values: { inclusionManuallyRemoved: true } }
    )
    const calls = []
    controller.validatorManager = {
      filterValidatorsByHtmlType: (t) => calls.push(["filter", t]),
      syncInclusionValidator: () => calls.push(["sync"]),
    }
    new TypeManager(controller).htmlTypeChanged()
    expect(controller.optionsSectionTarget.classList.contains("hidden")).toBe(false)
    expect(controller.inclusionManuallyRemoved).toBe(false)
    expect(calls).toEqual([["filter", "select"], ["sync"]])
  })

  it("htmlTypeChanged syncs reference availability when a referenceManager is attached", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="modalHtmlType"><option value="radio" selected>radio</option></select>` +
      `<div data-entity-form-target="optionsSection" class="hidden"></div>` +
      `<div data-entity-form-target="selectionConfig" class="hidden"></div>` +
      `<div data-entity-form-target="optionsContainer"><div data-option-item></div></div>`
    )
    controller.validatorManager = { filterValidatorsByHtmlType: vi.fn(), syncInclusionValidator: vi.fn() }
    controller.referenceManager = { syncAvailability: vi.fn() }
    new TypeManager(controller).htmlTypeChanged()
    expect(controller.referenceManager.syncAvailability).toHaveBeenCalledWith("radio")
  })
})
