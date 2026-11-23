import { Controller } from "@hotwired/stimulus"

// Audience card of the platform announcement form.
//
// Shows/hides the segment builder for the All vs Selected choice and asks the
// server how many tenants the current segment matches, so the owner never
// publishes a broadcast blind.
//
// All copy arrives from the server as Stimulus values (I18n); the defaults
// below are English fallbacks only.
export default class extends Controller {
  static targets = ["panel", "rules", "output"]

  static values = {
    previewUrl: String,
    loadingText: { type: String, default: "Checking audience…" },
    errorText: { type: String, default: "Could not size this audience." },
    countText: { type: String, default: "{count} customers match." },
    emptyText: { type: String, default: "No customers match these conditions." }
  }

  toggleAudience(event) {
    if (!this.hasPanelTarget) return

    this.panelTarget.classList.toggle("hidden", event.target.value === "all")
  }

  async preview() {
    if (!this.hasOutputTarget || !this.previewUrlValue) return

    this.outputTarget.textContent = this.loadingTextValue

    try {
      const response = await fetch(this.previewUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ target_rules_json: this.currentRules })
      })

      if (!response.ok) {
        this.outputTarget.textContent = this.errorTextValue
        return
      }

      const payload = await response.json()
      const count = Number(payload.count) || 0
      this.outputTarget.textContent =
        count > 0 ? this.countTextValue.replace("{count}", count) : this.emptyTextValue
    } catch {
      this.outputTarget.textContent = this.errorTextValue
    }
  }

  get currentRules() {
    return this.hasRulesTarget ? this.rulesTarget.value : "{}"
  }

  get csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }
}
