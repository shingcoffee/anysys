import { Controller } from "@hotwired/stimulus"
import { wrapEmailPreviewHtml } from "lib/email_preview_shell"
import { escapeHtml } from "utils"

export default class extends Controller {
  static targets = [
    "button", "subjectPane", "htmlPane", "textPane", 
    "tabSubject", "tabHtml", "tabText", "iframe",
    "testEmailInput", "testSendButton", "testStatus",
    "autoRefresh"
  ]
  static values = { 
    url: String, 
    testSendUrl: String,
    loadingLabel: { type: String, default: "Loading..." },
    sendingLabel: { type: String, default: "Sending..." },
    emptySubjectLabel: { type: String, default: "(Empty Subject)" },
    emptyTextLabel: { type: String, default: "(Empty Text)" },
    errorLoadingLabel: { type: String, default: "Error loading preview" },
    emailRequiredLabel: { type: String, default: "Please enter an email address" },
    sendFailedLabel: { type: String, default: "Failed to send test email" },
    networkErrorLabel: { type: String, default: "Network error sending test email" },
    popupBlockedLabel: { type: String, default: "Unable to open preview tab (popup blocked?)" }
  }

  connect() {
    // Automatically load preview upon mounting
    if (this.hasButtonTarget) {
      this.loadPreview()
    }
  }

  // Gather current form field values into an API-compatible nested structure
  getFormData() {
    const root = this.element.closest("form") || document

    const name = this.#fieldValue(root, "email_template[name]")
    const subject = this.#fieldValue(root, "email_template[subject]")
    const editorType = this.#fieldValue(root, "email_template[editor_type]") || "code"

    const body = this.#richTextBodyValue(root)
    const bodyHtml = this.#fieldValue(root, "email_template[body_html]")
    const bodyText = this.#fieldValue(root, "email_template[body_text]")
    const status = this.#fieldValue(root, "email_template[status]") || "draft"

    return {
      email_template: {
        name, subject, editor_type: editorType,
        body, body_html: bodyHtml, body_text: bodyText,
        status
      }
    }
  }

  // Lexxy is a form-associated custom element — prefer its live `.value` HTML
  // over a generic name lookup so preview matches the editor contents.
  #richTextBodyValue(root) {
    const editor = root.querySelector("lexxy-editor")
    if (editor && typeof editor.value === "string") return editor.value
    return this.#fieldValue(root, "email_template[body]")
  }

  // Rails check_box emits a hidden unchecked value before the checkbox. Prefer
  // :checked (or the non-hidden control) so activate-immediately is accurate.
  #fieldValue(root, name) {
    const checked = root.querySelector(`[name="${name}"]:checked`)
    if (checked) return checked.value

    const fields = [...root.querySelectorAll(`[name="${name}"]`)]
    const control = fields.find((el) => el.type !== "hidden") || fields[0]
    if (!control) return ""

    if (control.type === "checkbox" || control.type === "radio") {
      const hidden = fields.find((el) => el.type === "hidden")
      return hidden ? hidden.value : ""
    }

    return control.value
  }

  debouncedLoadPreview() {
    if (this.hasAutoRefreshTarget && !this.autoRefreshTarget.checked) return

    clearTimeout(this.previewTimeout)
    this.previewTimeout = setTimeout(() => {
      this.loadPreview()
    }, 1000)
  }

  async loadPreview(event) {
    if (event) event.preventDefault()
    if (!this.hasButtonTarget) return

    const spinnerHtml = `
      <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-current" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
    `

    const originalText = this.buttonTarget.textContent
    this.buttonTarget.disabled = true
    this.buttonTarget.innerHTML = `${spinnerHtml}<span>${escapeHtml(this.loadingLabelValue)}</span>`

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ""
      const payload = this.getFormData()

      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify(payload)
      })

      if (!response.ok) throw new Error("Failed to load preview")
      
      const data = await response.json()
      
      if (this.hasSubjectPaneTarget) {
        this.subjectPaneTarget.textContent = data.subject || this.emptySubjectLabelValue
      }
      
      if (this.hasIframeTarget) {
        // Prefer server-built document shell when present (Emails::AuthorPreview).
        this.iframeTarget.srcdoc = data.body_srcdoc || this.wrapContent(data.body_html || "")
      }
      
      if (this.hasTextPaneTarget) {
        this.textPaneTarget.textContent = data.body_text || this.emptyTextLabelValue
      }
      
    } catch (error) {
      console.error(error)
      alert(this.errorLoadingLabelValue)
    } finally {
      this.buttonTarget.disabled = false
      this.buttonTarget.innerHTML = originalText
    }
  }

  async sendTestEmail(event) {
    if (event) event.preventDefault()

    const to = this.testEmailInputTarget.value.trim()
    if (!to) {
      this.showStatus(this.emailRequiredLabelValue, "error")
      return
    }

    const spinnerHtml = `
      <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-current" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
    `

    const originalText = this.testSendButtonTarget.innerHTML
    this.testSendButtonTarget.disabled = true
    this.testSendButtonTarget.innerHTML = `${spinnerHtml}<span>${escapeHtml(this.sendingLabelValue)}</span>`
    this.clearStatus()

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ""
      const payload = {
        ...this.getFormData(),
        to: to
      }

      const response = await fetch(this.testSendUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify(payload)
      })

      const data = await response.json()

      if (response.ok && data.success) {
        this.showStatus(data.message, "success")
        this.testEmailInputTarget.value = ""
      } else {
        this.showStatus(data.error || this.sendFailedLabelValue, "error")
      }
    } catch (error) {
      console.error(error)
      this.showStatus(this.networkErrorLabelValue, "error")
    } finally {
      this.testSendButtonTarget.disabled = false
      this.testSendButtonTarget.innerHTML = originalText
    }
  }

  showStatus(message, type) {
    if (!this.hasTestStatusTarget) return

    const successIcon = `
      <svg class="w-5 h-5 text-green-600 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>
    `
    const errorIcon = `
      <svg class="w-5 h-5 text-red-600 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
      </svg>
    `

    const icon = type === "success" ? successIcon : errorIcon
    const bgClass = type === "success" ? "bg-green-50 border-green-200 text-green-800" : "bg-red-50 border-red-200 text-red-800"

    this.testStatusTarget.className = `rounded-lg p-4 border text-sm mt-3 flex items-start gap-2.5 ${bgClass}`
    this.testStatusTarget.innerHTML = `
      ${icon}
      <div class="flex-grow">
        <p class="font-medium">${escapeHtml(message)}</p>
      </div>
    `
    this.testStatusTarget.classList.remove("hidden")
  }

  clearStatus() {
    if (!this.hasTestStatusTarget) return
    this.testStatusTarget.textContent = ""
    this.testStatusTarget.className = "hidden"
    this.testStatusTarget.classList.add("hidden")
  }

  showTab(event) {
    if (event) event.preventDefault()
    const tabName = event.currentTarget.dataset.tab

    // subjectPane is a persistent header readout, not a tab panel — never hide it.
    if (this.hasHtmlPaneTarget) this.htmlPaneTarget.classList.add("hidden")
    if (this.hasTextPaneTarget) this.textPaneTarget.classList.add("hidden")

    if (this.hasTabSubjectTarget) this.deactivateTab(this.tabSubjectTarget)
    if (this.hasTabHtmlTarget) this.deactivateTab(this.tabHtmlTarget)
    if (this.hasTabTextTarget) this.deactivateTab(this.tabTextTarget)

    if (tabName === "html" && this.hasHtmlPaneTarget) {
      this.htmlPaneTarget.classList.remove("hidden")
      if (this.hasTabHtmlTarget) this.activateTab(this.tabHtmlTarget)
    } else if (tabName === "text" && this.hasTextPaneTarget) {
      this.textPaneTarget.classList.remove("hidden")
      if (this.hasTabTextTarget) this.activateTab(this.tabTextTarget)
    } else if (tabName === "subject") {
      // Legacy subject tab (usually hidden in UI) — keep HTML visible as fallback
      if (this.hasHtmlPaneTarget) this.htmlPaneTarget.classList.remove("hidden")
      if (this.hasTabSubjectTarget) this.activateTab(this.tabSubjectTarget)
    }
  }

  async openFullPagePreview(event) {
    if (event) event.preventDefault()

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""
    const url = this.#fullPagePreviewUrl()
    const payload = this.getFormData()

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify(payload)
      })

      if (!response.ok) throw new Error("Failed to load full-page preview")

      const data = await response.json()
      const html = data.body_srcdoc || this.wrapContent(data.body_html || "")
      const previewWindow = window.open("", "_blank")
      if (!previewWindow) {
        alert(this.popupBlockedLabelValue)
        return
      }
      // Do not document.write the email as the top document — authored HTML
      // would run as the admin origin. Isolate it the same way as the editor
      // iframe (sandbox="", srcdoc).
      previewWindow.document.open()
      previewWindow.document.write(
        '<!DOCTYPE html><html><body style="margin:0">' +
        '<iframe sandbox="" style="border:0;width:100%;min-height:100vh"></iframe>' +
        "</body></html>"
      )
      previewWindow.document.close()
      previewWindow.document.querySelector("iframe").srcdoc = html
    } catch (error) {
      console.error(error)
      alert(this.errorLoadingLabelValue)
    }
  }

  #fullPagePreviewUrl() {
    const base = this.urlValue || ""
    if (!base) return ""
    const joiner = base.includes("?") ? "&" : "?"
    return `${base}${joiner}preview_mode=full_page`
  }

  activateTab(el) {
    el.classList.add("border-primary", "text-primary")
    el.classList.remove("border-transparent", "text-text-muted", "hover:text-text", "hover:border-border")
  }

  deactivateTab(el) {
    el.classList.remove("border-primary", "text-primary")
    el.classList.add("border-transparent", "text-text-muted", "hover:text-text", "hover:border-border")
  }

  wrapContent(html) {
    return wrapEmailPreviewHtml(html)
  }
}
