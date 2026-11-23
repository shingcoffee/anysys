import { Controller } from "@hotwired/stimulus"
import { fuzzyMatch } from "utils"

/**
 * Flowchart List Controller
 *
 * Manages the flowchart list page with search and filtering functionality.
 * Provides fuzzy search across flowchart names and descriptions.
 */
export default class extends Controller {
  static targets = ["searchInput", "tableBody", "row", "emptyState"]

  // ===================
  // Lifecycle
  // ===================

  connect() {
    this.cachedRows = this.hasRowTarget ? this.rowTargets : []
  }

  // ===================
  // Actions
  // ===================

  /**
   * Filter rows based on search input value.
   * Uses fuzzy matching for flexible search.
   */
  search(event) {
    const query = this.normalizeSearchTerm(event.target.value)
    let visibleCount = 0

    this.cachedRows.forEach(row => {
      const isMatch = this.rowMatchesQuery(row, query)
      this.setRowVisibility(row, isMatch)
      if (isMatch) visibleCount++
    })

    this.toggleEmptyState(visibleCount === 0 && query.length > 0)
  }

  /**
   * Clear search input and show all rows.
   */
  clearSearch() {
    if (!this.hasSearchInputTarget) return

    this.searchInputTarget.value = ""
    this.cachedRows.forEach(row => this.setRowVisibility(row, true))
    this.toggleEmptyState(false)
  }

  // ===================
  // Private Methods
  // ===================

  normalizeSearchTerm(term) {
    return term.toLowerCase().trim()
  }

  rowMatchesQuery(row, query) {
    if (!query) return true

    const name = row.dataset.name?.toLowerCase() || ""
    const description = row.dataset.description?.toLowerCase() || ""

    return (
      name.includes(query) ||
      description.includes(query) ||
      fuzzyMatch(name, query) ||
      fuzzyMatch(description, query)
    )
  }

  setRowVisibility(row, visible) {
    row.classList.toggle("hidden", !visible)
  }

  toggleEmptyState(show) {
    if (!this.hasEmptyStateTarget) return
    this.emptyStateTarget.classList.toggle("hidden", !show)
  }
}
