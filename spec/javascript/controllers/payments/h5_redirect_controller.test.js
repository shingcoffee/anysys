import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/payments/h5_redirect_controller"
import { mountController } from "../../support/stimulus.js"

const ID = "payments--h5-redirect"
const html = (url) => `<div data-controller="${ID}" data-${ID}-url-value="${url}"></div>`

// The redirect fires from a 300ms setTimeout. We spy on setTimeout (pass-through)
// so we can drive the scheduled callback deterministically instead of waiting
// real wall-clock time — mountController itself relies on setTimeout, so we keep
// the original implementation.
describe("payments--h5-redirect", () => {
  let originalLocation, setTimeoutSpy
  beforeEach(() => {
    originalLocation = window.location
    setTimeoutSpy = vi.spyOn(globalThis, "setTimeout")
  })
  afterEach(() => {
    window.location = originalLocation
    vi.restoreAllMocks()
  })

  const scheduledRedirect = () =>
    setTimeoutSpy.mock.calls.find(([, delay]) => delay === 300)

  it("does not navigate immediately on connect (waits for the 300ms delay)", async () => {
    await mountController(ID, Controller, html("https://psp.example/pay"))
    expect(String(window.location)).not.toBe("https://psp.example/pay")
    expect(scheduledRedirect()).toBeTruthy()
  })

  it("navigates to the url value once the delayed callback runs", async () => {
    await mountController(ID, Controller, html("https://psp.example/pay/abc"))
    const [cb] = scheduledRedirect()
    cb()
    expect(String(window.location)).toBe("https://psp.example/pay/abc")
  })
})
