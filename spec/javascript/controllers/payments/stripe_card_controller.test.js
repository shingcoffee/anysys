import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/payments/stripe_card_controller"
import { mountController, controllerFor } from "../../support/stimulus.js"
import { loadStripeJs } from "lib/stripe_js_loader"

// The shared loader has its own dedicated spec (spec/javascript/lib/stripe_js_loader.test.js)
// covering script injection, memoization and retry. Here we only care how this
// controller reacts to it resolving/rejecting.
vi.mock("lib/stripe_js_loader", () => ({ loadStripeJs: vi.fn() }))

const ID = "payments--stripe-card"

const html = ({
  pk = "pk_test", clientSecret, resultUrl, setupIntentUrl, createUrl,
  billingSetup = false, requestKey, setupClientSecret, confirmationUrl,
  unavailableText = "Stripe unavailable", withElement = true, withError = true,
} = {}) => `
  <div data-controller="${ID}"
       data-${ID}-publishable-key-value="${pk}"
       ${clientSecret ? `data-${ID}-client-secret-value="${clientSecret}"` : ""}
       ${resultUrl ? `data-${ID}-result-url-value="${resultUrl}"` : ""}
       ${setupIntentUrl ? `data-${ID}-setup-intent-url-value="${setupIntentUrl}"` : ""}
        ${createUrl ? `data-${ID}-create-url-value="${createUrl}"` : ""}
        data-${ID}-billing-setup-value="${billingSetup}"
        ${requestKey ? `data-${ID}-request-key-value="${requestKey}"` : ""}
        ${setupClientSecret ? `data-${ID}-setup-client-secret-value="${setupClientSecret}"` : ""}
        ${confirmationUrl ? `data-${ID}-confirmation-url-value="${confirmationUrl}"` : ""}
       data-${ID}-unavailable-text-value="${unavailableText}">
    ${withElement ? `<div data-${ID}-target="element"></div>` : ""}
    ${withError ? `<p data-${ID}-target="error" class="hidden"></p>` : ""}
    <button data-action="click->${ID}#submit">Save card</button>
  </div>`

const errorEl = (el) => el.querySelector(`[data-${ID}-target="error"]`)
const buttonEl = (el) => el.querySelector("button")

// ── Stripe.js mock ──────────────────────────────────────────────────────────
let paymentElement, elementsInstance, stripeInstance
const installStripe = () => {
  paymentElement = { mount: vi.fn(), unmount: vi.fn() }
  elementsInstance = {
    create: vi.fn(() => paymentElement),
    getElement: vi.fn(() => paymentElement),
  }
  stripeInstance = {
    elements: vi.fn(() => elementsInstance),
    confirmPayment: vi.fn().mockResolvedValue({ error: null }),
    confirmSetup: vi.fn().mockResolvedValue({ setupIntent: { payment_method: "pm_1" }, error: null }),
  }
  window.Stripe = vi.fn(() => stripeInstance)
}

const mount = async (opts) => {
  const { application, element } = await mountController(ID, Controller, html(opts))
  return { application, element, controller: controllerFor(application, element, ID) }
}

describe("payments--stripe-card", () => {
  let originalLocation
  beforeEach(() => {
    originalLocation = window.location
    installStripe()
    global.fetch = vi.fn()
    document.head.innerHTML = '<meta name="csrf-token" content="tok-s">'
    loadStripeJs.mockReset()
    loadStripeJs.mockResolvedValue(undefined)
  })
  afterEach(() => {
    window.location = originalLocation
    delete window.Stripe
    document.head.innerHTML = ""
    vi.restoreAllMocks()
  })

  it("does nothing on connect without a publishable key", async () => {
    await mount({ pk: "" })
    expect(window.Stripe).not.toHaveBeenCalled()
  })

  describe("Mode A — checkout (PaymentIntent)", () => {
    it("mounts the Payment Element from the client_secret on connect", async () => {
      const { element, controller } = await mount({ clientSecret: "cs_1", resultUrl: "/done" })
      expect(window.Stripe).toHaveBeenCalledWith("pk_test")
      expect(stripeInstance.elements).toHaveBeenCalledWith({ clientSecret: "cs_1" })
      expect(elementsInstance.create).toHaveBeenCalledWith("payment")
      expect(paymentElement.mount).toHaveBeenCalledWith(
        element.querySelector(`[data-${ID}-target="element"]`),
      )
      expect(controller.elements).toBe(elementsInstance)
    })

    it("confirms the payment on submit with the result url as return_url", async () => {
      const { element, controller } = await mount({ clientSecret: "cs_1", resultUrl: "/done" })
      await controller.submit()
      expect(stripeInstance.confirmPayment).toHaveBeenCalledWith({
        elements: elementsInstance,
        confirmParams: { return_url: "/done" },
      })
      expect(errorEl(element).classList.contains("hidden")).toBe(true)
    })

    it("shows the Stripe error message when confirmPayment fails", async () => {
      stripeInstance.confirmPayment.mockResolvedValue({ error: { message: "Card declined" } })
      const { element, controller } = await mount({ clientSecret: "cs_1", resultUrl: "/done" })
      await controller.submit()
      expect(errorEl(element).textContent).toBe("Card declined")
      expect(errorEl(element).classList.contains("hidden")).toBe(false)
    })

    it("toggles submit buttons to a loading state during submit", async () => {
      let resolveConfirm
      stripeInstance.confirmPayment.mockReturnValue(new Promise((r) => { resolveConfirm = r }))
      const { element, controller } = await mount({ clientSecret: "cs_1", resultUrl: "/done" })

      const p = controller.submit()
      expect(buttonEl(element).disabled).toBe(true)
      expect(buttonEl(element).textContent).toBe("Processing…")

      resolveConfirm({ error: null })
      await p
      expect(buttonEl(element).disabled).toBe(false)
    })

    it("unmounts the Payment Element on disconnect", async () => {
      const { element } = await mount({ clientSecret: "cs_1", resultUrl: "/done" })
      element.remove()
      await new Promise((r) => setTimeout(r, 0))
      expect(paymentElement.unmount).toHaveBeenCalled()
    })

    it("disconnect is a no-op when getElement returns nothing to unmount", async () => {
      elementsInstance.getElement.mockReturnValue(undefined)
      const { element } = await mount({ clientSecret: "cs_1", resultUrl: "/done" })
      expect(() => element.remove()).not.toThrow()
      await new Promise((r) => setTimeout(r, 0))
      expect(paymentElement.unmount).not.toHaveBeenCalled()
    })

    it("disconnect swallows an error thrown while unmounting", async () => {
      paymentElement.unmount.mockImplementation(() => { throw new Error("already gone") })
      const { element } = await mount({ clientSecret: "cs_1", resultUrl: "/done" })
      expect(() => element.remove()).not.toThrow()
      await new Promise((r) => setTimeout(r, 0))
      expect(paymentElement.unmount).toHaveBeenCalled()
    })

    it("falls back to a default message when the Stripe error has no message", async () => {
      stripeInstance.confirmPayment.mockResolvedValue({ error: { message: "" } })
      const { element, controller } = await mount({ clientSecret: "cs_1", resultUrl: "/done" })
      await controller.submit()
      expect(errorEl(element).textContent).toBe("An unexpected error occurred. Please try again.")
    })

    it("_mountElement tolerates a missing element target", async () => {
      const htmlNoElement = `
        <div data-controller="${ID}"
             data-${ID}-publishable-key-value="pk_test"
             data-${ID}-client-secret-value="cs_1"
             data-${ID}-result-url-value="/done">
          <p data-${ID}-target="error" class="hidden"></p>
          <button data-action="click->${ID}#submit">Save card</button>
        </div>`
      await mountController(ID, Controller, htmlNoElement)
      expect(elementsInstance.create).not.toHaveBeenCalled()
    })

    it("submit tolerates a missing error target", async () => {
      const htmlNoError = `
        <div data-controller="${ID}"
             data-${ID}-publishable-key-value="pk_test"
             data-${ID}-client-secret-value="cs_1"
             data-${ID}-result-url-value="/done">
          <div data-${ID}-target="element"></div>
          <button data-action="click->${ID}#submit">Save card</button>
        </div>`
      stripeInstance.confirmPayment.mockResolvedValue({ error: { message: "Card declined" } })
      const { application, element } = await mountController(ID, Controller, htmlNoError)
      const controller = controllerFor(application, element, ID)
      await expect(controller.submit()).resolves.toBeUndefined()
    })
  })

  describe("Mode B — vault (SetupIntent)", () => {
    const vaultOpts = { setupIntentUrl: "/si", createUrl: "/cards" }

    beforeEach(() => {
      // _vaultCard reads window.location.href and calls reload()
      window.location = { href: "http://test/vault", reload: vi.fn() }
    })

    it("runs the full happy path: SetupIntent → confirmSetup → save → reload", async () => {
      global.fetch
        .mockResolvedValueOnce({ ok: true, json: async () => ({ client_secret: "cs_setup" }) })
        .mockResolvedValueOnce({ ok: true, json: async () => ({}) })

      const { controller } = await mount(vaultOpts)
      await controller.submit()

      expect(global.fetch).toHaveBeenNthCalledWith(1, "/si", expect.objectContaining({ method: "POST" }))
      // Payment Element mounted lazily with the fetched secret
      expect(stripeInstance.elements).toHaveBeenCalledWith({ clientSecret: "cs_setup" })
      expect(stripeInstance.confirmSetup).toHaveBeenCalled()
      expect(global.fetch).toHaveBeenNthCalledWith(2, "/cards", expect.objectContaining({
        method: "POST",
        body: JSON.stringify({ payment_method_id: "pm_1" }),
      }))
      expect(window.location.reload).toHaveBeenCalled()
    })

    it("errors when the SetupIntent request is not ok", async () => {
      global.fetch.mockResolvedValueOnce({ ok: false, status: 422 })
      const { element, controller } = await mount(vaultOpts)
      await controller.submit()
      expect(errorEl(element).textContent).toContain("Failed to create SetupIntent (422)")
    })

    it("errors when no client_secret is returned", async () => {
      global.fetch.mockResolvedValueOnce({ ok: true, json: async () => ({}) })
      const { element, controller } = await mount(vaultOpts)
      await controller.submit()
      expect(errorEl(element).textContent).toContain("Server did not return a client_secret")
    })

    it("surfaces a confirmSetup error", async () => {
      global.fetch.mockResolvedValueOnce({ ok: true, json: async () => ({ client_secret: "cs_setup" }) })
      stripeInstance.confirmSetup.mockResolvedValue({ error: { message: "3DS failed" } })
      const { element, controller } = await mount(vaultOpts)
      await controller.submit()
      expect(errorEl(element).textContent).toBe("3DS failed")
    })

    it("errors when confirmSetup returns no payment_method", async () => {
      global.fetch.mockResolvedValueOnce({ ok: true, json: async () => ({ client_secret: "cs_setup" }) })
      stripeInstance.confirmSetup.mockResolvedValue({ setupIntent: {}, error: null })
      const { element, controller } = await mount(vaultOpts)
      await controller.submit()
      expect(errorEl(element).textContent).toContain("did not return a payment_method id")
    })

    it("surfaces the server error body when the save call fails", async () => {
      global.fetch
        .mockResolvedValueOnce({ ok: true, json: async () => ({ client_secret: "cs_setup" }) })
        .mockResolvedValueOnce({ ok: false, status: 500, json: async () => ({ error: "Duplicate card" }) })
      const { element, controller } = await mount(vaultOpts)
      await controller.submit()
      expect(errorEl(element).textContent).toBe("Duplicate card")
    })

    it("falls back to a generic status message when the save error body has no error field", async () => {
      global.fetch
        .mockResolvedValueOnce({ ok: true, json: async () => ({ client_secret: "cs_setup" }) })
        .mockResolvedValueOnce({ ok: false, status: 500, json: async () => ({}) })
      const { element, controller } = await mount(vaultOpts)
      await controller.submit()
      expect(errorEl(element).textContent).toBe("Server error 500")
    })

    it("sends an empty CSRF token on both requests when no csrf-token meta tag is present", async () => {
      document.head.innerHTML = "" // no meta tag
      global.fetch
        .mockResolvedValueOnce({ ok: true, json: async () => ({ client_secret: "cs_setup" }) })
        .mockResolvedValueOnce({ ok: true, json: async () => ({}) })
      const { controller } = await mount(vaultOpts)
      await controller.submit()

      expect(global.fetch).toHaveBeenNthCalledWith(1, "/si", expect.objectContaining({
        headers: expect.objectContaining({ "X-CSRF-Token": "" }),
      }))
      expect(global.fetch).toHaveBeenNthCalledWith(2, "/cards", expect.objectContaining({
        headers: expect.objectContaining({ "X-CSRF-Token": "" }),
      }))
    })

    it("keeps the member-vault element mounted on a subsequent legacy submit", async () => {
      global.fetch
        .mockResolvedValueOnce({ ok: true, json: async () => ({ client_secret: "cs_setup" }) })
        .mockResolvedValueOnce({ ok: true })
        .mockResolvedValueOnce({ ok: true, json: async () => ({ client_secret: "cs_setup" }) })
        .mockResolvedValueOnce({ ok: true })
      const { controller } = await mount(vaultOpts)
      await controller.submit()
      await controller.submit()
      expect(stripeInstance.elements).toHaveBeenCalledTimes(1)
      expect(global.fetch).toHaveBeenCalledTimes(4)
    })

    it("localizes an unreadable legacy save error response", async () => {
      global.fetch
        .mockResolvedValueOnce({ ok: true, json: async () => ({ client_secret: "cs_setup" }) })
        .mockResolvedValueOnce({ ok: false, status: 500, json: async () => { throw new Error("bad JSON") } })
      const { controller, element } = await mount(vaultOpts)
      await controller.submit()
      expect(errorEl(element).textContent).toBe("Server error 500")
    })

    it("rejects a missing legacy setupIntent object", async () => {
      global.fetch.mockResolvedValueOnce({ ok: true, json: async () => ({ client_secret: "cs_setup" }) })
      stripeInstance.confirmSetup.mockResolvedValue({})
      const { controller, element } = await mount(vaultOpts)
      await controller.submit()
      expect(errorEl(element).textContent).toBe("SetupIntent did not return a payment_method id")
    })
  })

  describe("Stripe.js load failure", () => {
    it("connect() catches a rejected load and shows the unavailable-text error instead of leaving an unhandled rejection", async () => {
      loadStripeJs.mockRejectedValue(new Error("Failed to load Stripe.js"))
      const { element, controller } = await mount({ clientSecret: "cs_1", resultUrl: "/done" })

      expect(controller.stripe).toBeUndefined()
      expect(errorEl(element).textContent).toBe("Stripe unavailable")
      expect(errorEl(element).classList.contains("hidden")).toBe(false)
      expect(window.Stripe).not.toHaveBeenCalled()
      expect(elementsInstance.create).not.toHaveBeenCalled() // never reaches _mountElement
    })

    it("submit() shows the unavailable-text error (not a silent no-op) after a failed load — Mode A", async () => {
      loadStripeJs.mockRejectedValue(new Error("Failed to load Stripe.js"))
      const { element, controller } = await mount({ clientSecret: "cs_1", resultUrl: "/done" })

      await controller.submit()
      expect(stripeInstance.confirmPayment).not.toHaveBeenCalled()
      expect(errorEl(element).textContent).toBe("Stripe unavailable")
    })

    it("submit() shows the unavailable-text error (not a silent no-op) after a failed load — Mode B", async () => {
      loadStripeJs.mockRejectedValue(new Error("Failed to load Stripe.js"))
      const { element, controller } = await mount({ setupIntentUrl: "/si", createUrl: "/cards" })

      await controller.submit()
      expect(global.fetch).not.toHaveBeenCalled()
      expect(errorEl(element).textContent).toBe("Stripe unavailable")
    })

    it("tolerates a missing error target when the load fails", async () => {
      loadStripeJs.mockRejectedValue(new Error("Failed to load Stripe.js"))
      const htmlNoError = html({ clientSecret: "cs_1", resultUrl: "/done", withError: false })
      await expect(mountController(ID, Controller, htmlNoError)).resolves.toBeDefined()
    })
  })

  describe("billing SetupIntent extension", () => {
    const opts = { billingSetup: true, setupIntentUrl: "/billing/setup_intent", requestKey: "stable-key", resultUrl: "http://test/billing/methods/9/authorization" }
    const intent = { client_secret: "seti_secret", confirmation_url: "/billing/methods/9/confirmation" }
    const response = (body = intent) => ({ ok: true, json: async () => body })

    beforeEach(() => {
      window.location = { href: "http://test/billing", origin: "http://test", assign: vi.fn() }
    })

    it("prepares on arrival with a stable server key and mounts before confirmation", async () => {
      global.fetch.mockResolvedValueOnce(response())
      const { controller } = await mount(opts)
      expect(global.fetch).toHaveBeenCalledWith("/billing/setup_intent", expect.objectContaining({
        body: JSON.stringify({ billing_payment_method: { request_key: "stable-key" } }),
        headers: expect.objectContaining({ "X-CSRF-Token": "tok-s" }),
      }))
      expect(controller.elements).toBe(elementsInstance)
      expect(stripeInstance.confirmSetup).not.toHaveBeenCalled()
    })

    it("uses an existing authorization intent without creating another one or using confirmPayment", async () => {
      global.fetch.mockResolvedValueOnce(response({}))
      const { controller } = await mount({ ...opts, setupClientSecret: "seti_existing", confirmationUrl: intent.confirmation_url })
      stripeInstance.confirmSetup.mockResolvedValue({ setupIntent: { id: "seti_9", payment_method: "pm_9" } })
      await controller.submit()
      expect(global.fetch).toHaveBeenCalledTimes(1)
      expect(global.fetch).toHaveBeenCalledWith(intent.confirmation_url, expect.objectContaining({
        body: JSON.stringify({ setup_intent_id: "seti_9", payment_method_id: "pm_9" }),
      }))
      expect(stripeInstance.confirmSetup).toHaveBeenCalledWith({ elements: elementsInstance,
        confirmParams: { return_url: opts.resultUrl }, redirect: "if_required" })
      expect(stripeInstance.confirmPayment).not.toHaveBeenCalled()
      expect(window.location.assign).toHaveBeenCalledWith(opts.resultUrl)
    })

    it("reuses the same prepared intent after a failed confirmation", async () => {
      global.fetch.mockResolvedValueOnce(response()).mockResolvedValueOnce(response({}))
      stripeInstance.confirmSetup.mockResolvedValueOnce({ error: { message: "Authentication failed" } })
      const { controller, element } = await mount(opts)
      await controller.submit()
      expect(errorEl(element).textContent).toBe("Authentication failed")
      await controller.submit()
      expect(global.fetch).toHaveBeenCalledTimes(2)
      expect(stripeInstance.elements).toHaveBeenCalledTimes(1)
      expect(global.fetch).toHaveBeenLastCalledWith(intent.confirmation_url, expect.any(Object))
    })

    it("accepts pending verification without treating browser confirmation as authorization", async () => {
      global.fetch.mockResolvedValueOnce(response()).mockResolvedValueOnce({ ok: true, status: 202 })
      const { controller } = await mount(opts)
      await controller.submit()
      expect(window.location.assign).toHaveBeenCalledWith(opts.resultUrl)
    })

    it.each([
      [{}, "Server did not return a client_secret"],
      [{ client_secret: "seti_secret" }, "Server did not return a confirmation URL"],
      [{ client_secret: "seti_secret", confirmation_url: "https://other.test/steal" }, "Server did not return a confirmation URL"],
    ])("refuses incomplete or cross-origin setup responses %j", async (body, message) => {
      global.fetch.mockResolvedValueOnce(response(body))
      const { element } = await mount(opts)
      expect(errorEl(element).textContent).toBe(message)
      expect(paymentElement.mount).not.toHaveBeenCalled()
    })

    it("retries a failed preparation with the same key, including no CSRF meta token", async () => {
      document.head.innerHTML = ""
      global.fetch.mockResolvedValueOnce({ ok: false, status: 422 }).mockResolvedValueOnce(response())
        .mockResolvedValueOnce(response({}))
      const { element, controller } = await mount(opts)
      expect(errorEl(element).textContent).toBe("Failed to create SetupIntent (422)")
      await controller.submit()
      expect(global.fetch).toHaveBeenNthCalledWith(2, opts.setupIntentUrl, expect.objectContaining({
        headers: expect.objectContaining({ "X-CSRF-Token": "" }),
        body: JSON.stringify({ billing_payment_method: { request_key: "stable-key" } }),
      }))
    })

    it("uses the localized fallback for a preparation failure without a message", async () => {
      global.fetch.mockRejectedValueOnce(new Error(""))
      const { element } = await mount(opts)
      expect(errorEl(element).textContent).toBe("An unexpected error occurred. Please try again.")
    })

    it.each([undefined, {}])("rejects missing provider correlation %j", async (setupIntent) => {
      global.fetch.mockResolvedValueOnce(response())
      stripeInstance.confirmSetup.mockResolvedValue({ setupIntent })
      const { element, controller } = await mount(opts)
      await controller.submit()
      expect(errorEl(element).textContent).toBe("SetupIntent did not return a payment_method id")
      expect(global.fetch).toHaveBeenCalledTimes(1)
    })

    it.each([
      [async () => ({ error: "Not verified" }), "Not verified"],
      [async () => ({}), "Server error 422"],
      [async () => { throw new Error("invalid JSON") }, "Server error 422"],
    ])("preserves server confirmation failures and the prepared intent", async (json, message) => {
      global.fetch.mockResolvedValueOnce(response()).mockResolvedValueOnce({ ok: false, status: 422, json })
      const { controller, element } = await mount(opts)
      await controller.submit()
      expect(errorEl(element).textContent).toBe(message)
      expect(controller.elements).toBe(elementsInstance)
      expect(window.location.assign).not.toHaveBeenCalled()
    })

    it("prevents overlapping confirmation submits", async () => {
      let finish
      global.fetch.mockResolvedValueOnce(response()).mockResolvedValueOnce(response({}))
      stripeInstance.confirmSetup.mockReturnValue(new Promise(resolve => { finish = resolve }))
      const { controller } = await mount(opts)
      const first = controller.submit()
      await vi.waitFor(() => expect(stripeInstance.confirmSetup).toHaveBeenCalledTimes(1))
      await controller.submit()
      expect(stripeInstance.confirmSetup).toHaveBeenCalledTimes(1)
      finish({ setupIntent: { payment_method: "pm_1" } })
      await first
      expect(controller.submitting).toBe(false)
    })
  })
})
