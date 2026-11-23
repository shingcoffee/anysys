import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "templateCard", "scrollContainer",
    "associatedSection", "associatedContainer", "associatedCount",
    "availableSection", "availableContainer", "availableCount",
    "categoryTab", "categoryTabs", "categoryGroups",
    "searchInput", "searchClear", "noResults",
    "searchResultsCount", "searchResultsNumber",
    "previewModal", "previewModalContent", "previewModalName", "previewModalDescription", "previewModalTheme", "previewModalCategory",
    "mappedCount"
  ]

  static values = {
    industry: String,
    baseUrl: String,
    mappedKeys: Array
  }

  connect() {
    this.mappedKeys = new Set(this.mappedKeysValue)
    this.activeCategory = "all"
    this.searchQuery = ""
  }

  // ── Template toggle (add/remove association) ───────────────────

  async selectTemplate(event) {
    const card = event.currentTarget.closest("[data-template-key]")
    if (!card) return
    const key = card.dataset.templateKey
    if (!key) return

    const wasMapped = this.mappedKeys.has(key)

    // Optimistic update
    if (wasMapped) {
      this.mappedKeys.delete(key)
    } else {
      this.mappedKeys.add(key)
    }
    this.updateCardState(card)
    this.moveCard(card, !wasMapped)
    this.updateCounts()

    try {
      const url = wasMapped
        ? `${this.baseUrlValue}/${this.industryValue}/template_assignments/${encodeURIComponent(key)}`
        : `${this.baseUrlValue}/${this.industryValue}/template_assignments`

      const response = await fetch(url, {
        method: wasMapped ? "DELETE" : "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ template_key: key })
      })

      if (!response.ok) {
        this.revertToggle(key, wasMapped, card)
      }
    } catch {
      this.revertToggle(key, wasMapped, card)
    }
  }

  revertToggle(key, wasMapped, card) {
    if (wasMapped) {
      this.mappedKeys.add(key)
    } else {
      this.mappedKeys.delete(key)
    }
    this.updateCardState(card)
    this.moveCard(card, wasMapped)
    this.updateCounts()
  }

  handleDoubleClick(event) {
    this.openPreviewModal(event)
  }

  // ── Card movement between sections ─────────────────────────────

  moveCard(card, toAssociated) {
    const targetContainer = toAssociated
      ? this.associatedContainerTarget
      : this.availableContainerTarget

    // Animate card briefly
    card.style.transition = "opacity 0.15s ease"
    card.style.opacity = "0.5"

    requestAnimationFrame(() => {
      targetContainer.prepend(card)
      requestAnimationFrame(() => {
        card.style.opacity = "1"
        setTimeout(() => { card.style.transition = "" }, 150)
      })
    })
  }

  // ── Card state management ──────────────────────────────────────

  updateCardState(card) {
    const key = card.dataset.templateKey
    const isMapped = this.mappedKeys.has(key)

    card.classList.remove(
      "border-indigo-500", "ring-2", "ring-indigo-500", "shadow-md",
      "border-gray-200", "hover:border-indigo-300"
    )

    if (isMapped) {
      card.classList.add("border-indigo-500", "ring-2", "ring-indigo-500", "shadow-md")
    } else {
      card.classList.add("border-gray-200", "hover:border-indigo-300")
    }

    const checkmark = card.querySelector("[data-checkmark]")
    if (checkmark) {
      checkmark.classList.toggle("hidden", !isMapped)
    }
  }

  updateCounts() {
    const mappedCount = this.mappedKeys.size
    const _totalCards = this.templateCardTargets.length

    if (this.hasMappedCountTarget) {
      this.mappedCountTarget.textContent = mappedCount
    }

    // Update section counts
    if (this.hasAssociatedCountTarget) {
      const visibleAssociated = this.countVisibleCards(this.associatedContainerTarget)
      this.associatedCountTarget.textContent = visibleAssociated
    }
    if (this.hasAvailableCountTarget) {
      const visibleAvailable = this.countVisibleCards(this.availableContainerTarget)
      this.availableCountTarget.textContent = visibleAvailable
    }

    // Show/hide section headers
    if (this.hasAssociatedSectionTarget) {
      const hasAssociated = this.associatedContainerTarget.querySelector("[data-template-key]") !== null
      this.associatedSectionTarget.classList.toggle("hidden", !hasAssociated)
    }
    if (this.hasAvailableSectionTarget) {
      const hasAvailable = this.availableContainerTarget.querySelector("[data-template-key]") !== null
      this.availableSectionTarget.classList.toggle("hidden", !hasAvailable)
    }

    // Dispatch to parent
    this.dispatch("countChanged", {
      detail: { industry: this.industryValue, count: mappedCount },
      bubbles: true
    })
  }

  countVisibleCards(container) {
    return container.querySelectorAll("[data-template-key]:not(.hidden)").length
  }

  // ── Search ─────────────────────────────────────────────────────

  searchTemplates(event) {
    this.searchQuery = event.target.value.toLowerCase().trim()

    if (this.hasSearchClearTarget) {
      this.searchClearTarget.classList.toggle("hidden", this.searchQuery === "")
    }

    this.applyFilters()
  }

  clearSearch(event) {
    event.preventDefault()

    if (this.hasSearchInputTarget) {
      this.searchInputTarget.value = ""
    }
    this.searchQuery = ""

    if (this.hasSearchClearTarget) {
      this.searchClearTarget.classList.add("hidden")
    }

    this.applyFilters()

    if (this.hasSearchInputTarget) {
      this.searchInputTarget.focus()
    }
  }

  // ── Category filter ────────────────────────────────────────────

  filterCategory(event) {
    event.preventDefault()
    event.stopPropagation()
    const category = event.currentTarget.dataset.category
    this.activeCategory = category
    this.applyFilters()
  }

  toggleGroup(event) {
    event.preventDefault()
    const groupKey = event.currentTarget.dataset.groupKey
    const content = this.element.querySelector(`[data-group-content="${groupKey}"]`)
    const chevron = this.element.querySelector(`[data-group-chevron="${groupKey}"]`)

    if (!content) return

    const isHidden = content.classList.contains("hidden")
    content.classList.toggle("hidden", !isHidden)

    if (chevron) {
      chevron.classList.toggle("rotate-180", isHidden)
    }
  }

  // ── Combined filter logic ──────────────────────────────────────

  applyFilters() {
    let visibleCount = 0
    const categoryCounts = {}

    this.templateCardTargets.forEach(card => {
      const cardCategory = card.dataset.templateCategory
      const cardName = (card.dataset.templateName || "").toLowerCase()
      const cardDescription = (card.dataset.templateDescription || "").toLowerCase()
      const cardCategoryLabel = (card.dataset.templateCategoryLabel || "").toLowerCase()
      const cardCategoryGroup = (card.dataset.templateCategoryGroup || "").toLowerCase()

      const searchMatch = this.searchQuery === "" ||
                          cardName.includes(this.searchQuery) ||
                          cardDescription.includes(this.searchQuery) ||
                          cardCategoryLabel.includes(this.searchQuery) ||
                          cardCategoryGroup.includes(this.searchQuery)

      if (searchMatch) {
        categoryCounts[cardCategory] = (categoryCounts[cardCategory] || 0) + 1
        categoryCounts["all"] = (categoryCounts["all"] || 0) + 1
      }

      const categoryMatch = this.activeCategory === "all" || cardCategory === this.activeCategory
      const shouldShow = categoryMatch && searchMatch

      card.classList.toggle("hidden", !shouldShow)

      if (shouldShow) {
        visibleCount++
      }
    })

    this.updateCategoryTabs(categoryCounts)

    // Update section visibility based on visible cards
    this.updateSectionVisibility()

    if (this.hasSearchResultsCountTarget) {
      const isSearching = this.searchQuery !== ""
      this.searchResultsCountTarget.classList.toggle("hidden", !isSearching)
      if (isSearching && this.hasSearchResultsNumberTarget) {
        this.searchResultsNumberTarget.textContent = visibleCount
      }
    }

    if (this.hasNoResultsTarget) {
      this.noResultsTarget.classList.toggle("hidden", visibleCount > 0)
    }
  }

  updateSectionVisibility() {
    if (this.hasAssociatedSectionTarget && this.hasAssociatedContainerTarget) {
      const visibleAssociated = this.countVisibleCards(this.associatedContainerTarget)
      this.associatedSectionTarget.classList.toggle("hidden", visibleAssociated === 0)
      if (this.hasAssociatedCountTarget) {
        this.associatedCountTarget.textContent = visibleAssociated
      }
    }
    if (this.hasAvailableSectionTarget && this.hasAvailableContainerTarget) {
      const visibleAvailable = this.countVisibleCards(this.availableContainerTarget)
      this.availableSectionTarget.classList.toggle("hidden", visibleAvailable === 0)
      if (this.hasAvailableCountTarget) {
        this.availableCountTarget.textContent = visibleAvailable
      }
    }
  }

  updateCategoryTabs(categoryCounts) {
    const isSearching = this.searchQuery !== ""

    this.categoryTabTargets.forEach(tab => {
      const catKey = tab.dataset.category
      const isActive = catKey === this.activeCategory
      const totalCount = parseInt(tab.dataset.totalCount) || 0
      const matchedCount = categoryCounts[catKey] || 0
      const hasMatches = matchedCount > 0

      const badge = tab.querySelector("[data-count-badge]")
      if (badge) {
        badge.textContent = isSearching ? matchedCount : totalCount
      }

      tab.classList.remove(
        "bg-indigo-100", "text-indigo-700", "ring-1", "ring-indigo-200",
        "bg-green-50", "text-green-700", "ring-green-200",
        "bg-gray-100", "text-gray-600", "hover:bg-gray-200",
        "opacity-40"
      )

      if (isActive) {
        tab.classList.add("bg-indigo-100", "text-indigo-700", "ring-1", "ring-indigo-200")
      } else if (isSearching && hasMatches) {
        tab.classList.add("bg-green-50", "text-green-700", "ring-1", "ring-green-200", "hover:bg-gray-200")
      } else if (isSearching && !hasMatches) {
        tab.classList.add("bg-gray-100", "text-gray-600", "hover:bg-gray-200", "opacity-40")
      } else {
        tab.classList.add("bg-gray-100", "text-gray-600", "hover:bg-gray-200")
      }
    })

    if (isSearching) {
      this.element.querySelectorAll("[data-group-content]").forEach(content => {
        const groupKey = content.dataset.groupContent
        const chevron = this.element.querySelector(`[data-group-chevron="${groupKey}"]`)
        const pills = content.querySelectorAll("[data-industry-template-panel-target='categoryTab']")
        const groupHasMatches = Array.from(pills).some(pill => {
          const catKey = pill.dataset.category
          return (categoryCounts[catKey] || 0) > 0
        })

        content.classList.toggle("hidden", !groupHasMatches)
        if (chevron) {
          chevron.classList.toggle("rotate-180", groupHasMatches)
        }
      })
    }
  }

  // ── Preview zoom modal ─────────────────────────────────────────

  openPreviewModal(event) {
    event.stopPropagation()
    const card = event.currentTarget.closest("[data-template-key]")
    if (!card) return

    const name = card.dataset.templateName
    const description = card.dataset.templateDescription
    const theme = card.dataset.templateTheme
    const categoryLabel = card.dataset.templateCategoryLabel

    if (this.hasPreviewModalNameTarget) {
      this.previewModalNameTarget.textContent = name || ""
    }
    if (this.hasPreviewModalDescriptionTarget) {
      this.previewModalDescriptionTarget.textContent = description || ""
    }
    if (this.hasPreviewModalThemeTarget) {
      this.previewModalThemeTarget.textContent = theme ? theme.charAt(0).toUpperCase() + theme.slice(1) : ""
    }
    if (this.hasPreviewModalCategoryTarget) {
      this.previewModalCategoryTarget.textContent = categoryLabel || ""
    }

    if (this.hasPreviewModalContentTarget) {
      const previewElement = card.querySelector("[data-preview-content]")
      if (previewElement) {
        const clonedPreview = previewElement.cloneNode(true)
        clonedPreview.classList.remove("max-h-[110px]", "px-2", "py-1.5", "space-y-1")
        clonedPreview.classList.add("px-8", "py-6", "space-y-4")
        clonedPreview.style.maxHeight = "none"
        this.scalePreviewElements(clonedPreview)
        this.previewModalContentTarget.innerHTML = ""
        this.previewModalContentTarget.appendChild(clonedPreview)
      }
    }

    if (this.hasPreviewModalTarget) {
      this.previewModalTarget.classList.remove("hidden")
      document.body.style.overflow = "hidden"
    }
  }

  scalePreviewElements(container) {
    container.querySelectorAll('.text-\\[5px\\], .text-\\[4px\\], .text-\\[3px\\]').forEach(el => {
      el.classList.remove('text-[5px]', 'text-[4px]', 'text-[3px]')
      el.classList.add('text-sm')
    })

    container.querySelectorAll('.gap-1, .gap-0\\.5, .gap-px').forEach(el => {
      el.classList.remove('gap-1', 'gap-0.5', 'gap-px')
      el.classList.add('gap-3')
    })

    // Scale up textarea heights FIRST (bordered h-[14px]) so the general height
    // pass below doesn't strip the marker and size textareas as plain inputs.
    container.querySelectorAll('.h-\\[14px\\]').forEach(el => {
      if (el.classList.contains('border')) {
        el.classList.remove('h-[14px]')
        el.classList.add('h-20') // Textareas
      }
    })

    container.querySelectorAll('.h-\\[7px\\], .h-\\[14px\\], .h-\\[12px\\], .h-\\[8px\\], .h-\\[4px\\]').forEach(el => {
      el.classList.remove('h-[7px]', 'h-[14px]', 'h-[12px]', 'h-[8px]', 'h-[4px]')
      if (el.classList.contains('border')) {
        el.classList.add('h-10')
      } else {
        el.classList.add('h-8')
      }
    })

    container.querySelectorAll('.w-1, .w-1\\.5, .w-2, .w-\\[6px\\]').forEach(el => {
      el.classList.remove('w-1', 'w-1.5', 'w-2', 'w-[6px]')
      if (el.tagName === 'svg' || el.querySelector('svg')) {
        el.classList.add('w-5', 'h-5')
      } else {
        el.classList.add('w-4')
      }
    })

    container.querySelectorAll('.rounded-sm, .rounded-md').forEach(el => {
      el.classList.remove('rounded-sm')
      if (!el.classList.contains('rounded-md')) {
        el.classList.add('rounded-md')
      }
    })

    container.querySelectorAll('.mb-px, .mb-0\\.5, .mt-0\\.5, .px-0\\.5, .pr-0\\.5, .pl-0\\.5').forEach(el => {
      el.classList.remove('mb-px', 'mb-0.5', 'mt-0.5', 'px-0.5', 'pr-0.5', 'pl-0.5')
      el.classList.add('mb-2', 'mt-1', 'px-2')
    })
  }

  closePreviewModal(event) {
    if (event) event.preventDefault()
    if (this.hasPreviewModalTarget) {
      this.previewModalTarget.classList.add("hidden")
      document.body.style.overflow = ""
    }
  }

  closePreviewModalOnBackdrop(event) {
    if (event.target === event.currentTarget) {
      this.closePreviewModal(event)
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
