import { Controller } from "@hotwired/stimulus"

// Manages a "select all" checkbox + row checkboxes and enables the
// batch-action submit only when at least one row is selected.
//
// Targets:
//   all    — the header "select all" checkbox
//   item   — individual row checkboxes (name="user_ids[]")
//   submit — the batch-action submit button (disabled by default)
//
// Usage in the template:
//   data-controller="batch-select"
//   all    → data-batch-select-target="all"    data-action="change->batch-select#toggleAll"
//   item   → data-batch-select-target="item"   data-action="change->batch-select#refresh"
//   submit → data-batch-select-target="submit"
//   count    → optional selected-count label (countTemplate value)
//   toolbar  → optional default toolbar (hidden while bulk bar visible)
//   bulkbar  → optional bulk-action bar (hidden when nothing selected)
export default class extends Controller {
  static targets = ["all", "item", "submit", "count", "toolbar", "bulkbar"]
  static values = {
    countTemplate: { type: String, default: "{count} selected" }
  }

  connect() {
    this.refresh()
  }

  // Called when the "select all" checkbox changes. Syncs all item checkboxes
  // to match, then re-evaluates the submit button state.
  toggleAll() {
    this.itemTargets.forEach((cb) => { cb.checked = this.allTarget.checked })
    this.refresh()
  }

  // Called when any row checkbox changes. Re-evaluates the submit button and
  // syncs the "select all" checkbox to reflect the current selection state.
  refresh() {
    const selected = this.itemTargets.filter((cb) => cb.checked)
    const anyChecked = selected.length > 0
    const allChecked =
      this.itemTargets.length > 0 && selected.length === this.itemTargets.length

    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = !anyChecked
    }

    if (this.hasAllTarget) {
      this.allTarget.checked = allChecked
      this.allTarget.indeterminate = anyChecked && !allChecked
    }

    if (this.hasCountTarget) {
      this.countTarget.textContent = this.countTemplateValue.replace(
        "{count}",
        String(selected.length)
      )
    }

    if (this.hasToolbarTarget) {
      this.toolbarTarget.classList.toggle("hidden", anyChecked)
    }

    if (this.hasBulkbarTarget) {
      this.bulkbarTarget.classList.toggle("hidden", !anyChecked)
    }
  }

  clear() {
    if (this.hasAllTarget) {
      this.allTarget.checked = false
      this.allTarget.indeterminate = false
    }
    this.itemTargets.forEach((cb) => { cb.checked = false })
    this.refresh()
  }
}
