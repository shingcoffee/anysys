import { Controller } from "@hotwired/stimulus"

const AUDIENCES = ["admin", "member", "public"]
const LOCK_ON = ["opacity-60", "cursor-not-allowed"]
const HIDDEN_NAME = "page[visible_audiences][]"

/**
 * PageVisibility Controller
 *
 * Independent audience switches. The last remaining audience cannot be
 * turned off: that input is disabled and the reason comes from the
 * server-passed lastAudience value (English default when missing).
 * Hidden inputs keep a disabled last switch in the POST.
 *
 * Usage:
 *   <form data-controller="page-visibility"
 *         data-page-visibility-saving-value="Saving…"
 *         data-page-visibility-last-audience-value="A form needs at least one audience.">
 *     <span data-page-visibility-target="status"></span>
 *     <input type="checkbox" data-page-visibility-target="admin"
 *            data-action="change->page-visibility#sync">
 *   </form>
 */
export default class extends Controller {
  static targets = ["admin", "member", "public", "status"]

  static values = {
    saving: { type: String, default: "Saving…" },
    lastAudience: { type: String, default: "A form needs at least one audience." }
  }

  connect() {
    this.applyLock()
    this.rebuildHiddenInputs()
  }

  sync() {
    this.applyLock()
    this.rebuildHiddenInputs()
    this.submit()
  }

  submit() {
    this.showStatus(this.savingValue)

    if (this.element.requestSubmit) {
      this.element.requestSubmit()
    } else {
      this.element.submit()
    }
  }

  showStatus(text) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = text
    this.statusTarget.classList.remove("hidden")
  }

  applyLock() {
    const inputs = this.audienceInputs()
    const checked = inputs.filter((input) => input.checked)

    inputs.forEach((input) => {
      if (checked.length === 1 && input === checked[0]) {
        this.lockInput(input)
      } else {
        this.unlockInput(input)
      }
    })
  }

  audienceInputs() {
    return AUDIENCES.flatMap((name) => {
      const cap = name.charAt(0).toUpperCase() + name.slice(1)
      return this[`has${cap}Target`] ? [this[`${name}Target`]] : []
    })
  }

  lockInput(input) {
    input.disabled = true
    if (!input.dataset.unlockedAria) {
      const current = input.getAttribute("aria-label")
      if (current) input.dataset.unlockedAria = current
    }
    input.setAttribute("aria-label", this.lastAudienceValue)
    const wrapper = input.closest("label")
    if (!wrapper) return

    wrapper.classList.remove("cursor-pointer")
    wrapper.classList.add(...LOCK_ON)
    wrapper.dataset.tooltip = this.lastAudienceValue
  }

  unlockInput(input) {
    input.disabled = false
    if (input.dataset.unlockedAria) {
      input.setAttribute("aria-label", input.dataset.unlockedAria)
      delete input.dataset.unlockedAria
    }
    const wrapper = input.closest("label")
    if (!wrapper) return

    wrapper.classList.add("cursor-pointer")
    wrapper.classList.remove(...LOCK_ON)
    delete wrapper.dataset.tooltip
  }

  rebuildHiddenInputs() {
    this.element
      .querySelectorAll(`input[type="hidden"][name="${HIDDEN_NAME}"]`)
      .forEach((el) => el.remove())

    this.audienceInputs()
      .filter((input) => input.checked)
      .forEach((input) => {
        const hidden = document.createElement("input")
        hidden.type = "hidden"
        hidden.name = HIDDEN_NAME
        hidden.value = input.value
        this.element.appendChild(hidden)
      })
  }
}
