import { Controller } from "@hotwired/stimulus"
import { loadStripeJs } from "lib/stripe_js_loader"

// Drives on-session SCA / 3-D Secure recovery for a subscription charge that
// stalled off-session (Stripe returned requires_action). The server hands us the
// PaymentIntent client_secret; Stripe.js presents the authentication challenge,
// and on success we reload — the payment_intent.succeeded webhook has by then
// marked the payment paid and reactivated the subscription.
//
// Registered as `payments--sca-recovery` via eager-loading from
//   app/javascript/controllers/payments/
//
// Data values (set by the Rails component):
//   publishable-key   Stripe publishable key
//   client-secret     PaymentIntent client_secret to authenticate
//   error-text        Localized fallback error message (server-translated)
//   unavailable-text  Localized error shown when Stripe.js fails to load or
//                      initialize (server-translated) — e.g. js.stripe.com is
//                      blocked by an ad-blocker or a network policy.
//
// Target: error — <p aria-live="polite"> for inline error messages.
// Action: click->payments--sca-recovery#authenticate

export default class extends Controller {
  static values = {
    publishableKey: String,
    clientSecret:   String,
    // I18n: English default; the server passes the translated string via the
    // data-…-error-text-value attribute so no user-facing text is baked into JS.
    errorText:       { type: String, default: "We couldn't verify your payment. Please try again." },
    unavailableText: { type: String, default: "We couldn't load the secure payment form. Please refresh the page and try again." },
  }

  static targets = ["error"]

  async connect() {
    if (!this.publishableKeyValue) return

    try {
      await loadStripeJs()
      this.stripe = window.Stripe(this.publishableKeyValue)
    } catch (_err) {
      // Stripe.js failed to load/initialize — surface it instead of leaving
      // this.stripe unset and authenticate() silently doing nothing.
      this._showError(this.unavailableTextValue)
    }
  }

  async authenticate() {
    if (!this.stripe) {
      this._showError(this.unavailableTextValue)
      return
    }

    this._clearError()
    this._setLoading(true)

    try {
      const { error, paymentIntent } = await this.stripe.confirmCardPayment(this.clientSecretValue)
      if (error) throw new Error(error.message || this.errorTextValue)
      if (!paymentIntent || paymentIntent.status !== "succeeded") throw new Error(this.errorTextValue)

      window.location.reload()
    } catch (err) {
      this._showError(err.message)
    } finally {
      this._setLoading(false)
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
    this.element.querySelectorAll("[data-action*='sca-recovery#authenticate']").forEach((btn) => {
      btn.disabled = loading
    })
  }
}
