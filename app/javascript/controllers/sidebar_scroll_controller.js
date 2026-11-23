import { Controller } from "@hotwired/stimulus"

// The settings menu lives in its own overflow pane. A full visit replaces that
// pane, which would otherwise jump the scrollbar back to the top — most
// noticeable when opening a destination near the bottom, such as Invoices.
export default class extends Controller {
  static values = { key: String }

  connect() {
    this.restore()
    this.boundRemember = () => this.remember()
    this.element.addEventListener("scroll", this.boundRemember, { passive: true })
  }

  disconnect() {
    this.remember()
    this.element.removeEventListener("scroll", this.boundRemember)
  }

  remember() {
    const key = this.storageKey()
    if (!key) return

    sessionStorage.setItem(key, String(this.element.scrollTop))
  }

  restore() {
    const key = this.storageKey()
    if (!key) return

    const saved = sessionStorage.getItem(key)
    const top = Number(saved)
    if (saved == null || !Number.isFinite(top)) return

    this.element.scrollTop = top
  }

  storageKey() {
    if (!this.hasKeyValue || this.keyValue === "") return null

    return `sidebar-scroll:${this.keyValue}`
  }
}
