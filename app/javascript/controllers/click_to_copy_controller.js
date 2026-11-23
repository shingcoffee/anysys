import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    text: String,
    copiedFeedback: { type: String, default: "Copied!" }
  }

  copy(event) {
    if (event) event.preventDefault()
    const text = this.textValue

    if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
      navigator.clipboard.writeText(text).then(() => {
        this.showFeedback()
      }).catch((err) => {
        console.error("Failed to copy using clipboard API:", err)
        this.fallbackCopy(text)
      })
    } else {
      this.fallbackCopy(text)
    }
  }

  showFeedback() {
    if (this._originalText === undefined) {
      this._originalText = this.element.textContent
      this._originalClass = this.element.className
    }
    clearTimeout(this._restoreTimer)

    this.element.textContent = this.copiedFeedbackValue
    this.element.classList.add("bg-green-100", "text-green-800", "border-green-300")
    this.element.classList.remove("bg-gray-50", "text-gray-700", "border-gray-200")

    this._restoreTimer = setTimeout(() => {
      this.element.textContent = this._originalText
      this.element.className = this._originalClass
      this._originalText = undefined
      this._originalClass = undefined
    }, 1500)
  }

  fallbackCopy(text) {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.style.position = "fixed"
    textarea.style.left = "-9999px"
    textarea.style.top = "0"
    textarea.setAttribute("readonly", "")
    document.body.appendChild(textarea)
    textarea.select()
    textarea.setSelectionRange(0, text.length)

    try {
      if (document.execCommand("copy")) {
        this.showFeedback()
      }
    } catch (err) {
      console.error("Fallback copy failed:", err)
    } finally {
      document.body.removeChild(textarea)
    }
  }
}
