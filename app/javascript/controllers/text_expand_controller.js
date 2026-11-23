import { Controller } from "@hotwired/stimulus"

const IGNORE = "a, button, input, textarea, select, label"

function truncate(text, limit) {
  if (text.length <= limit) return text
  const budget = Math.max(1, limit - 1)
  return `${text.slice(0, budget).trimEnd()}…`
}

export default class extends Controller {
  static targets = ["clamped", "markRead"]
  static values = { limit: { type: Number, default: 140 } }

  connect() {
    this.expanded = false
    this.marked = false
    this.fullTexts = this.clampedTargets.map((el) => el.textContent)
    this.limits = this.clampedTargets.map((el) => this.limitFor(el))
    this.apply()
  }

  toggle(event) {
    if (event.target.closest(IGNORE)) return

    if (this.expanded || this.anyTruncatable()) {
      event.preventDefault()
      event.stopPropagation()
      this.expanded = !this.expanded
      this.apply()
    }

    this.markReadOnce()
  }

  apply() {
    this.clampedTargets.forEach((el, index) => {
      const full = this.fullTexts[index]
      el.textContent = this.expanded ? full : truncate(full, this.limits[index])
    })
    this.sync()
  }

  anyTruncatable() {
    return this.fullTexts.some((text, index) => text.length > this.limits[index])
  }

  limitFor(el) {
    const parsed = Number(el.dataset.limit)
    return Number.isFinite(parsed) && parsed > 0 ? parsed : this.limitValue
  }

  sync() {
    const active = this.anyTruncatable()
    this.element.classList.toggle("cursor-pointer", active)
    if (active) {
      this.element.setAttribute("aria-expanded", String(this.expanded))
      this.element.setAttribute("tabindex", "0")
    } else {
      this.element.removeAttribute("aria-expanded")
      this.element.removeAttribute("tabindex")
    }
  }

  markReadOnce() {
    if (this.marked || !this.hasMarkReadTarget) return
    this.marked = true
    this.markReadTarget.requestSubmit()
  }
}
