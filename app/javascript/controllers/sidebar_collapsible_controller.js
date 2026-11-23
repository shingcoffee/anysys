import { Controller } from "@hotwired/stimulus"

/**
 * Sidebar Collapsible Controller
 *
 * Collapses the admin shell's left sidebar to an icon rail and expands it
 * back. The controller only writes `data-state="expanded|collapsed"` on its
 * element; Tailwind `data-[state=…]` and `group-data-[state=…]/sidebar`
 * variants animate the width and crossfade the two panels.
 *
 * The choice is stored in a session cookie (name from the `cookie` value) so
 * the server renders the remembered state on the next request and full page
 * loads never flash the default. connect() re-reads the cookie so a Turbo
 * snapshot restored from history matches the latest choice.
 *
 * The hidden panel is `inert`. Cmd/Ctrl+B toggles the sidebar unless the
 * keystroke lands in an editable field (rich-text editors use it for bold).
 * When a toggle hides the panel that holds focus, focus moves to the toggle
 * in the panel that appears.
 *
 * Usage:
 *   <div data-controller="sidebar-collapsible"
 *        data-state="expanded"
 *        data-sidebar-collapsible-collapsed-value="false"
 *        data-sidebar-collapsible-cookie-value="sidebar_state_modules">
 *     <div data-sidebar-collapsible-target="full">…full sidebar…</div>
 *     <div data-sidebar-collapsible-target="rail">…icon rail…</div>
 *     <div data-sidebar-collapsible-target="tooltip" role="tooltip" class="hidden">
 *       <span data-sidebar-collapsible-target="tooltipLabel"></span>
 *       <kbd data-sidebar-collapsible-target="tooltipShortcut" class="hidden"></kbd>
 *     </div>
 *   </div>
 *
 * Controls set data-sidebar-rail-label (and optionally
 * data-sidebar-rail-shortcut). Hover and keyboard focus show them in the
 * tooltip, positioned just to the right of the control.
 *
 * Values:
 *   - collapsed: Boolean — server-rendered state (default false = expanded)
 *   - cookie: String — session cookie that remembers the choice
 */
export default class extends Controller {
  static targets = ["full", "rail", "tooltip", "tooltipLabel", "tooltipShortcut"]
  static values = {
    collapsed: { type: Boolean, default: false },
    cookie: { type: String, default: "sidebar_state" }
  }

  connect() {
    this.onPointerOver = (event) => this.showTip(event)
    this.onPointerOut = (event) => this.hideTip(event)
    this.onFocusIn = (event) => {
      if (event.target.matches(":focus-visible")) this.showTip(event)
    }
    this.onFocusOut = (event) => this.hideTip(event)
    this.onKeydown = (event) => this.shortcut(event)
    this.element.addEventListener("pointerover", this.onPointerOver)
    this.element.addEventListener("pointerout", this.onPointerOut)
    this.element.addEventListener("focusin", this.onFocusIn)
    this.element.addEventListener("focusout", this.onFocusOut)
    document.addEventListener("keydown", this.onKeydown)
    this.restore()
    this.render()
  }

  disconnect() {
    this.element.removeEventListener("pointerover", this.onPointerOver)
    this.element.removeEventListener("pointerout", this.onPointerOut)
    this.element.removeEventListener("focusin", this.onFocusIn)
    this.element.removeEventListener("focusout", this.onFocusOut)
    document.removeEventListener("keydown", this.onKeydown)
  }

  toggle() {
    this.#update(!this.collapsedValue)
  }

  expand() {
    this.#update(false)
  }

  collapse() {
    this.#update(true)
  }

  // Rail group control: open the full sidebar with that group disclosed.
  expandGroup(event) {
    const label = event.currentTarget?.getAttribute("data-sidebar-rail-label") || ""
    this.expand()
    if (!label || !this.hasFullTarget) return

    this.fullTarget.querySelectorAll("details").forEach((details) => {
      const summary = details.querySelector("summary")
      const text = (summary?.textContent || "").replace(/\s+/g, " ").trim()
      if (text !== label) return

      details.open = true
      summary.focus()
    })
  }

  // Rail search control: open the full sidebar with its search field focused.
  expandSearch() {
    this.expand()
    if (!this.hasFullTarget) return

    this.fullTarget.querySelector("input[type='search']")?.focus()
  }

  shortcut(event) {
    if (!(event.metaKey || event.ctrlKey) || event.key.toLowerCase() !== "b") return
    if (event.altKey || event.shiftKey || event.defaultPrevented || this.#editing(event.target)) return

    event.preventDefault()
    this.toggle()
  }

  render() {
    const collapsed = this.collapsedValue
    this.element.dataset.state = collapsed ? "collapsed" : "expanded"
    this.fullTargets.forEach((panel) => panel.toggleAttribute("inert", collapsed))
    this.railTargets.forEach((panel) => panel.toggleAttribute("inert", !collapsed))
    this.element.querySelectorAll("[data-sidebar-collapsible-toggle]").forEach((btn) => {
      btn.setAttribute("aria-expanded", String(!collapsed))
    })
    this.#clearTip()
  }

  showTip(event) {
    const trigger = event.target.closest("[data-sidebar-rail-label]")
    if (!trigger || !this.hasTooltipTarget) return
    const label = trigger.getAttribute("data-sidebar-rail-label")
    if (!label) return

    const shortcut = trigger.getAttribute("data-sidebar-rail-shortcut") || ""
    const rect = trigger.getBoundingClientRect()
    this.tooltipLabelTarget.textContent = label
    this.tooltipShortcutTarget.textContent = shortcut
    this.tooltipShortcutTarget.classList.toggle("hidden", !shortcut)
    this.tooltipTarget.style.left = `${rect.right + 8}px`
    this.tooltipTarget.style.top = `${rect.top + rect.height / 2}px`
    this.tooltipTarget.classList.remove("hidden")
    this.tooltipTarget.classList.add("flex")
  }

  hideTip(event) {
    if (!this.hasTooltipTarget) return
    const trigger = event.target.closest("[data-sidebar-rail-label]")
    if (!trigger) return
    const next = event.relatedTarget
    if (next && trigger.contains(next)) return
    this.#clearTip()
  }

  persist() {
    document.cookie = `${this.cookieValue}=${this.collapsedValue ? "collapsed" : "expanded"}; path=/; SameSite=Lax`
  }

  restore() {
    const prefix = `${this.cookieValue}=`
    const saved = document.cookie.split(/;\s*/).find((pair) => pair.startsWith(prefix))?.slice(prefix.length)
    if (saved === "collapsed") this.collapsedValue = true
    if (saved === "expanded") this.collapsedValue = false
  }

  #update(collapsed) {
    const leaving = collapsed ? this.fullTargets : this.railTargets
    const hadFocus = leaving.some((panel) => panel.contains(document.activeElement))
    this.collapsedValue = collapsed
    this.persist()
    this.render()
    if (!hadFocus) return

    const arriving = collapsed ? this.railTargets : this.fullTargets
    arriving[0]?.querySelector("[data-sidebar-collapsible-toggle]")?.focus()
  }

  #editing(target) {
    return target instanceof Element &&
      target.closest("input, textarea, select, [contenteditable]:not([contenteditable='false'])") !== null
  }

  #clearTip() {
    if (!this.hasTooltipTarget) return
    this.tooltipTarget.classList.add("hidden")
    this.tooltipTarget.classList.remove("flex")
    this.tooltipLabelTarget.textContent = ""
    this.tooltipShortcutTarget.textContent = ""
  }
}
