import { Controller } from "@hotwired/stimulus"
import { loadStripeJs } from "lib/stripe_js_loader"

// Drives Stripe card flows via the Stripe.js Payment Element / SetupIntent.
//
// Registered as `payments--stripe-card` via eager-loading from
//   app/javascript/controllers/payments/
//
// ─── TWO MODES ────────────────────────────────────────────────────────────────
//
// Mode A — CHECKOUT (CardCheckoutComponent):
//   Use when confirming a one-time PaymentIntent.
//   Required data values:
//     data-payments--stripe-card-publishable-key-value   Stripe publishable key
//     data-payments--stripe-card-client-secret-value     PaymentIntent client_secret
//     data-payments--stripe-card-result-url-value        Redirect URL after success
//   Optional:
//     (the "Save this card" checkbox posts save_card=1 as a regular form param;
//      it is rendered/hidden by the Rails component — no JS logic needed)
//
// Mode B — VAULT (PaymentMethodsComponent):
//   Use when adding a card to the member's vault (SetupIntent flow).
//   Required data values:
//     data-payments--stripe-card-publishable-key-value   Stripe publishable key
//     data-payments--stripe-card-setup-intent-url-value  POST → returns { client_secret }
//     data-payments--stripe-card-create-url-value        POST { payment_method_id } → vault row
//   Billing extension: billingSetup=true eagerly prepares one SetupIntent,
//   posts requestKey, and confirms only at its server-returned confirmation_url.
//   An authorization page can supply setupClientSecret + confirmationUrl;
//   those are never passed to the PaymentIntent/confirmPayment mode.
//
// ─── TARGETS ──────────────────────────────────────────────────────────────────
//   element   — div where the Payment Element mounts
//   error     — <p> or <span> for inline error messages (aria-live="polite")
//
// ─── ACTIONS ──────────────────────────────────────────────────────────────────
//   data-action="click->payments--stripe-card#submit"
//
// ─── STRIPE.JS ────────────────────────────────────────────────────────────────
//   Loaded dynamically from https://js.stripe.com/v3/ on connect() via the
//   shared lib/stripe_js_loader (memoized so multiple Stripe controllers on
//   one page never inject duplicate <script> tags).
//   The iframe that hosts card input is rendered by Stripe's SDK — no PAN
//   ever reaches our server (PCI SAQ-A).
//
//   unavailable-text-value — localized error shown when Stripe.js fails to
//   load or initialize (server-translated), e.g. js.stripe.com is blocked by
//   an ad-blocker or a network policy.

export default class extends Controller {
  static values = {
    publishableKey:  String,
    clientSecret:    String,  // Mode A: PaymentIntent client_secret
    setupIntentUrl:  String,  // Mode B: endpoint returning { client_secret }
    createUrl:       String,  // Mode B: endpoint to POST payment_method_id
    resultUrl:       String,  // Mode A: redirect after success
    billingSetup:   Boolean, // Billing keeps one prepared, method-scoped SetupIntent.
    requestKey:     String,
    setupClientSecret: String,
    confirmationUrl: String,
    missingConfirmationUrl: { type: String, default: "Server did not return a confirmation URL" },
    unavailableText: { type: String, default: "We couldn't load the secure payment form. Please refresh the page and try again." },
    unexpectedError: { type: String, default: "An unexpected error occurred. Please try again." },
    setupIntentFailed: { type: String, default: "Failed to create SetupIntent ({status})" },
    missingClientSecret: { type: String, default: "Server did not return a client_secret" },
    missingPaymentMethod: { type: String, default: "SetupIntent did not return a payment_method id" },
    serverError: { type: String, default: "Server error {status}" },
    processingText: { type: String, default: "Processing…" },
  }

  static targets = ["element", "error"]

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  async connect() {
    if (!this.publishableKeyValue) return

    try {
      await loadStripeJs()
      this.stripe = window.Stripe(this.publishableKeyValue)
    } catch (_err) {
      // Stripe.js failed to load/initialize — surface it instead of leaving
      // this.stripe unset and submit() silently doing nothing.
      this._showError(this.unavailableTextValue)
      return
    }

    if (this.billingSetupValue) {
      this._setLoading(true)
      try {
        await this._prepareBillingSetup()
      } catch (err) {
        this._showError(err.message || this.unexpectedErrorValue)
      } finally {
        this._setLoading(false)
      }
    } else if (this.clientSecretValue) {
      // Mode A — checkout: PaymentIntent already created server-side
      this._mountElement(this.clientSecretValue)
    }
    // Mode B — vault: SetupIntent client_secret is fetched lazily on submit
  }

  disconnect() {
    this._unmountElement()
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  async submit() {
    if (this.submitting) return
    if (!this.stripe) {
      this._showError(this.unavailableTextValue)
      return
    }

    this._clearError()
    this.submitting = true
    this._setLoading(true)

    try {
      if (this.billingSetupValue) {
        await this._confirmBillingSetup()
      } else if (this.clientSecretValue) {
        await this._confirmPayment()
      } else {
        await this._vaultCard()
      }
    } catch (err) {
      this._showError(err.message || this.unexpectedErrorValue)
    } finally {
      this.submitting = false
      this._setLoading(false)
    }
  }

  // ── Mode A: Confirm PaymentIntent ──────────────────────────────────────────

  async _confirmPayment() {
    const { error } = await this.stripe.confirmPayment({
      elements: this.elements,
      confirmParams: {
        return_url: this.resultUrlValue
      }
    })
    // confirmPayment redirects on success; only reaches here on error.
    if (error) throw new Error(error.message)
  }

  // ── Mode B: Vault card via SetupIntent ─────────────────────────────────────

  async _prepareBillingSetup() {
    if (!this.setupPreparation) {
      this.setupPreparation = this._fetchBillingSetup()
    }
    try {
      const intent = await this.setupPreparation
      if (!this.elements) this._mountElement(intent.client_secret)
      return intent
    } catch (err) {
      this.setupPreparation = null
      throw err
    }
  }

  async _fetchBillingSetup() {
    let intent
    if (this.setupClientSecretValue) {
      intent = { client_secret: this.setupClientSecretValue, confirmation_url: this.confirmationUrlValue }
    } else {
      const response = await fetch(this.setupIntentUrlValue, {
        method: "POST",
        headers: this._billingHeaders(),
        body: JSON.stringify({ billing_payment_method: { request_key: this.requestKeyValue } }),
      })
      if (!response.ok) throw new Error(this.setupIntentFailedValue.replace("{status}", String(response.status)))
      intent = await response.json()
    }
    if (!intent.client_secret) throw new Error(this.missingClientSecretValue)
    if (!intent.confirmation_url) throw new Error(this.missingConfirmationUrlValue)
    // Confirmation is always a same-origin, server-scoped billing route.
    const confirmation = new URL(intent.confirmation_url, window.location.href)
    if (confirmation.origin !== window.location.origin) throw new Error(this.missingConfirmationUrlValue)
    return intent
  }

  async _confirmBillingSetup() {
    const intent = await this._prepareBillingSetup()
    const { setupIntent, error } = await this.stripe.confirmSetup({
      elements: this.elements,
      confirmParams: { return_url: this.resultUrlValue },
      redirect: "if_required",
    })
    if (error) throw new Error(error.message)
    if (!setupIntent?.payment_method) throw new Error(this.missingPaymentMethodValue)
    const response = await fetch(intent.confirmation_url, {
      method: "POST",
      headers: this._billingHeaders(),
      body: JSON.stringify({ setup_intent_id: setupIntent.id, payment_method_id: setupIntent.payment_method }),
    })
    if (!response.ok) {
      const body = await response.json().catch(() => ({}))
      throw new Error(body.error || this.serverErrorValue.replace("{status}", String(response.status)))
    }
    // A 202 is pending verification, not proof of authorization. The next GET
    // displays the server state; redirected 3DS is reconciled by that GET/B.
    window.location.assign(this.resultUrlValue)
  }

  _billingHeaders() {
    return {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "",
    }
  }

  async _vaultCard() {
    // 1. Request a SetupIntent client_secret from the server.
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const intentRes = await fetch(this.setupIntentUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept":        "application/json",
        "X-CSRF-Token":  csrfToken ?? ""
      }
    })

    if (!intentRes.ok) {
      throw new Error(this.setupIntentFailedValue.replace("{status}", String(intentRes.status)))
    }

    const { client_secret: clientSecret } = await intentRes.json()
    if (!clientSecret) throw new Error(this.missingClientSecretValue)

    // 2. Mount the Payment Element if not already mounted (lazy for vault mode).
    if (!this.elements) this._mountElement(clientSecret)

    // 3. Confirm the SetupIntent client-side — card never touches our server.
    const { setupIntent, error } = await this.stripe.confirmSetup({
      elements: this.elements,
      confirmParams: {
        return_url: window.location.href  // Stripe may redirect for 3DS; we handle it below
      },
      redirect: "if_required"
    })

    if (error) throw new Error(error.message)
    if (!setupIntent?.payment_method) throw new Error(this.missingPaymentMethodValue)

    // 4. POST the resulting payment_method id to our server to create the vault row.
    const saveRes = await fetch(this.createUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept":        "application/json",
        "X-CSRF-Token":  csrfToken ?? ""
      },
      body: JSON.stringify({ payment_method_id: setupIntent.payment_method })
    })

    if (!saveRes.ok) {
      const body = await saveRes.json().catch(() => ({}))
      throw new Error(body.error || this.serverErrorValue.replace("{status}", String(saveRes.status)))
    }

    // 5. Reload the page to reflect the newly saved card.
    window.location.reload()
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  _mountElement(clientSecret) {
    if (!this.hasElementTarget) return

    this.elements = this.stripe.elements({ clientSecret })
    const paymentElement = this.elements.create("payment")
    paymentElement.mount(this.elementTarget)
  }

  _unmountElement() {
    if (this.elements) {
      try { this.elements.getElement("payment")?.unmount() } catch (_) { // best-effort; ignore
      }
    }
  }

  _showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  _clearError() {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }

  _setLoading(loading) {
    // Disable/enable any submit buttons inside this controller's element.
    this.element.querySelectorAll("[data-action*='stripe-card#submit']").forEach(btn => {
      if (!btn.dataset.originalLabel) btn.dataset.originalLabel = btn.textContent
      btn.disabled = loading
      btn.textContent = loading ? this.processingTextValue : btn.dataset.originalLabel
    })
  }
}
