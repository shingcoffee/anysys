import { Controller } from "@hotwired/stimulus"

// Handles the "Test connection" button in the GatewayConfigComponent.
// POSTs to the test_connection endpoint, shows a spinner in the result region,
// then renders success or error state inline.
//
// Registered as `payments--gateway-config` via eager-loading from
// app/javascript/controllers/payments/.
//
// Expected markup (data-controller on the <form> element):
//   data-controller="payments--gateway-config"
//   data-payments--gateway-config-test-url-value="<POST URL>"
//
// Targets:
//   result       — the TestConnectionResultComponent wrapper div
//   testButton   — the "Test connection" <button> (disabled during in-flight)
//   lastVerified — optional <span> for timestamp display
export default class extends Controller {
  static values = {
    testUrl: String,
    // i18n seam: English defaults are byte-identical to the former hardcoded
    // strings so existing behavior/specs are unaffected until the mount ERB
    // supplies translated values.
    testingLabel: { type: String, default: "Testing connection…" },
    verifiedLabel: { type: String, default: "Connection verified" },
    lastVerifiedPrefix: { type: String, default: "Last verified: " },
    failedLabel: { type: String, default: "Connection failed" },
    defaultErrorMessage: { type: String, default: "Connection test failed." },
    networkErrorMessage: { type: String, default: "Request failed — check your network connection." }
  }

  static targets = ["result", "testButton", "lastVerified"]

  async testConnection() {
    if (!this.hasResultTarget) return

    // Disable button during request
    if (this.hasTestButtonTarget) {
      this.testButtonTarget.disabled = true
    }

    // Show loading state
    this._showLoading()

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

      const res = await fetch(this.testUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken ?? ""
        }
      })

      const data = await res.json()

      if (data.ok) {
        this._showSuccess(data.message, data.verified_at, data.verified_at_label)
      } else {
        this._showError(data.message || this.defaultErrorMessageValue)
      }
    } catch (_err) {
      this._showError(this.networkErrorMessageValue)
    } finally {
      if (this.hasTestButtonTarget) {
        this.testButtonTarget.disabled = false
      }
    }
  }

  // ── private helpers ──────────────────────────────────────────────────────

  _showLoading() {
    this.resultTarget.className =
      "rounded-lg px-4 py-3 flex items-start gap-2 bg-canvas-elevated"
    this.resultTarget.innerHTML = `
      <svg class="animate-spin w-4 h-4 text-text-muted shrink-0 mt-0.5"
           xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"
           aria-hidden="true">
        <circle class="opacity-25" cx="12" cy="12" r="10"
                stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
      </svg>
      <span class="text-body-sm text-text-secondary">${this._escape(this.testingLabelValue)}</span>
    `
  }

  _showSuccess(message, verifiedAt, verifiedAtLabel) {
    this.resultTarget.className =
      "rounded-lg px-4 py-3 flex items-start gap-2 bg-success-subtle border border-success/30"

    const formatted = this._formatVerifiedAt(verifiedAt, verifiedAtLabel)
    const timestamp = formatted
      ? `<p class="text-caption text-text-secondary mt-0.5">${this._escape(this.lastVerifiedPrefixValue)}${formatted}</p>`
      : ""

    const detail = message
      ? `<p class="text-caption text-text-secondary mt-0.5">${this._escape(message)}</p>`
      : ""

    this.resultTarget.innerHTML = `
      <svg class="w-4 h-4 text-success shrink-0 mt-0.5"
           xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"
           fill="currentColor" aria-hidden="true">
        <path fill-rule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0
                 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0
                 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
              clip-rule="evenodd" />
      </svg>
      <div>
        <p class="text-body-sm font-medium text-success">${this._escape(this.verifiedLabelValue)}</p>
        ${timestamp}
        ${detail}
      </div>
    `
  }

  _showError(message) {
    this.resultTarget.className =
      "rounded-lg px-4 py-3 flex items-start gap-2 bg-danger-subtle border border-danger/30"

    this.resultTarget.innerHTML = `
      <svg class="w-4 h-4 text-danger shrink-0 mt-0.5"
           xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"
           fill="currentColor" aria-hidden="true">
        <path fill-rule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0
                 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0
                 101.414 1.414L10 11.414l1.293 1.293a1 1 0
                 001.414-1.414L11.414 10l1.293-1.293a1 1 0
                 00-1.414-1.414L10 8.586 8.707 7.293z"
              clip-rule="evenodd" />
      </svg>
      <div>
        <p class="text-body-sm font-medium text-danger">${this._escape(this.failedLabelValue)}</p>
        <p class="text-body-sm text-text-secondary mt-0.5">${this._escape(message)}</p>
      </div>
    `
  }

  _formatVerifiedAt(verifiedAt, verifiedAtLabel) {
    if (verifiedAtLabel) return this._escape(verifiedAtLabel)
    if (!verifiedAt) return ""
    return this._formatDate(verifiedAt)
  }

  _formatDate(isoString) {
    const d = new Date(isoString)
    if (Number.isNaN(d.getTime())) return this._escape(isoString)
    return new Intl.DateTimeFormat(undefined, {
      year: "numeric",
      month: "long",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
      timeZone: "UTC"
    }).format(d)
  }

  _escape(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
