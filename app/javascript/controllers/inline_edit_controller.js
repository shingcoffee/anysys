import { Controller } from "@hotwired/stimulus"

// Toggles a field between a read-only display and an inline edit form.
// Markup: a `display` target (shown by default) and a `form` target (hidden).
// `edit` reveals the form and focuses its `input`; `cancel` reverts. Only one
// display utility is ever present on each target, so `hidden`/`flex` never clash.
export default class extends Controller {
  static targets = ["display", "form", "input"]

  edit() {
    this.#hide(this.displayTarget)
    this.#show(this.formTarget)
    if (this.hasInputTarget) this.inputTarget.focus()
  }

  cancel() {
    this.#hide(this.formTarget)
    this.#show(this.displayTarget)
  }

  #show(el) {
    el.classList.remove("hidden")
    el.classList.add("flex")
  }

  #hide(el) {
    el.classList.add("hidden")
    el.classList.remove("flex")
  }
}
