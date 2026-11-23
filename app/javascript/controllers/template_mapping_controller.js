import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card", "checkbox", "counter", "filterTab", "grid"]

  connect() {
    this.currentCategory = "all"
    this.updateCounter()
  }

  filterCategory(event) {
    const category = event.currentTarget.dataset.category
    this.currentCategory = category

    // Update tab styles
    this.filterTabTargets.forEach(tab => {
      if (tab.dataset.category === category) {
        tab.className = "px-3 py-1.5 text-xs font-medium rounded-lg transition-colors bg-indigo-600 text-white"
      } else {
        tab.className = "px-3 py-1.5 text-xs font-medium rounded-lg transition-colors bg-gray-100 text-gray-700 hover:bg-gray-200"
      }
    })

    // Show/hide cards
    this.cardTargets.forEach(card => {
      if (category === "all" || card.dataset.category === category) {
        card.classList.remove("hidden")
      } else {
        card.classList.add("hidden")
      }
    })
  }

  selectAll() {
    this.visibleCheckboxes().forEach(cb => {
      cb.checked = true
      this.updateCardStyle(cb)
    })
    this.updateCounter()
  }

  deselectAll() {
    this.visibleCheckboxes().forEach(cb => {
      cb.checked = false
      this.updateCardStyle(cb)
    })
    this.updateCounter()
  }

  toggleCard(event) {
    this.updateCardStyle(event.target)
    this.updateCounter()
  }

  updateCardStyle(checkbox) {
    const card = checkbox.closest("[data-template-mapping-target='card']")
    if (!card) return

    if (checkbox.checked) {
      card.classList.remove("border-gray-200", "bg-white", "hover:border-gray-300")
      card.classList.add("border-indigo-300", "bg-indigo-50")
    } else {
      card.classList.remove("border-indigo-300", "bg-indigo-50")
      card.classList.add("border-gray-200", "bg-white", "hover:border-gray-300")
    }
  }

  updateCounter() {
    const count = this.checkboxTargets.filter(cb => cb.checked).length
    this.counterTargets.forEach(el => {
      el.textContent = count
    })
  }

  visibleCheckboxes() {
    return this.checkboxTargets.filter(cb => {
      const card = cb.closest("[data-template-mapping-target='card']")
      return card && !card.classList.contains("hidden")
    })
  }
}
