import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "templateGrid", "templateCard", "selectedTemplate",
    "entitySelect", "categoryTab", "categoryTabs", "categoryGroups", "templateContainer",
    "previewModal", "previewModalContent", "previewModalName", "previewModalDescription", "previewModalTheme",
    "themeSelector", "themeOption", "selectedTheme",
    "searchInput", "searchClear", "noResults",
    "searchResultsCount", "searchResultsNumber",
    "clearTemplateBtn", "changeBtn", "lockedNote",
    // Modal picker additions:
    "picker", "pickerModal", "triggerEmpty", "triggerSelected", "triggerName",
    "loadingState", "errorState", "confirmBtn"
  ]

  static values = {
    customerId: String,
    cardsUrl: String
  }

  connect() {
    // Cards are NOT rendered server-side anymore; they are lazy-fetched on first
    // modal open. Read the committed selection from the hidden field instead.
    const keyAttr = this.selectedTemplateTarget.dataset.templateKey
    this.selectedKey = keyAttr || this.selectedTemplateTarget.value || null
    this.pendingKey = this.selectedKey
    this.selectedTheme = this.hasSelectedThemeTarget ? this.selectedThemeTarget.value : null
    this.activeCategory = "all"
    this.searchQuery = ""
    this.loaded = false
    this.loadPromise = null
    this.locked = false
    this.refreshTrigger()
    this.applyLockState()
  }

  // ──────────────────────────────────────────────────────────────────
  // PICKER MODAL + LAZY LOAD
  // ──────────────────────────────────────────────────────────────────

  openModal(event) {
    if (event) event.preventDefault()
    // When the bound entity references a template the choice is locked to it.
    if (this.locked) return
    this.pendingKey = this.selectedKey
    if (this.hasPickerModalTarget) {
      this.pickerModalTarget.classList.remove("hidden")
      document.body.style.overflow = "hidden"
    }
    this.loadTemplates()
  }

  closeModal(event) {
    if (event) event.preventDefault()
    if (this.hasPickerModalTarget) {
      this.pickerModalTarget.classList.add("hidden")
      document.body.style.overflow = ""
    }
    // Discard any uncommitted pending highlight.
    this.pendingKey = this.selectedKey
    this.updateCardStates()
  }

  closeModalOnBackdrop(event) {
    if (event.target === event.currentTarget) this.closeModal(event)
  }

  // Fetch the card grid once. Returns a promise so callers (e.g. entityChanged)
  // can await it before selecting programmatically.
  loadTemplates() {
    if (this.loaded) return Promise.resolve()
    if (this.loadPromise) return this.loadPromise

    if (this.hasErrorStateTarget) this.errorStateTarget.classList.add("hidden")
    if (this.hasLoadingStateTarget) this.loadingStateTarget.classList.remove("hidden")

    const url = this.hasCardsUrlValue && this.cardsUrlValue
      ? this.cardsUrlValue
      : this.pickerTarget.dataset.templatePickerCardsUrl

    this.loadPromise = fetch(url, { headers: { "Accept": "text/html" } })
      .then(response => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        return response.text()
      })
      .then(html => {
        this.templateContainerTarget.innerHTML = html
        this.loaded = true
        if (this.hasLoadingStateTarget) this.loadingStateTarget.classList.add("hidden")
        // Cards just registered as targets; reflect selection + active filters.
        this.updateCardStates()
        this.applyFilters()
      })
      .catch(() => {
        if (this.hasLoadingStateTarget) this.loadingStateTarget.classList.add("hidden")
        if (this.hasErrorStateTarget) this.errorStateTarget.classList.remove("hidden")
      })
      .finally(() => { this.loadPromise = null })

    return this.loadPromise
  }

  confirmSelection(event) {
    if (event) event.preventDefault()
    if (!this.pendingKey) { this.closeModal(); return }

    // Remember the prior committed state so a downstream consumer (e.g. the entity
    // form's overwrite confirmation) can revert this commit if the user backs out.
    this._priorKey = this.selectedKey
    this._priorValue = this.selectedTemplateTarget.value
    this._priorTheme = this.selectedTheme

    this.selectedKey = this.pendingKey
    this.selectedTemplateTarget.value = this.selectedKey
    if ("templateKey" in this.selectedTemplateTarget.dataset) {
      this.selectedTemplateTarget.dataset.templateKey = this.selectedKey
    }

    const card = this.templateCardTargets.find(c => c.dataset.templateKey === this.selectedKey)
    if (card && card.dataset.templateTheme) {
      this.selectedTheme = card.dataset.templateTheme
      if (this.hasSelectedThemeTarget) this.selectedThemeTarget.value = this.selectedTheme
    }

    this.updateThemeSelector()
    this.refreshTrigger()
    this.dispatch("templateSelected", { detail: { key: this.selectedKey } })
    this.closeModal()
  }

  // Roll back the most recent confirmSelection commit. Triggered when a downstream
  // consumer rejects the selection (e.g. the user cancels the entity-form overwrite
  // confirmation) so the hidden field and trigger stay aligned with the unchanged form.
  revertCommit() {
    this.selectedKey = this._priorKey != null ? this._priorKey : null
    this.pendingKey = this.selectedKey
    this.selectedTemplateTarget.value = this._priorValue != null ? this._priorValue : ""
    if ("templateKey" in this.selectedTemplateTarget.dataset) {
      this.selectedTemplateTarget.dataset.templateKey = this.selectedKey || ""
    }
    this.selectedTheme = this._priorTheme != null ? this._priorTheme : null
    if (this.hasSelectedThemeTarget) this.selectedThemeTarget.value = this.selectedTheme || ""
    this.updateCardStates()
    this.updateThemeSelector()
    this.refreshTrigger()
  }

  refreshTrigger() {
    const hasSelection = !!this.selectedKey
    if (this.hasTriggerEmptyTarget) this.triggerEmptyTarget.classList.toggle("hidden", hasSelection)
    if (this.hasTriggerSelectedTarget) this.triggerSelectedTarget.classList.toggle("hidden", !hasSelection)
    if (hasSelection && this.hasTriggerNameTarget) {
      const card = this.templateCardTargets.find(c => c.dataset.templateKey === this.selectedKey)
      const name = card ? (card.dataset.templateName || this.selectedKey) : this.triggerNameTarget.textContent
      this.triggerNameTarget.textContent = name
    }
  }

  entityChanged(event) {
    this.refreshFromEntity(event.target.value)
  }

  // Page builder: align the template picker with the bound entity.
  //  • entity references a template → auto-select it and LOCK the picker to it.
  //  • entity references no template (or is deselected) → unlock and reset to empty
  //    so the user is free to choose one.
  async refreshFromEntity(entityId) {
    if (!entityId || !this.customerIdValue) {
      this.setLocked(false)
      this.resetSelection()
      return
    }

    try {
      const response = await fetch(`/${this.customerIdValue}/admin/maintenance/entities/${entityId}.json`, {
        headers: { "Accept": "application/json" }
      })
      if (!response.ok) { this.setLocked(false); return }

      const entity = await response.json()
      const refData = this.parseReferencedTemplate(entity.referenced_template)

      if (refData && refData.key) {
        const applied = await this.autoSelectTemplate(refData.key)
        if (applied) {
          this.setLocked(true)
        } else {
          // Referenced template not available in the picker — fall back to editable.
          this.setLocked(false)
          this.resetSelection()
        }
      } else {
        this.setLocked(false)
        this.resetSelection()
      }
    } catch (_e) {
      // Network/parse failure — leave the picker editable rather than locking blindly.
      this.setLocked(false)
    }
  }

  parseReferencedTemplate(ref) {
    if (!ref) return null
    try {
      return typeof ref === "string" ? JSON.parse(ref) : ref
    } catch (_e) {
      return null
    }
  }

  // Ensure the (lazy) cards are loaded so we can read the template's theme, then
  // commit the selection without opening the modal. Returns true when the template
  // was found and applied.
  async autoSelectTemplate(templateKey) {
    await this.loadTemplates()
    const card = this.templateCardTargets.find(c => c.dataset.templateKey === templateKey)
    if (!card) return false

    this.selectedKey = templateKey
    this.pendingKey = templateKey
    this.selectedTemplateTarget.value = templateKey
    if ("templateKey" in this.selectedTemplateTarget.dataset) {
      this.selectedTemplateTarget.dataset.templateKey = templateKey
    }
    if (card.dataset.templateTheme) {
      this.selectedTheme = card.dataset.templateTheme
      if (this.hasSelectedThemeTarget) this.selectedThemeTarget.value = this.selectedTheme
    }

    this.updateCardStates()
    this.updateThemeSelector()
    this.refreshTrigger()
    this.dispatch("templateSelected", { detail: { key: templateKey } })
    return true
  }

  // Toggle the locked state and reflect it in the trigger UI: when locked the
  // Change/Clear affordances are hidden and a "set by entity" note is shown.
  setLocked(locked) {
    this.locked = !!locked
    this.applyLockState()
  }

  applyLockState() {
    const locked = !!this.locked
    if (this.hasChangeBtnTarget) this.changeBtnTarget.classList.toggle("hidden", locked)
    if (this.hasClearTemplateBtnTarget) this.clearTemplateBtnTarget.classList.toggle("hidden", locked)
    if (this.hasLockedNoteTarget) this.lockedNoteTarget.classList.toggle("hidden", !locked)
  }

  // Reset to the empty (no template) state without dispatching the user-facing
  // "templateCleared" event — used when realigning to a freshly selected entity.
  resetSelection() {
    this.selectedKey = null
    this.pendingKey = null
    this.selectedTemplateTarget.value = ""
    if ("templateKey" in this.selectedTemplateTarget.dataset) {
      this.selectedTemplateTarget.dataset.templateKey = ""
    }
    this.selectedTheme = null
    if (this.hasSelectedThemeTarget) this.selectedThemeTarget.value = ""
    this.updateCardStates()
    this.updateThemeSelector()
    this.refreshTrigger()
  }

  // Card click inside the modal sets a PENDING selection only; the footer
  // "Use Template" button (confirmSelection) commits it.
  selectTemplate(event) {
    const card = event.currentTarget.closest("[data-template-key]")
    if (!card) return
    const key = card.dataset.templateKey
    if (!key) return
    this.pendingKey = key
    this.updateCardStates()
  }

  clearTemplate(event) {
    if (event) event.preventDefault()
    if (this.locked) return
    this.resetSelection()
    this.dispatch("templateCleared")
  }

  // Double-click to open preview modal
  handleDoubleClick(event) {
    this.openPreviewModal(event)
  }

  filterCategory(event) {
    event.preventDefault()
    event.stopPropagation() // Prevent group toggle when clicking a category pill
    const category = event.currentTarget.dataset.category
    this.activeCategory = category

    // Apply combined filters (category + search) — tab styles updated inside applyFilters
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

  // ──────────────────────────────────────────────────────────────────
  // TEMPLATE SEARCH
  // ──────────────────────────────────────────────────────────────────

  searchTemplates(event) {
    this.searchQuery = event.target.value.toLowerCase().trim()

    // Show/hide clear button
    if (this.hasSearchClearTarget) {
      this.searchClearTarget.classList.toggle("hidden", this.searchQuery === "")
    }

    // Apply combined filters (category + search)
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

    // Apply filters to show all (category filtered) templates
    this.applyFilters()

    // Focus back on search input
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.focus()
    }
  }

  applyFilters() {
    let visibleCount = 0
    const categoryCounts = {}

    this.templateCardTargets.forEach(card => {
      const cardCategory = card.dataset.templateCategory
      const cardName = (card.dataset.templateName || "").toLowerCase()
      const cardDescription = (card.dataset.templateDescription || "").toLowerCase()
      const cardCategoryLabel = (card.dataset.templateCategoryLabel || "").toLowerCase()
      const cardCategoryGroup = (card.dataset.templateCategoryGroup || "").toLowerCase()

      // Check search filter (applies across all categories for count)
      const searchMatch = this.searchQuery === "" ||
                          cardName.includes(this.searchQuery) ||
                          cardDescription.includes(this.searchQuery) ||
                          cardCategoryLabel.includes(this.searchQuery) ||
                          cardCategoryGroup.includes(this.searchQuery)

      // Track per-category search-matched counts
      if (searchMatch) {
        categoryCounts[cardCategory] = (categoryCounts[cardCategory] || 0) + 1
        categoryCounts["all"] = (categoryCounts["all"] || 0) + 1
      }

      // Check category filter
      const categoryMatch = this.activeCategory === "all" || cardCategory === this.activeCategory

      // Show card only if both filters match
      const shouldShow = categoryMatch && searchMatch

      card.classList.toggle("hidden", !shouldShow)

      if (shouldShow) {
        visibleCount++
      }
    })

    // Update category tab counts and highlight matched categories
    this.updateCategoryTabs(categoryCounts)

    // Show/hide search results count
    if (this.hasSearchResultsCountTarget) {
      const isSearching = this.searchQuery !== ""
      this.searchResultsCountTarget.classList.toggle("hidden", !isSearching)
      if (isSearching && this.hasSearchResultsNumberTarget) {
        this.searchResultsNumberTarget.textContent = visibleCount
      }
    }

    // Show/hide "no results" message
    if (this.hasNoResultsTarget) {
      this.noResultsTarget.classList.toggle("hidden", visibleCount > 0)
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

      // Update count badge
      const badge = tab.querySelector("[data-count-badge]")
      if (badge) {
        badge.textContent = isSearching ? matchedCount : totalCount
      }

      // Reset all style classes
      tab.classList.remove(
        "bg-indigo-100", "text-indigo-700", "ring-1", "ring-indigo-200",
        "bg-green-50", "text-green-700", "ring-green-200",
        "bg-gray-100", "text-gray-600", "hover:bg-gray-200",
        "opacity-40"
      )

      if (isActive) {
        // Active tab always gets indigo style
        tab.classList.add("bg-indigo-100", "text-indigo-700", "ring-1", "ring-indigo-200")
      } else if (isSearching && hasMatches) {
        // Non-active tabs with search matches get green highlight
        tab.classList.add("bg-green-50", "text-green-700", "ring-1", "ring-green-200", "hover:bg-gray-200")
      } else if (isSearching && !hasMatches) {
        // Non-active tabs with no matches get dimmed
        tab.classList.add("bg-gray-100", "text-gray-600", "hover:bg-gray-200", "opacity-40")
      } else {
        // Default non-active style
        tab.classList.add("bg-gray-100", "text-gray-600", "hover:bg-gray-200")
      }
    })

    // Auto-expand groups that have search matches, collapse those that don't
    if (isSearching) {
      this.element.querySelectorAll("[data-group-content]").forEach(content => {
        const groupKey = content.dataset.groupContent
        const chevron = this.element.querySelector(`[data-group-chevron="${groupKey}"]`)
        const pills = content.querySelectorAll("[data-template-selector-target='categoryTab']")
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

  updateCardStates() {
    this.templateCardTargets.forEach(card => {
      const highlightKey = this.pendingKey != null ? this.pendingKey : this.selectedKey
      const isSelected = card.dataset.templateKey === highlightKey

      // Reset classes
      card.classList.remove(
        "border-indigo-500", "ring-2", "ring-indigo-500", "shadow-md",
        "border-gray-200", "hover:border-indigo-300"
      )

      if (isSelected) {
        card.classList.add("border-indigo-500", "ring-2", "ring-indigo-500", "shadow-md")
      } else {
        card.classList.add("border-gray-200", "hover:border-indigo-300")
      }

      // Toggle checkmark
      const checkmark = card.querySelector("[data-checkmark]")
      if (checkmark) {
        checkmark.classList.toggle("hidden", !isSelected)
      }
    })
  }

  // ──────────────────────────────────────────────────────────────────
  // PREVIEW ZOOM MODAL
  // ──────────────────────────────────────────────────────────────────

  openPreviewModal(event) {
    event.stopPropagation() // Don't trigger template selection
    const card = event.currentTarget.closest("[data-template-key]")
    this.showPreviewForCard(card)
  }

  // Preview the currently-selected template. Opens the full server-rendered
  // template preview by key in a new tab — the same kind of preview the entity
  // detail page links to — so it works for not-yet-saved (new) entities too.
  async previewSelected(event) {
    if (event) event.preventDefault()
    if (!this.selectedKey) return

    if (this.hasCustomerIdValue && this.customerIdValue) {
      const url = `/${this.customerIdValue}/admin/maintenance/template_previews/${encodeURIComponent(this.selectedKey)}`
      window.open(url, "_blank", "noopener")
      return
    }

    // Fallback: client-side zoom preview when no customer id is available.
    await this.loadTemplates()
    const card = this.templateCardTargets.find(c => c.dataset.templateKey === this.selectedKey)
    this.showPreviewForCard(card)
  }

  showPreviewForCard(card) {
    if (!card) return

    const key = card.dataset.templateKey
    const name = card.dataset.templateName
    const description = card.dataset.templateDescription
    const theme = card.dataset.templateTheme

    // Update modal content
    if (this.hasPreviewModalNameTarget) {
      this.previewModalNameTarget.textContent = name || key
    }
    if (this.hasPreviewModalDescriptionTarget) {
      this.previewModalDescriptionTarget.textContent = description || ""
    }
    if (this.hasPreviewModalThemeTarget) {
      this.previewModalThemeTarget.textContent = theme ? theme.charAt(0).toUpperCase() + theme.slice(1) : ""
    }

    // Clone and inject preview content with much larger scaling
    if (this.hasPreviewModalContentTarget) {
      const previewElement = card.querySelector("[data-preview-content]")
      if (previewElement) {
        const clonedPreview = previewElement.cloneNode(true)
        // Scale up the preview significantly - remove size limits and increase font sizes
        clonedPreview.classList.remove("max-h-[110px]", "px-2", "py-1.5", "space-y-1")
        clonedPreview.classList.add("px-8", "py-6", "space-y-4")
        clonedPreview.style.maxHeight = "none"

        // Scale up all nested elements for better visibility
        this.scalePreviewElements(clonedPreview)

        this.previewModalContentTarget.innerHTML = ""
        this.previewModalContentTarget.appendChild(clonedPreview)
      }
    }

    // Show modal
    if (this.hasPreviewModalTarget) {
      this.previewModalTarget.classList.remove("hidden")
      document.body.style.overflow = "hidden"
    }
  }

  scalePreviewElements(container) {
    // Scale up text sizes
    const textElements = container.querySelectorAll('.text-\\[5px\\], .text-\\[4px\\], .text-\\[3px\\]')
    textElements.forEach(el => {
      el.classList.remove('text-[5px]', 'text-[4px]', 'text-[3px]')
      el.classList.add('text-sm')
    })

    // Scale up gaps and spacing
    const gapElements = container.querySelectorAll('.gap-1, .gap-0\\.5, .gap-px')
    gapElements.forEach(el => {
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

    // Scale up remaining input/field heights
    const heightElements = container.querySelectorAll('.h-\\[7px\\], .h-\\[14px\\], .h-\\[12px\\], .h-\\[8px\\], .h-\\[4px\\]')
    heightElements.forEach(el => {
      el.classList.remove('h-[7px]', 'h-[14px]', 'h-[12px]', 'h-[8px]', 'h-[4px]')
      if (el.classList.contains('border')) {
        el.classList.add('h-10') // Input fields
      } else {
        el.classList.add('h-8') // Spacers, buttons
      }
    })

    // Scale up width elements
    const widthElements = container.querySelectorAll('.w-1, .w-1\\.5, .w-2, .w-\\[6px\\]')
    widthElements.forEach(el => {
      el.classList.remove('w-1', 'w-1.5', 'w-2', 'w-[6px]')
      if (el.tagName === 'svg' || el.querySelector('svg')) {
        el.classList.add('w-5', 'h-5')
      } else {
        el.classList.add('w-4')
      }
    })

    // Scale up rounded elements
    const roundedElements = container.querySelectorAll('.rounded-sm, .rounded-md')
    roundedElements.forEach(el => {
      el.classList.remove('rounded-sm')
      if (!el.classList.contains('rounded-md')) {
        el.classList.add('rounded-md')
      }
    })

    // Scale up margins and paddings
    const spacingElements = container.querySelectorAll('.mb-px, .mb-0\\.5, .mt-0\\.5, .px-0\\.5, .pr-0\\.5, .pl-0\\.5')
    spacingElements.forEach(el => {
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

  // ──────────────────────────────────────────────────────────────────
  // THEME SELECTOR
  // ──────────────────────────────────────────────────────────────────

  updateThemeSelector() {
    if (!this.hasThemeSelectorTarget) return

    const selectedCard = this.templateCardTargets.find(card => card.dataset.templateKey === this.selectedKey)

    if (selectedCard) {
      this.themeSelectorTarget.classList.remove("hidden")

      // Set default theme from template if not already set
      if (!this.selectedTheme) {
        this.selectedTheme = selectedCard.dataset.templateTheme || "modern"
        if (this.hasSelectedThemeTarget) {
          this.selectedThemeTarget.value = this.selectedTheme
        }
      }

      this.updateThemeOptionStates()
    } else {
      this.themeSelectorTarget.classList.add("hidden")
    }
  }

  selectTheme(event) {
    const themeKey = event.currentTarget.dataset.themeKey
    if (!themeKey) return

    this.selectedTheme = themeKey
    if (this.hasSelectedThemeTarget) {
      this.selectedThemeTarget.value = themeKey
    }

    this.updateThemeOptionStates()
  }

  updateThemeOptionStates() {
    if (!this.hasThemeOptionTarget) return

    this.themeOptionTargets.forEach(option => {
      const isSelected = option.dataset.themeKey === this.selectedTheme

      option.classList.remove(
        "border-indigo-500", "ring-2", "ring-indigo-500", "bg-indigo-50",
        "border-gray-200", "hover:border-gray-300"
      )

      if (isSelected) {
        option.classList.add("border-indigo-500", "ring-2", "ring-indigo-500", "bg-indigo-50")
      } else {
        option.classList.add("border-gray-200", "hover:border-gray-300")
      }

      // Toggle checkmark
      const checkmark = option.querySelector("[data-theme-checkmark]")
      if (checkmark) {
        checkmark.classList.toggle("hidden", !isSelected)
      }
    })
  }
}
