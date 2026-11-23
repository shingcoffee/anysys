import { Controller } from "@hotwired/stimulus"

// Client-side locate for already-rendered lists (settings sidebar, modules
// sidebar + hub catalog). Search is a case-insensitive substring against each
// item's data-search-text (falling back to data-name, then text content).
// Groups hide when every nested item is hidden; <details> groups open while a
// query is active so matches stay visible, and restore their open state when
// the query clears.
export default class extends Controller {
  static targets = ["search", "item", "group", "empty", "directory", "details"]

  connect() {
    this.apply()
  }

  search(event) {
    if (event) event.preventDefault()
    this.apply()
  }

  apply() {
    const query = this.searchQuery()
    let visible = 0

    this.itemTargets.forEach((item) => {
      const show = this.matchesSearch(item, query)
      item.classList.toggle("hidden", !show)
      if (show) visible += 1
    })

    this.syncDetails(query)
    this.syncGroups()
    this.syncEmpty(visible)
  }

  searchQuery() {
    if (!this.hasSearchTarget) return ""
    return this.searchTarget.value.trim().toLowerCase()
  }

  matchesSearch(el, query) {
    if (!query) return true
    return this.haystackFor(el).includes(query)
  }

  haystackFor(el) {
    return (el.dataset.searchText || el.dataset.name || el.textContent || "").toLowerCase()
  }

  syncGroups() {
    if (!this.hasGroupTarget) return

    this.groupTargets.forEach((group) => {
      const items = this.itemTargets.filter((item) => group.contains(item))
      const anyVisible = items.some((item) => !item.classList.contains("hidden"))
      group.classList.toggle("hidden", items.length > 0 && !anyVisible)
    })
  }

  // While a query is active, force every collapsible group open so matches are
  // not hidden behind a closed disclosure. Remember which ones we opened so
  // clearing the query restores the user's own open/closed state.
  syncDetails(query) {
    if (!this.hasDetailsTarget) return

    const filtering = query.length > 0
    this.detailsTargets.forEach((details) => {
      if (filtering) {
        if (!details.open && !details.dataset.filterOpened) {
          details.dataset.filterOpened = "true"
        }
        details.open = true
      } else if (details.dataset.filterOpened) {
        details.open = false
        delete details.dataset.filterOpened
      }
    })
  }

  syncEmpty(visible) {
    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("hidden", visible > 0)
    }
    if (this.hasDirectoryTarget) {
      this.directoryTarget.classList.toggle("hidden", visible === 0)
    }
  }
}
