import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    autoDismiss: Boolean
  }

  connect() {
    if (this.autoDismissValue) {
      this.timeout = setTimeout(() => {
        this.dismiss()
      }, 5000) // Auto-dismiss after 5 seconds for success messages
    }
  }

  disconnect() {
    if (this.timeout) {
      clearTimeout(this.timeout)
    }
  }

  dismiss() {
    // Fade out animation
    this.element.style.transition = 'opacity 0.3s ease-out, max-height 0.3s ease-out, margin 0.3s ease-out'
    this.element.style.opacity = '0'
    this.element.style.maxHeight = '0'
    this.element.style.marginBottom = '0'
    this.element.style.overflow = 'hidden'

    // Remove element after animation
    setTimeout(() => {
      this.element.remove()
    }, 300)
  }
}
