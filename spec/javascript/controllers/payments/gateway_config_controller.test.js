import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/payments/gateway_config_controller"
import { mountController, controllerFor } from "../../support/stimulus.js"

const ID = "payments--gateway-config"

const html = ({ withResult = true, withButton = true } = {}) => `
  <form data-controller="${ID}" data-${ID}-test-url-value="/test-connection">
    ${withButton ? `<button data-${ID}-target="testButton">Test</button>` : ""}
    ${withResult ? `<div data-${ID}-target="result"></div>` : ""}
    <span data-${ID}-target="lastVerified"></span>
  </form>`

const mount = async (opts) => {
  const { application, element } = await mountController(ID, Controller, html(opts))
  return { application, element, controller: controllerFor(application, element, ID) }
}
const resultEl = (el) => el.querySelector(`[data-${ID}-target="result"]`)
const buttonEl = (el) => el.querySelector(`[data-${ID}-target="testButton"]`)

describe("payments--gateway-config", () => {
  beforeEach(() => {
    global.fetch = vi.fn()
    document.head.innerHTML = '<meta name="csrf-token" content="tok-123">'
  })
  afterEach(() => {
    vi.restoreAllMocks()
    document.head.innerHTML = ""
  })

  it("returns early (no fetch) when there is no result target", async () => {
    const { controller } = await mount({ withResult: false })
    await controller.testConnection()
    expect(global.fetch).not.toHaveBeenCalled()
  })

  it("shows the loading state and disables the button before the request resolves", async () => {
    let resolve
    global.fetch.mockReturnValue(new Promise((r) => { resolve = r }))
    const { element, controller } = await mount()

    const p = controller.testConnection()
    // synchronous work up to the first await already ran
    expect(resultEl(element).innerHTML).toContain("Testing connection")
    expect(buttonEl(element).disabled).toBe(true)

    resolve({ json: async () => ({ ok: true }) })
    await p
    expect(buttonEl(element).disabled).toBe(false)
  })

  it("POSTs to the test URL with the CSRF token header", async () => {
    global.fetch.mockResolvedValue({ json: async () => ({ ok: true }) })
    const { controller } = await mount()
    await controller.testConnection()

    expect(global.fetch).toHaveBeenCalledWith("/test-connection", expect.objectContaining({
      method: "POST",
      headers: expect.objectContaining({ "X-CSRF-Token": "tok-123", Accept: "application/json" }),
    }))
  })

  it("renders the success state with a formatted verified_at timestamp and message", async () => {
    global.fetch.mockResolvedValue({
      json: async () => ({
        ok: true,
        message: "All good",
        verified_at: "2026-07-07T10:30:00Z",
        verified_at_label: "July 07, 2026 10:30",
      }),
    })
    const { element, controller } = await mount()
    await controller.testConnection()

    const html = resultEl(element).innerHTML
    expect(html).toContain("Connection verified")
    expect(html).toContain("Last verified: July 07, 2026 10:30")
    expect(html).not.toContain(" UTC")
    expect(html).toContain("All good")
    expect(resultEl(element).className).toContain("bg-success-subtle")
  })

  it("falls back to a locale-aware UTC format when verified_at_label is absent", async () => {
    global.fetch.mockResolvedValue({
      json: async () => ({ ok: true, verified_at: "2026-07-07T10:30:00Z" }),
    })
    const { element, controller } = await mount()
    await controller.testConnection()

    const expected = new Intl.DateTimeFormat(undefined, {
      year: "numeric",
      month: "long",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
      timeZone: "UTC"
    }).format(new Date("2026-07-07T10:30:00Z"))

    const html = resultEl(element).innerHTML
    expect(html).toContain(`Last verified: ${expected}`)
    expect(html).not.toContain("2026-07-07 10:30 UTC")
  })

  it("renders the error state when the server reports ok:false", async () => {
    global.fetch.mockResolvedValue({ json: async () => ({ ok: false, message: "Bad key" }) })
    const { element, controller } = await mount()
    await controller.testConnection()

    expect(resultEl(element).innerHTML).toContain("Connection failed")
    expect(resultEl(element).innerHTML).toContain("Bad key")
    expect(resultEl(element).className).toContain("bg-danger-subtle")
  })

  it("falls back to a default message when ok:false has no message", async () => {
    global.fetch.mockResolvedValue({ json: async () => ({ ok: false }) })
    const { element, controller } = await mount()
    await controller.testConnection()
    expect(resultEl(element).innerHTML).toContain("Connection test failed.")
  })

  it("renders a network error when fetch rejects", async () => {
    global.fetch.mockRejectedValue(new Error("boom"))
    const { element, controller } = await mount()
    await controller.testConnection()
    expect(resultEl(element).innerHTML).toContain("Request failed")
    expect(buttonEl(element).disabled).toBe(false)
  })

  it("HTML-escapes an untrusted verified_at_label", async () => {
    global.fetch.mockResolvedValue({
      json: async () => ({ ok: true, verified_at_label: '<img src=x onerror="alert(1)">' }),
    })
    const { element, controller } = await mount()
    await controller.testConnection()
    const html = resultEl(element).innerHTML
    expect(html).toContain("&lt;img")
    expect(html).not.toContain("<img src=x")
  })

  it("HTML-escapes untrusted message text", async () => {
    global.fetch.mockResolvedValue({
      json: async () => ({ ok: false, message: '<img src=x onerror="alert(1)">' }),
    })
    const { element, controller } = await mount()
    await controller.testConnection()
    const html = resultEl(element).innerHTML
    expect(html).toContain("&lt;img")
    expect(html).not.toContain("<img src=x")
  })

  it("sends an empty CSRF token when no csrf-token meta tag is present", async () => {
    document.head.innerHTML = "" // no meta tag
    global.fetch.mockResolvedValue({ json: async () => ({ ok: true }) })
    const { controller } = await mount()
    await controller.testConnection()

    expect(global.fetch).toHaveBeenCalledWith("/test-connection", expect.objectContaining({
      headers: expect.objectContaining({ "X-CSRF-Token": "" }),
    }))
  })

  it("falls back to the escaped raw string when verified_at cannot be parsed as a date", async () => {
    global.fetch.mockResolvedValue({
      json: async () => ({ ok: true, verified_at: "<not-a-date>" }),
    })
    const { element, controller } = await mount()
    await controller.testConnection()

    const html = resultEl(element).innerHTML
    expect(html).toContain("Last verified: &lt;not-a-date&gt;")
  })

  it("works without a testButton target (optional)", async () => {
    global.fetch.mockResolvedValue({ json: async () => ({ ok: true }) })
    const { element, controller } = await mount({ withButton: false })
    await controller.testConnection()
    expect(resultEl(element).innerHTML).toContain("Connection verified")
  })
})
