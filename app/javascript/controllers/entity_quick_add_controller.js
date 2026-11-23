import { Controller } from "@hotwired/stimulus"

// Wraps an entity-backed <select> whose last option (data-quick-add-option)
// reads "+ Add New". Choosing it restores the previous choice and opens the
// entity-quick-add-dialog outlet; the saved entry is inserted before that
// option and selected.
export default class extends Controller {
  static targets = ["select"]
  static values = { url: String, title: String }
  static outlets = ["entity-quick-add-dialog"]

  selectTargetConnected(select) {
    this.previousIndex = select.selectedIndex
  }

  change() {
    const select = this.selectTarget
    const option = select.options[select.selectedIndex]
    if (!option || !option.hasAttribute("data-quick-add-option")) {
      this.previousIndex = select.selectedIndex
      return
    }

    select.selectedIndex = this.previousIndex
    if (!this.hasEntityQuickAddDialogOutlet) return

    this.entityQuickAddDialogOutlet.open({
      url: this.urlValue,
      title: this.titleValue,
      onCreated: (entry) => this.add(entry)
    })
  }

  add({ id, label }) {
    const select = this.selectTarget
    let option = Array.from(select.options)
      .find((candidate) => candidate.value === id && !candidate.hasAttribute("data-quick-add-option"))
    if (!option) {
      option = document.createElement("option")
      option.value = id
      option.textContent = label
      select.add(option, select.querySelector("option[data-quick-add-option]"))
    }
    option.selected = true
    select.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
