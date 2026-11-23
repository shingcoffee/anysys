import { Controller } from "@hotwired/stimulus"

// Toggles the static-membership vs dynamic-rules panel on the email list form
// when the list type select changes. Labels/copy are server-rendered i18n.
// Preview results load into a modal so the form page length stays stable.
export default class extends Controller {
  static targets = ["panel", "previewFrame", "previewButton", "previewRules", "previewModal"]
  static values = {
    listType: { type: String, default: "dynamic" },
    previewUrl: { type: String, default: "" },
    loadingLabel: { type: String, default: "Loading…" }
  }

  #boundEsc = null

  connect() {
    this.apply(this.listTypeValue)
    this.#boundEsc = (event) => {
      if (event.key === "Escape") this.closePreview()
    }
  }

  disconnect() {
    document.removeEventListener("keydown", this.#boundEsc)
  }

  toggle(event) {
    this.apply(event.target.value)
  }

  apply(listType) {
    this.listTypeValue = listType
    this.panelTargets.forEach((el) => {
      el.classList.toggle("hidden", el.dataset.listType !== listType)
    })
  }

  preview(event) {
    event?.preventDefault?.()
    return this.#loadPreview(1)
  }

  previewPage(event) {
    event?.preventDefault?.()
    const page = event?.params?.page || event?.target?.dataset?.page || "1"
    return this.#loadPreview(page)
  }

  closePreview(event) {
    event?.preventDefault?.()
    if (!this.hasPreviewModalTarget) return
    this.previewModalTarget.classList.add("hidden")
    document.removeEventListener("keydown", this.#boundEsc)
  }

  interceptPreviewNav(event) {
    const anchor = event.target.closest?.("a[href]")
    if (!anchor || !this.hasPreviewFrameTarget || !this.previewFrameTarget.contains(anchor)) return

    event.preventDefault()
    const page = new URL(anchor.href, window.location.origin).searchParams.get("page") || "1"
    return this.#loadPreview(page)
  }

  async #loadPreview(page) {
    if (!this.previewUrlValue || !this.hasPreviewFrameTarget) return

    const body = new FormData()
    body.set("segment_rules_json", this.#currentRulesJson())
    body.set("page", String(page))

    if (this.hasPreviewButtonTarget) {
      this.previewButtonTarget.disabled = true
      this.previewButtonTarget.dataset.originalLabel = this.previewButtonTarget.textContent
      this.previewButtonTarget.textContent = this.loadingLabelValue
    }

    try {
      const response = await fetch(this.previewUrlValue, {
        method: "POST",
        headers: {
          Accept: "text/html",
          "Turbo-Frame": "email_list_preview",
          "X-CSRF-Token": this.#csrfToken()
        },
        body,
        credentials: "same-origin"
      })
      this.#replaceFrame(await response.text())
      this.#openPreviewModal()
    } finally {
      if (this.hasPreviewButtonTarget) {
        this.previewButtonTarget.disabled = false
        this.previewButtonTarget.textContent = this.previewButtonTarget.dataset.originalLabel
      }
    }
  }

  #openPreviewModal() {
    if (!this.hasPreviewModalTarget) return
    this.previewModalTarget.classList.remove("hidden")
    document.addEventListener("keydown", this.#boundEsc)
  }

  #currentRulesJson() {
    const live = this.element.querySelector('[name="email_list[segment_rules_json]"]')
    if (live?.value) return live.value
    if (this.hasPreviewRulesTarget && this.previewRulesTarget.value) return this.previewRulesTarget.value
    return "{}"
  }

  #csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  #replaceFrame(html) {
    const doc = new DOMParser().parseFromString(html, "text/html")
    const next = doc.querySelector("turbo-frame#email_list_preview")
    if (!next) return
    this.previewFrameTarget.innerHTML = next.innerHTML
  }
}
