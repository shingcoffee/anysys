import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "templateCard", "searchInput", "categoryTab", "categoryTabs", "categoryGroups",
    "templatesGrid", "noResults", "applySection",
    "previewModal", "previewModalName", "previewModalDescription",
    "previewModalTheme", "previewModalContent",
    "searchResultsCount", "searchResultsNumber"
  ]

  static values = {
    pageId: Number,
    customerId: Number,
    entityId: Number,

    // ── i18n seam: English defaults keep JS specs green without any
    // data-*-value attribute; the mounting view (_editor.html.erb) supplies
    // translated strings via
    // data-template-applier-<name>-value="<%= t(...) %>". ──
    pageBuilderNotFoundMsg: { type: String, default: "Page builder not found." },
    applyingLabel: { type: String, default: "Applying..." },
    applyFailedFormat: { type: String, default: "Failed to apply template: {message}" },
    unknownErrorLabel: { type: String, default: "Unknown error" },
    applyFailedGenericMsg: { type: String, default: "Failed to apply template. Please try again." }
  }

  connect() {
    this.activeCategory = "all"
    this.searchQuery = ""
    this.selectedTemplate = null
  }

  handleDoubleClick(event) {
    this.openPreviewModal(event)
  }

  openPreviewModal(event) {
    event.stopPropagation()
    const card = event.currentTarget.closest("[data-template-key]")
    if (!card) return

    const name = card.dataset.templateName
    const description = card.dataset.templateDescription
    const theme = card.dataset.templateTheme

    // Update modal content
    if (this.hasPreviewModalNameTarget) {
      this.previewModalNameTarget.textContent = name || card.dataset.templateKey
    }
    if (this.hasPreviewModalDescriptionTarget) {
      this.previewModalDescriptionTarget.textContent = description || ""
    }
    if (this.hasPreviewModalThemeTarget) {
      this.previewModalThemeTarget.textContent = theme ? theme.charAt(0).toUpperCase() + theme.slice(1) : ""
    }

    // Clone and scale up preview
    if (this.hasPreviewModalContentTarget) {
      const previewElement = card.querySelector("[data-preview-content]")
      if (previewElement) {
        const clonedPreview = previewElement.cloneNode(true)

        // Scale up the preview significantly - remove size limits and increase font sizes
        clonedPreview.classList.remove("max-h-[110px]", "px-2", "py-1.5", "space-y-1")
        clonedPreview.classList.add('px-8', 'py-6', 'space-y-4')
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

  scalePreviewElements(container) {
    // Scale up text sizes
    const textElements = container.querySelectorAll('.text-\\[6px\\], .text-\\[5px\\], .text-\\[4px\\], .text-\\[3px\\]')
    textElements.forEach(el => {
      el.classList.remove('text-[6px]', 'text-[5px]', 'text-[4px]', 'text-[3px]')
      el.classList.add('text-sm')
    })

    // Scale up gaps and spacing
    const gapElements = container.querySelectorAll('.gap-1, .gap-0\\.5, .gap-px')
    gapElements.forEach(el => {
      el.classList.remove('gap-1', 'gap-0.5', 'gap-px')
      el.classList.add('gap-3')
    })

    // Scale up spacing between rows
    container.querySelectorAll('.space-y-1\\.5').forEach(el => {
      el.classList.remove('space-y-1.5')
      el.classList.add('space-y-4')
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

    // Scale up dots
    const dots = container.querySelectorAll('.w-1.h-1')
    dots.forEach(el => {
      el.classList.remove('w-1', 'h-1')
      el.classList.add('w-2', 'h-2')
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
    const spacingElements = container.querySelectorAll('.mb-px, .mb-0\\.5, .mt-0\\.5, .px-0\\.5, .pr-0\\.5, .pl-0\\.5, .my-0\\.5')
    spacingElements.forEach(el => {
      el.classList.remove('mb-px', 'mb-0.5', 'mt-0.5', 'px-0.5', 'pr-0.5', 'pl-0.5', 'my-0.5')
      el.classList.add('mb-2', 'mt-1', 'px-2', 'my-2')
    })
  }

  searchTemplates(event) {
    this.searchQuery = event.target.value.toLowerCase().trim()
    this.applyFilters()
  }

  filterCategory(event) {
    event.preventDefault()
    event.stopPropagation() // Prevent group toggle when clicking a category pill
    const category = event.currentTarget.dataset.category
    this.activeCategory = category

    // Apply combined filters — tab styles updated inside applyFilters
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

  applyFilters() {
    let visibleCount = 0
    const categoryCounts = {}

    this.templateCardTargets.forEach(card => {
      const cardCategory = card.dataset.templateCategory
      const cardName = (card.dataset.templateName || "").toLowerCase()
      const cardCategoryLabel = (card.dataset.templateCategoryLabel || "").toLowerCase()
      const cardCategoryGroup = (card.dataset.templateCategoryGroup || "").toLowerCase()

      // Check search filter (applies across all categories for count)
      const searchMatch = this.searchQuery === "" ||
                          cardName.includes(this.searchQuery) ||
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

    if (this.hasTemplatesGridTarget) {
      this.templatesGridTarget.classList.toggle("hidden", visibleCount === 0)
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
        const pills = content.querySelectorAll("[data-template-applier-target='categoryTab']")
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

  selectTemplate(event) {
    const card = event.currentTarget.closest("[data-template-key]") || event.currentTarget
    const templateKey = card.dataset.templateKey

    // Deselect all cards
    this.templateCardTargets.forEach(c => {
      c.classList.remove("border-indigo-500", "ring-2", "ring-indigo-500", "shadow-md")
      c.classList.add("border-gray-200")

      // Hide apply button
      const applySection = c.querySelector("[data-template-applier-target='applySection']")
      if (applySection) {
        applySection.classList.add("hidden")
      }

      // Hide checkmark
      const checkmark = c.querySelector("[data-checkmark]")
      if (checkmark) {
        checkmark.classList.add("hidden")
      }
    })

    // Select clicked card
    card.classList.remove("border-gray-200")
    card.classList.add("border-indigo-500", "ring-2", "ring-indigo-500", "shadow-md")

    // Show apply button for selected card
    const applySection = card.querySelector("[data-template-applier-target='applySection']")
    if (applySection) {
      applySection.classList.remove("hidden")
    }

    // Show checkmark for selected card
    const checkmark = card.querySelector("[data-checkmark]")
    if (checkmark) {
      checkmark.classList.remove("hidden")
    }

    this.selectedTemplate = templateKey
  }

  get pageBuilderController() {
    const element = document.querySelector("[data-controller~='page-builder']")
    if (!element) return null
    return this.application.getControllerForElementAndIdentifier(element, "page-builder")
  }

  async applyTemplate(event) {
    event.stopPropagation()

    if (!this.selectedTemplate) {
      return
    }

    const pageBuilder = this.pageBuilderController
    if (!pageBuilder) {
      alert(this.pageBuilderNotFoundMsgValue)
      return
    }

    const button = event.currentTarget
    const originalText = button.textContent

    // Disable button and show loading state
    button.disabled = true
    button.textContent = this.applyingLabelValue
    button.classList.add("opacity-75", "cursor-not-allowed")

    try {
      const response = await fetch(
        `/${this.customerIdValue}/admin/maintenance/pages/${this.pageIdValue}/apply_template`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": document.querySelector('[name="csrf-token"]').content,
            "Accept": "application/json"
          },
          body: JSON.stringify({
            template_key: this.selectedTemplate,
            configuration: JSON.stringify(pageBuilder.configuration)
          })
        }
      )

      if (response.ok) {
        const data = await response.json()

        // Save current state to undo stack before applying
        pageBuilder.saveState()

        // Apply the new configuration from the server
        const newConfig = data.configuration

        // Normalize into pages structure if needed
        if (newConfig.pages && Array.isArray(newConfig.pages)) {
          pageBuilder.configuration.pages = newConfig.pages
        } else if (newConfig.fields) {
          // Single page — update the current page's fields
          const currentPage = pageBuilder.currentPage
          if (currentPage) {
            currentPage.fields = newConfig.fields
          }
        }

        // Apply theme if present
        if (newConfig.theme) {
          pageBuilder.configuration.theme = newConfig.theme
        }

        // Persist layout_template_key in configuration metadata
        if (newConfig.metadata?.layout_template_key) {
          pageBuilder.configuration.metadata = {
            ...(pageBuilder.configuration.metadata || {}),
            layout_template_key: newConfig.metadata.layout_template_key
          }
        }

        // Update the active layout template so the canvas renders with new rules
        if (data.template_layout) {
          pageBuilder.layoutTemplateValue = data.template_layout
        }

        // Update fields reference and re-render
        pageBuilder.fields = pageBuilder.currentPageFields
        pageBuilder.pageManager.renderPageTabs()
        pageBuilder.fieldManager.renderFields()
        pageBuilder.fieldManager.deselectField()
        pageBuilder.saveManager.markDirty()

        // Close the templates panel
        pageBuilder.closeAllTabPanels()
      } else {
        const error = await response.json()
        alert(this.applyFailedFormatValue.replace("{message}", error.message || this.unknownErrorLabelValue))
      }
    } catch (error) {
      console.error("Error applying template:", error)
      alert(this.applyFailedGenericMsgValue)
    } finally {
      // Re-enable button
      button.disabled = false
      button.textContent = originalText
      button.classList.remove("opacity-75", "cursor-not-allowed")
    }
  }
}
