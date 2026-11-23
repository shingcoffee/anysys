import { Controller } from "@hotwired/stimulus"

// Repeatable bridge rows (Admin::Entities::AssociationEntriesFormComponent).
// add() clones the blank row template under a fresh rows[<index>] key;
// remove() drops a row but always keeps one. Row headings follow the rows'
// order, and the remove buttons only show while there is more than one row.
export default class extends Controller {
  static targets = ["list", "template", "row"]
  static values = {
    nextIndex: Number,
    heading: { type: String, default: "Entry {number}" }
  }

  connect() {
    this.refresh()
  }

  add() {
    const fragment = this.templateTarget.content.cloneNode(true)
    this.indexAttributes(fragment, String(this.nextIndexValue))
    this.nextIndexValue += 1
    this.listTarget.append(fragment)
    this.refresh()

    const row = this.rowTargets[this.rowTargets.length - 1]
    row.querySelector("input:not([type='hidden']), select, textarea")?.focus()
  }

  remove(event) {
    if (this.rowTargets.length < 2) return

    event.currentTarget.closest("[data-association-rows-target='row']").remove()
    this.refresh()
  }

  // Only attributes carry the row token; text such as option labels comes from
  // tenant data and must stay as written.
  indexAttributes(fragment, index) {
    fragment.querySelectorAll("*").forEach((element) => {
      for (const attribute of element.attributes) {
        if (attribute.value.includes("__ROW__")) attribute.value = attribute.value.replaceAll("__ROW__", index)
      }
    })
  }

  refresh() {
    const rows = this.rowTargets
    rows.forEach((row, index) => {
      row.querySelector("[data-association-rows-target='heading']").textContent =
        this.headingValue.replace("{number}", String(index + 1))
      row.querySelector("[data-association-rows-target='remove']").classList.toggle("hidden", rows.length < 2)
    })
  }
}
