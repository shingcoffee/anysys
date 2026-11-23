import { Controller } from "@hotwired/stimulus"

// The "+ Add New" modal (Admin::Entities::QuickAddDialogComponent).
// open() loads an entity's Create Entry form into the Turbo frame; when the
// saved-entry marker (created target) arrives, the opener's callback receives
// { id, label } and the dialog closes. A nested level's dialog lives inside
// this frame, so its bubbling frame events are left to its own controller.
export default class extends Controller {
  static targets = ["title", "frame", "loading", "failure", "created"]

  open({ url, title, onCreated }) {
    this.onCreated = onCreated
    this.titleTarget.textContent = title
    this.frameTarget.innerHTML = this.loadingTarget.innerHTML
    // Drop src first so reopening the same entity reloads a blank form.
    this.frameTarget.removeAttribute("src")
    this.frameTarget.setAttribute("src", url)
    this.element.showModal()
  }

  close() {
    this.element.close()
  }

  backdrop(event) {
    if (event.target === this.element) this.close()
  }

  // The close event is queued, so it can arrive after a quick reopen; it must
  // not wipe the reopened form.
  reset() {
    if (this.element.open) return

    this.onCreated = null
    this.frameTarget.removeAttribute("src")
    this.frameTarget.innerHTML = ""
  }

  missing(event) {
    if (event.target !== this.frameTarget) return

    event.preventDefault()
    this.frameTarget.innerHTML = this.failureTarget.innerHTML
  }

  createdTargetConnected(element) {
    const callback = this.onCreated
    this.close()
    if (callback) callback({ id: element.dataset.entryId, label: element.dataset.entryLabel })
  }
}
