// NOTE: happy-dom reports `offsetWidth` as 0 by default. For handleTouchMove's
// swipe math we stub `offsetWidth` (per COVERAGE_100_BRIEF's guidance) so the
// drag-left branch exercises real, non-zero geometry instead of asserting on
// zeros. We cover open()/close() state transitions and the touch-start/move/end
// wiring. Every assertion after an rAF/setTimeout awaits a tick to stay
// deterministic.
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/drawer_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

const html = `
  <div data-controller="drawer">
    <div data-drawer-target="backdrop" class="hidden"></div>
    <div data-drawer-target="panel" class="-translate-x-full"></div>
  </div>`

const panel = (el) => el.querySelector("[data-drawer-target='panel']")
const backdrop = (el) => el.querySelector("[data-drawer-target='backdrop']")

describe("drawer controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element } = await mountController("drawer", Controller, html))
    ctrl = controllerFor(application, element, "drawer")
  })
  afterEach(() => {
    document.body.style.overflow = ""
    vi.useRealTimers()
  })

  describe("open", () => {
    it("locks body scroll and reveals the backdrop immediately", () => {
      ctrl.open()
      expect(document.body.style.overflow).toBe("hidden")
      expect(backdrop(element).classList.contains("hidden")).toBe(false)
    })

    it("animates panel + backdrop in on the next frame", async () => {
      ctrl.open()
      await tick() // requestAnimationFrame is stubbed to a macrotask in setup.js
      expect(backdrop(element).style.opacity).toBe("1")
      expect(panel(element).classList.contains("translate-x-0")).toBe(true)
      expect(panel(element).classList.contains("-translate-x-full")).toBe(false)
    })
  })

  describe("close", () => {
    it("applies the closing state synchronously", async () => {
      ctrl.open()
      await tick()
      ctrl.close()
      expect(document.body.style.overflow).toBe("")
      expect(backdrop(element).style.opacity).toBe("0")
      expect(panel(element).classList.contains("-translate-x-full")).toBe(true)
      expect(panel(element).classList.contains("translate-x-0")).toBe(false)
      expect(panel(element).style.transform).toBe("")
    })

    it("hides the backdrop after the 300ms transition", () => {
      ctrl.open() // synchronously removes `hidden` from the backdrop
      vi.useFakeTimers()
      ctrl.close()
      expect(backdrop(element).classList.contains("hidden")).toBe(false)
      vi.advanceTimersByTime(300)
      expect(backdrop(element).classList.contains("hidden")).toBe(true)
    })
  })

  describe("touch gestures (non-geometry parts)", () => {
    const touchEvent = (type, x) => {
      const e = new Event(type, { bubbles: true, cancelable: true })
      Object.defineProperty(e, "touches", { value: [{ clientX: x }] })
      return e
    }

    it("touchstart records the start position and freezes the transition", () => {
      panel(element).dispatchEvent(touchEvent("touchstart", 200))
      expect(ctrl.isDragging).toBe(true)
      expect(ctrl.touchStartX).toBe(200)
      expect(panel(element).style.transition).toBe("none")
    })

    it("touchend without an active drag is a no-op", () => {
      ctrl.isDragging = false
      expect(() => panel(element).dispatchEvent(touchEvent("touchend", 0))).not.toThrow()
    })

    it("touchend that did not cross the threshold snaps the panel back open", () => {
      panel(element).dispatchEvent(touchEvent("touchstart", 100))
      // No move dispatched, so touchCurrentX == touchStartX; diff 0 is not < -threshold.
      panel(element).dispatchEvent(touchEvent("touchend", 100))
      expect(ctrl.isDragging).toBe(false)
      expect(panel(element).style.transform).toBe("")
      expect(backdrop(element).style.opacity).toBe("1")
    })

    it("touchend past the close threshold closes the drawer", () => {
      // Stub offsetWidth (0 in happy-dom) so threshold = offsetWidth * 0.3 is non-zero.
      Object.defineProperty(panel(element), "offsetWidth", { value: 300, configurable: true })
      panel(element).dispatchEvent(touchEvent("touchstart", 200))
      ctrl.touchCurrentX = 0 // diff = -200, past the -90 (300*0.3) threshold
      const closeSpy = vi.spyOn(ctrl, "close")
      panel(element).dispatchEvent(touchEvent("touchend", 0))
      expect(closeSpy).toHaveBeenCalledOnce()
    })

    it("touchmove while dragging left translates the panel and fades the backdrop", () => {
      Object.defineProperty(panel(element), "offsetWidth", { value: 200, configurable: true })
      panel(element).dispatchEvent(touchEvent("touchstart", 200))
      const moveEvent = touchEvent("touchmove", 150) // diff = -50, dragging left
      const preventDefault = vi.spyOn(moveEvent, "preventDefault")
      panel(element).dispatchEvent(moveEvent)
      expect(preventDefault).toHaveBeenCalledOnce()
      expect(panel(element).style.transform).toBe("translateX(-50px)")
      expect(backdrop(element).style.opacity).toBe(String(1 - (50 / 200) * 0.5))
    })

    it("touchmove clamps the translate to -offsetWidth when dragged past the panel width", () => {
      Object.defineProperty(panel(element), "offsetWidth", { value: 100, configurable: true })
      panel(element).dispatchEvent(touchEvent("touchstart", 500))
      panel(element).dispatchEvent(touchEvent("touchmove", 0)) // diff = -500, clamps to -100
      expect(panel(element).style.transform).toBe("translateX(-100px)")
    })

    it("touchmove while dragging right (diff >= 0) does not translate the panel", () => {
      Object.defineProperty(panel(element), "offsetWidth", { value: 200, configurable: true })
      panel(element).dispatchEvent(touchEvent("touchstart", 100))
      const moveEvent = touchEvent("touchmove", 150) // diff = +50, dragging right
      const preventDefault = vi.spyOn(moveEvent, "preventDefault")
      panel(element).dispatchEvent(moveEvent)
      expect(preventDefault).not.toHaveBeenCalled()
      expect(panel(element).style.transform).toBe("")
    })

    it("touchmove without an active drag is a no-op", () => {
      ctrl.isDragging = false
      expect(() => panel(element).dispatchEvent(touchEvent("touchmove", 50))).not.toThrow()
      expect(panel(element).style.transform).toBe("")
    })
  })

  it("removes touch listeners on disconnect (no throw after teardown)", async () => {
    const p = panel(element)
    element.remove()
    await tick() // let Stimulus' MutationObserver fire disconnect()
    const e = new Event("touchstart", { bubbles: true })
    Object.defineProperty(e, "touches", { value: [{ clientX: 0 }] })
    ctrl.isDragging = false
    expect(() => p.dispatchEvent(e)).not.toThrow()
    expect(ctrl.isDragging).toBe(false) // handler no longer wired
  })
})
