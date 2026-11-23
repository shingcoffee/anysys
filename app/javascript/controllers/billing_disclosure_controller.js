import { Controller } from "@hotwired/stimulus"

// Progressive-enhancement disclosure for secondary billing sections (plan
// catalog when already subscribed, coupon redemption, manage subscription,
// inactive payment methods).
//
// SSR / no-JS HTML does NOT put `hidden` on the panel, so server-rendered
// HTML and Capybara specs without JS can inspect everything inside. On
// connect, JS applies `hidden` from the open value unless the URL hash
// targets this section (or one of `hashes`).
//
// Usage (emitted by Billing::Admin::DisclosureComponent):
//   data-controller="billing-disclosure"
//   data-billing-disclosure-open-value="false"
//   data-billing-disclosure-hashes-value='["coupon-form"]'
export default class extends Controller {
  static targets = ["trigger", "panel", "icon"]
  static values = { open: { type: Boolean, default: true }, hashes: { type: Array, default: [] } }

  connect() {
    this._onHashChange = this.#onHashChange.bind(this)
    this._onDocumentClick = this.#onDocumentClick.bind(this)
    window.addEventListener("hashchange", this._onHashChange)
    document.addEventListener("click", this._onDocumentClick)

    if (this.#matchesHash(window.location.hash)) {
      this.openValue = true
    } else {
      this.#sync()
    }
  }

  disconnect() {
    window.removeEventListener("hashchange", this._onHashChange)
    document.removeEventListener("click", this._onDocumentClick)
  }

  toggle() {
    this.openValue = !this.openValue
  }

  open() {
    this.openValue = true
  }

  close() {
    this.openValue = false
  }

  openValueChanged() {
    this.#sync()
  }

  #matchesHash(rawHash) {
    const id = (rawHash || "").replace(/^#/, "")
    return Boolean(id) && (id === this.element.id || this.hashesValue.includes(id))
  }

  #onHashChange() {
    if (this.#matchesHash(window.location.hash)) this.open()
  }

  #onDocumentClick(event) {
    const anchor = event.target instanceof Element ? event.target.closest("a[href^='#']") : null
    if (anchor && this.#matchesHash(anchor.getAttribute("href"))) this.open()
  }

  #sync() {
    this.panelTarget.classList.toggle("hidden", !this.openValue)
    this.triggerTarget.setAttribute("aria-expanded", String(this.openValue))
    this.iconTarget.classList.toggle("rotate-90", this.openValue)
  }
}
