import { describe, it, expect, vi, beforeEach } from "vitest"
import { ConstantsManager } from "controllers/entity_form/constants_manager"
import { buildController, fakeEvent } from "./support.js"

beforeEach(() => { vi.restoreAllMocks() })

// A controller wired for a customer with an empty constant <select> ready to fill.
const selectController = () =>
  buildController(
    `<select data-entity-form-target="constantSelect"><option value="">--</option></select>`,
    { values: { hasCustomerIdValue: true, customerIdValue: "9", constants: [] } }
  ).controller

// A controller carrying just the constant-preview targets.
const previewController = () =>
  buildController(
    `<div data-entity-form-target="constantPreview" class="hidden"></div>` +
    `<span data-entity-form-target="constantOptionsCount"></span>` +
    `<div data-entity-form-target="constantPreviewList"></div>`
  ).controller

describe("ConstantsManager#loadConstants", () => {
  it("does nothing without a customer id value", async () => {
    const { controller } = buildController("", { values: { hasCustomerIdValue: false } })
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true, json: async () => [] })
    await new ConstantsManager(controller).loadConstants()
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it("fetches, stores constants, and populates the select", async () => {
    const controller = selectController()
    vi.spyOn(globalThis, "fetch").mockResolvedValue({
      ok: true,
      json: async () => [{ id: 1, name: "Colors", options: ["r", "g"] }],
    })
    await new ConstantsManager(controller).loadConstants()
    expect(controller.constants).toEqual([{ id: 1, name: "Colors", options: ["r", "g"] }])
    const opts = controller.constantSelectTarget.querySelectorAll("option")
    expect(opts.length).toBe(2)
    expect(opts[1].textContent).toBe("Colors (2 options)")
    expect(JSON.parse(opts[1].dataset.constantData).id).toBe(1)
  })

  it("silently ignores a non-ok response", async () => {
    const controller = selectController()
    vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: false })
    await expect(new ConstantsManager(controller).loadConstants()).resolves.toBeUndefined()
    expect(controller.constantSelectTarget.querySelectorAll("option").length).toBe(1)
  })

  it("swallows fetch rejections", async () => {
    const { controller } = buildController("", { values: { hasCustomerIdValue: true, customerIdValue: "9" } })
    vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("network"))
    await expect(new ConstantsManager(controller).loadConstants()).resolves.toBeUndefined()
  })
})

describe("ConstantsManager#populateConstantSelect", () => {
  it("rebuilds options beyond the placeholder each call (idempotent)", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="constantSelect"><option value="">--</option><option value="stale">stale</option></select>`,
      { values: { constants: [{ id: 5, name: "Sizes", options: [] }] } }
    )
    new ConstantsManager(controller).populateConstantSelect()
    const opts = controller.constantSelectTarget.querySelectorAll("option")
    expect([...opts].map((o) => o.textContent)).toEqual(["--", "Sizes (0 options)"])
  })

  it("does nothing without a constant select target", () => {
    const { controller } = buildController("", { values: { constants: [{ id: 1, name: "X" }] } })
    expect(() => new ConstantsManager(controller).populateConstantSelect()).not.toThrow()
  })
})

describe("ConstantsManager#updateOptionsSourceUI", () => {
  function ui(mode) {
    const { controller } = buildController(
      `<button data-entity-form-target="manualOptionsBtn"></button>` +
      `<button data-entity-form-target="constantOptionsBtn"></button>` +
      `<button data-entity-form-target="entityRecordsOptionsBtn"></button>` +
      `<div data-entity-form-target="manualOptionsSection"></div>` +
      `<div data-entity-form-target="constantOptionsSection"></div>` +
      `<div data-entity-form-target="entityRecordsOptionsSection"></div>`,
      { values: { optionsSourceMode: mode } }
    )
    new ConstantsManager(controller).updateOptionsSourceUI()
    return controller
  }

  it("manual mode: manual active + section visible, constant section hidden", () => {
    const c = ui("manual")
    expect(c.manualOptionsBtnTarget.classList.contains("bg-accent-subtle")).toBe(true)
    expect(c.manualOptionsSectionTarget.classList.contains("hidden")).toBe(false)
    expect(c.constantOptionsSectionTarget.classList.contains("hidden")).toBe(true)
  })

  it("constant mode: constant active + section visible, manual section hidden", () => {
    const c = ui("constant")
    expect(c.constantOptionsBtnTarget.classList.contains("bg-accent-subtle")).toBe(true)
    expect(c.constantOptionsSectionTarget.classList.contains("hidden")).toBe(false)
    expect(c.manualOptionsSectionTarget.classList.contains("hidden")).toBe(true)
  })

  it("entity_entries mode: records active + section visible, the other sections hidden", () => {
    const c = ui("entity_entries")
    expect(c.entityRecordsOptionsBtnTarget.classList.contains("bg-accent-subtle")).toBe(true)
    expect(c.manualOptionsBtnTarget.classList.contains("bg-accent-subtle")).toBe(false)
    expect(c.entityRecordsOptionsSectionTarget.classList.contains("hidden")).toBe(false)
    expect(c.manualOptionsSectionTarget.classList.contains("hidden")).toBe(true)
    expect(c.constantOptionsSectionTarget.classList.contains("hidden")).toBe(true)
  })

  it("works without the entity-records targets", () => {
    const { controller } = buildController(
      `<button data-entity-form-target="manualOptionsBtn"></button>` +
      `<button data-entity-form-target="constantOptionsBtn"></button>`,
      { values: { optionsSourceMode: "constant" } }
    )
    new ConstantsManager(controller).updateOptionsSourceUI()
    expect(controller.constantOptionsBtnTarget.classList.contains("bg-accent-subtle")).toBe(true)
  })
})

describe("ConstantsManager selection actions", () => {
  it("selectManualOptions/selectConstantOptions flip the mode + sync inclusion", () => {
    const { controller } = buildController(
      `<button data-entity-form-target="manualOptionsBtn"></button>` +
      `<button data-entity-form-target="constantOptionsBtn"></button>` +
      `<div data-entity-form-target="manualOptionsSection"></div>` +
      `<div data-entity-form-target="constantOptionsSection"></div>`
    )
    const sync = vi.fn()
    controller.validatorManager = { syncInclusionValidator: sync }
    const mgr = new ConstantsManager(controller)

    mgr.selectConstantOptions(fakeEvent())
    expect(controller.optionsSourceMode).toBe("constant")
    mgr.selectManualOptions(fakeEvent())
    expect(controller.optionsSourceMode).toBe("manual")
    expect(sync).toHaveBeenCalledTimes(2)
  })
})

describe("ConstantsManager#updateOptionsSourceUI missing targets", () => {
  it("does nothing without both toggle button targets", () => {
    const { controller } = buildController(`<button data-entity-form-target="manualOptionsBtn"></button>`)
    expect(() => new ConstantsManager(controller).updateOptionsSourceUI()).not.toThrow()
  })
})

describe("ConstantsManager#constantChanged + preview", () => {
  it("shows the preview + option count for the selected constant", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="constantSelect">` +
      `<option value="">--</option>` +
      `<option value="1" selected data-constant-data='{"name":"C","options":["a","b","c"]}'>C</option>` +
      `</select>` +
      `<div data-entity-form-target="constantPreview" class="hidden"></div>` +
      `<span data-entity-form-target="constantOptionsCount"></span>` +
      `<div data-entity-form-target="constantPreviewList"></div>`
    )
    controller.validatorManager = { syncInclusionValidator: vi.fn() }
    const select = controller.constantSelectTarget
    new ConstantsManager(controller).constantChanged({ target: select })
    expect(controller.constantPreviewTarget.classList.contains("hidden")).toBe(false)
    expect(controller.constantOptionsCountTarget.textContent).toBe("3 options")
    expect(controller.constantPreviewListTarget.textContent).toContain("a")
  })

  it("hides the preview when the selected option carries no constant data", () => {
    const { controller } = buildController(
      `<select data-entity-form-target="constantSelect"><option value="" selected>--</option></select>` +
      `<div data-entity-form-target="constantPreview"></div>`
    )
    const mgr = new ConstantsManager(controller)
    mgr.constantChanged({ target: controller.constantSelectTarget })
    expect(controller.constantPreviewTarget.classList.contains("hidden")).toBe(true)
  })

  it("singularizes '1 option'", () => {
    const controller = previewController()
    new ConstantsManager(controller).showConstantPreview({ options: ["only"] })
    expect(controller.constantOptionsCountTarget.textContent).toBe("1 option")
  })

  it("defaults to an empty options list when the constant has none", () => {
    const controller = previewController()
    new ConstantsManager(controller).showConstantPreview({})
    expect(controller.constantOptionsCountTarget.textContent).toBe("0 options")
  })

  it("showConstantPreview does nothing without a constantPreview target", () => {
    const { controller } = buildController("")
    expect(() => new ConstantsManager(controller).showConstantPreview({ options: [] })).not.toThrow()
  })

  it("hideConstantPreview does nothing without a constantPreview target", () => {
    const { controller } = buildController("")
    expect(() => new ConstantsManager(controller).hideConstantPreview()).not.toThrow()
  })
})
