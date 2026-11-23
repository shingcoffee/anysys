import { Controller } from "@hotwired/stimulus"
import { fuzzyMatch } from "utils"
import { DEFAULT_ELEMENT_SPACING, DEFAULT_ELEMENT_HEIGHT, GRID_SIZE } from "flowchart/constants"
import { flowchartUrl } from "flowchart/urls"

/**
 * Element Palette Controller
 * Manages the sidebar palette of flowchart elements with drag-drop and search functionality.
 */
export default class extends Controller {
  static targets = [
    "basicElements",
    "flowchartsList",
    "flowchartsPlaceholder",
    "searchInput"
  ]

  static values = {
    currentFlowchartId: Number,
    // i18n seam: English defaults byte-identical to the former hardcoded copy.
    startTitle: { type: String, default: "Start" },
    startDisabledTitle: { type: String, default: "Only one Start element allowed per flowchart" },
    noOtherFlows: { type: String, default: "No other flows" },
    noCustomerContext: { type: String, default: "No customer context" },
    loadFailed: { type: String, default: "Failed to load flowcharts" },
    noFlowchartsAvailable: { type: String, default: "No flowcharts available" },
    subflowNamePrefix: { type: String, default: "Sub-flow: " }
  }

  // ===================
  // Lifecycle
  // ===================

  connect() {
    this.flowchartsData = []
    this._setupDragAndDrop()
    this._loadFlowcharts()
    this._setupCanvasChangeListener()
    // Initial check for Start element and read-only state
    this._syncPaletteMutability()
  }

  disconnect() {
    this._removeCanvasChangeListener()
    this._removeDropZone()
    this._clearDropIndicatorTimer()
  }

  _canCanvasMutate() {
    const canvasElement = document.querySelector('[data-controller*="flowchart-canvas"]')
    if (canvasElement?.dataset.flowchartCanvasReadOnlyValue === "true") return false
    return canvasElement?.flowchartCanvas?.canMutate?.() !== false
  }

  _setupCanvasChangeListener() {
    const canvasElement = document.querySelector('[data-controller*="flowchart-canvas"]')
    if (canvasElement) {
      this._boundUpdateStartElementState = this._updateStartElementState.bind(this)
      this._boundSyncPaletteMutability = this._syncPaletteMutability.bind(this)
      canvasElement.addEventListener("flowchartChanged", this._boundUpdateStartElementState)
      canvasElement.addEventListener("flowchartMutabilityChanged", this._boundSyncPaletteMutability)
    }
  }

  _removeCanvasChangeListener() {
    const canvasElement = document.querySelector('[data-controller*="flowchart-canvas"]')
    if (canvasElement) {
      if (this._boundUpdateStartElementState) {
        canvasElement.removeEventListener("flowchartChanged", this._boundUpdateStartElementState)
      }
      if (this._boundSyncPaletteMutability) {
        canvasElement.removeEventListener("flowchartMutabilityChanged", this._boundSyncPaletteMutability)
      }
    }
  }

  _syncPaletteMutability() {
    const mutable = this._canCanvasMutate()
    this.element.querySelectorAll('[data-drag-source="true"]').forEach((item) => {
      if (!mutable) {
        item.draggable = false
        item.style.cursor = "not-allowed"
        item.classList.add("opacity-50", "cursor-not-allowed")
        item.classList.remove("cursor-grab")
      } else if (item.dataset.flowchartElement !== "start") {
        item.draggable = true
        item.style.cursor = "grab"
        item.classList.remove("opacity-50", "cursor-not-allowed")
        item.classList.add("cursor-grab")
      }
    })
    if (mutable) this._updateStartElementState()
  }

  _updateStartElementState() {
    const canvasElement = document.querySelector('[data-controller*="flowchart-canvas"]')
    const flowchartCanvas = canvasElement?.flowchartCanvas
    const hasStart = flowchartCanvas?.hasStartElement() || false

    const startElement = this.element.querySelector('[data-flowchart-element="start"]')
    if (startElement) {
      if (hasStart) {
        startElement.draggable = false
        startElement.classList.add("opacity-50", "cursor-not-allowed")
        startElement.classList.remove("cursor-grab")
        startElement.title = this.startDisabledTitleValue
      } else {
        startElement.draggable = true
        startElement.classList.remove("opacity-50", "cursor-not-allowed")
        startElement.classList.add("cursor-grab")
        startElement.title = this.startTitleValue
      }
    }
  }

  // ===================
  // Initialization
  // ===================

  _setupDragAndDrop() {
    const draggableElements = this.element.querySelectorAll('[data-drag-source="true"]')
    draggableElements.forEach(element => this._setupDraggableElement(element))
    this._setupDropZone()
  }

  _setupDraggableElement(element) {
    element.draggable = true
    element.style.cursor = "grab"

    element.addEventListener("dragstart", this._handleDragStart.bind(this))
    element.addEventListener("dragend", this._handleDragEnd.bind(this))
    element.addEventListener("mouseenter", this._handleMouseEnter.bind(this))
    element.addEventListener("mouseleave", this._handleMouseLeave.bind(this))
    // Add double-click handler for adding element to canvas
    element.addEventListener("dblclick", this._handleDoubleClick.bind(this))
  }

  _setupDropZone() {
    // Use canvasContainer which doesn't get replaced during FlowchartCanvas initialization
    const canvasContainer = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
    if (!canvasContainer) return

    this._dropZone = canvasContainer
    this._boundHandleDragOver = this._handleDragOver.bind(this)
    this._boundHandleDrop = this._handleDrop.bind(this)
    this._boundHandleDragEnter = this._handleDragEnter.bind(this)
    this._boundHandleDragLeave = this._handleDragLeave.bind(this)

    canvasContainer.addEventListener("dragover", this._boundHandleDragOver)
    canvasContainer.addEventListener("drop", this._boundHandleDrop)
    canvasContainer.addEventListener("dragenter", this._boundHandleDragEnter)
    canvasContainer.addEventListener("dragleave", this._boundHandleDragLeave)
  }

  _removeDropZone() {
    if (!this._dropZone) return
    this._dropZone.removeEventListener("dragover", this._boundHandleDragOver)
    this._dropZone.removeEventListener("drop", this._boundHandleDrop)
    this._dropZone.removeEventListener("dragenter", this._boundHandleDragEnter)
    this._dropZone.removeEventListener("dragleave", this._boundHandleDragLeave)
    this._dropZone = null
  }

  // ===================
  // Double-Click Handler
  // ===================

  _handleDoubleClick(event) {
    event.preventDefault()
    event.stopPropagation()

    const element = event.target.closest("[data-flowchart-element]")
    if (!element) return

    const elementType = element.dataset.flowchartElement

    const canvasElement = document.querySelector('[data-controller*="flowchart-canvas"]')
    const canvasContainer = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
    if (!canvasElement || !canvasContainer) return

    // Get the canvas instance to determine optimal position
    const flowchartCanvas = canvasElement.flowchartCanvas
    if (flowchartCanvas?.canMutate?.() === false) return
    const position = this._calculateOptimalPosition(flowchartCanvas)

    // Prepare custom data for subflow elements
    let customData = null
    if (element.dataset.flowchartId) {
      customData = {
        name: `${this.subflowNamePrefixValue}${element.dataset.flowchartName}`,
        flowchartId: element.dataset.flowchartId
      }
    }

    this._dispatchElementDrop(elementType, position.x, position.y, customData, true)
    this._showClickFeedback(element)
  }

  _calculateOptimalPosition(flowchartCanvas) {
    const DEFAULT_X = 400
    const DEFAULT_Y = 80

    // If no canvas or no elements, use default starting position
    if (!flowchartCanvas || !flowchartCanvas.elements || flowchartCanvas.elements.length === 0) {
      return { x: DEFAULT_X, y: DEFAULT_Y }
    }

    // Find the last element in the flowchart
    const elements = flowchartCanvas.elements
    const lastElement = elements[elements.length - 1]

    // Position below the last element with grid-aligned center-to-center distance
    const rawDist = lastElement.height / 2 + DEFAULT_ELEMENT_SPACING + DEFAULT_ELEMENT_HEIGHT / 2
    const gridDist = Math.round(rawDist / GRID_SIZE) * GRID_SIZE
    return {
      x: lastElement.x,
      y: lastElement.y + gridDist
    }
  }

  _showClickFeedback(element) {
    element.classList.add("ring-2", "ring-blue-500", "scale-95")
    setTimeout(() => {
      element.classList.remove("ring-2", "ring-blue-500", "scale-95")
    }, 150)
  }

  // ===================
  // Drag Event Handlers
  // ===================

  _handleDragStart(event) {
    if (!this._canCanvasMutate()) {
      event.preventDefault?.()
      return
    }
    const element = event.target.closest("[data-flowchart-element]")
    if (!element) return

    const dragData = {
      elementType: element.dataset.flowchartElement,
      elementId: element.dataset.elementId,
      label: element.dataset.label
    }

    // Include flowchart reference data for subflow elements
    if (element.dataset.flowchartId) {
      dragData.flowchartId = element.dataset.flowchartId
      dragData.flowchartName = element.dataset.flowchartName
    }

    event.dataTransfer.setData("application/json", JSON.stringify(dragData))
    event.dataTransfer.effectAllowed = "copy"

    element.style.opacity = "0.5"
    element.style.cursor = "grabbing"
    document.body.classList.add("dragging-element")
  }

  _handleDragEnd(event) {
    const element = event.target.closest("[data-flowchart-element]")
    if (element) {
      element.style.opacity = ""
      element.style.cursor = "grab"
    }

    document.body.classList.remove("dragging-element")
    this._removeDropZoneHighlight()
  }

  _handleMouseEnter(event) {
    if (!this._canCanvasMutate()) return
    const element = event.target.closest("[data-flowchart-element]")
    if (element) {
      element.style.transform = "scale(1.05)"
      element.style.transition = "transform 0.2s ease"
    }
  }

  _handleMouseLeave(event) {
    const element = event.target.closest("[data-flowchart-element]")
    if (element) {
      element.style.transform = ""
    }
  }

  // ===================
  // Drop Zone Handlers
  // ===================

  _handleDragOver(event) {
    if (!this._canCanvasMutate()) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "copy"

    // Highlight element under cursor for visual feedback
    const dropPosition = this._getDropPosition(event)
    const canvasElement = document.querySelector('[data-controller*="flowchart-canvas"]')
    if (canvasElement && canvasElement.flowchartCanvas) {
      canvasElement.flowchartCanvas.highlightDropTargetAt(dropPosition.x, dropPosition.y)
    }
  }

  _handleDragEnter(event) {
    if (!this._canCanvasMutate()) return
    event.preventDefault()
    this._addDropZoneHighlight(event.currentTarget)
  }

  _handleDragLeave(event) {
    if (!event.currentTarget.contains(event.relatedTarget)) {
      this._removeDropZoneHighlight()
      // Clear element highlight when leaving canvas area
      const canvasElement = document.querySelector('[data-controller*="flowchart-canvas"]')
      if (canvasElement && canvasElement.flowchartCanvas) {
        canvasElement.flowchartCanvas.clearExternalDropHighlight()
      }
    }
  }

  _handleDrop(event) {
    event.preventDefault()

    const canvasElement = document.querySelector('[data-controller*="flowchart-canvas"]')
    const flowchartCanvas = canvasElement?.flowchartCanvas
    if (flowchartCanvas?.canMutate?.() === false) return

    // Capture the drop target BEFORE clearing the highlight
    const dropTarget = flowchartCanvas?.getExternalDropTarget()

    // Clear element highlight on drop
    if (flowchartCanvas) {
      flowchartCanvas.clearExternalDropHighlight()
    }

    try {
      const dragData = JSON.parse(event.dataTransfer.getData("application/json"))
      const dropPosition = this._getDropPosition(event)

      this._removeDropZoneHighlight()

      // Prepare custom data for subflow elements
      let customData = null
      if (dragData.flowchartId) {
        customData = {
          name: `${this.subflowNamePrefixValue}${dragData.flowchartName}`,
          flowchartId: dragData.flowchartId
        }
      }

      this._dispatchElementDrop(
        dragData.elementType,
        dropPosition.x,
        dropPosition.y,
        customData,
        false,
        dropTarget
      )
      this._showDropSuccess(event)
    } catch (error) {
      console.error("[element-palette] Failed to handle element drop:", error)
    }
  }

  _addDropZoneHighlight(dropZone) {
    dropZone.classList.add("drop-zone-active")
  }

  _removeDropZoneHighlight() {
    document.querySelectorAll(".drop-zone-active").forEach(zone => {
      zone.classList.remove("drop-zone-active")
    })
  }

  // ===================
  // Flowcharts
  // ===================

  async _loadFlowcharts() {
    try {
      const currentId = this.currentFlowchartIdValue
      const baseUrl = flowchartUrl(null, "list")
      if (!baseUrl) {
        this._showFlowchartsError(this.noCustomerContextValue)
        return
      }
      const url = currentId ? `${baseUrl}?except_id=${currentId}` : baseUrl
      const response = await fetch(url)
      if (response.ok) {
        this.flowchartsData = await response.json()
        this._renderFlowcharts(this.flowchartsData)
      } else {
        this._showFlowchartsError(this.loadFailedValue)
      }
    } catch (error) {
      console.error("[element-palette] Failed to load flowcharts:", error)
      this._showFlowchartsError(this.noFlowchartsAvailableValue)
    }
  }

  _renderFlowcharts(flowcharts) {
    if (!this.hasFlowchartsListTarget) return

    if (this.hasFlowchartsPlaceholderTarget) {
      this.flowchartsPlaceholderTarget.style.display = "none"
    }

    this.flowchartsListTarget.innerHTML = ""

    if (flowcharts.length === 0) {
      this.flowchartsListTarget.innerHTML = `
        <div class="text-sm text-gray-500 py-2 text-center">
          ${this.noOtherFlowsValue}
        </div>
      `
      return
    }

    flowcharts.forEach(flowchart => {
      const flowchartElement = this._createFlowchartItem(flowchart)
      this.flowchartsListTarget.appendChild(flowchartElement)
      // Set up drag handlers for the flow item
      this._setupDraggableElement(flowchartElement.querySelector('[data-drag-source="true"]') || flowchartElement)
    })
    this._syncPaletteMutability()
  }

  _createFlowchartItem(flowchart) {
    // Wrapper with relative positioning for the instant tooltip
    const wrapper = document.createElement("div")
    wrapper.className = "relative group"

    const element = document.createElement("div")
    element.className = "flex items-center gap-2 py-2 px-2.5 text-xs font-medium text-slate-700 bg-white border border-slate-200 rounded-lg truncate cursor-grab select-none transition-all hover:text-indigo-600 hover:bg-indigo-50 hover:border-indigo-300 hover:shadow-sm active:cursor-grabbing active:scale-[0.98]"

    // Flow icon
    const icon = document.createElement("span")
    icon.innerHTML = '<svg class="h-3.5 w-3.5 flex-shrink-0 text-slate-400 group-hover:text-indigo-400 transition-colors" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" /></svg>'

    const nameSpan = document.createElement("span")
    nameSpan.className = "truncate"
    nameSpan.textContent = flowchart.name

    element.appendChild(icon)
    element.appendChild(nameSpan)

    // Tooltip shown on hover — uses fixed positioning to escape overflow-hidden sidebar
    const tooltipText = flowchart.description || flowchart.name

    wrapper.appendChild(element)

    let tooltip = null
    wrapper.addEventListener("mouseenter", () => {
      tooltip = document.createElement("div")
      tooltip.className = "fixed px-2.5 py-1.5 bg-slate-800 text-white text-[11px] rounded-md shadow-lg pointer-events-none z-[9999] max-w-[300px]"
      tooltip.textContent = tooltipText
      document.body.appendChild(tooltip)

      const rect = wrapper.getBoundingClientRect()
      tooltip.style.left = `${rect.right + 8}px`
      tooltip.style.top = `${rect.top + rect.height / 2}px`
      tooltip.style.transform = "translateY(-50%)"
    })
    wrapper.addEventListener("mouseleave", () => {
      tooltip?.remove()
      tooltip = null
    })

    // Set up data attributes for drag and drop on the inner element
    element.dataset.dragSource = "true"
    element.dataset.flowchartElement = "subflow"
    element.dataset.elementId = `flow_${flowchart.id}`
    element.dataset.label = flowchart.name
    element.dataset.flowchartId = flowchart.id
    element.dataset.flowchartName = flowchart.name

    return wrapper
  }

  _showFlowchartsError(message) {
    if (!this.hasFlowchartsPlaceholderTarget) return
    this.flowchartsPlaceholderTarget.textContent = message
  }

  // ===================
  // Search
  // ===================

  searchFlowcharts(event) {
    const searchTerm = event.target.value.toLowerCase().trim()

    if (!searchTerm) {
      this._renderFlowcharts(this.flowchartsData)
      return
    }

    const filteredFlowcharts = this.flowchartsData.filter(flowchart => {
      const name = flowchart.name.toLowerCase()
      const description = (flowchart.description || '').toLowerCase()
      return fuzzyMatch(name, searchTerm) || fuzzyMatch(description, searchTerm)
    })

    this._renderFlowcharts(filteredFlowcharts)
  }

  // ===================
  // Utilities
  // ===================

  _getDropPosition(event) {
    const canvasElement = document.querySelector('[data-controller*="flowchart-canvas"]')
    const flowchartCanvas = canvasElement?.flowchartCanvas
    if (flowchartCanvas?.zoomPanManager) {
      return flowchartCanvas.zoomPanManager.clientToSVG(event.clientX, event.clientY)
    }

    // Fallback if canvas not ready
    const canvasContainer = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
    if (!canvasContainer) return { x: 100, y: 100 }

    const containerRect = canvasContainer.getBoundingClientRect()
    return {
      x: event.clientX - containerRect.left + canvasContainer.scrollLeft,
      y: event.clientY - containerRect.top + canvasContainer.scrollTop
    }
  }

  _showDropSuccess(event) {
    const canvasContainer = document.querySelector('[data-flowchart-canvas-target="canvasContainer"]')
    if (!canvasContainer) return

    const rect = canvasContainer.getBoundingClientRect()
    const indicator = document.createElement("div")

    indicator.className = "drop-success-animation"
    indicator.style.left = (event.clientX - rect.left + canvasContainer.scrollLeft - 25) + "px"
    indicator.style.top = (event.clientY - rect.top + canvasContainer.scrollTop - 25) + "px"
    indicator.style.width = "50px"
    indicator.style.height = "50px"

    this._clearDropIndicatorTimer()
    canvasContainer.appendChild(indicator)
    this._dropIndicator = indicator
    this._dropIndicatorTimer = setTimeout(() => {
      this._dropIndicatorTimer = null
      this._dropIndicator = null
      indicator.remove()
    }, 1000)
  }

  _clearDropIndicatorTimer() {
    if (this._dropIndicatorTimer) {
      clearTimeout(this._dropIndicatorTimer)
      this._dropIndicatorTimer = null
    }
    this._dropIndicator?.remove()
    this._dropIndicator = null
  }

  _dispatchElementDrop(elementType, x, y, customElementData = null, isDoubleClick = false, dropTarget = null) {
    const canvasElement = document.querySelector('[data-controller*="flowchart-canvas"]')
    if (!canvasElement) return

    canvasElement.dispatchEvent(new CustomEvent("elementDrop", {
      detail: { elementType, x, y, customElementData, isDoubleClick, dropTarget }
    }))
  }
}
