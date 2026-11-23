import { Controller } from "@hotwired/stimulus"

const HIGHLIGHT_MS = 4000

// Scrolls the section named by the id value into view once the page is shown,
// then briefly highlights it and the cue targets (its call to action) inside.
// A Turbo visit scrolls to the top after the new body connects, so mid-visit
// (the root is aria-busy) the reveal waits for turbo:load. The value is cleared
// and the highlight dropped before caching so a page restored by Back stays put.
export default class extends Controller {
  static values = { id: String }
  static targets = ["cue"]
  static classes = ["highlight", "cue"]

  connect() {
    if (!this.idValue) return

    if (document.documentElement.hasAttribute("aria-busy")) {
      document.addEventListener("turbo:load", this.reveal, { once: true })
    } else {
      this.reveal()
    }
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.reveal)
    this.settle()
  }

  reveal = () => {
    const section = document.getElementById(this.idValue)
    this.idValue = ""
    if (!section) return

    section.scrollIntoView()
    this.highlighted = [
      [section, this.highlightClasses],
      ...this.cueTargets.filter((cue) => section.contains(cue)).map((cue) => [cue, this.cueClasses])
    ]
    this.highlighted.forEach(([node, classes]) => node.classList.add(...classes))
    this.timeout = setTimeout(this.settle, HIGHLIGHT_MS)
    document.addEventListener("turbo:before-cache", this.settle, { once: true })
  }

  settle = () => {
    clearTimeout(this.timeout)
    document.removeEventListener("turbo:before-cache", this.settle)
    this.highlighted?.forEach(([node, classes]) => node.classList.remove(...classes))
    this.highlighted = null
  }
}
