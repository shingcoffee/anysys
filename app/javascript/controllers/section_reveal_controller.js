import { Controller } from "@hotwired/stimulus"

// Opens a collapsed section's <details> before an in-page jump lands on it,
// for the URL fragment on load and for index links clicked afterwards.
export default class extends Controller {
  connect() {
    this.reveal(window.location.hash)
  }

  open(event) {
    this.reveal(event.currentTarget.hash)
  }

  reveal(hash) {
    const target = hash && document.getElementById(hash.slice(1))
    if (!target || !this.element.contains(target)) return

    const details = Array.from(target.children).find((child) => child.tagName === "DETAILS")
    if (details) details.open = true
  }
}
