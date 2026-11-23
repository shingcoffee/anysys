import { Controller } from "@hotwired/stimulus"
import { escapeHtml } from "utils"

export default class extends Controller {
  static targets = ["editor", "validationResult"]
  static values = {
    validateUrl: String,

    // ── i18n seam: English defaults keep JS specs green without any
    // data-*-value attribute; the mount template supplies translated
    // strings via data-code-editor-<name>-value="<%= t(...) %>". ──
    validatingLabel: { type: String, default: "Validating..." },
    allChecksPassedLabel: { type: String, default: "All checks passed" },
    validationFailedLabel: { type: String, default: "Validation failed" },
    requestFailedFormat: { type: String, default: "Request failed: {message}" }
  }

  async validate() {
    if (!this.validateUrlValue) return

    const source = this.editorTarget.value
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const el = this.validationResultTarget

    el.classList.remove("hidden")
    el.className = "px-4 py-2.5 text-sm bg-gray-50 border-b border-gray-200 flex items-center gap-2 text-gray-500"
    el.innerHTML = `<svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path></svg> ${escapeHtml(this.validatingLabelValue)}`

    try {
      const response = await fetch(this.validateUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": token
        },
        body: new URLSearchParams({ methods_body: source })
      })

      const data = await response.json()

      if (data.valid) {
        el.className = "px-4 py-2.5 text-sm bg-emerald-50 border-b border-emerald-100 flex items-center gap-2 text-emerald-700"
        el.innerHTML = `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/></svg> ${escapeHtml(this.allChecksPassedLabelValue)}`
      } else {
        el.className = "px-4 py-2.5 text-sm bg-red-50 border-b border-red-100 text-red-700"
        el.innerHTML = `<div class="flex items-center gap-2 mb-1"><svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/></svg> <strong>${escapeHtml(this.validationFailedLabelValue)}</strong></div><ul class="ml-6 space-y-0.5">${data.errors.map(e => `<li>&bull; ${escapeHtml(e)}</li>`).join("")}</ul>`
      }
    } catch (err) {
      el.className = "px-4 py-2.5 text-sm bg-amber-50 border-b border-amber-100 flex items-center gap-2 text-amber-700"
      el.innerHTML = `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.082 16.5c-.77.833.192 2.5 1.732 2.5z"/></svg> ${escapeHtml(this.requestFailedFormatValue.replace("{message}", err.message))}`
    }
  }
}
