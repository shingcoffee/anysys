import { Controller } from "@hotwired/stimulus"
import { loadCaptchaSdk } from "lib/captcha_sdk_loader"

// Renders a Cloudflare Turnstile widget on a public form. Keeps submit disabled
// until a token is issued; clears it and re-disables on error/expiry so a stale
// token is never submitted. The token is written into the hidden
// captcha_verify_param input the server reads.
export default class extends Controller {
  static targets = ["mount", "input"]
  static values  = { siteKey: String, sdkUrl: String }

  connect() {
    const url = this.sdkUrlValue || "https://challenges.cloudflare.com/turnstile/v0/api.js"
    loadCaptchaSdk(url, () => window.turnstile)
      .then(() => this.render())
      .catch(err => console.warn("[captcha-turnstile]", err))
  }

  render() {
    if (!window.turnstile || !this.hasMountTarget) return

    const submit = this.submitButton()
    if (submit) submit.disabled = true

    this.widgetId = window.turnstile.render(this.mountTarget, {
      sitekey:            this.siteKeyValue,
      callback:           (token) => this.onSuccess(token, submit),
      "error-callback":   () => this.onFailure(submit),
      "expired-callback": () => this.onFailure(submit)
    })
  }

  onSuccess(token, submit) {
    if (this.hasInputTarget) this.inputTarget.value = token || ""
    if (submit) submit.disabled = false
  }

  onFailure(submit) {
    if (this.hasInputTarget) this.inputTarget.value = ""
    if (submit) submit.disabled = true
  }

  submitButton() {
    const form = this.element.closest("form")
    return form && form.querySelector("button[type='submit'], input[type='submit']")
  }

  disconnect() {
    if (this.widgetId && window.turnstile && window.turnstile.remove) {
      window.turnstile.remove(this.widgetId)
    }
  }
}
