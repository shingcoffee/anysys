import { Controller } from "@hotwired/stimulus"

// Code generator playground: posts the config JSON to the test-run endpoint
// and swaps in the server-rendered result.
export default class extends Controller {
  static targets = ["config", "result", "runButton", "spinner"]
  static values = {
    url: String,
    sample: { type: String, default: "{}" },

    // i18n seam: the detail component passes the translated template via
    // data-generator-test-runner-request-failed-format-value.
    requestFailedFormat: { type: String, default: "Request failed: {message}" }
  }

  reset() {
    this.configTarget.value = this.sampleValue
    this.configTarget.focus()
  }

  async run(event) {
    event?.preventDefault()
    if (this.runButtonTarget.disabled) return

    this.busy(true)
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        },
        body: JSON.stringify({ sample_config: this.configTarget.value })
      })
      const data = await response.json()
      if (data.html) {
        this.resultTarget.innerHTML = data.html
      } else {
        this.showError(data.error)
      }
    } catch (error) {
      this.showError(this.requestFailedFormatValue.replace("{message}", error.message))
    } finally {
      this.busy(false)
    }
  }

  busy(state) {
    this.runButtonTarget.disabled = state
    this.spinnerTarget.classList.toggle("hidden", !state)
  }

  showError(message) {
    const alert = document.createElement("div")
    alert.setAttribute("role", "alert")
    alert.className = "rounded-lg border border-danger/20 bg-danger-subtle px-3 py-2.5 text-sm text-danger break-words"
    alert.textContent = message
    this.resultTarget.replaceChildren(alert)
  }
}
