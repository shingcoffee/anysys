import { Controller } from "@hotwired/stimulus"

// Composes the admin's answers into ordinary message text. Sending is the
// parent `ai-assistant` controller's job — this only dispatches `{ body }`.
export default class extends Controller {
  static values = {
    noPreference: { type: String, default: "No preference" },
    listSeparator: { type: String, default: ", " },
    skipReply: {
      type: String,
      default: "Use your best judgement for these and go ahead."
    }
  }

  send(event) {
    if (event) event.preventDefault()
    this.dispatch("answer", { detail: { body: this.#compose() } })
  }

  skip(event) {
    if (event) event.preventDefault()
    this.dispatch("answer", { detail: { body: this.skipReplyValue } })
  }

  // A picked radio on a single question replaces a typed other-answer.
  pickOption(event) {
    const fieldset = this.#fieldsetFor(event)
    if (!fieldset || fieldset.dataset.questionType !== "single") return

    const other = this.#otherInput(fieldset)
    if (other) other.value = ""
  }

  // Typing into a single question's other input drops its radio selection.
  // Multiple questions keep both.
  typeOther(event) {
    const fieldset = this.#fieldsetFor(event)
    if (!fieldset || fieldset.dataset.questionType !== "single") return

    fieldset.querySelectorAll('input[type="radio"]').forEach((input) => {
      input.checked = false
    })
  }

  // Enter in an other/text field must not submit — a card can hold five
  // questions, and Send is the only way out.
  preventSubmit(event) {
    if (!event || event.key !== "Enter") return

    event.preventDefault()
  }

  #compose() {
    return this.#questionFieldsets()
      .map((fieldset) => {
        const prompt = fieldset.dataset.questionPrompt || ""
        return `${prompt}\n${this.#answerFor(fieldset)}`
      })
      .join("\n\n")
  }

  #answerFor(fieldset) {
    const type = fieldset.dataset.questionType
    if (type === "text") {
      const input = fieldset.querySelector("[data-question-text]")
      const value = input ? input.value.trim() : ""
      return value || this.noPreferenceValue
    }
    if (type === "single") {
      const other = this.#otherInput(fieldset)
      const otherValue = other ? other.value.trim() : ""
      if (otherValue) return otherValue

      const checked = fieldset.querySelector('input[type="radio"]:checked')
      return checked ? checked.value : this.noPreferenceValue
    }
    if (type === "multiple") {
      const checked = Array.from(fieldset.querySelectorAll('input[type="checkbox"]:checked'))
        .map((input) => input.value)
      const other = this.#otherInput(fieldset)
      const otherValue = other ? other.value.trim() : ""
      const parts = otherValue ? [ ...checked, otherValue ] : checked
      return parts.length ? parts.join(this.listSeparatorValue) : this.noPreferenceValue
    }

    return this.noPreferenceValue
  }

  #questionFieldsets() {
    return Array.from(this.element.querySelectorAll("[data-question-type]"))
  }

  #otherInput(fieldset) {
    return fieldset.querySelector("[data-question-other]")
  }

  #fieldsetFor(event) {
    const target = event && event.currentTarget
    if (!target || typeof target.closest !== "function") return null

    return target.closest("[data-question-type]")
  }
}
