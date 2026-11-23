import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/oauth_native_handoff_controller"
import { mountController } from "../support/stimulus.js"

const ID = "oauth-native-handoff"
const html = (url) =>
  `<div data-controller="${ID}" data-${ID}-url-value="${url}"></div>`

describe("oauth-native-handoff", () => {
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
    await mountController(ID, Controller, html("http://127.0.0.1:8765/callback?code=a"))
    expect(String(window.location)).not.toContain("127.0.0.1")
    expect(scheduledRedirect()).toBeTruthy()
  })

  it("navigates to the url value once the delayed callback runs", async () => {
    await mountController(ID, Controller, html("http://127.0.0.1:8765/callback?code=abc"))
    const [cb] = scheduledRedirect()
    cb()
    expect(String(window.location)).toBe("http://127.0.0.1:8765/callback?code=abc")
  })

  it("does not schedule a redirect when the url value is empty", async () => {
    await mountController(ID, Controller, html(""))
    expect(scheduledRedirect()).toBeUndefined()
  })
})
