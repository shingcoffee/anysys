import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    fieldId: String,
    status: String,
    transcript: String,
    error: String
  }

  connect() {
    const field = this.fieldIdValue ? document.getElementById(this.fieldIdValue) : null
    const status = this.#statusElement()

    if (this.statusValue === "succeeded") {
      if (this.transcriptValue && field) {
        const current = field.value
        field.value = current ? `${current} ${this.transcriptValue}` : this.transcriptValue
      }
      this.#setStatus(status, "", false)
      return
    }

    if (this.statusValue === "failed") {
      this.#setStatus(status, this.errorValue, true)
    }
  }

  #statusElement() {
    let node = this.element.parentElement
    while (node) {
      const tokens = (node.getAttribute("data-controller") || "").split(/\s+/).filter(Boolean)
      if (tokens.includes("speech-to-text")) {
        return node.querySelector("[data-speech-to-text-target='status']")
      }
      node = node.parentElement
    }
    return null
  }

  #setStatus(node, text, isError) {
    if (!node) return
    node.textContent = text || ""
    node.classList.toggle("text-danger", Boolean(isError) && Boolean(text))
    node.classList.toggle("text-text-muted", !isError || !text)
  }
}
