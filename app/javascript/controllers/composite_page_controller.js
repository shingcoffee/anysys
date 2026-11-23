import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Bind once and keep the references so disconnect() can actually remove
    // these listeners — a fresh `.bind(this)` produces a new function that
    // removeEventListener would never match, leaking the listeners.
    this._onRowSelected = this.handleRowSelected.bind(this)
    this._onRowAction = this.handleRowAction.bind(this)
    this.element.addEventListener("list-module:row-selected", this._onRowSelected)
    this.element.addEventListener("list-module:row-action", this._onRowAction)
  }

  disconnect() {
    this.element.removeEventListener("list-module:row-selected", this._onRowSelected)
    this.element.removeEventListener("list-module:row-action", this._onRowAction)
  }

  handleRowSelected(event) {
    const { recordId, moduleId } = event.detail
    this.showModulesListeningTo("row:selected")
    this.dispatch("row-selected", { detail: { recordId, moduleId } })
  }

  handleRowAction(event) {
    const { action, recordId, moduleId } = event.detail
    this.dispatch("row-action", { detail: { action, recordId, moduleId } })
  }

  showModulesListeningTo(eventName) {
    this.element.querySelectorAll("[data-module-id]").forEach(mod => {
      const listenEvents = (mod.dataset.listenEvents || "").split(",")
      if (listenEvents.includes(eventName)) {
        mod.classList.remove("hidden")
      }
    })
  }
}
