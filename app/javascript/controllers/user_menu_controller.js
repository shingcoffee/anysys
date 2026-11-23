import { Controller } from "@hotwired/stimulus"
import { announceTopbarMenuOpen, onPeerTopbarMenuOpen, TOPBAR_MENU_OPEN } from "controllers/shared/topbar_menu"

// Toggles a user-menu dropdown panel. Used by both the admin and member
// shells (and the locale switcher); the `trigger` target is optional (admin's
// user-menu binds only the `panel` target and relies on `hasTriggerTarget`
// guards below).
export default class extends Controller {
  static targets = ["trigger", "panel"]

  connect() {
    this.boundOutsideClick = this.handleOutsideClick.bind(this)
    this.boundKeydown = this.handleKeydown.bind(this)
    this.boundPeerOpen = onPeerTopbarMenuOpen(this.element, () => this.close())
    document.addEventListener("click", this.boundOutsideClick)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutsideClick)
    document.removeEventListener("keydown", this.boundKeydown)
    document.removeEventListener(TOPBAR_MENU_OPEN, this.boundPeerOpen)
  }

  toggle(event) {
    event.stopPropagation()
    const willOpen = this.panelTarget.classList.contains("hidden")
    if (willOpen) announceTopbarMenuOpen(this.element)
    this.panelTarget.classList.toggle("hidden", !willOpen)
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", String(willOpen))
    }
  }

  close() {
    this.panelTarget.classList.add("hidden")
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", "false")
    }
  }

  handleOutsideClick(event) {
    if (this.element.contains(event.target)) return
    this.close()
  }

  handleKeydown(event) {
    if (event.key === "Escape") this.close()
  }
}
