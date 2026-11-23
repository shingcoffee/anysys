import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/payments/gateway_toggle_controller"
import { mountController, controllerFor } from "../../support/stimulus.js"

const ID = "payments--gateway-toggle"

const html = (currentState = "disabled") => `
  <div data-controller="${ID}"
       data-${ID}-url-value="/account"
       data-${ID}-current-state-value="${currentState}">
    <input type="checkbox" data-${ID}-target="toggle">
    <span data-${ID}-target="statusLabel">Disabled</span>
  </div>`

const mount = async (currentState) => {
  const { application, element } = await mountController(ID, Controller, html(currentState))
  return { application, element, controller: controllerFor(application, element, ID) }
}
const toggleEl = (el) => el.querySelector(`[data-${ID}-target="toggle"]`)
const labelEl = (el) => el.querySelector(`[data-${ID}-target="statusLabel"]`)

describe("payments--gateway-toggle", () => {
  beforeEach(() => {
    global.fetch = vi.fn()
    document.head.innerHTML = '<meta name="csrf-token" content="tok-xyz">'
  })
  afterEach(() => {
    vi.restoreAllMocks()
    document.head.innerHTML = ""
  })

  it("PATCHes status:active and updates the label/state when toggled on", async () => {
    global.fetch.mockResolvedValue({ ok: true })
    const { element, controller } = await mount("disabled")

    toggleEl(element).checked = true
    await controller.toggle()

    expect(labelEl(element).textContent).toBe("Enabled")
    expect(controller.currentStateValue).toBe("active")
    expect(global.fetch).toHaveBeenCalledWith("/account", expect.objectContaining({
      method: "PATCH",
      headers: expect.objectContaining({ "X-CSRF-Token": "tok-xyz" }),
      body: JSON.stringify({ payment_merchant_account: { status: "active" } }),
    }))
  })

  it("PATCHes status:disabled when toggled off", async () => {
    global.fetch.mockResolvedValue({ ok: true })
    const { element, controller } = await mount("active")

    toggleEl(element).checked = false
    await controller.toggle()

    expect(labelEl(element).textContent).toBe("Disabled")
    expect(controller.currentStateValue).toBe("disabled")
    expect(global.fetch).toHaveBeenCalledWith("/account", expect.objectContaining({
      body: JSON.stringify({ payment_merchant_account: { status: "disabled" } }),
    }))
  })

  it("reverts optimistic UI when the server responds non-ok", async () => {
    const err = vi.spyOn(console, "error").mockImplementation(() => {})
    global.fetch.mockResolvedValue({ ok: false, status: 500 })
    const { element, controller } = await mount("disabled")

    toggleEl(element).checked = true
    await controller.toggle()

    // reverted to the stored baseline ("disabled")
    expect(controller.currentStateValue).toBe("disabled")
    expect(toggleEl(element).checked).toBe(false)
    expect(labelEl(element).textContent).toBe("Disabled")
    expect(err).toHaveBeenCalled()
    err.mockRestore()
  })

  it("sends an empty CSRF token when no csrf-token meta tag is present", async () => {
    document.head.innerHTML = "" // no meta tag
    global.fetch.mockResolvedValue({ ok: true })
    const { element, controller } = await mount("disabled")

    toggleEl(element).checked = true
    await controller.toggle()

    expect(global.fetch).toHaveBeenCalledWith("/account", expect.objectContaining({
      headers: expect.objectContaining({ "X-CSRF-Token": "" }),
    }))
  })

  it("reverts when fetch itself rejects", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {})
    global.fetch.mockRejectedValue(new Error("network"))
    const { element, controller } = await mount("active")

    toggleEl(element).checked = false
    await controller.toggle()

    // baseline was "active" -> checkbox re-checked, label back to Enabled
    expect(controller.currentStateValue).toBe("active")
    expect(toggleEl(element).checked).toBe(true)
    expect(labelEl(element).textContent).toBe("Enabled")
  })
})
