import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/website_feature_tabs_controller"
import { mountController, click, tick, controllerFor } from "../support/stimulus.js"

const tab = (id, selected) =>
  `<button type="button" data-website-feature-tabs-target="tab" role="tab" aria-selected="${selected}" tabindex="${selected ? 0 : -1}"` +
  ` data-action="click->website-feature-tabs#choose keydown->website-feature-tabs#navigate"` +
  ` class="${selected ? "on extra" : "off muted"}">${id}</button>`

const panel = (id, selected) =>
  `<div data-website-feature-tabs-target="panel" role="tabpanel" class="${selected ? "" : "hidden"}"${selected ? "" : " hidden"}>${id}</div>`

const html = (opts = {}) => {
  const classes = opts.classes === false
    ? ""
    : ` data-website-feature-tabs-active-class="on extra" data-website-feature-tabs-inactive-class="off muted"`
  const index = opts.index === undefined ? "" : ` data-website-feature-tabs-index-value="${opts.index}"`
  const tabs = opts.tabs === false ? "" : tab("one", true) + tab("two", false) + tab("three", false)
  const panels = opts.panels === false ? "" : panel("one", true) + panel("two", false) + panel("three", false)
  return `<div data-controller="website-feature-tabs"${classes}${index}>${tabs}${panels}</div>`
}

const selectedTab = (el) =>
  [...el.querySelectorAll("[data-website-feature-tabs-target='tab']")].find((t) => t.getAttribute("aria-selected") === "true")

const visiblePanels = (el) =>
  [...el.querySelectorAll("[data-website-feature-tabs-target='panel']")].filter((p) => !p.classList.contains("hidden") && !p.hidden)

describe("website-feature-tabs controller", () => {
  let application, element

  const mount = async (markup) => {
    ;({ application, element } = await mountController("website-feature-tabs", Controller, markup))
  }

  const ctrl = () => controllerFor(application, element, "website-feature-tabs")

  beforeEach(async () => {
    await mount(html())
  })

  afterEach(async () => {
    element?.remove()
    await tick()
    application?.stop()
  })

  it("keeps the first tab selected on connect and leaves the others hidden", () => {
    expect(selectedTab(element).textContent).toBe("one")
    expect(selectedTab(element).tabIndex).toBe(0)
    expect(visiblePanels(element)).toHaveLength(1)
    expect(visiblePanels(element)[0].textContent).toBe("one")
    const second = element.querySelectorAll("[role='tab']")[1]
    expect(second.getAttribute("aria-selected")).toBe("false")
    expect(second.tabIndex).toBe(-1)
    expect(second.classList.contains("off")).toBe(true)
  })

  it("choose switches the panel, aria-selected, tabindex and class tokens", async () => {
    const two = element.querySelectorAll("[role='tab']")[1]
    await click(two)
    expect(selectedTab(element)).toBe(two)
    expect(two.classList.contains("on")).toBe(true)
    expect(two.classList.contains("extra")).toBe(true)
    expect(two.classList.contains("off")).toBe(false)
    expect(visiblePanels(element)[0].textContent).toBe("two")
    expect(ctrl().indexValue).toBe(1)
    const one = element.querySelectorAll("[role='tab']")[0]
    expect(one.classList.contains("muted")).toBe(true)
    expect(one.getAttribute("aria-selected")).toBe("false")
  })

  it("choose no-ops when the event target is not a tab", () => {
    ctrl().choose({ currentTarget: document.createElement("button") })
    expect(selectedTab(element).textContent).toBe("one")
    expect(ctrl().indexValue).toBe(0)
  })

  it("honors a starting index value on connect", async () => {
    await mount(html({ index: 2 }))
    expect(selectedTab(element).textContent).toBe("three")
    expect(visiblePanels(element)[0].textContent).toBe("three")
  })

  it.each([
    ["ArrowRight", "two"],
    ["ArrowDown", "two"],
    ["End", "three"]
  ])("navigate %s moves to %s and focuses it", (key, label) => {
    const event = new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true })
    const prevent = vi.spyOn(event, "preventDefault")
    selectedTab(element).dispatchEvent(event)
    expect(prevent).toHaveBeenCalled()
    expect(selectedTab(element).textContent).toBe(label)
    expect(document.activeElement).toBe(selectedTab(element))
  })

  it.each([
    ["ArrowLeft", "three"],
    ["ArrowUp", "three"],
    ["Home", "one"]
  ])("navigate %s from the first tab resolves to %s", async (key, label) => {
    const event = new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true })
    ctrl().navigate(event)
    expect(selectedTab(element).textContent).toBe(label)
  })

  it("ignores keys that are not part of the tablist contract", () => {
    const event = new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })
    const prevent = vi.spyOn(event, "preventDefault")
    ctrl().navigate(event)
    expect(prevent).not.toHaveBeenCalled()
    expect(selectedTab(element).textContent).toBe("one")
  })

  it("wraps ArrowRight from the last tab back to the first", () => {
    ctrl().activate(2, { focus: false })
    const event = new KeyboardEvent("keydown", { key: "ArrowRight", cancelable: true })
    ctrl().navigate(event)
    expect(selectedTab(element).textContent).toBe("one")
  })

  it("activate without options does not steal focus", () => {
    const outside = document.createElement("button")
    document.body.append(outside)
    outside.focus()
    ctrl().activate(1)
    expect(selectedTab(element).textContent).toBe("two")
    expect(document.activeElement).toBe(outside)
  })

  it("is a no-op when no tab targets are present", async () => {
    await mount(html({ tabs: false, panels: false }))
    const c = ctrl()
    expect(c.hasTabTarget).toBe(false)
    expect(c.clampedIndex(4)).toBe(0)
    expect(c.clampedIndex(Number.NaN)).toBe(0)
    expect(c.nextIndex("end")).toBe(0)
    expect(() => c.activate(1, { focus: true })).not.toThrow()
    expect(() => c.choose({ currentTarget: document.createElement("button") })).not.toThrow()
  })

  it("clampedIndex wraps, truncates fractions and rejects non-finite values", () => {
    const c = ctrl()
    expect(c.clampedIndex(-1)).toBe(2)
    expect(c.clampedIndex(4)).toBe(1)
    expect(c.clampedIndex(1.8)).toBe(1)
    expect(c.clampedIndex("nope")).toBe(0)
    expect(c.clampedIndex()).toBe(0)
  })

  it("deltaFor and nextIndex cover every recognised key", () => {
    const c = ctrl()
    expect(c.deltaFor("ArrowRight")).toBe(1)
    expect(c.deltaFor("ArrowDown")).toBe(1)
    expect(c.deltaFor("ArrowLeft")).toBe(-1)
    expect(c.deltaFor("ArrowUp")).toBe(-1)
    expect(c.deltaFor("Home")).toBe("home")
    expect(c.deltaFor("End")).toBe("end")
    expect(c.deltaFor("Tab")).toBeNull()
    expect(c.nextIndex("home")).toBe(0)
    expect(c.nextIndex("end")).toBe(2)
    expect(c.nextIndex(1)).toBe(1)
  })

  it("toggles nothing when active/inactive class lists are empty", async () => {
    await mount(html({ classes: false }))
    const two = element.querySelectorAll("[role='tab']")[1]
    await click(two)
    expect(two.getAttribute("aria-selected")).toBe("true")
    expect(visiblePanels(element)[0].textContent).toBe("two")
  })
})
