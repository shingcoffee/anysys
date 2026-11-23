import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/menu_placement_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

const html = `
  <div id="clipper" style="overflow: hidden; height: 120px;">
    <details data-controller="menu-placement" data-action="toggle->menu-placement#reposition">
      <summary>More</summary>
      <div data-menu-placement-target="panel" class="absolute right-0 mt-1">
        <a href="#">Preview</a>
      </div>
    </details>
  </div>`

function stubRect(el, rect) {
  el.getBoundingClientRect = () => ({ top: 0, bottom: 0, height: 0, left: 0, right: 0, width: 0, ...rect })
}

describe("menu-placement controller", () => {
  let details, panel, summary, application

  beforeEach(async () => {
    vi.stubGlobal("innerWidth", 1200)
    vi.stubGlobal("innerHeight", 800)
    const mounted = await mountController("menu-placement", Controller, html)
    details = mounted.element
    application = mounted.application
    panel = details.querySelector("[data-menu-placement-target='panel']")
    summary = details.querySelector("summary")
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    application?.stop()
  })

  function toggle(open) {
    details.open = open
    details.dispatchEvent(new Event("toggle"))
    return tick()
  }

  it("pins the menu with position:fixed below the trigger when it fits", async () => {
    stubRect(summary, { top: 100, bottom: 132, right: 1100, left: 1068, width: 32, height: 32 })
    stubRect(panel, { top: 136, bottom: 216, height: 80, width: 176, left: 924, right: 1100 })

    await toggle(true)

    expect(panel.style.position).toBe("fixed")
    expect(panel.style.top).toBe("136px") // 132 + 4
    expect(panel.style.bottom).toBe("auto")
    expect(panel.style.right).toBe("100px") // 1200 - 1100
    expect(panel.style.zIndex).toBe("50")
  })

  it("flips above the trigger when there is more room above than below", async () => {
    stubRect(summary, { top: 720, bottom: 752, right: 1100, left: 1068, width: 32, height: 32 })
    // First measure (below) overflows viewport
    stubRect(panel, { top: 756, bottom: 936, height: 180, width: 176, left: 924, right: 1100 })

    await toggle(true)

    expect(panel.style.position).toBe("fixed")
    expect(panel.style.top).toBe("auto")
    expect(panel.style.bottom).toBe("84px") // 800 - 720 + 4
  })

  it("clears fixed styles when the menu closes", async () => {
    stubRect(summary, { top: 100, bottom: 132, right: 1100, left: 1068, width: 32, height: 32 })
    stubRect(panel, { top: 136, bottom: 216, height: 80, width: 176, left: 924, right: 1100 })

    await toggle(true)
    expect(panel.style.position).toBe("fixed")

    await toggle(false)
    expect(panel.style.position).toBe("")
    expect(panel.style.top).toBe("")
    expect(panel.style.bottom).toBe("")
    expect(panel.style.right).toBe("")
    expect(panel.style.zIndex).toBe("")
  })

  it("does nothing when closed on first toggle", async () => {
    await toggle(false)
    expect(panel.style.position).toBe("")
  })

  it("closes when clicking outside the details element", async () => {
    stubRect(summary, { top: 100, bottom: 132, right: 1100, left: 1068, width: 32, height: 32 })
    stubRect(panel, { top: 136, bottom: 216, height: 80, width: 176, left: 924, right: 1100 })
    await toggle(true)
    expect(details.open).toBe(true)

    document.body.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    await tick()

    expect(details.open).toBe(false)
    expect(panel.style.position).toBe("")
  })

  it("does not close when clicking inside the details element", async () => {
    stubRect(summary, { top: 100, bottom: 132, right: 1100, left: 1068, width: 32, height: 32 })
    stubRect(panel, { top: 136, bottom: 216, height: 80, width: 176, left: 924, right: 1100 })
    await toggle(true)

    panel.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    await tick()

    expect(details.open).toBe(true)
    expect(panel.style.position).toBe("fixed")
  })

  it("repositions on window resize while open", async () => {
    stubRect(summary, { top: 100, bottom: 132, right: 1100, left: 1068, width: 32, height: 32 })
    stubRect(panel, { top: 136, bottom: 216, height: 80, width: 176, left: 924, right: 1100 })
    await toggle(true)

    stubRect(summary, { top: 100, bottom: 132, right: 1000, left: 968, width: 32, height: 32 })
    window.dispatchEvent(new Event("resize"))
    await tick()

    expect(panel.style.right).toBe("200px") // 1200 - 1000
  })

  it("tears down listeners and clears styles on disconnect", async () => {
    stubRect(summary, { top: 100, bottom: 132, right: 1100, left: 1068, width: 32, height: 32 })
    stubRect(panel, { top: 136, bottom: 216, height: 80, width: 176, left: 924, right: 1100 })
    await toggle(true)
    expect(panel.style.position).toBe("fixed")

    const controller = controllerFor(application, details, "menu-placement")
    controller.disconnect()

    expect(panel.style.position).toBe("")
  })

  it("keeps below placement when it overflows but there is not enough room above", async () => {
    stubRect(summary, { top: 40, bottom: 72, right: 1100, left: 1068, width: 32, height: 32 })
    stubRect(panel, { top: 76, bottom: 356, height: 280, width: 176, left: 924, right: 1100 })

    await toggle(true)

    expect(panel.style.top).toBe("76px")
    expect(panel.style.bottom).toBe("auto")
  })

  it("no-ops reposition when the panel target is missing", async () => {
    panel.removeAttribute("data-menu-placement-target")
    await toggle(true)
    expect(panel.style.position).toBe("")
  })

  it("clears styles safely when the panel target is removed before disconnect", async () => {
    stubRect(summary, { top: 100, bottom: 132, right: 1100, left: 1068, width: 32, height: 32 })
    stubRect(panel, { top: 136, bottom: 216, height: 80, width: 176, left: 924, right: 1100 })
    await toggle(true)
    expect(panel.style.position).toBe("fixed")

    panel.removeAttribute("data-menu-placement-target")
    const controller = controllerFor(application, details, "menu-placement")
    expect(() => controller.disconnect()).not.toThrow()
  })

  it("ignores outside-click handler when the menu is already closed", async () => {
    stubRect(summary, { top: 100, bottom: 132, right: 1100, left: 1068, width: 32, height: 32 })
    stubRect(panel, { top: 136, bottom: 216, height: 80, width: 176, left: 924, right: 1100 })
    await toggle(true)
    await toggle(false)

    const controller = controllerFor(application, details, "menu-placement")
    expect(() => {
      controller.boundCloseOnOutside({ target: document.body })
    }).not.toThrow()
    expect(details.open).toBe(false)
  })

  it("disconnects cleanly when never opened", async () => {
    const controller = controllerFor(application, details, "menu-placement")
    expect(() => controller.disconnect()).not.toThrow()
  })

  it("anchors to the details element when summary is absent", async () => {
    summary.remove()
    stubRect(details, { top: 100, bottom: 132, right: 1100, left: 1068, width: 32, height: 32 })
    stubRect(panel, { top: 136, bottom: 216, height: 80, width: 176, left: 924, right: 1100 })

    await toggle(true)

    expect(panel.style.position).toBe("fixed")
    expect(panel.style.top).toBe("136px")
  })
})
