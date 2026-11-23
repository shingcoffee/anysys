import { Controller } from "@hotwired/stimulus"

// Toggles the visible per-provider config field group (and, when available,
// swaps the access-key labels) to match the selected SMS vendor adapter on
// the platform credential form. Pure DOM toggling — no user-facing strings
// originate in this controller (labels are server-rendered i18n).
//
// The provider <select> intentionally does NOT declare itself as a target
// (co-locating a target and an action on the same element is unreliable —
// see billing_coupon_form_controller for the same pattern); the initial
// provider comes from the `provider` Value and subsequent changes come from
// the change event's own target.
export default class extends Controller {
  static targets = ["fields", "accessKeyIdLabel", "accessKeySecretLabel"]
  static values = { provider: String, labels: Object }

  connect() {
    this.apply(this.providerValue)
  }

  toggle(event) {
    this.apply(event.target.value)
  }

  apply(provider) {
    this.fieldsTargets.forEach((el) => {
      el.classList.toggle("hidden", el.dataset.provider !== provider)
    })

    this.applyLabels(provider)
  }

  applyLabels(provider) {
    const labels = this.labelsValue[provider]
    if (!labels) return

    if (this.hasAccessKeyIdLabelTarget && labels.access_key_id) {
      this.accessKeyIdLabelTarget.textContent = labels.access_key_id
    }
    if (this.hasAccessKeySecretLabelTarget && labels.access_key_secret) {
      this.accessKeySecretLabelTarget.textContent = labels.access_key_secret
    }
  }
}
