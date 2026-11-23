import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/payments/paypal_buttons_controller"
import { mountController, controllerFor } from "../../support/stimulus.js"

const ID = "payments--paypal-buttons"
const html = ({ clientId = "CID", orderId = "ORDER-1" } = {}) => `
  <div data-controller="${ID}"
       data-${ID}-client-id-value="${clientId}"
       data-${ID}-paypal-order-id-value="${orderId}"
       data-${ID}-currency-value="USD"
       data-${ID}-result-url-value="/result"
       data-${ID}-status-url-value="/status">
    <div data-${ID}-target="element"></div>
    <p data-${ID}-target="error" class="hidden"></p>
  </div>`

const errorEl = (el) => el.querySelector(`[data-${ID}-target="error"]`)

// Capture the config passed to paypal.Buttons() so we can drive its callbacks.
let buttonsConfig, renderSpy
const installPaypal = () => {
  renderSpy = vi.fn()
  window.paypal = {
    Buttons: vi.fn((config) => {
      buttonsConfig = config
      return { render: renderSpy }
    }),
  }
}

describe("payments--paypal-buttons", () => {
  let originalLocation
  beforeEach(() => {
    originalLocation = window.location
    global.fetch = vi.fn().mockResolvedValue({ ok: true })
    buttonsConfig = undefined
  })
  afterEach(() => {
    window.location = originalLocation
    delete window.paypal
    document.head.innerHTML = ""
    vi.restoreAllMocks()
  })

  it("renders nothing when clientId is blank", async () => {
    installPaypal()
    await mountController(ID, Controller, html({ clientId: "" }))
    expect(window.paypal.Buttons).not.toHaveBeenCalled()
  })

  it("renders Smart Buttons into the element target when the SDK is present", async () => {
    installPaypal()
    const { element } = await mountController(ID, Controller, html())
    expect(window.paypal.Buttons).toHaveBeenCalledOnce()
    expect(renderSpy).toHaveBeenCalledWith(element.querySelector(`[data-${ID}-target="element"]`))
  })

  it("createOrder returns the server-created order id", async () => {
    installPaypal()
    await mountController(ID, Controller, html({ orderId: "ORDER-42" }))
    expect(buttonsConfig.createOrder()).toBe("ORDER-42")
  })

  it("onApprove hits the status endpoint then redirects to the result url", async () => {
    installPaypal()
    const { element } = await mountController(ID, Controller, html())
    await buttonsConfig.onApprove()
    expect(global.fetch).toHaveBeenCalledWith("/status", expect.objectContaining({
      headers: { Accept: "application/json" },
    }))
    expect(errorEl(element).classList.contains("hidden")).toBe(true)
    expect(String(window.location)).toBe("/result")
  })

  it("onApprove still redirects even if the status fetch fails", async () => {
    installPaypal()
    global.fetch.mockRejectedValue(new Error("down"))
    await mountController(ID, Controller, html())
    await buttonsConfig.onApprove()
    expect(String(window.location)).toBe("/result")
  })

  it("onCancel shows a cancellation message", async () => {
    installPaypal()
    const { element } = await mountController(ID, Controller, html())
    buttonsConfig.onCancel()
    expect(errorEl(element).textContent).toContain("Payment cancelled")
    expect(errorEl(element).classList.contains("hidden")).toBe(false)
  })

  it("onError shows a generic error message", async () => {
    installPaypal()
    const { element } = await mountController(ID, Controller, html())
    buttonsConfig.onError()
    expect(errorEl(element).textContent).toContain("Something went wrong with PayPal")
  })

  it("onCancel/onApprove tolerate a missing error target", async () => {
    installPaypal()
    const htmlNoError = `
      <div data-controller="${ID}"
           data-${ID}-client-id-value="CID"
           data-${ID}-paypal-order-id-value="ORDER-1"
           data-${ID}-currency-value="USD"
           data-${ID}-result-url-value="/result"
           data-${ID}-status-url-value="/status">
        <div data-${ID}-target="element"></div>
      </div>`
    await mountController(ID, Controller, htmlNoError)
    expect(() => buttonsConfig.onCancel()).not.toThrow()
    await expect(buttonsConfig.onApprove()).resolves.toBeUndefined()
  })

  it("shows an SDK load error when the injected script fails", async () => {
    // window.paypal absent -> _loadPayPalSdk injects a <script>; fire its onerror.
    const appendSpy = vi.spyOn(document.head, "appendChild").mockImplementation((node) => {
      Promise.resolve().then(() => node.onerror(new Event("error")))
      return node
    })
    const { application, element } = await mountController(ID, Controller, html())
    // allow the rejected SDK promise + catch to settle
    await new Promise((r) => setTimeout(r, 0))

    expect(errorEl(element).textContent).toContain("Could not load the PayPal SDK")
    appendSpy.mockRestore()
    application.stop()
  })

  it("loads the SDK by injecting a script and renders on load success", async () => {
    let injected
    const appendSpy = vi.spyOn(document.head, "appendChild").mockImplementation((node) => {
      injected = node
      // Simulate the browser finishing the download, then expose window.paypal.
      Promise.resolve().then(() => { installPaypal(); node.onload() })
      return node
    })
    await mountController(ID, Controller, html())
    await new Promise((r) => setTimeout(r, 0))

    expect(injected.src).toContain("https://www.paypal.com/sdk/js")
    expect(injected.src).toContain("client-id=CID")
    expect(injected.src).toContain("currency=USD")
    expect(injected.src).toContain("intent=capture")
    expect(window.paypal.Buttons).toHaveBeenCalled()
    appendSpy.mockRestore()
  })
})
