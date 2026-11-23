import { Controller } from "@hotwired/stimulus"

// Right-side slide-over panel with a backdrop. Dismisses when the backdrop
// is clicked, Escape is pressed, or close() is invoked (e.g. the Close link).
// Clearing the host turbo-frame removes the panel without a full-page reload.
//
// Targets:
//   backdrop — full-screen scrim behind the panel
//   panel    — the slide-over content (optional; used for focus containment)
//
// Values:
//   frameId — turbo-frame id to clear on close (blank: remove the element)
//
// Usage:
//   <div data-controller="slide-over" data-slide-over-frame-id-value="page-publishing">
//     <div data-slide-over-target="backdrop" data-action="click->slide-over#close"></div>
//     <aside data-slide-over-target="panel">…</aside>
//   </div>
export default class extends Controller {
  static targets = ["backdrop", "panel"]
  static values = {
    frameId: { type: String, default: "" }
  }

  connect() {
    this.boundKeydown = this.keydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
    document.body.style.overflow = "hidden"
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
    document.body.style.overflow = ""
  }

  close(event) {
    if (event) event.preventDefault()

    const frame = this.#frame()
    if (frame) {
      frame.removeAttribute("src")
      frame.innerHTML = ""
      return
    }

    this.element.remove()
  }

  keydown(event) {
    if (event.key === "Escape") this.close(event)
  }

  #frame() {
    const id = this.frameIdValue
    if (!id) return null
    return this.element.closest("turbo-frame") || document.getElementById(id)
  }
}
