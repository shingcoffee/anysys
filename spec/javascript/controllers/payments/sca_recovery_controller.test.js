import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/payments/sca_recovery_controller"
import { mountController, controllerFor } from "../../support/stimulus.js"
import { loadStripeJs } from "lib/stripe_js_loader"

// The shared loader has its own dedicated spec (spec/javascript/lib/stripe_js_loader.test.js)
// covering script injection, memoization and retry. Here we only care how this
// controller reacts to it resolving/rejecting.
vi.mock("lib/stripe_js_loader", () => ({ loadStripeJs: vi.fn() }))

const ID = "payments--sca-recovery"

const html = ({
  pk = "pk_test", clientSecret = "cs_1", errorText = "Fallback error",
  unavailableText = "Stripe unavailable", withError = true,
} = {}) => `
  <div data-controller="${ID}"
       data-${ID}-publishable-key-value="${pk}"
       data-${ID}-client-secret-value="${clientSecret}"
       data-${ID}-error-text-value="${errorText}"
       data-${ID}-unavailable-text-value="${unavailableText}">
    <button data-action="click->${ID}#authenticate">Verify</button>
    ${withError ? `<p data-${ID}-target="error" class="hidden"></p>` : ""}
  </div>`

const errorEl = (el) => el.querySelector(`[data-${ID}-target="error"]`)
const buttonEl = (el) => el.querySelector("button")

// ── Stripe.js mock ────────────────────────────────────────────────────────────
let stripeInstance
const installStripe = () => {
  stripeInstance = {
    confirmCardPayment: vi.fn().mockResolvedValue({ paymentIntent: { status: "succeeded" }, error: null }),
  }
  window.Stripe = vi.fn(() => stripeInstance)
}

const mount = async (opts) => {
  const { application, element } = await mountController(ID, Controller, html(opts))
  return { application, element, controller: controllerFor(application, element, ID) }
}

describe("payments--sca-recovery", () => {
  let originalLocation
  beforeEach(() => {
    originalLocation = window.location
    installStripe()
    window.location = { reload: vi.fn() }
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

  it("initializes Stripe on connect with a publishable key", async () => {
    const { controller } = await mount({})
    expect(window.Stripe).toHaveBeenCalledWith("pk_test")
    expect(controller.stripe).toBe(stripeInstance)
  })

  it("authenticate shows the unavailable-text error (not a silent no-op) when Stripe was never initialized", async () => {
    const { element, controller } = await mount({ pk: "" }) // connect returned early → no this.stripe
    await controller.authenticate()
    expect(stripeInstance.confirmCardPayment).not.toHaveBeenCalled()
    expect(errorEl(element).textContent).toBe("Stripe unavailable")
    expect(errorEl(element).classList.contains("hidden")).toBe(false)
  })

  it("confirms the PaymentIntent and reloads on success", async () => {
    const { controller } = await mount({})
    await controller.authenticate()
    expect(stripeInstance.confirmCardPayment).toHaveBeenCalledWith("cs_1")
    expect(window.location.reload).toHaveBeenCalled()
  })

  it("shows the Stripe error message when authentication fails", async () => {
    stripeInstance.confirmCardPayment.mockResolvedValue({ error: { message: "Authentication failed" } })
    const { element, controller } = await mount({})
    await controller.authenticate()
    expect(errorEl(element).textContent).toBe("Authentication failed")
    expect(errorEl(element).classList.contains("hidden")).toBe(false)
    expect(window.location.reload).not.toHaveBeenCalled()
  })

  it("falls back to the localized error text when the Stripe error has no message", async () => {
    stripeInstance.confirmCardPayment.mockResolvedValue({ error: { message: "" } })
    const { element, controller } = await mount({ errorText: "Please try again" })
    await controller.authenticate()
    expect(errorEl(element).textContent).toBe("Please try again")
  })

  it("shows the localized error when the PaymentIntent did not reach succeeded", async () => {
    stripeInstance.confirmCardPayment.mockResolvedValue({ paymentIntent: { status: "requires_action" }, error: null })
    const { element, controller } = await mount({ errorText: "Please try again" })
    await controller.authenticate()
    expect(errorEl(element).textContent).toBe("Please try again")
    expect(window.location.reload).not.toHaveBeenCalled()
  })

  it("shows the localized error when no PaymentIntent is returned", async () => {
    stripeInstance.confirmCardPayment.mockResolvedValue({ error: null })
    const { element, controller } = await mount({ errorText: "Please try again" })
    await controller.authenticate()
    expect(errorEl(element).textContent).toBe("Please try again")
  })

  it("tolerates a missing error target", async () => {
    stripeInstance.confirmCardPayment.mockResolvedValue({ error: { message: "boom" } })
    const { application, element } = await mountController(ID, Controller, html({ withError: false }))
    const controller = controllerFor(application, element, ID)
    await expect(controller.authenticate()).resolves.toBeUndefined()
  })

  it("disables the button while authenticating and re-enables it after", async () => {
    let resolveConfirm
    stripeInstance.confirmCardPayment.mockReturnValue(new Promise((r) => { resolveConfirm = r }))
    const { element, controller } = await mount({})

    const p = controller.authenticate()
    expect(buttonEl(element).disabled).toBe(true)

    resolveConfirm({ paymentIntent: { status: "succeeded" }, error: null })
    await p
    expect(buttonEl(element).disabled).toBe(false)
  })

  describe("Stripe.js load failure", () => {
    it("connect() catches a rejected load and shows the unavailable-text error instead of leaving an unhandled rejection", async () => {
      loadStripeJs.mockRejectedValue(new Error("Failed to load Stripe.js"))
      const { element, controller } = await mount({})

      expect(controller.stripe).toBeUndefined()
      expect(errorEl(element).textContent).toBe("Stripe unavailable")
      expect(errorEl(element).classList.contains("hidden")).toBe(false)
      expect(window.Stripe).not.toHaveBeenCalled()
    })

    it("authenticate() shows the unavailable-text error (not a silent no-op) after a failed load", async () => {
      loadStripeJs.mockRejectedValue(new Error("Failed to load Stripe.js"))
      const { element, controller } = await mount({})

      await controller.authenticate()
      expect(stripeInstance.confirmCardPayment).not.toHaveBeenCalled()
      expect(errorEl(element).textContent).toBe("Stripe unavailable")
    })

    it("tolerates a missing error target when the load fails", async () => {
      loadStripeJs.mockRejectedValue(new Error("Failed to load Stripe.js"))
      await expect(mountController(ID, Controller, html({ withError: false }))).resolves.toBeDefined()
    })
  })
})
