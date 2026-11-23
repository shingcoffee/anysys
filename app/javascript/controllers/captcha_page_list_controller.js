import { Controller } from "@hotwired/stimulus"

// Client-side locate for one captcha URL section (protected or skip).
// Search is a case-insensitive substring against name and path.
export default class extends Controller {
  static targets = ["row", "group", "search", "emptyFilter", "directory"]

  connect() {
    this.apply()
  }

  search() {
    this.apply()
  }

  apply() {
    const query = this.searchQuery()
    let visible = 0

    if (this.hasRowTarget) {
      this.rowTargets.forEach((row) => {
        const show = this.matchesSearch(row, query)
        row.classList.toggle("hidden", !show)
        if (show) visible += 1
      })
    }

    if (this.hasGroupTarget) {
      this.groupTargets.forEach((group) => {
        const rows = group.querySelectorAll("[data-captcha-page-list-target='row']")
        const anyVisible = [...rows].some((row) => !row.classList.contains("hidden"))
        group.classList.toggle("hidden", rows.length > 0 && !anyVisible)
      })
    }

    if (this.hasEmptyFilterTarget) {
      this.emptyFilterTarget.classList.toggle("hidden", visible > 0)
    }
    if (this.hasDirectoryTarget) {
      this.directoryTarget.classList.toggle("hidden", visible === 0)
    }
  }

  searchQuery() {
    if (!this.hasSearchTarget) return ""
    return this.searchTarget.value.trim().toLowerCase()
  }

  matchesSearch(row, query) {
    if (!query) return true
    const haystack = [row.dataset.name, row.dataset.path].join(" ").toLowerCase()
    return haystack.includes(query)
  }
}
