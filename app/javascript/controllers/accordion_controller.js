import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]

  closeOthers(event) {
    const opened = event.currentTarget
    if (!opened.open) return

    this.itemTargets.forEach((item) => {
      if (item !== opened) {
        item.open = false
      }
    })
  }
}
