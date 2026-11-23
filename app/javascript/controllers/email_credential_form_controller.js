import { Controller } from "@hotwired/stimulus"

// Toggles the visible per-provider config field group (SMTP typed columns vs.
// an API vendor's config_fields) and swaps the shared secret field's label to
// match the selected Email provider on the platform credential form. Also keeps
// HTML `required` in sync so hidden provider groups and optional DKIM/secret
// fields do not block native form validation. Pure DOM toggling — no
// user-facing strings originate in this controller (labels are server-rendered
// i18n).
//
// The provider <select> intentionally does NOT declare itself as a target
// (co-locating a target and an action on the same element is unreliable —
// see sms_credential_form_controller for the same pattern); the initial
// provider comes from the `provider` Value and subsequent changes come from
// the change event's own target.
export default class extends Controller {
  static targets = [
    "fields",
    "secretLabel",
    "secretInput",
    "requiredWhenVisible",
    "dkimEnabled",
    "dkimRequired",
    "dkimLabel",
    "dkimKeyInput",
    "dkimKeyLabel"
  ]
  static values = { provider: String, labels: Object, secretRequired: Boolean }

  connect() {
    this.apply(this.providerValue)
  }

  toggle(event) {
    this.apply(event.target.value)
  }

  toggleDkim() {
    this.applyDkimRequired()
  }

  apply(provider) {
    this.fieldsTargets.forEach((el) => {
      const visible = el.dataset.provider === provider
      el.classList.toggle("hidden", !visible)
      el.querySelectorAll("input, select, textarea").forEach((input) => {
        input.disabled = !visible
      })
      el.querySelectorAll('[data-email-credential-form-target="requiredWhenVisible"]').forEach((input) => {
        input.required = visible
      })
    })

    this.applyLabel(provider)
    this.applySecretRequired()
    this.applyDkimRequired(provider)
  }

  applyLabel(provider) {
    const label = this.labelsValue[provider]
    if (!label) return

    if (this.hasSecretLabelTarget) {
      this.secretLabelTarget.textContent = label
      this.secretLabelTarget.classList.toggle("form-label-required", this.secretRequiredValue)
    }
  }

  applySecretRequired() {
    if (!this.hasSecretInputTarget) return
    this.secretInputTarget.required = this.secretRequiredValue
  }

  applyDkimRequired(provider = this.providerValue) {
    const smtpVisible = provider === "smtp"
    const enabled = smtpVisible && this.hasDkimEnabledTarget && this.dkimEnabledTarget.checked

    this.dkimRequiredTargets.forEach((input) => {
      input.required = enabled
    })
    this.dkimLabelTargets.forEach((label) => {
      label.classList.toggle("form-label-required", enabled)
    })

    if (this.hasDkimKeyInputTarget) {
      this.dkimKeyInputTarget.required = enabled && this.secretRequiredValue
    }
    if (this.hasDkimKeyLabelTarget) {
      this.dkimKeyLabelTarget.classList.toggle("form-label-required", enabled && this.secretRequiredValue)
    }
  }
}
