import { Controller } from "@hotwired/stimulus"

// Drives PayPal Smart Buttons (Orders API v2) for the `:card` / widget flow.
//
// Registered as `payments--paypal-buttons` via eager-loading from
//   app/javascript/controllers/payments/
//
// The PayPal order is created server-side (prepay_payload[:paypal_order_id]).
// This controller loads the PayPal JS SDK dynamically, renders the Smart
// Buttons widget, and — on buyer approval — triggers server-side
// capture+reconcile via the status endpoint before redirecting to the result
// page.
//
// ─── REQUIRED DATA VALUES ────────────────────────────────────────────────────
//   data-payments--paypal-buttons-client-id-value      PayPal client ID (live/sandbox)
//   data-payments--paypal-buttons-paypal-order-id-value Server-created Order ID
//   data-payments--paypal-buttons-currency-value        ISO-4217 currency code (e.g. "USD")
//   data-payments--paypal-buttons-result-url-value      Redirect URL after capture
//   data-payments--paypal-buttons-status-url-value      JSON status / capture endpoint
//
// ─── TARGETS ─────────────────────────────────────────────────────────────────
//   element   — div where Smart Buttons mount
//   error     — <p> for inline error messages (aria-live="polite")
//
// ─── PAYPAL JS SDK ────────────────────────────────────────────────────────────
//   Loaded dynamically on connect() from https://www.paypal.com/sdk/js.
//   The script is idempotent — skipped if window.paypal already exists (e.g.
//   navigating back / Turbo cache restore).

const PAYPAL_SDK_BASE = "https://www.paypal.com/sdk/js"

export default class extends Controller {
  static values = {
    clientId:      String,
    paypalOrderId: String,
    currency:      String,
    resultUrl:     String,
    statusUrl:     String,
    sdkError:      { type: String, default: "Could not load the PayPal SDK. Please refresh and try again." },
    cancelledText: { type: String, default: "Payment cancelled. You can try again." },
    errorText:     { type: String, default: "Something went wrong with PayPal. Please try again." }
  }

  static targets = ["element", "error"]

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  async connect() {
    if (!this.clientIdValue) return

    try {
      await this._loadPayPalSdk()
    } catch (_err) {
      this._showError(this.sdkErrorValue)
      return
    }

    this._renderButtons()
  }

  // ── Internal: render Smart Buttons ────────────────────────────────────────

  _renderButtons() {
    window.paypal.Buttons({
      // Order is already created server-side; return its ID directly.
      createOrder: () => this.paypalOrderIdValue,

      // Buyer approved the payment in the PayPal popup. Trigger server-side
      // capture+reconcile via the status endpoint, then navigate to the
      // result page regardless of the fetch outcome (the server handles
      // idempotent capture retries).
      onApprove: async () => {
        this._clearError()
        try {
          await fetch(this.statusUrlValue, {
            headers: { Accept: "application/json" }
          })
        } catch (_) {
          // Non-fatal: the server will reconcile on the next status poll.
        }
        window.location = this.resultUrlValue
      },

      onCancel: () => {
        this._showError(this.cancelledTextValue)
      },

      onError: () => {
        this._showError(this.errorTextValue)
      }
    }).render(this.elementTarget)
  }

  // ── Internal: SDK loader ───────────────────────────────────────────────────

  _loadPayPalSdk() {
    // Idempotent — skip if already loaded (Turbo cache, back-navigation).
    if (window.paypal) return Promise.resolve()

    return new Promise((resolve, reject) => {
      const src =
        `${PAYPAL_SDK_BASE}` +
        `?client-id=${encodeURIComponent(this.clientIdValue)}` +
        `&currency=${encodeURIComponent(this.currencyValue)}` +
        `&intent=capture`

      const script = document.createElement("script")
      script.src   = src
      script.async = true
      script.onload  = resolve
      script.onerror = () => reject(new Error("Failed to load PayPal JS SDK"))
      document.head.appendChild(script)
    })
  }

  // ── Internal: error target helpers ────────────────────────────────────────

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
}
