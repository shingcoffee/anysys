import { Controller } from "@hotwired/stimulus"

// Static color map for icon classes (Tailwind-safe, no dynamic construction)
const ICON_COLOR_CLASSES = {
  blue: "text-blue-500", cyan: "text-cyan-500", green: "text-green-500",
  red: "text-red-500", indigo: "text-indigo-500", purple: "text-purple-500",
  emerald: "text-emerald-500", amber: "text-amber-500", pink: "text-pink-500",
  teal: "text-teal-500", gray: "text-gray-500"
}

/**
 * Searchable Select Controller
 *
 * A filterable, grouped dropdown select with collapsible parent-child groups
 * and keyboard navigation. Replaces native <select> for large option lists.
 *
 * Groups act as collapsible parent categories. Click a group header to
 * expand/collapse its child options. Searching auto-expands matching groups.
 *
 * Item format: [displayName, value] or [displayName, value, meta]
 * where meta is an optional object with { icon, color, description, disabled }.
 */
export default class extends Controller {
  static targets = ["search", "hidden", "dropdown", "option", "group", "groupHeader", "groupItems", "clear", "noResults"]
  static values = {
    options: Array, selected: String, expandAll: Boolean,

    // ── i18n seam: English defaults keep JS specs green without any
    // data-*-value attribute; the mounting component
    // (searchable_select_component.html.erb) supplies translated strings via
    // data-searchable-select-<name>-value="<%= t(...) %>". ──
    noMatchLabel: { type: String, default: "No matching options found" },
    alreadyUsedLabel: { type: String, default: "(already used)" }
  }

  connect() {
    this.highlightIndex = -1
    this.boundClickOutside = this.clickOutside.bind(this)
    document.addEventListener("click", this.boundClickOutside)
    this.renderOptions()
    if (this.expandAllValue) this.expandAllGroups()

    if (this.selectedValue) {
      this.setSelectedFromValue(this.selectedValue)
    }
  }

  disconnect() {
    document.removeEventListener("click", this.boundClickOutside)
  }

  // --- Rendering ---

  renderOptions() {
    const container = this.dropdownTarget
    container.innerHTML = ""

    const noResults = document.createElement("div")
    noResults.setAttribute("data-searchable-select-target", "noResults")
    noResults.className = "hidden px-3 py-6 text-sm text-gray-400 italic text-center"
    noResults.textContent = this.noMatchLabelValue
    container.appendChild(noResults)

    this.optionsValue.forEach((group, groupIndex) => {
      const groupEl = document.createElement("div")
      groupEl.setAttribute("data-searchable-select-target", "group")
      groupEl.setAttribute("data-group-name", group.group.toLowerCase())

      // Group header (parent) — clickable to expand/collapse
      const header = document.createElement("div")
      header.setAttribute("data-searchable-select-target", "groupHeader")
      header.setAttribute("data-group-index", groupIndex)
      header.className = "flex items-center justify-between px-3 py-2 cursor-pointer select-none hover:bg-gray-50 transition-colors border-b border-gray-100"
      header.addEventListener("click", (e) => {
        e.stopPropagation()
        this.toggleGroup(groupIndex)
      })

      const headerLeft = document.createElement("div")
      headerLeft.className = "flex items-center gap-2"

      const chevron = document.createElement("svg")
      chevron.setAttribute("class", "w-3.5 h-3.5 text-gray-400 transition-transform duration-200")
      chevron.setAttribute("data-chevron", "true")
      chevron.setAttribute("fill", "none")
      chevron.setAttribute("viewBox", "0 0 24 24")
      chevron.setAttribute("stroke", "currentColor")
      chevron.setAttribute("stroke-width", "2")
      chevron.innerHTML = '<path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />'
      headerLeft.appendChild(chevron)

      const label = document.createElement("span")
      label.className = "text-sm font-medium text-gray-700"
      label.textContent = group.group
      headerLeft.appendChild(label)

      header.appendChild(headerLeft)

      const count = document.createElement("span")
      count.className = "text-xs text-gray-400 bg-gray-100 px-1.5 py-0.5 rounded-full"
      count.textContent = group.items.length
      header.appendChild(count)

      groupEl.appendChild(header)

      // Group items container (children) — collapsed by default
      const itemsContainer = document.createElement("div")
      itemsContainer.setAttribute("data-searchable-select-target", "groupItems")
      itemsContainer.setAttribute("data-group-index", groupIndex)
      itemsContainer.className = "hidden"

      group.items.forEach((item) => {
        const displayName = item[0]
        const value = item[1]
        const meta = item[2] || {}

        const opt = document.createElement("div")
        opt.setAttribute("data-searchable-select-target", "option")
        opt.setAttribute("data-value", value)
        opt.setAttribute("data-label", displayName)
        opt.setAttribute("data-group-label", group.group)
        opt.setAttribute("data-group-index", groupIndex)
        opt.setAttribute("role", "option")

        // Search data includes description when available
        const searchText = meta.description
          ? `${displayName} ${group.group} ${meta.description}`.toLowerCase()
          : `${displayName} ${group.group}`.toLowerCase()
        opt.setAttribute("data-search", searchText)

        opt.className = "pl-9 pr-3 py-1.5 text-sm text-gray-600 cursor-pointer hover:bg-indigo-50 hover:text-indigo-700 transition-colors"

        // Description tooltip
        if (meta.description) {
          opt.title = meta.description
        }

        // SVG icon rendering
        if (meta.icon) {
          const colorClass = ICON_COLOR_CLASSES[meta.color] || ICON_COLOR_CLASSES.gray
          const iconWrap = document.createElement("span")
          iconWrap.className = "inline-flex items-center justify-center w-4 h-4 mr-1.5 flex-shrink-0"
          iconWrap.innerHTML = `<svg class="w-3.5 h-3.5 ${colorClass}" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="${meta.icon}" /></svg>`
          opt.appendChild(iconWrap)

          const labelSpan = document.createElement("span")
          labelSpan.textContent = displayName
          opt.appendChild(labelSpan)
          opt.classList.add("flex", "items-center")
        } else {
          opt.textContent = displayName
        }

        // Disabled item support
        if (meta.disabled) {
          opt.classList.add("opacity-40", "cursor-not-allowed")
          opt.classList.remove("cursor-pointer", "hover:bg-indigo-50", "hover:text-indigo-700")
          opt.setAttribute("data-disabled", "true")

          const suffix = document.createElement("span")
          suffix.className = "text-xs text-gray-400 ml-1"
          suffix.textContent = this.alreadyUsedLabelValue
          opt.appendChild(suffix)
        } else {
          opt.addEventListener("click", () => this.select(value, displayName, group.group))
        }

        itemsContainer.appendChild(opt)
      })

      groupEl.appendChild(itemsContainer)
      container.appendChild(groupEl)
    })
  }

  // --- Group expand/collapse ---

  toggleGroup(groupIndex) {
    const items = this.groupItemsTargets.find(el => el.dataset.groupIndex === String(groupIndex))
    const header = this.groupHeaderTargets.find(el => el.dataset.groupIndex === String(groupIndex))
    if (!items || !header) return

    const isExpanded = !items.classList.contains("hidden")
    if (isExpanded) {
      this.collapseGroup(items, header)
    } else {
      this.expandGroup(items, header)
    }
  }

  expandGroup(items, header) {
    items.classList.remove("hidden")
    const chevron = header.querySelector("[data-chevron]")
    if (chevron) chevron.classList.add("rotate-90")
  }

  collapseGroup(items, header) {
    items.classList.add("hidden")
    const chevron = header.querySelector("[data-chevron]")
    if (chevron) chevron.classList.remove("rotate-90")
  }

  expandAllGroups() {
    this.groupItemsTargets.forEach((items, i) => {
      const header = this.groupHeaderTargets[i]
      if (header) this.expandGroup(items, header)
    })
  }

  collapseAllGroups() {
    this.groupItemsTargets.forEach((items, i) => {
      const header = this.groupHeaderTargets[i]
      if (header) this.collapseGroup(items, header)
    })
  }

  // --- Search / Filter ---

  filter() {
    const query = this.searchTarget.value.toLowerCase().trim()
    let visibleCount = 0
    this.highlightIndex = -1

    this.groupTargets.forEach(group => {
      let groupHasMatch = false
      const _groupIndex = group.querySelector("[data-group-index]")?.dataset.groupIndex
      const items = group.querySelector("[data-searchable-select-target='groupItems']")
      const header = group.querySelector("[data-searchable-select-target='groupHeader']")
      const options = group.querySelectorAll("[data-searchable-select-target='option']")

      // If no query, collapse all groups and show all options
      if (!query) {
        group.classList.remove("hidden")
        header?.classList.remove("hidden")
        options.forEach(opt => {
          opt.classList.remove("hidden")
          opt.classList.remove("bg-indigo-50", "text-indigo-700")
        })
        if (items && header) {
          if (this.expandAllValue) { this.expandGroup(items, header) } else { this.collapseGroup(items, header) }
        }
        return
      }

      // Check if group name matches
      const groupName = group.dataset.groupName || ""
      const groupNameMatches = groupName.includes(query)

      options.forEach(opt => {
        const optMatches = opt.dataset.search.includes(query)
        const show = optMatches || groupNameMatches
        opt.classList.toggle("hidden", !show)
        opt.classList.remove("bg-indigo-50", "text-indigo-700")
        if (show) {
          groupHasMatch = true
          visibleCount++
        }
      })

      group.classList.toggle("hidden", !groupHasMatch)
      if (header) header.classList.toggle("hidden", !groupHasMatch)

      // Auto-expand groups with matches when searching
      if (groupHasMatch && items && header) {
        this.expandGroup(items, header)
      } else if (!groupHasMatch && items && header) {
        this.collapseGroup(items, header)
      }
    })

    this.noResultsTarget.classList.toggle("hidden", visibleCount > 0)
  }

  // --- Open / Close ---

  open() {
    // Only reset the highlight when actually opening (was hidden). Resetting on
    // every call would let a repeated ArrowDown (which calls open()) clobber the
    // highlight back to -1 each time, so it could never advance past the first row.
    const wasHidden = this.dropdownTarget.classList.contains("hidden")
    this.dropdownTarget.classList.remove("hidden")
    if (wasHidden) this.highlightIndex = -1
  }

  close() {
    this.dropdownTarget.classList.add("hidden")
    this.highlightIndex = -1
    this.clearHighlight()

    // Reset filter if nothing selected
    if (!this.hiddenTarget.value) {
      this.searchTarget.value = ""
      this.resetFilter()
    }
  }

  toggle() {
    if (this.dropdownTarget.classList.contains("hidden")) {
      this.open()
      this.searchTarget.focus()
    } else {
      this.close()
    }
  }

  // --- Keyboard navigation ---

  keydown(event) {
    const visible = this.visibleOptions()

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.open()
        this.highlightIndex = Math.min(this.highlightIndex + 1, visible.length - 1)
        this.updateHighlight(visible)
        break
      case "ArrowUp":
        event.preventDefault()
        this.highlightIndex = Math.max(this.highlightIndex - 1, 0)
        this.updateHighlight(visible)
        break
      case "Enter":
        event.preventDefault()
        if (this.highlightIndex >= 0 && visible[this.highlightIndex]) {
          const opt = visible[this.highlightIndex]
          this.select(opt.dataset.value, opt.dataset.label, opt.dataset.groupLabel)
        }
        break
      case "Escape":
        if (!this.dropdownTarget.classList.contains("hidden")) {
          event.preventDefault()
        }
        this.close()
        this.searchTarget.blur()
        break
      case "Tab":
        this.close()
        break
    }
  }

  // --- Selection ---

  select(value, label, groupLabel) {
    this.hiddenTarget.value = value
    this.searchTarget.value = groupLabel ? `${label}  —  ${groupLabel}` : label
    this.selectedValue = value
    this.close()
    this.resetFilter()

    if (this.hasClearTarget) {
      this.clearTarget.classList.remove("hidden")
    }

    // Mark selected option
    this.optionTargets.forEach(opt => {
      const isSelected = opt.dataset.value === value
      opt.classList.toggle("font-semibold", isSelected)
      opt.classList.toggle("text-indigo-600", isSelected)
    })

    this.hiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  clearSelection() {
    this.hiddenTarget.value = ""
    this.searchTarget.value = ""
    this.selectedValue = ""

    if (this.hasClearTarget) {
      this.clearTarget.classList.add("hidden")
    }

    this.optionTargets.forEach(opt => {
      opt.classList.remove("font-semibold", "text-indigo-600")
    })

    this.resetFilter()
    this.searchTarget.focus()
    this.open()
    this.hiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  // --- Private helpers ---

  setSelectedFromValue(value) {
    const opt = this.optionTargets.find(o => o.dataset.value === value)
    if (opt) {
      const groupLabel = opt.dataset.groupLabel
      this.searchTarget.value = groupLabel ? `${opt.dataset.label}  —  ${groupLabel}` : opt.dataset.label
      opt.classList.add("font-semibold", "text-indigo-600")

      // Expand the group containing the selected option
      const groupIndex = opt.dataset.groupIndex
      if (groupIndex) {
        const items = this.groupItemsTargets.find(el => el.dataset.groupIndex === groupIndex)
        const header = this.groupHeaderTargets.find(el => el.dataset.groupIndex === groupIndex)
        if (items && header) this.expandGroup(items, header)
      }

      if (this.hasClearTarget) {
        this.clearTarget.classList.remove("hidden")
      }
    }
  }

  resetFilter() {
    this.groupTargets.forEach(group => {
      group.classList.remove("hidden")
      const header = group.querySelector("[data-searchable-select-target='groupHeader']")
      if (header) header.classList.remove("hidden")
    })
    this.optionTargets.forEach(opt => opt.classList.remove("hidden"))
    if (this.expandAllValue) { this.expandAllGroups() } else { this.collapseAllGroups() }
    this.noResultsTarget.classList.add("hidden")
  }

  visibleOptions() {
    return this.optionTargets.filter(o => {
      if (o.classList.contains("hidden")) return false
      if (o.dataset.disabled === "true") return false
      const group = o.closest("[data-searchable-select-target='group']")
      if (group?.classList.contains("hidden")) return false
      const items = o.closest("[data-searchable-select-target='groupItems']")
      if (items?.classList.contains("hidden")) return false
      return true
    })
  }

  updateHighlight(visible) {
    this.clearHighlight()
    if (visible[this.highlightIndex]) {
      visible[this.highlightIndex].classList.add("bg-indigo-50", "text-indigo-700")
      visible[this.highlightIndex].scrollIntoView({ block: "nearest" })
    }
  }

  clearHighlight() {
    this.optionTargets.forEach(opt => {
      opt.classList.remove("bg-indigo-50", "text-indigo-700")
    })
  }
}
