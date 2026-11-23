import { Controller } from "@hotwired/stimulus"
import { loadCaptchaSdk } from "lib/captcha_sdk_loader"

const DEFAULT_SDK_URL = "https://www.google.com/recaptcha/api.js"

// Google reCAPTCHA v3 is invisible: it never renders a widget, and the token is
// fetched only when the user submits the form. The shared Captcha::WidgetComponent
// renders a "mount" target with loading text; we clear it so the widget stays
// hidden while the SDK loads.
export default class extends Controller {
  static targets = ["mount", "input"]
  static values = { siteKey: String, sdkUrl: String }

  connect() {
    this.clearMount()
    loadCaptchaSdk(this.sdkUrlValue || DEFAULT_SDK_URL, () => window.grecaptcha && window.grecaptcha.ready)
      .then(() => {
        this.clearMount()
        this.bindForm()
      })
      .catch((err) => {
        this.clearMount()
        console.warn("[captcha-google-recaptcha-v3]", err)
      })
  }

  disconnect() {
    this.unbindForm()
  }

  bindForm() {
    const form = this.element.closest("form")
    if (!form) return

    this.form = form
    this.submitHandler = (event) => this.handleSubmit(event)
    this.form.addEventListener("submit", this.submitHandler)
  }

  unbindForm() {
    if (this.form && this.submitHandler) {
      this.form.removeEventListener("submit", this.submitHandler)
    }
  }

  async handleSubmit(event) {
    event.preventDefault()
    const submit = this.submitButton
    if (submit) submit.disabled = true

    try {
      const token = await this.fetchToken()
      this.setToken(token)
      // requestSubmit dispatches a real submit event so Turbo and any other
      // submit listeners run. Temporarily unbind our own handler first so we
      // don't recurse back into this method.
      this.unbindForm()
      this.form.requestSubmit()
      this.bindForm()
    } catch (err) {
      console.warn("[captcha-google-recaptcha-v3]", err)
      if (submit) submit.disabled = false
    }
  }

  fetchToken() {
    return new Promise((resolve, reject) => {
      if (!window.grecaptcha || !window.grecaptcha.ready) {
        reject(new Error("reCAPTCHA SDK is not ready"))
        return
      }

      window.grecaptcha.ready(() => {
        window.grecaptcha.execute(this.siteKeyValue, { action: "submit" })
          .then(resolve)
          .catch(reject)
      })
    })
  }

  setToken(token) {
    if (this.hasInputTarget) {
      this.inputTarget.value = token || ""
    }
  }

  clearMount() {
    if (this.hasMountTarget) {
      this.mountTarget.textContent = ""
    }
  }

  get submitButton() {
    const form = this.form || this.element.closest("form")
    if (!form) return null
    return form.querySelector("button[type='submit'], input[type='submit']")
  }
}
