import { Controller } from "@hotwired/stimulus"

// Progressive-enhancement interval filter for the plan comparison grid.
// Server-rendered HTML keeps every plan card visible (Capybara / no-JS).
// On connect, paid cards are filtered by interval while free cards stay visible.
export default class extends Controller {
  static targets = ["button", "card"]
  static values = { interval: { type: String, default: "monthly" } }

  connect() {
    this.#sync()
  }

  selectInterval(event) {
    this.intervalValue = event.params.interval
    this.#sync()
  }

  keydown(event) {
    if (event.key === "ArrowRight" || event.key === "ArrowDown" || event.key === "ArrowLeft" || event.key === "ArrowUp") {
      event.preventDefault()
      const buttons = this.buttonTargets
      const delta = event.key === "ArrowRight" || event.key === "ArrowDown" ? 1 : -1
      const nextBtn = buttons[(buttons.indexOf(event.currentTarget) + delta + buttons.length) % buttons.length]
      this.intervalValue = nextBtn.dataset.billingPlanCatalogIntervalParam
      this.#sync()
      nextBtn.focus()
    }
  }

  #sync() {
    this.buttonTargets.forEach((btn) => {
      const active = btn.dataset.billingPlanCatalogIntervalParam === this.intervalValue
      btn.setAttribute("aria-checked", active ? "true" : "false")
      btn.tabIndex = active ? 0 : -1
      btn.classList.toggle("bg-surface", active)
      btn.classList.toggle("text-text-primary", active)
      btn.classList.toggle("shadow-xs", active)
      btn.classList.toggle("text-text-secondary", !active)
      btn.classList.toggle("hover:text-text-primary", !active)
    })

    this.cardTargets.forEach((card) => {
      const isFree = card.dataset.free === "true"
      const matches = isFree || card.dataset.interval === this.intervalValue
      card.classList.toggle("hidden", !matches)
    })
  }
}
