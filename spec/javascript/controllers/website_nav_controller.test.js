import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/website_nav_controller"
import { mountController, click, tick, controllerFor } from "../support/stimulus.js"

const fullHtml = (labels = true) =>
  `<div data-controller="website-nav"` +
  (labels
    ? ` data-website-nav-open-label-value="Open menu" data-website-nav-close-label-value="Close menu"`
    : "") +
  `>` +
  `<button data-website-nav-target="trigger" data-action="click->website-nav#toggle" aria-expanded="false" aria-label="Open menu">menu</button>` +
  `<div data-website-nav-target="backdrop" data-action="click->website-nav#close" class="hidden"></div>` +
  `<div data-website-nav-target="panel" class="hidden">` +
  `<button data-action="click->website-nav#close">close</button><a href="#features">Features</a></div>` +
  `</div>`

describe("website-nav controller", () => {
  let application, element

  const mount = async (html) => {
    if (element) {
      element.remove()
      await tick()
      application.stop()
    }
    ;({ application, element } = await mountController("website-nav", Controller, html))
  }

  beforeEach(async () => {
    document.documentElement.style.overflow = ""
    await mount(fullHtml())
  })

  afterEach(async () => {
    element.remove()
    await tick()
    application.stop()
    document.documentElement.style.overflow = ""
  })

  const trigger = () => element.querySelector("[data-website-nav-target='trigger']")
  const panel = () => element.querySelector("[data-website-nav-target='panel']")
  const backdrop = () => element.querySelector("[data-website-nav-target='backdrop']")
  const ctrl = () => controllerFor(application, element, "website-nav")

  it("starts closed with aria-expanded false and the open label", () => {
    expect(panel().classList.contains("hidden")).toBe(true)
    expect(backdrop().classList.contains("hidden")).toBe(true)
    expect(trigger().getAttribute("aria-expanded")).toBe("false")
    expect(trigger().getAttribute("aria-label")).toBe("Open menu")
    expect(document.documentElement.style.overflow).toBe("")
  })

  it("toggle opens the sheet, locks root scroll, and switches the trigger label", async () => {
    await click(trigger())
    expect(panel().classList.contains("hidden")).toBe(false)
    expect(backdrop().classList.contains("hidden")).toBe(false)
    expect(trigger().getAttribute("aria-expanded")).toBe("true")
    expect(trigger().getAttribute("aria-label")).toBe("Close menu")
    expect(document.documentElement.style.overflow).toBe("hidden")
    expect(document.body.style.overflow).toBe("")
  })

  it("toggle closes an open sheet and restores overflow", async () => {
    await click(trigger())
    await click(trigger())
    expect(panel().classList.contains("hidden")).toBe(true)
    expect(trigger().getAttribute("aria-expanded")).toBe("false")
    expect(trigger().getAttribute("aria-label")).toBe("Open menu")
    expect(document.documentElement.style.overflow).toBe("")
  })

  it("open and close methods are idempotent", () => {
    const c = ctrl()
    c.open()
    c.open()
    expect(panel().classList.contains("hidden")).toBe(false)
    expect(document.documentElement.style.overflow).toBe("hidden")
    c.close()
    c.close()
    expect(panel().classList.contains("hidden")).toBe(true)
    expect(document.documentElement.style.overflow).toBe("")
  })

  it("closes on Escape and ignores other keys", async () => {
    await click(trigger())
    const link = panel().querySelector("a")
    link.focus()
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }))
    expect(panel().classList.contains("hidden")).toBe(false)
    expect(document.activeElement).toBe(link)
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))
    expect(panel().classList.contains("hidden")).toBe(true)
    expect(document.activeElement).toBe(trigger())
  })

  it.each(["backdrop", "close button", "trigger"])("restores trigger focus when closed via %s", async (method) => {
    await click(trigger())
    const link = panel().querySelector("a")
    link.focus()
    expect(document.activeElement).toBe(link)
    const targets = { backdrop: backdrop(), "close button": panel().querySelector("button"), trigger: trigger() }
    await click(targets[method])
    expect(panel().classList.contains("hidden")).toBe(true)
    expect(document.documentElement.style.overflow).toBe("")
    expect(document.activeElement).toBe(trigger())
  })

  it("does not steal focus on Escape when already closed", () => {
    const outside = document.createElement("button")
    document.body.append(outside)
    outside.focus()
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))
    expect(document.activeElement).toBe(outside)
  })

  it("restores a pre-existing overflow value after close", () => {
    document.documentElement.style.overflow = "scroll"
    const c = ctrl()
    c.close()
    c.open()
    expect(document.documentElement.style.overflow).toBe("hidden")
    c.close()
    expect(document.documentElement.style.overflow).toBe("scroll")
  })

  it("restores overflow on disconnect while open", async () => {
    document.documentElement.style.overflow = "auto"
    ctrl().open()
    expect(document.documentElement.style.overflow).toBe("hidden")
    element.remove()
    await tick()
    expect(document.documentElement.style.overflow).toBe("auto")
    application.stop()
  })

  it("disconnect while closed is a no-op on overflow", async () => {
    expect(document.documentElement.style.overflow).toBe("")
    element.remove()
    await tick()
    expect(document.documentElement.style.overflow).toBe("")
    application.stop()
  })

  it("uses default open/close labels when values are omitted", async () => {
    await mount(fullHtml(false))
    expect(trigger().getAttribute("aria-label")).toBe("Open menu")
    await click(trigger())
    expect(trigger().getAttribute("aria-label")).toBe("Close menu")
  })

  it("opens without a trigger target", async () => {
    const html =
      `<div data-controller="website-nav">` +
      `<div data-website-nav-target="backdrop" class="hidden"></div>` +
      `<div data-website-nav-target="panel" class="hidden"></div>` +
      `</div>`
    await mount(html)
    const c = ctrl()
    c.open()
    expect(panel().classList.contains("hidden")).toBe(false)
    expect(document.documentElement.style.overflow).toBe("hidden")
    c.close()
    expect(panel().classList.contains("hidden")).toBe(true)
  })

  it("does not throw when panel and backdrop targets are missing", async () => {
    const html =
      `<div data-controller="website-nav">` +
      `<button data-website-nav-target="trigger" data-action="click->website-nav#toggle" aria-expanded="false">menu</button>` +
      `</div>`
    await mount(html)
    const c = ctrl()
    expect(() => c.open()).not.toThrow()
    expect(trigger().getAttribute("aria-expanded")).toBe("true")
    expect(() => c.close()).not.toThrow()
    expect(trigger().getAttribute("aria-expanded")).toBe("false")
  })

  it("closes the sheet when the viewport reaches the desktop nav breakpoint", async () => {
    await click(trigger())
    expect(panel().classList.contains("hidden")).toBe(false)
    const original = window.matchMedia
    window.matchMedia = (query) => ({
      matches: String(query).includes("1024"),
      media: query,
      addEventListener() {},
      removeEventListener() {}
    })
    window.dispatchEvent(new Event("resize"))
    expect(panel().classList.contains("hidden")).toBe(true)
    expect(document.documentElement.style.overflow).toBe("")
    window.matchMedia = original
  })

  it("keeps the sheet open when resize stays below the desktop breakpoint", async () => {
    await click(trigger())
    const original = window.matchMedia
    window.matchMedia = (query) => ({
      matches: false,
      media: query,
      addEventListener() {},
      removeEventListener() {}
    })
    window.dispatchEvent(new Event("resize"))
    expect(panel().classList.contains("hidden")).toBe(false)
    window.matchMedia = original
  })

  it("treats a missing matchMedia as still-compact and leaves the sheet open", async () => {
    await click(trigger())
    const original = window.matchMedia
    Object.defineProperty(window, "matchMedia", { configurable: true, value: undefined, writable: true })
    window.dispatchEvent(new Event("resize"))
    expect(panel().classList.contains("hidden")).toBe(false)
    window.matchMedia = original
  })
})

const nativeHtml =
  `<div data-controller="website-nav" data-website-nav-open-label-value="打开菜单" data-website-nav-close-label-value="关闭菜单">` +
  `<button data-website-nav-target="trigger" data-action="click->website-nav#toggle">menu</button>` +
  `<dialog data-website-nav-target="panel" data-action="cancel->website-nav#close:prevent click->website-nav#dismissBackdrop">` +
  `<div><button autofocus data-action="click->website-nav#close">close</button><a href="#features">Features</a></div>` +
  `</dialog></div>`

describe("website-nav native dialog", () => {
  let application, element, panel, trigger, controller, showModal, closeDialog

  beforeEach(async () => {
    document.documentElement.style.overflow = "auto"
    ;({ application, element } = await mountController("website-nav", Controller, nativeHtml))
    panel = element.querySelector("dialog")
    trigger = element.querySelector("[data-website-nav-target='trigger']")
    controller = controllerFor(application, element, "website-nav")
    // Model only the API's open-state contract. Real native focus, inertness and
    // Tab confinement are asserted in website_native_dialog.app.spec.js.
    showModal = vi.fn(() => panel.setAttribute("open", ""))
    closeDialog = vi.fn(() => panel.removeAttribute("open"))
    panel.showModal = showModal
    panel.close = closeDialog
  })

  afterEach(async () => {
    element.remove()
    await tick()
    application.stop()
    vi.restoreAllMocks()
    document.documentElement.style.overflow = ""
  })

  it("starts closed without invoking native APIs and keeps translated labels", () => {
    controller.sync()
    expect(panel.open).toBe(false)
    expect(showModal).not.toHaveBeenCalled()
    expect(closeDialog).not.toHaveBeenCalled()
    expect(trigger.getAttribute("aria-expanded")).toBe("false")
    expect(trigger.getAttribute("aria-label")).toBe("打开菜单")
    expect(document.documentElement.style.overflow).toBe("auto")
  })

  it("opens modally once and repeated open/sync preserves the original overflow", async () => {
    await click(trigger)
    controller.open()
    controller.sync()
    expect(showModal).toHaveBeenCalledOnce()
    expect(panel.open).toBe(true)
    expect(panel.classList.contains("hidden")).toBe(false)
    expect(trigger.getAttribute("aria-expanded")).toBe("true")
    expect(trigger.getAttribute("aria-label")).toBe("关闭菜单")
    expect(document.documentElement.style.overflow).toBe("hidden")
    controller.close()
    expect(document.documentElement.style.overflow).toBe("auto")
  })

  it("closes natively once, restores trigger focus, and does not steal focus on repeated close", async () => {
    await click(trigger)
    panel.querySelector("a").focus()
    const focus = vi.spyOn(trigger, "focus")
    controller.close()
    controller.close()
    controller.sync()
    expect(closeDialog).toHaveBeenCalledOnce()
    expect(panel.open).toBe(false)
    expect(controller.opened).toBe(false)
    expect(trigger.getAttribute("aria-expanded")).toBe("false")
    expect(trigger.getAttribute("aria-label")).toBe("打开菜单")
    expect(document.documentElement.style.overflow).toBe("auto")
    expect(document.activeElement).toBe(trigger)
    expect(focus).toHaveBeenCalledOnce()
  })

  it("leaves native Escape to cancel, prevents its default, then closes and restores focus", async () => {
    await click(trigger)
    panel.querySelector("a").focus()
    panel.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))
    expect(controller.opened).toBe(true)
    expect(closeDialog).not.toHaveBeenCalled()
    const cancel = new Event("cancel", { cancelable: true })
    panel.dispatchEvent(cancel)
    expect(cancel.defaultPrevented).toBe(true)
    expect(closeDialog).toHaveBeenCalledOnce()
    expect(panel.open).toBe(false)
    expect(document.activeElement).toBe(trigger)
    expect(document.documentElement.style.overflow).toBe("auto")
  })

  it("dismisses only a click on the transparent dialog itself, not inner sheet or link clicks", async () => {
    await click(trigger)
    await click(panel.querySelector("div"))
    await click(panel.querySelector("a"))
    expect(controller.opened).toBe(true)
    expect(closeDialog).not.toHaveBeenCalled()
    await click(panel)
    expect(closeDialog).toHaveBeenCalledOnce()
    expect(panel.open).toBe(false)
    expect(document.activeElement).toBe(trigger)
    expect(document.documentElement.style.overflow).toBe("auto")
  })

  it("closes from the sheet close button even though its click bubbles to the dialog", async () => {
    await click(trigger)
    panel.querySelector("a").focus()
    await click(panel.querySelector("button"))
    expect(closeDialog).toHaveBeenCalledOnce()
    expect(panel.open).toBe(false)
    expect(document.activeElement).toBe(trigger)
    expect(document.documentElement.style.overflow).toBe("auto")
  })

  it("keeps the native sheet open on compact resize and closes/unlocks at desktop", async () => {
    await click(trigger)
    vi.spyOn(window, "matchMedia").mockReturnValue({ matches: false })
    window.dispatchEvent(new Event("resize"))
    expect(panel.open).toBe(true)
    window.matchMedia.mockReturnValue({ matches: true })
    window.dispatchEvent(new Event("resize"))
    expect(window.matchMedia).toHaveBeenCalledWith("(min-width: 1024px)")
    expect(panel.open).toBe(false)
    expect(controller.opened).toBe(false)
    expect(closeDialog).toHaveBeenCalledOnce()
    expect(document.documentElement.style.overflow).toBe("auto")
  })

  it("disconnect closes an open native modal, unlocks, resets state and removes global listeners", async () => {
    controller.open()
    const resize = vi.spyOn(controller, "close")
    const media = vi.spyOn(window, "matchMedia").mockReturnValue({ matches: true })
    element.removeAttribute("data-controller")
    await tick()
    expect(panel.open).toBe(false)
    expect(controller.opened).toBe(false)
    expect(closeDialog).toHaveBeenCalledOnce()
    expect(document.documentElement.style.overflow).toBe("auto")
    resize.mockClear()
    window.dispatchEvent(new Event("resize"))
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))
    expect(resize).not.toHaveBeenCalled()
    expect(media).not.toHaveBeenCalled()
  })

  it("also closes and unlocks when the entire open modal mount is removed", async () => {
    controller.open()
    element.remove()
    await tick()
    expect(panel.open).toBe(false)
    expect(closeDialog).toHaveBeenCalledOnce()
    expect(controller.opened).toBe(false)
    expect(document.documentElement.style.overflow).toBe("auto")
  })

  it("disconnect of an already closed native dialog leaves focus and overflow alone", async () => {
    trigger.focus()
    const focus = vi.spyOn(trigger, "focus")
    element.removeAttribute("data-controller")
    await tick()
    expect(controller.opened).toBe(false)
    expect(closeDialog).not.toHaveBeenCalled()
    expect(focus).not.toHaveBeenCalled()
    expect(document.documentElement.style.overflow).toBe("auto")
  })

  it.each(["showModal", "close"])("falls back to generic visibility and Escape behavior when %s is absent", (method) => {
    panel[method] = undefined
    controller.open()
    expect(panel.classList.contains("hidden")).toBe(false)
    expect(showModal).not.toHaveBeenCalled()
    expect(document.documentElement.style.overflow).toBe("hidden")
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))
    expect(controller.opened).toBe(false)
    expect(panel.classList.contains("hidden")).toBe(true)
    expect(closeDialog).not.toHaveBeenCalled()
    expect(document.documentElement.style.overflow).toBe("auto")
  })

  it("does not treat a generic div with similarly named methods as a native dialog", async () => {
    panel.replaceWith(document.createElement("div"))
    panel = element.querySelector("div")
    panel.setAttribute("data-website-nav-target", "panel")
    panel.showModal = showModal
    panel.close = closeDialog
    await tick()
    controller.open()
    expect(showModal).not.toHaveBeenCalled()
    expect(panel.classList.contains("hidden")).toBe(false)
    controller.close()
    expect(closeDialog).not.toHaveBeenCalled()
    expect(panel.classList.contains("hidden")).toBe(true)
  })
})
