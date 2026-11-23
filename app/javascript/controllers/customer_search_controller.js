import { Controller } from "@hotwired/stimulus"

// Debounces input changes and submits the wrapping <form>.
// The form has data-turbo-frame=... so Turbo swaps only the frame.
export default class extends Controller {
  static values = { wait: { type: Number, default: 250 } }

  connect() {
    this.timer = null
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  submit() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      this.element.requestSubmit()
    }, this.waitValue)
  }
}
