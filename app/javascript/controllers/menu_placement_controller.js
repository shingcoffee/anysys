import { Controller } from "@hotwired/stimulus"

// Places a <details> popup menu with position:fixed so it is never clipped by
// overflow:hidden / overflow-x-auto ancestors (admin table cards, table scroll
// wrappers). On open, anchors to the summary trigger; flips above when there
// is more room above the trigger than below.
//
// Usage:
//   <details data-controller="menu-placement" data-action="toggle->menu-placement#reposition">
//     <summary>…</summary>
//     <div data-menu-placement-target="panel" class="absolute right-0 mt-1 …">…</div>
//   </details>
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.boundReposition = this.reposition.bind(this)
    this.boundCloseOnOutside = this.#closeOnOutside.bind(this)
  }

  disconnect() {
    this.#teardownListeners()
    this.#clearFixed()
  }

  reposition() {
    if (!this.hasPanelTarget) return

    if (!this.element.open) {
      this.#teardownListeners()
      this.#clearFixed()
      return
    }

    this.#placeFixed()
    this.#setupListeners()
  }

  #placeFixed() {
    const panel = this.panelTarget
    const trigger = this.element.querySelector("summary") || this.element
    const rect = trigger.getBoundingClientRect()
    const gap = 4

    // Escape overflow clipping by pinning to the viewport.
    panel.style.position = "fixed"
    panel.style.left = "auto"
    panel.style.right = `${Math.max(8, window.innerWidth - rect.right)}px`
    panel.style.zIndex = "50"

    // Measure below first, then flip if needed.
    panel.style.top = `${rect.bottom + gap}px`
    panel.style.bottom = "auto"

    const menu = panel.getBoundingClientRect()
    const roomBelow = window.innerHeight - rect.bottom - gap
    const roomAbove = rect.top - gap

    if (menu.height > roomBelow && roomAbove >= menu.height) {
      panel.style.top = "auto"
      panel.style.bottom = `${Math.max(8, window.innerHeight - rect.top + gap)}px`
    }
  }

  #clearFixed() {
    if (!this.hasPanelTarget) return
    const panel = this.panelTarget
    panel.style.position = ""
    panel.style.top = ""
    panel.style.bottom = ""
    panel.style.left = ""
    panel.style.right = ""
    panel.style.zIndex = ""
  }

  #setupListeners() {
    if (this.listening) return
    this.listening = true
    window.addEventListener("scroll", this.boundReposition, true)
    window.addEventListener("resize", this.boundReposition)
    document.addEventListener("click", this.boundCloseOnOutside, true)
  }

  #teardownListeners() {
    if (!this.listening) return
    this.listening = false
    window.removeEventListener("scroll", this.boundReposition, true)
    window.removeEventListener("resize", this.boundReposition)
    document.removeEventListener("click", this.boundCloseOnOutside, true)
  }

  #closeOnOutside(event) {
    if (!this.element.open) return
    if (this.element.contains(event.target)) return
    this.element.open = false
    this.reposition()
  }
}
