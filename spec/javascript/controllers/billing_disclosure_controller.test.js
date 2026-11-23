import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/billing_disclosure_controller"
import { mountController, controllerFor, click, tick } from "../support/stimulus.js"

const html = ({ id = "plans", open = false, hashes = [] } = {}) => `
  <section id="${id}"
           data-controller="billing-disclosure"
           data-billing-disclosure-open-value="${open}"
           data-billing-disclosure-hashes-value='${JSON.stringify(hashes)}'>
    <button type="button" data-billing-disclosure-target="trigger"
            data-action="billing-disclosure#toggle"
            aria-expanded="${open}" aria-controls="${id}-panel">Toggle</button>
    <span data-billing-disclosure-target="icon"${open ? ' class="rotate-90"' : ""}>icon</span>
    <div id="${id}-panel" data-billing-disclosure-target="panel">body</div>
  </section>`

const trigger = (el) => el.querySelector("[data-billing-disclosure-target='trigger']")
const panel = (el) => el.querySelector("[data-billing-disclosure-target='panel']")
const icon = (el) => el.querySelector("[data-billing-disclosure-target='icon']")

const isOpen = (el) => ({
  hidden: panel(el).classList.contains("hidden"),
  expanded: trigger(el).getAttribute("aria-expanded"),
  rotated: icon(el).classList.contains("rotate-90")
})

describe("billing-disclosure controller", () => {
  beforeEach(() => {
    window.location.hash = ""
  })

  afterEach(() => {
    window.location.hash = ""
    vi.restoreAllMocks()
  })

  it("on connect without a hash, closed SSR stays inspectable until JS hides the panel", async () => {
    const { element } = await mountController("billing-disclosure", Controller, html({ open: false }))
    expect(isOpen(element)).toEqual({ hidden: true, expanded: "false", rotated: false })
  })

  it("on connect without a hash, an open section stays visible and rotated", async () => {
    const { element } = await mountController("billing-disclosure", Controller, html({ open: true }))
    expect(isOpen(element)).toEqual({ hidden: false, expanded: "true", rotated: true })
  })

  it("on connect, a hash matching the section id opens a closed panel", async () => {
    window.location.hash = "#plans"
    const { element } = await mountController("billing-disclosure", Controller, html({ id: "plans", open: false }))
    expect(isOpen(element)).toEqual({ hidden: false, expanded: "true", rotated: true })
  })

  it("on connect, a hash matching hashesValue opens a closed panel", async () => {
    window.location.hash = "#coupon-form"
    const { element } = await mountController(
      "billing-disclosure",
      Controller,
      html({ id: "coupon-section", open: false, hashes: ["coupon-form"] })
    )
    expect(isOpen(element)).toEqual({ hidden: false, expanded: "true", rotated: true })
  })

  it("on connect, a non-matching hash leaves a closed panel hidden", async () => {
    window.location.hash = "#other"
    const { element } = await mountController("billing-disclosure", Controller, html({ id: "plans", open: false }))
    expect(isOpen(element)).toEqual({ hidden: true, expanded: "false", rotated: false })
  })

  it("on connect, a hash that already matches an open section stays open", async () => {
    window.location.hash = "#plans"
    const { element } = await mountController("billing-disclosure", Controller, html({ id: "plans", open: true }))
    expect(isOpen(element)).toEqual({ hidden: false, expanded: "true", rotated: true })
  })

  it("toggle() flips visibility, aria-expanded, and icon rotation", async () => {
    const { element } = await mountController("billing-disclosure", Controller, html({ open: false }))
    await click(trigger(element))
    expect(isOpen(element)).toEqual({ hidden: false, expanded: "true", rotated: true })
    await click(trigger(element))
    expect(isOpen(element)).toEqual({ hidden: true, expanded: "false", rotated: false })
  })

  it("open() and close() drive the state programmatically", async () => {
    const { application, element } = await mountController("billing-disclosure", Controller, html({ open: false }))
    const ctrl = controllerFor(application, element, "billing-disclosure")
    ctrl.open()
    await tick()
    expect(isOpen(element)).toEqual({ hidden: false, expanded: "true", rotated: true })
    ctrl.open()
    await tick()
    expect(isOpen(element)).toEqual({ hidden: false, expanded: "true", rotated: true })
    ctrl.close()
    await tick()
    expect(isOpen(element)).toEqual({ hidden: true, expanded: "false", rotated: false })
    ctrl.close()
    await tick()
    expect(isOpen(element)).toEqual({ hidden: true, expanded: "false", rotated: false })
  })

  it("hashchange to a matching id opens the panel and ignores a later unmatched hash", async () => {
    const { element } = await mountController("billing-disclosure", Controller, html({ id: "plans", open: false }))
    window.location.hash = "#plans"
    window.dispatchEvent(new HashChangeEvent("hashchange"))
    await tick()
    expect(isOpen(element)).toEqual({ hidden: false, expanded: "true", rotated: true })

    window.location.hash = "#other"
    window.dispatchEvent(new HashChangeEvent("hashchange"))
    await tick()
    expect(isOpen(element)).toEqual({ hidden: false, expanded: "true", rotated: true })
  })

  it("a document click on a matching hash link (or its child) opens the panel", async () => {
    const { application, element } = await mountController(
      "billing-disclosure",
      Controller,
      html({ id: "plans", open: false, hashes: ["coupon-form"] }) +
      `<a href="#plans" id="jump-id"><span id="jump-id-label">plans</span></a>` +
      `<a href="#coupon-form" id="jump-hash">coupon</a>` +
      `<a href="#other" id="jump-miss">other</a>` +
      `<a href="/plans" id="jump-path">path</a>` +
      `<div id="not-a-link">plain</div>`
    )
    const ctrl = controllerFor(application, element, "billing-disclosure")

    await click(document.getElementById("jump-id-label"))
    expect(isOpen(element)).toEqual({ hidden: false, expanded: "true", rotated: true })

    ctrl.close()
    await tick()
    await click(document.getElementById("jump-hash"))
    expect(isOpen(element)).toEqual({ hidden: false, expanded: "true", rotated: true })

    ctrl.close()
    await tick()
    await click(document.getElementById("jump-miss"))
    await click(document.getElementById("jump-path"))
    await click(document.getElementById("not-a-link"))
    document.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    await tick()
    expect(isOpen(element)).toEqual({ hidden: true, expanded: "false", rotated: false })
  })

  it("disconnect removes hashchange and document click listeners", async () => {
    const { application, element } = await mountController(
      "billing-disclosure",
      Controller,
      html({ id: "plans", open: false }) + `<a href="#plans" id="after-stop">plans</a>`
    )
    const ctrl = controllerFor(application, element, "billing-disclosure")
    const windowRemove = vi.spyOn(window, "removeEventListener")
    const docRemove = vi.spyOn(document, "removeEventListener")
    ctrl.disconnect()
    expect(windowRemove).toHaveBeenCalledWith("hashchange", ctrl._onHashChange)
    expect(docRemove).toHaveBeenCalledWith("click", ctrl._onDocumentClick)

    window.location.hash = "#plans"
    window.dispatchEvent(new HashChangeEvent("hashchange"))
    await click(document.getElementById("after-stop"))
    await tick()
    expect(panel(element).classList.contains("hidden")).toBe(true)
    expect(trigger(element).getAttribute("aria-expanded")).toBe("false")
  })
})
