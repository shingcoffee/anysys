import { Controller } from "@hotwired/stimulus"

// Accessible tablist for the feature_tabs marketing section.
// The first tab is selected in the HTML so the panel is visible without JS.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static classes = ["active", "inactive"]
  static values = { index: { type: Number, default: 0 } }

  connect() {
    this.activate(this.clampedIndex(), { focus: false })
  }

  choose(event) {
    const index = this.tabTargets.indexOf(event.currentTarget)
    if (index < 0) return
    this.activate(index, { focus: false })
  }

  navigate(event) {
    const delta = this.deltaFor(event.key)
    if (delta === null) return

    event.preventDefault()
    this.activate(this.nextIndex(delta), { focus: true })
  }

  activate(index, options) {
    const focus = options ? options.focus : false
    if (!this.hasTabTarget) return

    const selected = this.clampedIndex(index)
    this.indexValue = selected

    this.tabTargets.forEach((tab, i) => {
      const on = i === selected
      tab.setAttribute("aria-selected", on ? "true" : "false")
      tab.tabIndex = on ? 0 : -1
      this.activeClasses.forEach((cls) => tab.classList.toggle(cls, on))
      this.inactiveClasses.forEach((cls) => tab.classList.toggle(cls, !on))
    })

    this.panelTargets.forEach((panel, i) => {
      const on = i === selected
      panel.toggleAttribute("hidden", !on)
      panel.classList.toggle("hidden", !on)
    })

    if (focus) this.tabTargets[selected].focus()
  }

  clampedIndex(index = this.indexValue) {
    const count = this.tabTargets.length
    if (count === 0) return 0
    const n = Number(index)
    if (!Number.isFinite(n)) return 0
    const i = Math.trunc(n)
    return ((i % count) + count) % count
  }

  deltaFor(key) {
    if (key === "ArrowRight" || key === "ArrowDown") return 1
    if (key === "ArrowLeft" || key === "ArrowUp") return -1
    if (key === "Home") return "home"
    if (key === "End") return "end"
    return null
  }

  nextIndex(delta) {
    if (delta === "home") return 0
    if (delta === "end") return Math.max(this.tabTargets.length - 1, 0)
    return this.clampedIndex(this.indexValue + delta)
  }
}
