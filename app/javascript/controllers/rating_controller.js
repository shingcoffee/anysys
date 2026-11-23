import { Controller } from "@hotwired/stimulus"

/**
 * Rating Controller
 *
 * Handles star rating interactivity for the RatingFieldComponent.
 * Supports click to select, hover preview, and keyboard navigation.
 */
export default class extends Controller {
  static targets = ["stars", "input", "label"]
  static values = {
    notRatedLabel: { type: String, default: "Not rated" },
    valueOfFormat: { type: String, default: "{value} of {max}" }
  }

  connect() {
    this.updateDisplay()
  }

  select(event) {
    const value = parseInt(event.currentTarget.dataset.value, 10)
    this.inputTarget.value = value
    this.updateDisplay()

    // Dispatch change event for form handling
    this.inputTarget.dispatchEvent(new Event('change', { bubbles: true }))
  }

  hover(event) {
    const value = parseInt(event.currentTarget.dataset.value, 10)
    this.highlightStars(value)
  }

  unhover() {
    const currentValue = parseInt(this.inputTarget.value, 10) || 0
    this.highlightStars(currentValue)
  }

  updateDisplay() {
    const value = parseInt(this.inputTarget.value, 10) || 0
    this.highlightStars(value)
    this.updateLabel(value)
  }

  highlightStars(upTo) {
    const stars = this.starsTarget.querySelectorAll('[data-rating-star]')
    const _max = stars.length

    stars.forEach((star, index) => {
      const starValue = index + 1
      const isSelected = starValue <= upTo

      star.dataset.selected = isSelected
      const svg = star.querySelector('svg')

      if (isSelected) {
        svg.classList.remove('text-gray-300')
        svg.classList.add('text-amber-400', 'fill-current')
      } else {
        svg.classList.remove('text-amber-400', 'fill-current')
        svg.classList.add('text-gray-300')
      }
    })
  }

  updateLabel(value) {
    if (!this.hasLabelTarget) return

    const max = this.starsTarget.querySelectorAll('[data-rating-star]').length
    this.labelTarget.textContent = value > 0
      ? this.valueOfFormatValue.replace("{value}", String(value)).replace("{max}", String(max))
      : this.notRatedLabelValue
  }
}
