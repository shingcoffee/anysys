import { Controller } from "@hotwired/stimulus"

const ACTIVE_TAB_CLASSES = ["bg-surface", "text-text-primary", "shadow-xs"]
const INACTIVE_TAB_CLASSES = ["text-text-muted", "hover:text-text-primary"]
const NAVIGATION_KEYS = ["ArrowLeft", "ArrowRight", "Home", "End"]
// Matches the `lg:` breakpoint at which the template hides the tablist and
// shows both panels side by side.
const DESKTOP_QUERY = "(min-width: 1024px)"

export default class extends Controller {
  static targets = ["tab", "panel", "artifact", "artifactDot"]
  static values = {
    active: { type: String, default: "conversation" }
  }

  connect() {
    this.desktopQuery = this.#mediaQuery()
    this.onLayoutChange = () => this.#applyLayout()
    if (this.desktopQuery && this.desktopQuery.addEventListener) {
      this.desktopQuery.addEventListener("change", this.onLayoutChange)
    }
    this.#applyLayout()
  }

  disconnect() {
    if (this.desktopQuery && this.desktopQuery.removeEventListener) {
      this.desktopQuery.removeEventListener("change", this.onLayoutChange)
    }
    this.desktopQuery = null
  }

  select(event) {
    this.selectTab(event.currentTarget?.dataset.assistantWorkspaceId)
  }

  selectTab(id) {
    if (!this.tabTargets.some((tab) => tab.dataset.assistantWorkspaceId === id)) return

    this.activeValue = id
    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.assistantWorkspaceId === id
      tab.setAttribute("aria-selected", String(active))
      tab.tabIndex = active ? 0 : -1
      tab.classList.remove(...ACTIVE_TAB_CLASSES, ...INACTIVE_TAB_CLASSES)
      tab.classList.add(...(active ? ACTIVE_TAB_CLASSES : INACTIVE_TAB_CLASSES))
    })
    // At desktop both panels are on screen at once, so showing one would hide
    // half the workspace. Tab state is still tracked for the way back down.
    if (this.#isDesktop()) return

    this.panelTargets.forEach((panel) => {
      const active = panel.dataset.assistantWorkspaceId === id
      panel.classList.toggle("hidden", !active)
      panel.tabIndex = active ? 0 : -1
    })
  }

  keydown(event) {
    if (!NAVIGATION_KEYS.includes(event.key)) return

    const currentIndex = this.tabTargets.indexOf(event.currentTarget)
    if (currentIndex < 0) return

    event.preventDefault()
    let nextIndex
    switch (event.key) {
      case "ArrowLeft":
        nextIndex = (currentIndex - 1 + this.tabTargets.length) % this.tabTargets.length
        break
      case "ArrowRight":
        nextIndex = (currentIndex + 1) % this.tabTargets.length
        break
      case "Home":
        nextIndex = 0
        break
      default:
        nextIndex = this.tabTargets.length - 1
    }

    const nextTab = this.tabTargets[nextIndex]
    nextTab.focus()
    this.selectTab(nextTab.dataset.assistantWorkspaceId)
  }

  #applyLayout() {
    if (this.#isDesktop()) this.#applyDesktop()
    else this.#applyMobile()
  }

  // The pane behind the Preview tab is refreshed by its own Turbo broadcast,
  // which never reaches the tablist. Its re-connect is the only signal the tab
  // gets that there is now something to look at.
  artifactTargetConnected(pane) {
    if (!this.hasArtifactDotTarget) return

    this.artifactDotTarget.classList.toggle("hidden", pane.dataset.artifactPresent !== "true")
  }

  // Both panels are visible regions, not tabpanels: the tablist that would
  // label them is display:none here, so a tabpanel role would point at a
  // hidden name and one visible panel would report aria-selected="false".
  // tabIndex -1 for the same reason — with no tabs to move between, two
  // focusable regions are just two stops on the way to the composer.
  #applyDesktop() {
    this.panelTargets.forEach((panel) => {
      panel.classList.remove("hidden")
      panel.tabIndex = -1
      panel.removeAttribute("role")
      panel.removeAttribute("aria-labelledby")
    })
  }

  // Read from the template rather than from a snapshot taken at connect: a
  // controller that reconnects against a DOM `#applyDesktop` has already
  // stripped would snapshot nothing and never restore the tab semantics on the
  // way back down.
  #applyMobile() {
    this.panelTargets.forEach((panel) => {
      const { assistantWorkspaceRole: role, assistantWorkspaceLabelledBy: labelledBy } = panel.dataset
      if (role) panel.setAttribute("role", role)
      if (labelledBy) panel.setAttribute("aria-labelledby", labelledBy)
    })
    this.selectTab(this.activeValue)
  }

  #isDesktop() {
    return Boolean(this.desktopQuery && this.desktopQuery.matches)
  }

  // happy-dom and older browsers may not implement matchMedia; without it the
  // controller simply stays in its mobile behaviour.
  #mediaQuery() {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") return null

    return window.matchMedia(DESKTOP_QUERY)
  }
}
