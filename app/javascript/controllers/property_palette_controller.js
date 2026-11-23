import { Controller } from "@hotwired/stimulus"

/**
 * Property Palette Controller
 * Manages the left sidebar property palette with drag-drop and search functionality.
 */
export default class extends Controller {
  static targets = [
    "propertiesList",
    "searchInput",
    "placeholder"
  ]

  static values = {
    entityProperties: Array,
    // i18n seam: English default byte-identical to the former hardcoded copy.
    // NOTE: this controller currently has no ERB mount in the app (superseded
    // by the page-builder module's own canvas/toolbar) — see notes in the
    // frontend delivery report. The Value keeps the seam ready for reuse.
    selectEntityToSeeProperties: { type: String, default: "Select an entity to see properties" }
  }

  // ===================
  // Lifecycle
  // ===================

  connect() {
    this.properties = this.entityPropertiesValue || []
    this._renderProperties(this.properties)
  }

  // ===================
  // Property Updates
  // ===================

  updateProperties(properties) {
    this.properties = properties
    this._renderProperties(this.properties)
  }

  entityPropertiesValueChanged() {
    this.properties = this.entityPropertiesValue || []
    this._renderProperties(this.properties)
  }

  // ===================
  // Rendering
  // ===================

  _renderProperties(properties) {
    if (!this.hasPropertiesListTarget) return

    // Clear existing items
    this.propertiesListTarget.innerHTML = ""

    if (properties.length === 0) {
      this.propertiesListTarget.innerHTML = `
        <div class="text-sm text-gray-500 py-4 text-center">
          ${this.selectEntityToSeePropertiesValue}
        </div>
      `
      return
    }

    properties.forEach(property => {
      const propertyElement = this._createPropertyItem(property)
      this.propertiesListTarget.appendChild(propertyElement)
    })
  }

  _createPropertyItem(property) {
    const element = document.createElement("div")
    element.className = "property-item px-3 py-2 bg-gray-50 rounded-lg border border-gray-200 cursor-move hover:border-indigo-300 hover:bg-indigo-50 transition-colors mb-1"
    element.draggable = true
    element.dataset.propertySlug = property.name_slug
    element.dataset.propertyName = property.name
    element.dataset.propertyType = property.type

    element.innerHTML = `
      <div class="flex items-center justify-between gap-2">
        <div class="flex items-center min-w-0 gap-2">
          <svg class="size-4 flex-shrink-0 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8h16M4 16h16" />
          </svg>
          <span class="text-sm font-medium text-gray-700 truncate">${this._escapeHtml(property.name)}</span>
        </div>
        <span class="px-1.5 py-0.5 bg-gray-200 rounded text-xs text-gray-500 flex-shrink-0">${this._escapeHtml(property.type)}</span>
      </div>
    `

    // Event listeners
    element.addEventListener("dragstart", (e) => this.dragStart(e))
    element.addEventListener("dragend", (e) => this.dragEnd(e))
    element.addEventListener("dblclick", (e) => this.addToCanvas(e))

    return element
  }

  _escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  // ===================
  // Drag & Drop
  // ===================

  dragStart(event) {
    const element = event.target.closest("[data-property-slug]")
    if (!element) return

    const dragData = {
      propertySlug: element.dataset.propertySlug,
      propertyName: element.dataset.propertyName,
      propertyType: element.dataset.propertyType
    }

    event.dataTransfer.setData("application/json", JSON.stringify(dragData))
    event.dataTransfer.effectAllowed = "copy"

    element.style.opacity = "0.5"
    element.style.cursor = "grabbing"
  }

  dragEnd(event) {
    const element = event.target.closest("[data-property-slug]")
    if (element) {
      element.style.opacity = ""
      element.style.cursor = "grab"
    }
  }

  addToCanvas(event) {
    event.preventDefault()
    const element = event.target.closest("[data-property-slug]")
    if (!element) return

    const canvasController = this._getCanvasController()
    if (!canvasController) return

    const propertyData = {
      propertySlug: element.dataset.propertySlug,
      propertyName: element.dataset.propertyName,
      propertyType: element.dataset.propertyType
    }

    canvasController.addFieldFromPalette(propertyData)
    this._showClickFeedback(element)
  }

  _showClickFeedback(element) {
    element.classList.add("ring-2", "ring-indigo-500", "scale-95")
    setTimeout(() => {
      element.classList.remove("ring-2", "ring-indigo-500", "scale-95")
    }, 150)
  }

  // ===================
  // Search
  // ===================

  searchProperties(event) {
    const searchTerm = event.target.value.toLowerCase().trim()

    if (!searchTerm) {
      this._renderProperties(this.properties)
      return
    }

    const filtered = this.properties.filter(property => {
      const name = property.name.toLowerCase()
      const slug = property.name_slug.toLowerCase()
      return name.includes(searchTerm) || slug.includes(searchTerm)
    })

    this._renderProperties(filtered)
  }

  // ===================
  // Utilities
  // ===================

  _getCanvasController() {
    const canvasElement = document.querySelector('[data-controller*="page-canvas"]')
    if (!canvasElement) return null

    return this.application.getControllerForElementAndIdentifier(
      canvasElement,
      "page-canvas"
    )
  }
}
