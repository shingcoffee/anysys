import { describe, it, expect, vi, beforeEach } from "vitest"
import { ReferenceManager, ENTITY_ENTRIES } from "controllers/entity_form/reference_manager"
import { buildController, fakeEvent } from "./support.js"

beforeEach(() => { vi.restoreAllMocks() })

const TARGETS = [
  { id: 7, name: "Course", property_schema: [
    { name: "Title", name_slug: "title", labelable: true },
    { name: "Notes", name_slug: "notes", labelable: false }
  ] },
  { id: 9, name: "Room" }
]

const HTML =
  `<button data-entity-form-target="entityRecordsOptionsBtn"></button>` +
  `<select data-entity-form-target="referenceEntitySelect"><option value="">—</option></select>` +
  `<select data-entity-form-target="referenceLabelFieldSelect"><option value="">—</option></select>` +
  `<div data-entity-form-target="ownerSection" class="hidden"></div>` +
  `<input type="checkbox" data-entity-form-target="modalOwner">`

function setup(values = {}) {
  const { controller } = buildController(HTML, {
    values: {
      hasCustomerIdValue: true, customerIdValue: "5", optionsSourceMode: "manual",
      personEntityIdsValue: [7], ...values
    }
  })
  controller.constantsManager = { updateOptionsSourceUI: vi.fn() }
  controller.validatorManager = { syncInclusionValidator: vi.fn() }
  return { controller, manager: new ReferenceManager(controller) }
}

const okFetch = (body = TARGETS) =>
  vi.spyOn(globalThis, "fetch").mockResolvedValue({ ok: true, json: async () => body })

const optionValues = (select) => [...select.options].map(option => option.value)

describe("ReferenceManager#loadTargets", () => {
  it("fetches the tenant's entities once and fills the entity select", async () => {
    const fetchSpy = okFetch()
    const { controller, manager } = setup()

    expect(await manager.loadTargets()).toEqual(TARGETS)
    expect(await manager.loadTargets()).toEqual(TARGETS)
    expect(fetchSpy).toHaveBeenCalledTimes(1)
    expect(fetchSpy.mock.calls[0][0]).toBe("/5/admin/maintenance/entities.json")
    expect(optionValues(controller.referenceEntitySelectTarget)).toEqual(["", "7", "9"])
    expect(controller.referenceEntitySelectTarget.options[1].textContent).toBe("Course")
  })

  it("does not fetch without a customer id", async () => {
    const fetchSpy = okFetch()
    const { manager } = setup({ hasCustomerIdValue: false })

    expect(await manager.loadTargets()).toEqual([])
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it("keeps the placeholder and retries after a failed response or a network error", async () => {
    const { controller, manager } = setup()
    const fetchSpy = vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce({ ok: false })
      .mockRejectedValueOnce(new Error("offline"))

    expect(await manager.loadTargets()).toEqual([])
    expect(await manager.loadTargets()).toEqual([])
    expect(fetchSpy).toHaveBeenCalledTimes(2)
    expect(optionValues(controller.referenceEntitySelectTarget)).toEqual([""])
  })

  it("clears stale entity options before filling", async () => {
    okFetch()
    const { controller } = buildController(
      `<button data-entity-form-target="entityRecordsOptionsBtn"></button>` +
      `<select data-entity-form-target="referenceEntitySelect"><option value="">—</option><option value="stale">stale</option></select>` +
      `<select data-entity-form-target="referenceLabelFieldSelect"><option value="">—</option></select>`,
      { values: { hasCustomerIdValue: true, customerIdValue: "5", optionsSourceMode: "manual" } }
    )
    controller.constantsManager = { updateOptionsSourceUI: vi.fn() }
    controller.validatorManager = { syncInclusionValidator: vi.fn() }

    await new ReferenceManager(controller).loadTargets()
    expect(optionValues(controller.referenceEntitySelectTarget)).toEqual(["", "7", "9"])
  })

  it("tolerates a missing entity select", async () => {
    okFetch()
    const { controller } = buildController("", { values: { hasCustomerIdValue: true, customerIdValue: "5" } })

    expect(await new ReferenceManager(controller).loadTargets()).toEqual(TARGETS)
  })
})

describe("ReferenceManager display fields", () => {
  it("lists only labelable attributes of the chosen entity", async () => {
    okFetch()
    const { controller, manager } = setup()
    await manager.loadTargets()

    controller.referenceEntitySelectTarget.value = "7"
    manager.entityChanged()
    expect(optionValues(controller.referenceLabelFieldSelectTarget)).toEqual(["", "title"])

    controller.referenceEntitySelectTarget.value = "9"
    manager.entityChanged()
    expect(optionValues(controller.referenceLabelFieldSelectTarget)).toEqual([""])
  })

  it("clears the display fields when nothing is loaded", () => {
    const { controller, manager } = setup()
    manager.entityChanged()
    expect(optionValues(controller.referenceLabelFieldSelectTarget)).toEqual([""])
  })

  it("tolerates a missing display-field select", () => {
    const { controller } = buildController("")
    expect(() => new ReferenceManager(controller).populateLabelFieldSelect(null)).not.toThrow()
  })
})

describe("ReferenceManager config", () => {
  it("returns the stored config only when both selects are chosen", async () => {
    okFetch()
    const { controller, manager } = setup()
    await manager.loadTargets()
    expect(manager.getConfig()).toBeNull()

    controller.referenceEntitySelectTarget.value = "7"
    manager.entityChanged()
    expect(manager.getConfig()).toBeNull()

    controller.referenceLabelFieldSelectTarget.value = "title"
    expect(manager.getConfig()).toEqual({ options_source: ENTITY_ENTRIES, entity_id: "7", label_field: "title" })
  })

  it("reports the first missing choice with the translated alert", async () => {
    okFetch()
    const { controller, manager } = setup({
      selectTargetEntityMsgValue: "Pick an entity", selectDisplayFieldMsgValue: "Pick a field"
    })
    await manager.loadTargets()
    expect(manager.validate()).toEqual({ target: "referenceEntitySelect", message: "Pick an entity" })

    controller.referenceEntitySelectTarget.value = "7"
    manager.entityChanged()
    expect(manager.validate()).toEqual({ target: "referenceLabelFieldSelect", message: "Pick a field" })

    controller.referenceLabelFieldSelectTarget.value = "title"
    expect(manager.validate()).toBeNull()
  })

  it("applies a saved config, switching the mode on", async () => {
    okFetch()
    const { controller, manager } = setup()

    await manager.applyConfig({ options_source: ENTITY_ENTRIES, entity_id: 7, label_field: "title" })

    expect(controller.optionsSourceMode).toBe(ENTITY_ENTRIES)
    expect(controller.constantsManager.updateOptionsSourceUI).toHaveBeenCalled()
    expect(controller.referenceEntitySelectTarget.value).toBe("7")
    expect(controller.referenceLabelFieldSelectTarget.value).toBe("title")
  })

  it("applies a partial config without choosing anything", async () => {
    okFetch()
    const { controller, manager } = setup()

    await manager.applyConfig({ options_source: ENTITY_ENTRIES })

    expect(controller.referenceEntitySelectTarget.value).toBe("")
    expect(controller.referenceLabelFieldSelectTarget.value).toBe("")
  })

  it("applies a config without the select targets", async () => {
    okFetch()
    const { controller } = buildController("", { values: { hasCustomerIdValue: true, customerIdValue: "5" } })
    controller.constantsManager = { updateOptionsSourceUI: vi.fn() }

    await expect(new ReferenceManager(controller).applyConfig({ entity_id: 7 })).resolves.toBeUndefined()
  })

  it("resets both selects", async () => {
    okFetch()
    const { controller, manager } = setup()
    await manager.applyConfig({ entity_id: 7, label_field: "title" })

    manager.reset()

    expect(controller.referenceEntitySelectTarget.selectedIndex).toBe(0)
    expect(optionValues(controller.referenceLabelFieldSelectTarget)).toEqual([""])
  })

  it("resets without targets", () => {
    const { controller } = buildController("")
    expect(() => new ReferenceManager(controller).reset()).not.toThrow()
  })
})

describe("ReferenceManager mode", () => {
  it("selectEntityRecordsOptions switches the mode, syncs inclusion and loads entities", async () => {
    const fetchSpy = okFetch()
    const { controller, manager } = setup()
    const event = fakeEvent({ preventDefault: vi.fn() })

    await manager.selectEntityRecordsOptions(event)

    expect(event.preventDefault).toHaveBeenCalled()
    expect(controller.optionsSourceMode).toBe(ENTITY_ENTRIES)
    expect(controller.constantsManager.updateOptionsSourceUI).toHaveBeenCalled()
    expect(controller.validatorManager.syncInclusionValidator).toHaveBeenCalled()
    expect(fetchSpy).toHaveBeenCalled()
  })

  it("offers the mode for select and radio only and leaves it when the type changes", () => {
    const { controller, manager } = setup({ optionsSourceMode: ENTITY_ENTRIES })

    manager.syncAvailability("radio")
    expect(controller.entityRecordsOptionsBtnTarget.classList.contains("hidden")).toBe(false)
    expect(controller.optionsSourceMode).toBe(ENTITY_ENTRIES)

    manager.syncAvailability("checkbox")
    expect(controller.entityRecordsOptionsBtnTarget.classList.contains("hidden")).toBe(true)
    expect(controller.optionsSourceMode).toBe("manual")
    expect(controller.constantsManager.updateOptionsSourceUI).toHaveBeenCalledTimes(1)

    manager.syncAvailability("text")
    expect(controller.constantsManager.updateOptionsSourceUI).toHaveBeenCalledTimes(1)
  })

  it("syncs availability without a button target", () => {
    const { controller } = buildController("", { values: { optionsSourceMode: "manual" } })
    expect(() => new ReferenceManager(controller).syncAvailability("select")).not.toThrow()
  })
})

describe("ReferenceManager owner switch", () => {
  it("keeps the switch hidden for a non-person target and shows it for a person target", async () => {
    okFetch()
    const { controller, manager } = setup({ optionsSourceMode: ENTITY_ENTRIES })
    await manager.loadTargets()

    controller.referenceEntitySelectTarget.value = "9"
    manager.entityChanged()
    expect(controller.ownerSectionTarget.classList.contains("hidden")).toBe(true)

    controller.referenceEntitySelectTarget.value = "7"
    manager.entityChanged()
    expect(controller.ownerSectionTarget.classList.contains("hidden")).toBe(false)
  })

  it("hides the switch again and unchecks it when the target changes away from a person entity", async () => {
    okFetch()
    const { controller, manager } = setup({ optionsSourceMode: ENTITY_ENTRIES })
    await manager.loadTargets()

    controller.referenceEntitySelectTarget.value = "7"
    manager.entityChanged()
    controller.modalOwnerTarget.checked = true

    controller.referenceEntitySelectTarget.value = "9"
    manager.entityChanged()
    expect(controller.ownerSectionTarget.classList.contains("hidden")).toBe(true)
    expect(controller.modalOwnerTarget.checked).toBe(false)
  })

  it("hides the switch in association context even when the target is a person entity", async () => {
    okFetch()
    const { controller, manager } = setup({
      optionsSourceMode: ENTITY_ENTRIES, attributeModalContext: "association"
    })
    await manager.loadTargets()
    controller.referenceEntitySelectTarget.value = "7"
    manager.entityChanged()
    expect(controller.ownerSectionTarget.classList.contains("hidden")).toBe(true)
  })

  it("treats a missing personEntityIdsValue as an empty list", () => {
    const { manager } = setup({ personEntityIdsValue: undefined, optionsSourceMode: ENTITY_ENTRIES })
    expect(manager.personEntityIds()).toEqual([])
    expect(manager.ownerAvailable()).toBe(false)
  })

  it("does not uncheck when applyConfig restores a person target", async () => {
    okFetch()
    const { controller, manager } = setup()
    controller.modalOwnerTarget.checked = true

    await manager.applyConfig({ options_source: ENTITY_ENTRIES, entity_id: 7, label_field: "title" })

    expect(controller.ownerSectionTarget.classList.contains("hidden")).toBe(false)
    expect(controller.modalOwnerTarget.checked).toBe(true)
  })

  it("reset hides and unchecks the switch", async () => {
    okFetch()
    const { controller, manager } = setup({ optionsSourceMode: ENTITY_ENTRIES })
    await manager.applyConfig({ entity_id: 7, label_field: "title" })
    controller.modalOwnerTarget.checked = true

    manager.reset()

    expect(controller.ownerSectionTarget.classList.contains("hidden")).toBe(true)
    expect(controller.modalOwnerTarget.checked).toBe(false)
  })

  it("syncOwnerVisibility no-ops without an owner section", () => {
    const { controller } = buildController("")
    expect(() => new ReferenceManager(controller).syncOwnerVisibility()).not.toThrow()
  })

  it("leaves the checkbox alone when hiding without a modalOwner target", async () => {
    okFetch()
    const { controller } = buildController(
      `<button data-entity-form-target="entityRecordsOptionsBtn"></button>` +
      `<select data-entity-form-target="referenceEntitySelect"><option value="">—</option></select>` +
      `<select data-entity-form-target="referenceLabelFieldSelect"><option value="">—</option></select>` +
      `<div data-entity-form-target="ownerSection"></div>`,
      { values: { hasCustomerIdValue: true, customerIdValue: "5", optionsSourceMode: ENTITY_ENTRIES, personEntityIdsValue: [7] } }
    )
    controller.constantsManager = { updateOptionsSourceUI: vi.fn() }
    controller.validatorManager = { syncInclusionValidator: vi.fn() }

    expect(() => new ReferenceManager(controller).syncOwnerVisibility()).not.toThrow()
    expect(controller.ownerSectionTarget.classList.contains("hidden")).toBe(true)
  })
})
