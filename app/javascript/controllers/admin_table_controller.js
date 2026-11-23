import { Controller } from "@hotwired/stimulus"

// Debounced list search. The submit re-renders the surrounding turbo-frame,
// which replaces the search box mid-typing; the last typed state is kept at
// module level so the fresh input gets focus, caret and any characters typed
// while the request was in flight back.
const PENDING_TTL_MS = 10000
let pendingFocus = null

export default class extends Controller {
  static targets = ["searchInput"]

  disconnect() {
    clearTimeout(this._debounceHandle)
  }

  debounceSubmit(event) {
    const input = event.target
    this.#remember(input)
    this.#schedule(input)
  }

  submit(event) {
    event.target.form.requestSubmit()
  }

  searchInputTargetConnected(input) {
    const pending = pendingFocus
    if (!pending || pending.name !== input.name || Date.now() - pending.at > PENDING_TTL_MS) return

    pendingFocus = null
    if (input.value !== pending.value) {
      input.value = pending.value
      this.#remember(input)
      this.#schedule(input)
    }
    input.focus()
    const end = input.value.length
    input.setSelectionRange(end, end)
  }

  #remember(input) {
    pendingFocus = { name: input.name, value: input.value, at: Date.now() }
  }

  #schedule(input) {
    clearTimeout(this._debounceHandle)
    this._debounceHandle = setTimeout(() => input.form.requestSubmit(), 300)
  }
}
