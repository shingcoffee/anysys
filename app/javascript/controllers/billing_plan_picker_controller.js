import { Controller } from "@hotwired/stimulus"

// Handles the plan-picker card grid. Clicking a card highlights it and checks
// the hidden radio input so the form posts the correct plan_code.
//
// Usage (added automatically by PlanPickerComponent):
//   data-controller="billing-plan-picker"
//   data-billing-plan-picker-target="card" (each label)
//   data-billing-plan-picker-target="radio" (each radio input inside label)
export default class extends Controller {
  static targets = ["card", "radio"]

  connect() {
    // Highlight the initially selected card (page reload after error, etc.)
    this.radioTargets.forEach((radio, idx) => {
      if (radio.checked) this.#activateCard(this.cardTargets[idx])
    })
  }

  // Called by clicking anywhere on a card label; the browser also
  // checks the radio via the <label> association, so we just re-style.
  select(event) {
    const card = event.currentTarget
    this.cardTargets.forEach(c => this.#deactivateCard(c))
    this.#activateCard(card)
  }

  #activateCard(card) {
    card.classList.remove("border-border-subtle", "hover:border-accent/50")
    card.classList.add("border-accent", "bg-accent/5")
  }

  #deactivateCard(card) {
    card.classList.remove("border-accent", "bg-accent/5")
    card.classList.add("border-border-subtle", "hover:border-accent/50")
  }
}
