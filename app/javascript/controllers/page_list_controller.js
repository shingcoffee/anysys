import { Controller } from "@hotwired/stimulus"

/**
 * Page List Controller
 * Manages the page list table with search functionality.
 */
export default class extends Controller {
  static targets = [
    "searchInput",
    "clearButton",
    "tableBody",
    "row",
    "emptyState"
  ]

  // ===================
  // Lifecycle
  // ===================

  connect() {
    this._updateClearButtonVisibility()
  }

  // ===================
  // Search
  // ===================

  search(event) {
    const searchTerm = event.target.value.toLowerCase().trim()
    this._updateClearButtonVisibility()

    let visibleCount = 0

    this.rowTargets.forEach(row => {
      const name = row.dataset.name || ""
      const description = row.dataset.description || ""

      const matches = name.includes(searchTerm) || description.includes(searchTerm)
      row.style.display = matches ? "" : "none"

      if (matches) visibleCount++
    })

    // Show/hide empty state
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.toggle("hidden", visibleCount > 0)
    }

    // Show/hide table body
    if (this.hasTableBodyTarget) {
      this.tableBodyTarget.classList.toggle("hidden", visibleCount === 0)
    }
  }

  clearSearch() {
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.value = ""
      this.search({ target: this.searchInputTarget })
    }
  }

  _updateClearButtonVisibility() {
    if (this.hasClearButtonTarget && this.hasSearchInputTarget) {
      const hasValue = this.searchInputTarget.value.trim().length > 0
      this.clearButtonTarget.classList.toggle("hidden", !hasValue)
    }
  }
}
