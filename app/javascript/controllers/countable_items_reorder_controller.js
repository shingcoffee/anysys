import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

// Provides reordering for the Countable Items form list.
//
// Two interaction modes:
//   1. Drag-and-drop via the drag handle, powered by SortableJS
//      (data-countable-items-reorder-target="handle")
//   2. Up / Down buttons (data-action="click->countable-items-reorder#moveUp" etc.)
//
// After any reorder the controller renumbers:
//   - Each row's hidden position input (0-based sequential)
//   - Each row's visible position indicator (data-countable-items-reorder-target="positionLabel")
//   - Up button disabled state (first row)
//   - Down button disabled state (last row)
//
// HTML contract (set by CountableItemsFormComponent):
//   data-controller="countable-items-reorder"                — on the <ol>/<ul> list
//   data-countable-items-reorder-target="row"               — on every item row
//   data-countable-items-reorder-target="handle"            — on each drag-handle element
//   data-countable-items-reorder-target="positionLabel"     — on each visible position indicator
//   data-countable-items-reorder-target="positionInput"     — on each hidden position <input>
//   data-countable-items-reorder-target="upButton"          — on each Move Up button
//   data-countable-items-reorder-target="downButton"        — on each Move Down button
//   data-action="click->countable-items-reorder#moveUp"     — on each Move Up button
//   data-action="click->countable-items-reorder#moveDown"   — on each Move Down button

export default class extends Controller {
  static targets = ["row", "handle", "positionLabel", "positionInput", "upButton", "downButton"]

  connect() {
    this.#refreshNumbers()
    this.sortable = Sortable.create(this.element, {
      handle: "[data-countable-items-reorder-target='handle']",
      draggable: "[data-countable-items-reorder-target='row']",
      animation: 150,
      ghostClass: "opacity-40",
      onEnd: () => this.#refreshNumbers()
    })
  }

  disconnect() {
    this.sortable?.destroy()
    this.sortable = null
  }

  // ─── Up / Down buttons ───────────────────────────────────────────────────
  //
  // Neighbours are looked up via rowTargets (not element siblings) because the
  // list interleaves hidden [id] inputs between the <li> rows.

  moveUp(event) {
    const row = event.currentTarget.closest("[data-countable-items-reorder-target='row']")
    const rows = this.rowTargets
    const idx = rows.indexOf(row)
    if (idx <= 0) return
    rows[idx - 1].insertAdjacentElement("beforebegin", row)
    this.#refreshNumbers()
  }

  moveDown(event) {
    const row = event.currentTarget.closest("[data-countable-items-reorder-target='row']")
    const rows = this.rowTargets
    const idx = rows.indexOf(row)
    if (idx === -1 || idx >= rows.length - 1) return
    rows[idx + 1].insertAdjacentElement("afterend", row)
    this.#refreshNumbers()
  }

  // ─── Shared numbering helper ──────────────────────────────────────────────

  #refreshNumbers() {
    const rows = this.rowTargets
    rows.forEach((row, idx) => {
      // Update hidden position input (0-based)
      const posInput = row.querySelector("[data-countable-items-reorder-target='positionInput']")
      if (posInput) posInput.value = idx

      // Update visible position label (1-based for display)
      const posLabel = row.querySelector("[data-countable-items-reorder-target='positionLabel']")
      if (posLabel) posLabel.textContent = idx + 1

      // Update Up/Down button disabled states
      const upBtn   = row.querySelector("[data-countable-items-reorder-target='upButton']")
      const downBtn = row.querySelector("[data-countable-items-reorder-target='downButton']")

      if (upBtn)   upBtn.disabled   = (idx === 0)
      if (downBtn) downBtn.disabled = (idx === rows.length - 1)
    })
  }
}
