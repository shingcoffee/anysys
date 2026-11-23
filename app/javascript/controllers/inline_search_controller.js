import { Controller } from "@hotwired/stimulus"
import { announceTopbarMenuOpen, onPeerTopbarMenuOpen, TOPBAR_MENU_OPEN } from "controllers/shared/topbar_menu"

export default class extends Controller {
  static targets = ["trigger", "expanded", "backdrop", "input", "results", "empty"]
  static values  = {
    customerId: String,
    // i18n seam: English defaults byte-identical to the former hardcoded copy.
    noResultsFormat: { type: String, default: 'No results for "{query}"' },
    typeToSearch: { type: String, default: "Type to search pages, entities, and modules" }
  }

  connect() {
    this.debounceTimer = null
    this.activeIndex   = -1
    this.currentItems  = []
    this.isExpanded    = false

    this.boundKeydown = (event) => {
      const meta = event.metaKey || event.ctrlKey
      if (meta && event.key.toLowerCase() === "k") {
        event.preventDefault()
        this.expand()
      } else if (event.key === "Escape" && this.isExpanded) {
        event.preventDefault()
        this.collapse()
      }
    }
    this.boundPeerOpen = onPeerTopbarMenuOpen(this.element, () => this.collapse())
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
    document.removeEventListener(TOPBAR_MENU_OPEN, this.boundPeerOpen)
    clearTimeout(this.debounceTimer)
  }

  expand() {
    if (this.isExpanded) return
    this.isExpanded = true
    announceTopbarMenuOpen(this.element)

    this.triggerTarget.classList.add("hidden")
    this.expandedTarget.classList.remove("hidden")
    this.backdropTarget.classList.remove("hidden")

    requestAnimationFrame(() => {
      this.inputTarget.focus()
    })
  }

  collapse() {
    if (!this.isExpanded) return
    this.isExpanded = false

    this.expandedTarget.classList.add("hidden")
    this.backdropTarget.classList.add("hidden")
    this.triggerTarget.classList.remove("hidden")

    this.inputTarget.value = ""
    this.renderResults([])
  }

  query() {
    clearTimeout(this.debounceTimer)
    const q = this.inputTarget.value.trim()
    this.debounceTimer = setTimeout(() => this.fetchResults(q), 150)
  }

  async fetchResults(q) {
    if (q.length < 2) {
      this.renderResults([])
      return
    }
    const url = `/${this.customerIdValue}/admin/search?q=${encodeURIComponent(q)}`
    try {
      const resp = await fetch(url, {
        credentials: "same-origin",
        headers: { "Accept": "application/json" }
      })
      if (!resp.ok) { this.renderResults([]); return }
      const body = await resp.json()
      this.renderResults(body.groups || [])
    } catch (_e) {
      this.renderResults([])
    }
  }

  renderResults(groups) {
    this.currentItems = []
    this.activeIndex  = -1
    this.resultsTarget.innerHTML = ""

    const hasGroups = groups.length > 0
    const q = this.inputTarget.value.trim()

    this.resultsTarget.classList.toggle("hidden", !hasGroups)

    if (this.hasEmptyTarget) {
      if (!hasGroups && q.length >= 2) {
        const highlightedQuery = `<span class="font-medium text-gray-700">${this.escapeHtml(q)}</span>`
        const message = this.noResultsFormatValue.replace("{query}", highlightedQuery)
        this.emptyTarget.innerHTML = `
          <svg class="w-8 h-8 mx-auto mb-2 text-gray-300" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="11" cy="11" r="7"/>
            <path d="m21 21-4.35-4.35"/>
          </svg>
          ${message}
        `
        this.emptyTarget.classList.remove("hidden")
      } else if (!hasGroups) {
        this.emptyTarget.innerHTML = `
          <svg class="w-8 h-8 mx-auto mb-2 text-gray-300" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="11" cy="11" r="7"/>
            <path d="m21 21-4.35-4.35"/>
          </svg>
          ${this.typeToSearchValue}
        `
        this.emptyTarget.classList.remove("hidden")
      } else {
        this.emptyTarget.classList.add("hidden")
      }
    }

    groups.forEach((group) => {
      const heading = document.createElement("div")
      heading.className = "px-3 pt-3 pb-1.5 text-[11px] font-medium uppercase tracking-wider text-gray-400"
      heading.textContent = group.label
      this.resultsTarget.appendChild(heading)

      group.items.forEach((item) => {
        const link = document.createElement("a")
        link.href = item.path
        link.className =
          "flex items-center gap-3 mx-2 px-2 py-2 text-sm text-gray-700 rounded-md " +
          "hover:bg-indigo-50 hover:text-indigo-900 " +
          "focus:bg-indigo-50 focus:text-indigo-900 focus:outline-none transition-colors"

        const icon = this.iconForType(item.type)
        if (icon) {
          const iconWrapper = document.createElement("span")
          iconWrapper.className = "flex-shrink-0 w-5 h-5 flex items-center justify-center text-gray-400"
          iconWrapper.innerHTML = icon
          link.appendChild(iconWrapper)
        }

        const label = document.createElement("span")
        label.className = "truncate"
        label.textContent = item.label
        link.appendChild(label)

        this.resultsTarget.appendChild(link)
        this.currentItems.push(link)
      })
    })
  }

  iconForType(type) {
    const icons = {
      page: '<svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z"/></svg>',
      entity: '<svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125"/></svg>',
      module: '<svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path stroke-linecap="round" stroke-linejoin="round" d="M21 7.5l-9-5.25L3 7.5m18 0l-9 5.25m9-5.25v9l-9 5.25M3 7.5l9 5.25M3 7.5v9l9 5.25m0-9v9"/></svg>'
    }
    return icons[type] || null
  }

  escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }

  navigate(event) {
    if (!["ArrowDown", "ArrowUp", "Enter"].includes(event.key)) return
    if (this.currentItems.length === 0) return

    if (event.key === "Enter") {
      event.preventDefault()
      const target = this.activeIndex >= 0
        ? this.currentItems[this.activeIndex]
        : this.currentItems[0]
      if (target) target.click()
      return
    }

    event.preventDefault()
    const delta = event.key === "ArrowDown" ? 1 : -1
    this.activeIndex =
      (this.activeIndex + delta + this.currentItems.length) % this.currentItems.length

    this.currentItems.forEach((el, i) => {
      const isActive = i === this.activeIndex
      el.classList.toggle("bg-indigo-50", isActive)
      el.classList.toggle("text-indigo-900", isActive)
    })
    this.currentItems[this.activeIndex].scrollIntoView({ block: "nearest" })
  }
}
