import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/payments/qr_poll_controller"
import { mountController, controllerFor } from "../../support/stimulus.js"

const ID = "payments--qr-poll"
const html = () => `
  <div data-controller="${ID}"
       data-${ID}-status-url-value="/status"
       data-${ID}-result-url-value="/result">
    <span data-${ID}-target="status"></span>
  </div>`

const statusEl = (el) => el.querySelector(`[data-${ID}-target="status"]`)

describe("payments--qr-poll", () => {
  let originalLocation, setIntervalSpy, clearIntervalSpy
  beforeEach(() => {
    originalLocation = window.location
    global.fetch = vi.fn()
    // Prevent the 2s interval from ever really firing; we call poll() directly.
    setIntervalSpy = vi.spyOn(globalThis, "setInterval").mockReturnValue(777)
    clearIntervalSpy = vi.spyOn(globalThis, "clearInterval")
  })
  afterEach(() => {
    window.location = originalLocation
    vi.restoreAllMocks()
  })

  const mount = async () => {
    const { application, element } = await mountController(ID, Controller, html())
    return { application, element, controller: controllerFor(application, element, ID) }
  }

  it("schedules a 2s polling interval on connect", async () => {
    await mount()
    expect(setIntervalSpy).toHaveBeenCalledWith(expect.any(Function), 2000)
  })

  it("updates the status text and keeps polling on a non-terminal status", async () => {
    global.fetch.mockResolvedValue({ json: async () => ({ status: "pending" }) })
    const { element, controller } = await mount()
    clearIntervalSpy.mockClear()

    await controller.poll()

    expect(statusEl(element).textContent).toBe("Status: Pending")
    expect(clearIntervalSpy).not.toHaveBeenCalled()
    expect(String(window.location)).not.toBe("/result")
  })

  it.each(["succeeded", "failed", "closed"])(
    "stops the timer and redirects on terminal status %s",
    async (status) => {
      global.fetch.mockResolvedValue({ json: async () => ({ status }) })
      const { element, controller } = await mount()
      clearIntervalSpy.mockClear()

      await controller.poll()

      expect(statusEl(element).textContent).toBe(`Status: ${{ succeeded: "Succeeded", failed: "Failed", closed: "Closed" }[status]}`)
      expect(clearIntervalSpy).toHaveBeenCalledWith(777)
      expect(String(window.location)).toBe("/result")
    },
  )

  it("falls back to the raw status token when no localized label exists", async () => {
    global.fetch.mockResolvedValue({ json: async () => ({ status: "created" }) })
    const { element, controller } = await mount()
    clearIntervalSpy.mockClear()

    await controller.poll()

    expect(statusEl(element).textContent).toBe("Status: created")
    expect(clearIntervalSpy).not.toHaveBeenCalled()
  })

  it("clears the interval on disconnect", async () => {
    const { element } = await mount()
    clearIntervalSpy.mockClear()
    element.remove()
    await new Promise((r) => setTimeout(r, 0))
    expect(clearIntervalSpy).toHaveBeenCalledWith(777)
  })
})
