import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/property_editor/controls/reference_picker_controller"
import { resetReferenceCache } from "controllers/property_editor/controls/reference_options"
import { mountController, controllerFor, click, tick } from "../../../support/stimulus.js"

const IDENTIFIER = "property-editor--controls--reference-picker"

function pickerHTML() {
  return `
    <meta name="csrf-token" content="tok">
    <div data-controller="flowchart-canvas"
         data-flowchart-canvas-urls-value='{"referenceOptions":"/ref/__SOURCE__.json"}'></div>
    <div data-controller="${IDENTIFIER}"
         data-${IDENTIFIER}-source-value="entities"
         data-${IDENTIFIER}-selected-value=""
         data-${IDENTIFIER}-loading-label-value="Loading…"
         data-${IDENTIFIER}-empty-label-value="No matches"
         data-${IDENTIFIER}-error-label-value="Could not load options"
         data-${IDENTIFIER}-placeholder-value="Select…">
      <input type="hidden" data-${IDENTIFIER}-target="hidden" value="">
      <button type="button" data-${IDENTIFIER}-target="trigger" data-action="click->${IDENTIFIER}#toggle" aria-expanded="false">
        <span data-${IDENTIFIER}-target="label">Select…</span>
      </button>
      <div data-${IDENTIFIER}-target="dropdown" class="hidden">
        <input data-${IDENTIFIER}-target="search" data-action="input->${IDENTIFIER}#filter keydown->${IDENTIFIER}#keydown">
        <div data-${IDENTIFIER}-target="status"></div>
        <div data-${IDENTIFIER}-target="list"></div>
      </div>
    </div>`
}

describe("reference picker controller", () => {
  let application, element, ctrl

  beforeEach(() => {
    resetReferenceCache()
    vi.unstubAllGlobals()
  })

  afterEach(() => {
    resetReferenceCache()
    vi.unstubAllGlobals()
    application?.stop()
  })

  async function mount(fetchImpl) {
    if (fetchImpl) vi.stubGlobal("fetch", fetchImpl)
    ;({ application, element } = await mountController(IDENTIFIER, Controller, pickerHTML()))
    ctrl = controllerFor(application, element, IDENTIFIER)
    return ctrl
  }

  it("paints the placeholder on connect and no-ops pick/clickOutside when idle", async () => {
    await mount()
    expect(ctrl.labelTarget.textContent).toBe("Select…")
    ctrl.pick({ target: element })
    expect(ctrl.hiddenTarget.value).toBe("")
    ctrl.clickOutside({ target: document.body })
    expect(ctrl.open).toBe(false)
  })

  it("loads options on first open, filters them, and picks a value", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ options: [{ value: "e1", label: "Alpha" }, { value: "e2", label: "Beta" }] }),
    })
    await mount(fetchMock)
    await ctrl.toggle({ preventDefault() {} })
    await tick()
    expect(ctrl.open).toBe(true)
    expect(ctrl.listTarget.textContent).toContain("Alpha")
    expect(ctrl.statusTarget.classList.contains("hidden")).toBe(true)

    ctrl.searchTarget.value = "bet"
    ctrl.filter()
    expect(ctrl.listTarget.textContent).toContain("Beta")
    expect(ctrl.listTarget.textContent).not.toContain("Alpha")

    const option = ctrl.listTarget.querySelector("[data-reference-option]")
    option.dispatchEvent(new Event("change", { bubbles: true }))
    ctrl.pick({ target: option })
    expect(ctrl.hiddenTarget.value).toBe("e2")
    expect(ctrl.labelTarget.textContent).toBe("Beta")
    expect(ctrl.open).toBe(false)
  })

  it("closes on a second toggle, Escape, and an outside click", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ options: [{ value: "1", label: "One" }] }),
    }))
    await mount()
    await ctrl.toggle({ preventDefault() {} })
    await tick()
    expect(ctrl.open).toBe(true)

    ctrl.keydown({ key: "Enter", preventDefault() {} })
    expect(ctrl.open).toBe(true)
    ctrl.keydown({ key: "Escape", preventDefault() {} })
    expect(ctrl.open).toBe(false)

    await ctrl.toggle({ preventDefault() {} })
    await tick()
    ctrl.clickOutside({ target: ctrl.searchTarget })
    expect(ctrl.open).toBe(true)
    ctrl.clickOutside({ target: document.body })
    expect(ctrl.open).toBe(false)

    await ctrl.toggle({ preventDefault() {} })
    await tick()
    await ctrl.toggle({ preventDefault() {} })
    expect(ctrl.open).toBe(false)
  })

  it("shows the error and empty statuses", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false }))
    await mount()
    await ctrl.toggle({ preventDefault() {} })
    await tick()
    expect(ctrl.statusTarget.textContent).toBe("Could not load options")
    expect(ctrl.listTarget.innerHTML).toBe("")

    ctrl.loaded = true
    ctrl.options = []
    ctrl.filter()
    expect(ctrl.statusTarget.textContent).toBe("No matches")
  })

  it("falls back to the value when an option has no label", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ options: [{ value: "only" }] }),
    }))
    await mount()
    await ctrl.toggle({ preventDefault() {} })
    await tick()
    const option = ctrl.listTarget.querySelector("[data-reference-option]")
    expect(option.textContent).toBe("only")
    delete option.dataset.referenceLabel
    ctrl.pick({ target: option })
    expect(ctrl.labelTarget.textContent).toBe("only")
  })

  it("renders an option whose value is missing", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ options: [{ label: "Nameless" }] }),
    }))
    await mount()
    await ctrl.toggle({ preventDefault() {} })
    await tick()
    expect(ctrl.listTarget.textContent).toContain("Nameless")
  })

  it("uses the click helper path on the trigger", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ options: [] }),
    }))
    await mount()
    await click(ctrl.triggerTarget)
    await tick()
    expect(ctrl.open).toBe(true)
  })

  it("resolves a stored value to its option label on connect, highlights it, picks without a hidden target, and disconnects", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ options: [{ value: "e1", label: "Alpha" }] }),
    }))
    const html = pickerHTML()
      .replace('data-property-editor--controls--reference-picker-selected-value=""',
        'data-property-editor--controls--reference-picker-selected-value="e1"')
      .replace('<input type="hidden" data-property-editor--controls--reference-picker-target="hidden" value="">', "")
    ;({ application, element } = await mountController(IDENTIFIER, Controller, html))
    ctrl = controllerFor(application, element, IDENTIFIER)
    expect(ctrl.labelTarget.textContent).toBe("Alpha")

    await ctrl.toggle({ preventDefault() {} })
    await tick()
    expect(ctrl.listTarget.innerHTML).toContain("bg-indigo-50")

    const option = ctrl.listTarget.querySelector("[data-reference-option]")
    ctrl.pick({ target: option })
    expect(ctrl.selectedValue).toBe("e1")
    expect(ctrl.open).toBe(false)

    ctrl.disconnect()
  })

  it("skips painting when the label target is absent and handles unresolved/nameless stored options", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false }))
    const failHtml = pickerHTML().replace(
      'data-property-editor--controls--reference-picker-selected-value=""',
      'data-property-editor--controls--reference-picker-selected-value="missing"'
    )
    ;({ application, element } = await mountController(IDENTIFIER, Controller, failHtml))
    ctrl = controllerFor(application, element, IDENTIFIER)
    expect(ctrl.labelTarget.textContent).toBe("missing")
    application.stop()
    resetReferenceCache()

    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ options: [{}, { value: "raw" }] }),
    }))
    const rawHtml = pickerHTML().replace(
      'data-property-editor--controls--reference-picker-selected-value=""',
      'data-property-editor--controls--reference-picker-selected-value="raw"'
    )
    ;({ application, element } = await mountController(IDENTIFIER, Controller, rawHtml))
    ctrl = controllerFor(application, element, IDENTIFIER)
    expect(ctrl.labelTarget.textContent).toBe("raw")
    application.stop()
    resetReferenceCache()

    const html = pickerHTML().replace(
      '<span data-property-editor--controls--reference-picker-target="label">Select…</span>',
      "",
    )
    ;({ application, element } = await mountController(IDENTIFIER, Controller, html))
    ctrl = controllerFor(application, element, IDENTIFIER)
    expect(ctrl.hasLabelTarget).toBe(false)
  })
})
