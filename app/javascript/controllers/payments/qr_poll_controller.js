import { Controller } from "@hotwired/stimulus"

// Polls the server-side payment status endpoint every 2 seconds and
// redirects to the result page once the payment reaches a terminal
// state (succeeded/failed/closed). Registered as `payments--qr-poll`
// via eager-loading from app/javascript/controllers/payments/.
export default class extends Controller {
  static values = {
    statusUrl: String,
    resultUrl: String,
    // i18n seam: English default byte-identical to the former hardcoded prefix.
    statusPrefix: { type: String, default: "Status: " },
    statusLabels: { type: Object, default: { pending: "Pending", succeeded: "Succeeded", failed: "Failed", closed: "Closed" } }
  }
  static targets = ["status"]

  connect() {
    this.timer = setInterval(() => this.poll(), 2000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async poll() {
    const res = await fetch(this.statusUrlValue, { headers: { Accept: "application/json" } })
    const { status } = await res.json()
    if (this.hasStatusTarget) {
      const label = this.statusLabelsValue[status] || status
      this.statusTarget.textContent = `${this.statusPrefixValue}${label}`
    }
    if (["succeeded", "failed", "closed"].includes(status)) {
      clearInterval(this.timer)
      window.location = this.resultUrlValue
    }
  }
}
