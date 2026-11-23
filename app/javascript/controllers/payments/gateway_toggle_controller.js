import { Controller } from "@hotwired/stimulus"

// Handles the inline enable/disable toggle for a payment gateway.
// Fires a PATCH to the account update URL with { status: "active" | "disabled" },
// applies optimistic UI immediately and reverts on error.
//
// Registered as `payments--gateway-toggle` via eager-loading from
// app/javascript/controllers/payments/.
//
// Expected markup (data-controller on a wrapper element):
//   data-controller="payments--gateway-toggle"
//   data-payments--gateway-toggle-url-value="<PATCH URL>"
//   data-payments--gateway-toggle-current-state-value="active|disabled"
//
// Targets:
//   toggle      — <input type="checkbox"> driving the toggle
//   badge       — StatusBadgeComponent wrapper (optional; refreshed via Turbo if absent)
//   statusLabel — <span> showing "Enabled" / "Disabled" text next to toggle
export default class extends Controller {
  static values = {
    url:           String,
    currentState:  String,
    enabledLabel:  { type: String, default: "Enabled" },
    disabledLabel: { type: String, default: "Disabled" }
  }

  static targets = ["toggle", "badge", "statusLabel"]

  // Fired on `change` of the toggle checkbox.
  async toggle() {
    const newState = this.toggleTarget.checked ? "active" : "disabled"

    // Optimistic UI
    this._applyState(newState)

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

      const res = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken ?? ""
        },
        body: JSON.stringify({
          payment_merchant_account: { status: newState }
        })
      })

      if (!res.ok) {
        throw new Error(`Server responded with ${res.status}`)
      }

      // Update the stored state so a subsequent toggle has the right baseline.
      this.currentStateValue = newState
    } catch (err) {
      console.error("[gateway-toggle] toggle failed, reverting:", err)
      // Revert optimistic UI
      this._applyState(this.currentStateValue)
    }
  }

  // ── private helpers ──────────────────────────────────────────────────────

  _applyState(state) {
    const isActive = state === "active"

    // Update the checkbox
    if (this.hasToggleTarget) {
      this.toggleTarget.checked = isActive
    }

    // Update the label text
    if (this.hasStatusLabelTarget) {
      this.statusLabelTarget.textContent = isActive ? this.enabledLabelValue : this.disabledLabelValue
    }
  }
}
