import { Controller } from "@hotwired/stimulus"

/**
 * Copy Code Controller
 * Handles copying code blocks to clipboard with visual feedback.
 */
export default class extends Controller {
  static targets = ["code", "copyIcon", "checkIcon", "copyText"]
  static values = {
    copy: { type: String, default: "Copy" },
    copied: { type: String, default: "Copied!" }
  }

  copy() {
    const code = this.codeTarget.textContent

    // Check if clipboard API is available (requires HTTPS or localhost)
    if (navigator.clipboard && typeof navigator.clipboard.writeText === "function") {
      navigator.clipboard.writeText(code).then(() => {
        this.showCopiedFeedback()
      }).catch(() => {
        // Fallback if clipboard API fails
        this.fallbackCopy(code)
      })
    } else {
      // Use fallback for non-secure contexts
      this.fallbackCopy(code)
    }
  }

  showCopiedFeedback() {
    // Update button appearance
    this.element.classList.add("copied")
    this.copyIconTarget.classList.add("hidden")
    this.checkIconTarget.classList.remove("hidden")
    this.copyTextTarget.textContent = this.copiedValue

    // Reset after 2 seconds
    setTimeout(() => {
      this.element.classList.remove("copied")
      this.copyIconTarget.classList.remove("hidden")
      this.checkIconTarget.classList.add("hidden")
      this.copyTextTarget.textContent = this.copyValue
    }, 2000)
  }

  fallbackCopy(text) {
    // Fallback using textarea for non-secure contexts
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
        this.showCopiedFeedback()
      }
    } catch (err) {
      console.error("Copy failed:", err)
    }

    document.body.removeChild(textarea)
  }
}
