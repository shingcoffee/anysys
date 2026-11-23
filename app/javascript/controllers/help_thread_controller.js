import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["thread", "form"]

  connect() {
    this.observer = null
    if (this.hasThreadTarget) {
      this.observer = new MutationObserver(() => this.#scrollToBottom())
      this.observer.observe(this.threadTarget, { childList: true, subtree: true })
    }
    this.#scrollToBottom()
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
      this.observer = null
    }
  }

  keydown(event) {
    if (event.key !== "Enter" || event.shiftKey) return
    event.preventDefault()
    this.submit()
  }

  submit() {
    if (!this.hasFormTarget) return
    this.formTarget.requestSubmit()
  }

  #scrollToBottom() {
    if (!this.hasThreadTarget) return
    this.threadTarget.scrollTop = this.threadTarget.scrollHeight
  }
}
