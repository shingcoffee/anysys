import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["previewPanel", "previewLineCount"]
  static values = {
    previewUrl: String,

    // ── i18n seam: English default keeps JS specs green without any
    // data-*-value attribute; the mounting form (form_component.html.erb)
    // supplies the translated string via
    // data-generator-form-lines-count-format-value="<%= t(...) %>". ──
    linesCountFormat: { type: String, default: "{count} lines" }
  }

  connect() {
    this.debounceTimer = null
    this.requestPreview()
  }

  fieldChanged() {
    this.debouncedPreview()
  }

  debouncedPreview() {
    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => this.requestPreview(), 300)
  }

  async requestPreview() {
    const formData = this.collectFormData()
    try {
      const response = await fetch(this.previewUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
          "Accept": "application/json"
        },
        body: JSON.stringify(formData)
      })
      if (!response.ok) return
      const data = await response.json()
      this.updatePreview(data)
    } catch (_e) {
      // Silently ignore preview errors
    }
  }

  collectFormData() {
    const form = this.element
    return {
      kind: form.querySelector('[name="kind"]')?.value || "step_action",
      file_name: form.querySelector('[name="file_name"]')?.value || "my_generator",
      category: form.querySelector('[name="category"]')?.value || "uncategorized",
      description: form.querySelector('[name="description"]')?.value || "",
      version: form.querySelector('[name="version"]')?.value || "1.0.0",
      registered_names: form.querySelector('[name="registered_names"]')?.value || "",
      methods_body: form.querySelector('[name="methods_body"]')?.value || ""
    }
  }

  updatePreview(data) {
    if (this.hasPreviewPanelTarget) {
      // Build line numbers
      const lineCount = data.line_count || 0
      let lineNumbers = ""
      for (let i = 1; i <= lineCount; i++) {
        lineNumbers += `<div class="leading-6">${i}</div>`
      }

      this.previewPanelTarget.innerHTML = `
        <div class="flex font-mono text-sm">
          <div class="select-none border-r border-gray-200 pr-4 text-right text-gray-400">
            ${lineNumbers}
          </div>
          <div class="pl-4 flex-1">
            <pre class="leading-6"><code class="highlight">${data.highlighted}</code></pre>
          </div>
        </div>
      `
    }
    if (this.hasPreviewLineCountTarget) {
      this.previewLineCountTarget.textContent = this.linesCountFormatValue.replace("{count}", data.line_count || 0)
    }
  }
}
