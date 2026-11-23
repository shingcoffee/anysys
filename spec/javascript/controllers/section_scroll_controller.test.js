import { afterEach, beforeEach, describe, it, expect, vi } from "vitest"
import Controller from "controllers/section_scroll_controller"
import { mountController } from "../support/stimulus.js"

const html = (id) => `
  <div data-controller="section-scroll" data-section-scroll-id-value="${id}"
       data-section-scroll-highlight-class="ring-2 shadow-lg" data-section-scroll-cue-class="animate-pulse">
    <section id="first"><a id="first-add" data-section-scroll-target="cue">Add</a></section>
    <section id="target"><a id="target-add" data-section-scroll-target="cue">Add</a></section>
  </div>`

const byId = (id) => document.getElementById(id)
const classes = (id) => Array.from(byId(id).classList)

describe("section scroll controller", () => {
  let scroll

  beforeEach(() => {
    scroll = vi.fn()
    Element.prototype.scrollIntoView = scroll
  })

  afterEach(() => {
    vi.useRealTimers()
    document.documentElement.removeAttribute("aria-busy")
    delete Element.prototype.scrollIntoView
  })

  it("scrolls the named section into view on connect and clears the value", async () => {
    const { element } = await mountController("section-scroll", Controller, html("target"))

    expect(scroll).toHaveBeenCalledTimes(1)
    expect(scroll.mock.contexts[0]).toBe(byId("target"))
    expect(element.getAttribute("data-section-scroll-id-value")).toBe("")
  })

  it("highlights the section and only its own cue, then settles after a few seconds", async () => {
    document.documentElement.setAttribute("aria-busy", "true")
    await mountController("section-scroll", Controller, html("target"))
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] })
    document.dispatchEvent(new Event("turbo:load"))

    expect(classes("target")).toEqual(["ring-2", "shadow-lg"])
    expect(classes("target-add")).toEqual(["animate-pulse"])
    expect(classes("first")).toEqual([])
    expect(classes("first-add")).toEqual([])

    vi.advanceTimersByTime(3999)
    expect(classes("target")).toEqual(["ring-2", "shadow-lg"])

    vi.advanceTimersByTime(1)
    expect(classes("target")).toEqual([])
    expect(classes("target-add")).toEqual([])
  })

  it("drops the highlight before Turbo caches the page", async () => {
    await mountController("section-scroll", Controller, html("target"))

    document.dispatchEvent(new Event("turbo:before-cache"))

    expect(classes("target")).toEqual([])
    expect(classes("target-add")).toEqual([])
  })

  it("drops the highlight on disconnect", async () => {
    const { element } = await mountController("section-scroll", Controller, html("target"))
    const section = byId("target")

    element.remove()
    await new Promise((resolve) => setTimeout(resolve, 0))

    expect(Array.from(section.classList)).toEqual([])
  })

  it("waits for turbo:load while a Turbo visit is rendering", async () => {
    document.documentElement.setAttribute("aria-busy", "true")
    await mountController("section-scroll", Controller, html("target"))
    expect(scroll).not.toHaveBeenCalled()
    expect(classes("target")).toEqual([])

    document.dispatchEvent(new Event("turbo:load"))
    document.dispatchEvent(new Event("turbo:load"))

    expect(scroll).toHaveBeenCalledTimes(1)
    expect(scroll.mock.contexts[0]).toBe(byId("target"))
    expect(classes("target")).toEqual(["ring-2", "shadow-lg"])
  })

  it("stops waiting for turbo:load once disconnected", async () => {
    document.documentElement.setAttribute("aria-busy", "true")
    const { element } = await mountController("section-scroll", Controller, html("target"))

    element.remove()
    await new Promise((resolve) => setTimeout(resolve, 0))
    document.dispatchEvent(new Event("turbo:load"))

    expect(scroll).not.toHaveBeenCalled()
  })

  it("does nothing without an id or when the section is missing", async () => {
    await mountController("section-scroll", Controller, html(""))
    const { element } = await mountController("section-scroll", Controller, html("missing"))

    expect(scroll).not.toHaveBeenCalled()
    expect(element.getAttribute("data-section-scroll-id-value")).toBe("")
    expect(document.querySelectorAll("[class]").length).toBe(0)
  })
})
