import { Controller } from "@hotwired/stimulus"

/**
 * Developer Docs Nav Controller
 *
 * Owns the docs reader's mobile "Contents" slide-over drawer and reveals the
 * current guide when the desktop rail first becomes visible. On mobile the
 * links live inside a drawer opened by a floating "Contents" button and
 * dismissed by a backdrop click, the close button, or by picking a page.
 *
 * Values:
 *   - openLabel / closeLabel: String — aria-labels for the drawer toggle
 *
 * Targets:
 *   - drawer:   the mobile slide-over wrapper
 *   - drawerList: optional independently scrolling guide/results list
 *   - backdrop: the mobile dimming layer
 *   - trigger / desktop: complementary container-query navigation surfaces
 */
export default class extends Controller {
  static targets = ["drawer", "drawerList", "backdrop", "trigger", "desktop"]
  static values = {
    openLabel: { type: String, default: "Open contents" },
    closeLabel: { type: String, default: "Close contents" }
  }

  connect() {
    this.isOpen = false
    this.desktopVisible = false
    // Keep element references available after Stimulus removes the controller scope.
    this.drawer = this.hasDrawerTarget ? this.drawerTarget : null
    this.backdrop = this.hasBackdropTarget ? this.backdropTarget : null
    this.trigger = this.hasTriggerTarget ? this.triggerTarget : null
    if (this.drawer) {
      this.drawer.tabIndex = -1
      this.setExpanded(false)
    }
    this.onKeydown = this.keydown.bind(this)
    this.onFocus = this.containFocus.bind(this)
    this.onResize = this.syncLayout.bind(this)
    document.addEventListener("keydown", this.onKeydown, true)
    document.addEventListener("focusin", this.onFocus)
    window.addEventListener("resize", this.onResize)
    this.resizeObserver = new ResizeObserver(this.onResize)
    this.resizeObserver.observe(this.element)
    this.syncLayout()
  }

  disconnect() {
    this.dismiss(false)
    clearTimeout(this.closeTimer)
    if (this.backdrop) this.backdrop.classList.add("hidden")
    this.resizeObserver.disconnect()
    document.removeEventListener("keydown", this.onKeydown, true)
    document.removeEventListener("focusin", this.onFocus)
    window.removeEventListener("resize", this.onResize)
  }

  openDrawer() {
    if (!this.drawer || !this.backdrop || this.isOpen || this.desktopMode) return
    clearTimeout(this.closeTimer)
    this.returnFocus = this.hasTriggerTarget ? this.triggerTarget : document.activeElement
    this.previousOverflow = document.body.style.overflow
    this.isOpen = true
    document.body.style.overflow = "hidden"
    this.setExpanded(true)
    this.backdropTarget.classList.remove("hidden")
    this.drawerTarget.classList.remove("-translate-x-full")
    this.drawerTarget.classList.add("translate-x-0")
    this.openFrame = requestAnimationFrame(() => {
      this.openFrame = null
      this.backdropTarget.style.opacity = "1"
      this.focusDrawer()
      this.revealCurrentGuide()
    })
  }

  closeDrawer() {
    this.dismiss(true)
  }

  dismiss(restoreFocus) {
    cancelAnimationFrame(this.openFrame)
    if (!this.isOpen) return
    clearTimeout(this.closeTimer)
    this.isOpen = false
    document.body.style.overflow = this.previousOverflow
    this.backdrop.style.opacity = "0"
    this.drawer.classList.remove("translate-x-0")
    this.drawer.classList.add("-translate-x-full")
    // Move focus before making the dialog inert/aria-hidden.
    if (restoreFocus) {
      if (this.returnFocus.isConnected && this.returnFocus.checkVisibility({ visibilityProperty: true })) {
        this.returnFocus.focus()
      } else if (this.hasDesktopTarget && this.desktopTarget.checkVisibility({ visibilityProperty: true })) {
        this.desktopTarget.tabIndex = -1
        this.desktopTarget.focus()
      }
    }
    this.setExpanded(false)
    this.closeTimer = setTimeout(() => {
      this.backdrop.classList.add("hidden")
    }, 250)
  }

  navigate() {
    this.dismiss(false)
  }

  setExpanded(open) {
    this.drawer.inert = !open
    this.drawer.setAttribute("aria-hidden", String(!open))
    if (this.trigger) {
      this.trigger.setAttribute("aria-expanded", String(open))
      this.trigger.setAttribute("aria-label", open ? this.closeLabelValue : this.openLabelValue)
    }
  }

  get desktopMode() {
    // CSS is the source of truth: W=896px belongs to the reader, not the viewport.
    return this.hasTriggerTarget && !this.triggerTarget.checkVisibility({ visibilityProperty: true })
  }

  syncLayout() {
    if (this.isOpen && this.desktopMode) this.closeDrawer()
    const desktopVisible = this.hasDesktopTarget && this.desktopTarget.checkVisibility({ visibilityProperty: true })
    // Reveal on initial layout or entry into desktop, never on repeated resize
    // notifications that would override the reader's scrolling/disclosures.
    if (desktopVisible && !this.desktopVisible) {
      const desktop = this.desktopTarget
      this.revealGuide(desktop.querySelector("[data-docs-nav-list='desktop']"), desktop.querySelector("[data-docs-current-guide]"))
    }
    this.desktopVisible = desktopVisible
  }

  focusableElements() {
    return Array.from(this.drawerTarget.querySelectorAll("a[href], button, input:not([type='hidden']), select, textarea, summary, [tabindex]"))
      .filter((element) => (!element.hasAttribute("tabindex") || element.tabIndex >= 0) &&
        !element.matches(":disabled, [aria-disabled='true']") && !element.closest("[inert]") &&
        // Native visibility also excludes descendants of closed details.
        element.checkVisibility({ visibilityProperty: true }))
  }

  focusDrawer() {
    const target = this.focusableElements()[0] || this.drawerTarget
    target.focus({ preventScroll: true })
  }

  revealCurrentGuide() {
    if (!this.hasDrawerListTarget) return
    this.revealGuide(this.drawerListTarget, this.drawerTarget.querySelector("[data-docs-current-guide]"))
  }

  revealGuide(list, current) {
    if (!list || !current) return
    // Search pins the canonical current guide in the header, above the results.
    if (!list.contains(current)) {
      list.scrollTop = 0
      return
    }

    const group = current.closest("details")
    if (group && !group.open) group.open = true
    if (list.clientHeight === 0) return

    // Measure after expanding the owning group. scrollIntoView would also move
    // the app shell/window; only adjust this list's scroll offset instead.
    const top = list.getBoundingClientRect().top + list.clientTop
    const row = current.getBoundingClientRect()
    const above = row.top - top
    const below = row.bottom - (top + list.clientHeight)
    if (above < 0) {
      list.scrollTop += above
    } else if (below > 0) {
      // A row taller than the viewport cannot fit: keep its beginning visible.
      list.scrollTop += Math.min(above, below)
    }
  }

  containFocus(event) {
    if (this.isOpen && !this.drawerTarget.contains(event.target)) this.focusDrawer()
  }

  keydown(event) {
    if (!this.isOpen) return
    if (event.key === "Escape") {
      event.preventDefault()
      event.stopPropagation()
      this.closeDrawer()
    } else if (event.key === "Tab") {
      const items = this.focusableElements()
      const index = items.indexOf(document.activeElement)
      if (items.length === 0) {
        event.preventDefault()
        this.drawerTarget.focus()
      } else if (event.shiftKey ? index <= 0 : index === -1 || index === items.length - 1) {
        event.preventDefault()
        const target = event.shiftKey ? items[items.length - 1] : items[0]
        target.focus()
      }
    }
  }
}
