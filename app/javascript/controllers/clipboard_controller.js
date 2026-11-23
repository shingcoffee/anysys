import { Controller } from "@hotwired/stimulus"

/**
 * Clipboard Controller
 * Provides copy-to-clipboard functionality with visual feedback.
 */
export default class extends Controller {
  static targets = ["text", "button", "icon", "success"]

  connect() {
  }

  copy(event) {
    event.preventDefault()
    event.stopPropagation()

    // Get text from data attribute or text target
    const textToCopy = this.element.dataset.clipboardValueValue ||
                       (this.hasTextTarget ? this.textTarget.textContent.trim() : "")

    if (!textToCopy) {
      console.error("No text to copy")
      return
    }

    if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
      navigator.clipboard.writeText(textToCopy).then(() => {
        this.showSuccess()
      }).catch(() => {
        this.fallbackCopy(textToCopy)
      })
    } else {
      this.fallbackCopy(textToCopy)
    }
  }

  showSuccess() {
    if (this.hasIconTarget && this.hasSuccessTarget) {
      this.iconTarget.classList.add("hidden")
      this.successTarget.classList.remove("hidden")

      setTimeout(() => {
        this.iconTarget.classList.remove("hidden")
        this.successTarget.classList.add("hidden")
      }, 1500)
    }

    if (this.hasButtonTarget) {
      this.buttonTarget.classList.add("text-green-600")
      setTimeout(() => {
        this.buttonTarget.classList.remove("text-green-600")
      }, 1500)
    }
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
      const successful = document.execCommand("copy")
      if (successful) {
        this.showSuccess()
      }
    } catch {
      // Copy failed silently
    }

    document.body.removeChild(textarea)
  }
}
