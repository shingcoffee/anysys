// NOTE: render() positions the tooltip via getBoundingClientRect + window
// dimensions — real geometry that happy-dom returns as zeros. The final
// left/top pixel math is covered by Playwright (spec/e2e), not unit tests.
// Here we cover the DOM-structural behaviour: title stripping, tooltip
// creation/removal, and the same-target de-dup guard.
import { describe, it, expect, beforeEach, vi } from "vitest"
import Controller from "controllers/tooltip_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

const html =
  `<div data-controller="tooltip">` +
  `<button id="a" title="Save changes">A</button>` +
  `<button id="b" title="Delete">B</button>` +
  `<button id="c">No title</button>` +
  `<button id="d" title="">Empty title</button>` +
  `</div>`

const tips = () => [...document.body.querySelectorAll("div.fixed.z-\\[100\\]")]

describe("tooltip controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element } = await mountController("tooltip", Controller, html))
    ctrl = controllerFor(application, element, "tooltip")
  })

  it("strips native title into data-tooltip + aria-label on connect", () => {
    const a = element.querySelector("#a")
    expect(a.hasAttribute("title")).toBe(false)
    expect(a.dataset.tooltip).toBe("Save changes")
    expect(a.getAttribute("aria-label")).toBe("Save changes")
    expect(element.querySelector("#c").dataset.tooltip).toBeUndefined()
  })

  it("leaves a title=\"\" attribute alone (falsy-text guard)", () => {
    // `[title]` still matches an empty-string title, but `if (!text) return`
    // bails before stripping it, so the attribute survives untouched.
    const d = element.querySelector("#d")
    expect(d.hasAttribute("title")).toBe(true)
    expect(d.dataset.tooltip).toBeUndefined()
  })

  it("show() renders a body-level tooltip with the target text", () => {
    const a = element.querySelector("#a")
    ctrl.show({ target: a })
    expect(tips().length).toBe(1)
    expect(tips()[0].textContent).toBe("Save changes")
    // currentTarget survives the show() (it is assigned AFTER render(), whose
    // internal remove() would otherwise clear it) so the de-dup guard can work.
    expect(ctrl.currentTarget).toBe(a)
  })

  it("ignores show for elements without a tooltip", () => {
    ctrl.show({ target: element.querySelector("#c") })
    expect(tips().length).toBe(0)
  })

  it("does not re-render when hovering the same target twice (de-dup guard)", () => {
    const a = element.querySelector("#a")
    ctrl.show({ target: a })
    const first = tips()[0]
    ctrl.show({ target: a }) // de-dup guard trips -> no re-render
    expect(tips().length).toBe(1)
    expect(tips()[0]).toBe(first) // the same node, not recreated
  })

  it("switching targets replaces the tooltip", () => {
    ctrl.show({ target: element.querySelector("#a") })
    ctrl.show({ target: element.querySelector("#b") })
    expect(tips().length).toBe(1)
    expect(tips()[0].textContent).toBe("Delete")
  })

  it("remove() tears down the tooltip and clears currentTarget", () => {
    ctrl.show({ target: element.querySelector("#a") })
    ctrl.remove()
    expect(tips().length).toBe(0)
    expect(ctrl.currentTarget).toBeNull()
  })

  it("hide() removes the tooltip when the pointer leaves the trigger", () => {
    ctrl.show({ target: element.querySelector("#a") })
    ctrl.hide({ relatedTarget: document.body })
    expect(tips().length).toBe(0)
  })

  it("show() de-dup guard trips when currentTarget is already the same target", () => {
    const a = element.querySelector("#a")
    ctrl.currentTarget = a
    ctrl.show({ target: a })
    expect(tips().length).toBe(0) // guard returned early, render() never ran
  })

  it("hide() removes the tooltip when currentTarget is set but relatedTarget is absent", () => {
    const a = element.querySelector("#a")
    ctrl.show({ target: a })
    ctrl.currentTarget = a // prime it back since render()'s remove() cleared it
    ctrl.hide({ relatedTarget: null })
    expect(ctrl.currentTarget).toBeNull()
  })

  it("hide() removes the tooltip when relatedTarget is outside currentTarget", () => {
    const a = element.querySelector("#a")
    const b = element.querySelector("#b")
    ctrl.show({ target: a })
    ctrl.currentTarget = a
    ctrl.hide({ relatedTarget: b })
    expect(ctrl.currentTarget).toBeNull()
  })

  it("hide() keeps the tooltip when relatedTarget is contained within currentTarget", () => {
    const a = element.querySelector("#a")
    const child = document.createElement("span")
    a.appendChild(child)
    ctrl.show({ target: a })
    ctrl.currentTarget = a
    ctrl.hide({ relatedTarget: child })
    expect(ctrl.currentTarget).toBe(a) // guard tripped, remove() never ran
  })

  it("render() flips the tooltip above the trigger when it would overflow the viewport bottom", () => {
    // getBoundingClientRect returns zeros in happy-dom; stub it so the
    // bottom-overflow branch computes real (non-zero) geometry instead of
    // asserting on zeros, per COVERAGE_100_BRIEF's guidance.
    const rectStub = vi.spyOn(Element.prototype, "getBoundingClientRect").mockReturnValue({
      x: 0, y: 700, width: 80, height: 100, top: 700, left: 100, right: 180, bottom: 1000,
    })
    ctrl.render(element.querySelector("#a"), "Flips above")
    const tip = tips()[0]
    expect(parseFloat(tip.style.top)).toBe(700 - 100 - 6) // rect.top - tipRect.height - 6
    rectStub.mockRestore()
  })

  it("renders a multiline tooltip when data-tooltip-multiline is true", async () => {
    const trigger = document.createElement("button")
    trigger.dataset.tooltip = "Required\nEmail"
    trigger.dataset.tooltipMultiline = "true"
    element.appendChild(trigger)
    ctrl.show({ target: trigger })
    const tip = tips()[0]
    expect(tip.textContent).toBe("Required\nEmail")
    expect(tip.className).toContain("whitespace-pre-line")
    expect(tip.className).toContain("max-w-xs")
  })

  it("skips overflow-gated tooltips when the trigger is not overflowing", () => {
    const trigger = document.createElement("button")
    trigger.dataset.tooltip = "Full list"
    trigger.dataset.tooltipOverflow = "true"
    element.appendChild(trigger)
    vi.spyOn(trigger, "scrollWidth", "get").mockReturnValue(40)
    vi.spyOn(trigger, "clientWidth", "get").mockReturnValue(40)
    vi.spyOn(trigger, "scrollHeight", "get").mockReturnValue(20)
    vi.spyOn(trigger, "clientHeight", "get").mockReturnValue(20)
    ctrl.show({ target: trigger })
    expect(tips().length).toBe(0)
  })

  it("shows overflow-gated tooltips when the trigger content overflows", () => {
    const trigger = document.createElement("button")
    trigger.dataset.tooltip = "Full list"
    trigger.dataset.tooltipOverflow = "true"
    element.appendChild(trigger)
    vi.spyOn(trigger, "scrollWidth", "get").mockReturnValue(120)
    vi.spyOn(trigger, "clientWidth", "get").mockReturnValue(40)
    vi.spyOn(trigger, "scrollHeight", "get").mockReturnValue(20)
    vi.spyOn(trigger, "clientHeight", "get").mockReturnValue(20)
    ctrl.show({ target: trigger })
    expect(tips().length).toBe(1)
    expect(tips()[0].textContent).toBe("Full list")
  })

  it("disconnect removes the DOM listeners and tears down any open tooltip", async () => {
    ctrl.show({ target: element.querySelector("#a") })
    ctrl.currentTarget = element.querySelector("#a")
    expect(tips().length).toBe(1)
    const removeSpy = vi.spyOn(element, "removeEventListener")
    element.remove() // Stimulus disconnects controllers whose element leaves the DOM
    await tick()
    expect(removeSpy).toHaveBeenCalledWith("mouseover", expect.any(Function))
    expect(removeSpy).toHaveBeenCalledWith("mouseout", expect.any(Function))
    expect(removeSpy).toHaveBeenCalledWith("mousedown", expect.any(Function))
    expect(removeSpy).toHaveBeenCalledWith("mouseleave", expect.any(Function))
    expect(tips().length).toBe(0)
  })
})
