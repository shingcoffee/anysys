import { Controller } from "@hotwired/stimulus"

// Public marketing mobile nav. Targets: panel, backdrop, trigger (optional).
// Labels are Stimulus values — the server passes translated strings.
export default class extends Controller {
  static targets = ["panel", "backdrop", "trigger"]
  static values = {
    openLabel: { type: String, default: "Open menu" },
    closeLabel: { type: String, default: "Close menu" }
  }

  connect() {
    this.opened = false
    this.nativePanel = null
    this.scrollLocked = false
    this.savedOverflow = ""
    this.onKeydown = this.handleKeydown.bind(this)
    this.onResize = this.handleResize.bind(this)
    document.addEventListener("keydown", this.onKeydown)
    window.addEventListener("resize", this.onResize)
    this.sync()
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("resize", this.onResize)
    // Stimulus targets may already be unavailable when the controller attribute
    // is removed. Keep the modal reference so it cannot strand an inert page.
    if (this.nativePanel && this.nativePanel.open) this.nativePanel.close()
    this.opened = false
    this.unlockScroll()
  }

  open() {
    this.opened = true
    this.sync()
  }

  close() {
    const restoreFocus = this.opened && this.hasTriggerTarget
    this.opened = false
    this.sync()
    if (restoreFocus) this.triggerTarget.focus()
  }

  toggle() {
    if (this.opened) {
      this.close()
    } else {
      this.open()
    }
  }

  handleKeydown(event) {
    // Native dialogs dispatch cancel; let the browser own Escape and focus.
    if (event.key === "Escape" && !this.#nativePanel()) {
      this.close()
    }
  }

  dismissBackdrop(event) {
    if (event.target === event.currentTarget) this.close()
  }

  handleResize() {
    if (this.#desktopNav()) this.close()
  }

  sync() {
    this.applyHidden(this.hasPanelTarget ? this.panelTarget : null)
    this.applyHidden(this.hasBackdropTarget ? this.backdropTarget : null)
    if (this.#nativePanel()) {
      const panel = this.panelTarget
      this.nativePanel = panel
      if (this.opened) {
        if (!panel.open) panel.showModal()
      } else if (panel.open) {
        panel.close()
      }
    }
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", this.opened ? "true" : "false")
      this.triggerTarget.setAttribute("aria-label", this.opened ? this.closeLabelValue : this.openLabelValue)
    }
    if (this.opened) {
      this.lockScroll()
    } else {
      this.unlockScroll()
    }
  }

  applyHidden(el) {
    if (!el) return
    el.classList.toggle("hidden", !this.opened)
  }

  // Lock the root, not <body>: the site layout clips <html> overflow-x, so body
  // overflow no longer reaches the viewport and would break the sticky header.
  lockScroll() {
    if (this.scrollLocked) return
    const root = document.documentElement
    this.savedOverflow = root.style.overflow
    root.style.overflow = "hidden"
    this.scrollLocked = true
  }

  unlockScroll() {
    if (!this.scrollLocked) return
    document.documentElement.style.overflow = this.savedOverflow
    this.scrollLocked = false
  }

  #desktopNav() {
    return typeof window.matchMedia === "function" && window.matchMedia("(min-width: 1024px)").matches
  }

  #nativePanel() {
    return this.hasPanelTarget && this.panelTarget.tagName === "DIALOG" &&
      typeof this.panelTarget.showModal === "function" && typeof this.panelTarget.close === "function"
  }
}
