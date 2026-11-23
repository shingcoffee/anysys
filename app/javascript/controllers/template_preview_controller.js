import { Controller } from "@hotwired/stimulus"
import { wrapEmailPreviewHtml } from "lib/email_preview_shell"

export default class extends Controller {
  static targets = ["source", "preview"]
  static values = {
    debounce: { type: Number, default: 300 },

    // i18n seam: English default keeps the JS spec green without a
    // data-*-value attribute; the mounting view supplies the translated
    // string via data-template-preview-empty-placeholder-value="<%= t(...) %>".
    emptyPlaceholder: { type: String, default: "Start typing HTML to see preview..." }
  }

  connect() {
    this.updatePreview()
  }

  sourceChanged() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.updatePreview(), this.debounceValue)
  }

  updatePreview() {
    const content = this.sourceTarget.value || `<p style='color: #999; font-family: sans-serif;'>${this.emptyPlaceholderValue}</p>`
    this.previewTarget.srcdoc = this.wrapContent(content)
  }

  wrapContent(html) {
    return wrapEmailPreviewHtml(html)
  }
}
