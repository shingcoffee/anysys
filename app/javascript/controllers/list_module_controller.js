import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { moduleId: String, page: { type: Number, default: 1 } }

  selectRow(event) {
    if (event.target.closest("a")) return

    const row = event.currentTarget
    const recordId = row.dataset.recordId

    this.element.querySelectorAll("tr").forEach(tr => tr.classList.remove("bg-indigo-50"))
    row.classList.add("bg-indigo-50")

    this.dispatch("row-selected", {
      detail: { recordId, moduleId: this.moduleIdValue },
      bubbles: true
    })
  }

  rowAction(event) {
    event.stopPropagation()
    const action = event.currentTarget.dataset.rowAction
    const recordId = event.currentTarget.dataset.recordId

    this.dispatch("row-action", {
      detail: { action, recordId, moduleId: this.moduleIdValue },
      bubbles: true
    })
  }

  prevPage() {
    this.pageValue = Math.max(1, this.pageValue - 1)
    this.reload()
  }

  nextPage() {
    this.pageValue += 1
    this.reload()
  }

  reload() {
    this.dispatch("page-changed", {
      detail: { page: this.pageValue, moduleId: this.moduleIdValue },
      bubbles: true
    })
  }
}
