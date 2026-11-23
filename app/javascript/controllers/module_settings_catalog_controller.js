import { Controller } from "@hotwired/stimulus"

// Client-side locate + filter for the already-rendered platform module
// catalog. Search is a case-insensitive substring against name/key/description;
// filter pills are All / Active / Inactive / Required. Combining both is AND.
export default class extends Controller {
  static targets = ["row", "emptyFilter", "directory", "search", "filter"]
  static values = { filter: { type: String, default: "all" } }

  connect() {
    this.apply()
  }

  search() {
    this.apply()
  }

  setFilter(event) {
    const next = event.currentTarget.dataset.filter
    this.filterValue = next || "all"
  }

  filterValueChanged() {
    this.apply()
  }

  apply() {
    const query = this.searchQuery()
    const filter = this.filterValue
    let visible = 0

    this.rowTargets.forEach((row) => {
      const show = this.matchesFilter(row, filter) && this.matchesSearch(row, query)
      row.classList.toggle("hidden", !show)
      if (show) visible += 1
    })

    if (this.hasEmptyFilterTarget) {
      this.emptyFilterTarget.classList.toggle("hidden", visible > 0)
    }
    if (this.hasDirectoryTarget) {
      this.directoryTarget.classList.toggle("hidden", visible === 0)
    }

    this.syncFilterPills(filter)
  }

  searchQuery() {
    if (!this.hasSearchTarget) return ""
    return this.searchTarget.value.trim().toLowerCase()
  }

  matchesFilter(row, filter) {
    if (filter === "active") return row.dataset.active === "true"
    if (filter === "inactive") return row.dataset.active !== "true"
    if (filter === "required") return row.dataset.required === "true"
    return true
  }

  matchesSearch(row, query) {
    if (!query) return true
    const haystack = [
      row.dataset.name,
      row.dataset.key,
      row.dataset.description
    ].join(" ").toLowerCase()
    return haystack.includes(query)
  }

  syncFilterPills(filter) {
    this.filterTargets.forEach((btn) => {
      const active = btn.dataset.filter === filter
      btn.setAttribute("aria-pressed", active ? "true" : "false")
      btn.classList.toggle("bg-surface", active)
      btn.classList.toggle("text-text-primary", active)
      btn.classList.toggle("shadow-sm", active)
      btn.classList.toggle("ring-1", active)
      btn.classList.toggle("ring-border-subtle", active)
      btn.classList.toggle("text-text-muted", !active)
    })
  }
}
