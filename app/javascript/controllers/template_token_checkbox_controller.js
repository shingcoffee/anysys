import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "badge"]
  static values = {
    url: String,
    tokenModel: String,
    tokenAttribute: String,
    active: Boolean,
    availableLabel: { type: String, default: "Token Available" },
    notAvailableLabel: { type: String, default: "Not Tokenized" },
    savingLabel: { type: String, default: "Saving…" },
    failedLabel: { type: String, default: "Failed" }
  }

  connect() {
    this.isSaving = false
  }

  async toggle(event) {
    if (event) {
      event.stopPropagation()
    }

    if (this.isSaving) return

    const desiredActive = this.checkboxTarget.checked
    this.isSaving = true
    this.checkboxTarget.disabled = true

    this.renderState("saving")

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken || ""
        },
        body: JSON.stringify({
          token_model: this.tokenModelValue,
          token_attribute: this.tokenAttributeValue,
          token_enabled: desiredActive ? "1" : "0"
        })
      })

      if (!response.ok) {
        throw new Error(`HTTP error ${response.status}`)
      }

      this.activeValue = desiredActive
      this.renderState("saved")
    } catch (error) {
      console.error("[template-token-checkbox] Update failed:", error)
      this.checkboxTarget.checked = this.activeValue
      this.renderState("error")
    } finally {
      this.isSaving = false
      this.checkboxTarget.disabled = false
    }
  }

  renderState(state) {
    if (!this.hasBadgeTarget) return

    if (state === "saving") {
      this.badgeTarget.innerHTML = `<span class="badge badge-accent px-2 py-0.5 text-xs animate-pulse">${this.escapeHtml(this.savingLabelValue)}</span>`
    } else if (state === "saved") {
      if (this.activeValue) {
        this.badgeTarget.innerHTML = `<span class="badge badge-success px-2 py-0.5 text-xs">${this.escapeHtml(this.availableLabelValue)}</span>`
      } else {
        this.badgeTarget.innerHTML = `<span class="badge badge-default px-2 py-0.5 text-xs">${this.escapeHtml(this.notAvailableLabelValue)}</span>`
      }
    } else if (state === "error") {
      this.badgeTarget.innerHTML = `<span class="badge badge-danger px-2 py-0.5 text-xs">${this.escapeHtml(this.failedLabelValue)}</span>`
      setTimeout(() => {
        this.renderState("saved")
      }, 2000)
    }
  }

  escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str || ""
    return div.innerHTML
  }
}
