import { Controller } from "@hotwired/stimulus"

// Submits the surrounding form when an input fires the `submit` action.
// Used by the per-source enabled-toggle to persist on change.
export default class extends Controller {
  submit() {
    if (this.element.requestSubmit) {
      this.element.requestSubmit()
    } else {
      this.element.submit()
    }
  }
}
