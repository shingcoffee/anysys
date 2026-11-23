/**
 * FlowchartCanvas - Main canvas class for flowchart editing.
 *
 * Provides an SVG-based canvas for creating and editing flowcharts with:
 * - Element creation and management
 * - Drag and drop support
 * - Connection management
 * - Undo/redo hooks
 * - Keyboard shortcuts
 */

import { createSvgElement, createGroup, createRect, createLine } from "utils"
import {
  GRID_SIZE,
  ZOOM_STEP
} from "flowchart/constants"
import { elementSchemaMap } from "flowchart/constants/element_registry"
import { ElementRendererMixin } from "flowchart/element_renderer"
import { ConnectionManagerMixin } from "flowchart/connection_manager"
import { SelectionManagerMixin } from "flowchart/selection_manager"
import { DragHandlerMixin } from "flowchart/drag_handler"
import { ResizeHandlerMixin } from "flowchart/resize_handler"
import { ZoomPanManager } from "flowchart/zoom_pan_manager"
import { ClipboardManager } from "flowchart/clipboard_manager"
import { AlignmentManager } from "flowchart/alignment_manager"
import { LayoutManager } from "flowchart/layout_manager"
import { ElementManagementMixin } from "flowchart/canvas/element_management"
import { ExternalDropMixin } from "flowchart/canvas/external_drop"
import { SerializationMixin } from "flowchart/canvas/serialization"
import { TraceOverlayMixin } from "flowchart/canvas/trace_overlay"

export class FlowchartCanvas {
  constructor(containerElement) {
    this.containerElement = containerElement

    // Read-only mode disables every mutation entry point: drag, resize,
    // delete, paste, connection draw/redirect, inline editing. The
    // Stimulus controller already short-circuits its own buttons on
    // `readOnlyValue`, but the canvas owns its own DOM event handlers
    // and the document-level keyboard shortcuts, so without a flag here
    // an active (non-draft) flowchart is still fully editable via the
    // canvas itself. Defaults to false so callers that don't set the
    // flag get the same behavior they had before.
    this.isReadOnly = false
    // True while an expanded subflow is shown: the canvas is a read-only preview.
    this.previewMode = false
    // Numbers each nudge burst so a later burst never coalesces into an earlier one.
    this._nudgeBurstSeq = 0

    // Data
    this.elements = []
    this.connections = []
    this.selectedElements = []
    Object.defineProperty(this, "elementSchemas", {
      get: elementSchemaMap,
      enumerable: true
    })

    // I/O pin cache: step_id -> { inputs: [...], outputs: [...] }
    this.stepPins = {}

    // I/O pin cache: element_id -> { inputs: [...], outputs: [...] }
    this.elementPins = {}

    // Connection routing mode: "straight" or "orthogonal" (default)
    this.connectionRouting = "orthogonal"

    // Preserved metadata from loaded config — passed through on save so
    // server-known keys (canvas size, zoom, custom metadata) are not
    // silently wiped each time the user clicks Save.
    this._loadedMetadata = {}

    // State
    this._initState()

    // Callbacks
    this.onchange = null
    this.onBeforeChange = null
    this.onElementSelected = null
    this.onElementDoubleClick = null
    this.onCanvasClick = null
    this.onConnectionSelected = null
    this.onundo = null
    this.onredo = null
    this.onZoomChange = null
    this.onSelectionChanged = null
    this.onSearchRequested = null
    this.onToast = null

    this._initCanvas()
  }

  canMutate() {
    return !this.isReadOnly && !this.previewMode
  }

  /**
   * Initialize interaction state.
   */
  _initState() {
    // Connection drawing
    this.isDrawingConnection = false
    this.connectionStartElement = null
    this.connectionStartHandle = null
    this.connectionLine = null
    this.selectedConnectionId = null

    // Connection endpoint dragging
    this.isDraggingConnectionEndpoint = false
    this.draggingConnection = null
    this.draggingEndpointType = null
    this.connectionDragLine = null
    this.highlightedElement = null

    // Element dragging
    this.isDragging = false
    this.draggedElement = null
    this.draggedElements = null
    this.dragStartPosition = null
    this.draggedSubTree = null
    this.dragOffset = { x: 0, y: 0 }
    this.dropTargetElement = null
    this.externalDropTarget = null

    // Selection rectangle
    this.isSelecting = false
    this.selectionStart = null
    this.selectionRect = null

    // Resize
    this.isResizing = false
    this._resizeState = null

    // Tooltip
    this._activeTooltip = null
    this._lastTapElementId = null
    this._lastTapAt = 0

  }

  // ===================
  // Initialization
  // ===================

  _initCanvas() {
    this._createSvg()
    this._createLayers()
    this._drawGrid()
    this._bindEvents()

    this.canvas = this.svg
  }

  _createSvg() {
    this.svg = createSvgElement("svg", {
      class: "flowchart-svg",
      style: "width: 100%; height: 100%;"
    })
    this.svg.style.cursor = "default"

    this.containerElement.parentNode.replaceChild(this.svg, this.containerElement)
    this.container = this.svg
    this.zoomPanManager = new ZoomPanManager(this.svg)
    this.clipboardManager = new ClipboardManager(this)
    this.alignmentManager = new AlignmentManager(this)
    this.layoutManager = new LayoutManager(this)
  }

  _createLayers() {
    const layers = ["grid", "connection", "element", "handle", "guide", "selection"]

    layers.forEach(name => {
      this[`${name}Layer`] = createGroup({ class: `${name}-layer` })
      this.svg.appendChild(this[`${name}Layer`])
    })
  }

  _drawGrid() {
    const defs = createSvgElement("defs")
    const pattern = createSvgElement("pattern", {
      id: "grid-pattern",
      width: GRID_SIZE,
      height: GRID_SIZE,
      patternUnits: "userSpaceOnUse"
    })

    pattern.appendChild(createSvgElement("circle", {
      cx: GRID_SIZE / 2,
      cy: GRID_SIZE / 2,
      r: 1,
      fill: "#cbd5e1"
    }))

    defs.appendChild(pattern)

    // Add search highlight styles
    const style = createSvgElement("style")
    style.textContent = `
      .search-highlight rect,
      .search-highlight ellipse,
      .search-highlight polygon,
      .search-highlight path.shape-path {
        stroke-dasharray: 6 3;
        stroke-width: 3;
      }
      .search-current rect,
      .search-current ellipse,
      .search-current polygon,
      .search-current path.shape-path {
        stroke: #f59e0b !important;
        stroke-width: 3;
        stroke-dasharray: 6 3;
      }
      .selected rect,
      .selected ellipse,
      .selected polygon,
      .selected path.shape-path {
        stroke: #6366f1 !important;
        stroke-width: 2.5;
        stroke-dasharray: 6 3;
      }
      .connection-line.flow-animated {
        stroke-dasharray: 6 4;
        animation: connectionFlow 0.6s linear infinite;
      }
      @keyframes connectionFlow {
        to { stroke-dashoffset: -10; }
      }
    `
    defs.appendChild(style)

    this.svg.insertBefore(defs, this.svg.firstChild)

    this.gridLayer.appendChild(createRect(-10000, -10000, 20000, 20000, {
      fill: "url(#grid-pattern)"
    }))
  }

  _bindEvents() {
    const events = {
      mousedown: "_handleMouseDown",
      mousemove: "_handleMouseMove",
      mouseup: "_handleMouseUp",
      click: "_handleClick",
      dblclick: "_handleDoubleClick"
    }

    Object.entries(events).forEach(([event, handler]) => {
      this.svg.addEventListener(event, e => this[handler](e))
    })

    this.svg.addEventListener("contextmenu", e => e.preventDefault())

    this.svg.addEventListener("wheel", e => this._handleWheel(e), { passive: false })
    this.svg.addEventListener("touchstart", e => this._handleTouchStart(e), { passive: true })
    this.svg.addEventListener("touchmove", e => this._handleTouchMove(e), { passive: false })
    this.svg.addEventListener("touchend", () => this._handleTouchEnd())

    this._keyDownHandler = e => this._handleKeyDown(e)
    document.addEventListener("keydown", this._keyDownHandler)
    this._keyUpHandler = e => this._handleKeyUp(e)
    document.addEventListener("keyup", this._keyUpHandler)
  }

  _bindDocumentDragListeners() {
    if (this._documentDragMoveHandler) return
    this._documentDragMoveHandler = e => this._handleMouseMove(e)
    this._documentDragUpHandler = e => this._handleMouseUp(e)
    document.addEventListener("mousemove", this._documentDragMoveHandler)
    document.addEventListener("mouseup", this._documentDragUpHandler)
  }

  _unbindDocumentDragListeners() {
    if (!this._documentDragMoveHandler) return
    document.removeEventListener("mousemove", this._documentDragMoveHandler)
    document.removeEventListener("mouseup", this._documentDragUpHandler)
    this._documentDragMoveHandler = null
    this._documentDragUpHandler = null
  }

  // ===================
  // Mouse Events
  // ===================

  _handleMouseDown(e) {
    if (this.zoomPanManager.isSpaceHeld) {
      this.zoomPanManager.startPan(e.clientX, e.clientY)
      return
    }

    const resizeTarget = e.target.closest("[data-resize-handle]")
    if (resizeTarget) {
      if (!this.canMutate()) return
      const corner = resizeTarget.dataset.resizeHandle
      const elementId = resizeTarget.dataset.resizeElementId
      const element = this.elements.find(el => el.id === elementId)
      if (element) {
        this._handleResizeStart(element, corner, e)
        return
      }
    }

    const endpointTarget = e.target.closest("[data-connection-endpoint]")
    if (endpointTarget) {
      if (!this.canMutate()) return
      e.stopPropagation()
      this._startConnectionEndpointDrag(endpointTarget)
      return
    }

    const handleTarget = e.target.closest("[data-handle-position]")
    if (handleTarget) {
      if (!this.canMutate()) return
      e.stopPropagation()
      const elementGroup = handleTarget.closest("[data-element-id]") ||
                           this._findElementGroupByHandle(handleTarget)
      if (elementGroup) this._startConnectionDraw(elementGroup, handleTarget)
      return
    }

    const connectionTarget = e.target.closest("[data-connection-id]")
    if (connectionTarget) {
      e.stopPropagation()
      this.selectConnection(connectionTarget.dataset.connectionId)
      return
    }

    const elementTarget = e.target.closest("[data-element-id]")
    if (elementTarget) {
      this._handleElementMouseDown(elementTarget, e)
    } else {
      this._handleCanvasMouseDown(e)
    }
  }

  _handleElementMouseDown(target, e) {
    const element = this.elements.find(el => el.id === target.dataset.elementId)
    if (!element) return

    if (this._isAdditiveSelect(e)) {
      e.preventDefault()
      e.stopPropagation()
      this._toggleElementSelection(element)
    } else {
      if (!this._isElementSelected(element)) {
        this._clearSelection()
        this._addToSelection(element)
      }
      // In read-only mode selection still works (so users can inspect /
      // copy element data), but dragging is suppressed — otherwise an
      // active flowchart could be rearranged on the canvas even though
      // the save round-trip would reject the write.
      if (this.canMutate()) {
        this._startDrag(element, e)
      }
    }
  }

  _handleCanvasMouseDown(e) {
    if (!this._isAdditiveSelect(e)) {
      this._clearSelection()
    }
    this._startSelectionRect(e)
  }

  _handleMouseMove(e) {
    if (this.zoomPanManager.isPanning) {
      this.zoomPanManager.updatePan(e.clientX, e.clientY)
      return
    }

    if (this.isResizing) {
      this._handleResizeMove(e)
      return
    }

    const point = this._getSVGPoint(e)

    if (this.isSelecting) {
      this._updateSelectionRect(point)
      return
    }

    if (this.isDraggingConnectionEndpoint) {
      this._updateConnectionEndpointDrag(point)
      this._highlightElementAtPoint(point.x, point.y)
      return
    }

    if (this.isDrawingConnection && this.connectionLine) {
      this.connectionLine.setAttribute("x2", point.x)
      this.connectionLine.setAttribute("y2", point.y)
      return
    }

    if (this.isDragging && this.draggedElement) {
      this._handleDragMove(point)
    }
  }

  _handleDragMove(point) {
    const newX = point.x - this.dragOffset.x
    const newY = point.y - this.dragOffset.y

    if (this.draggedElements?.length > 1) {
      // Multi-element drag
      const deltaX = newX - this.dragStartPosition.x
      const deltaY = newY - this.dragStartPosition.y

      this.draggedElements.forEach(({ element, startX, startY }) => {
        this._moveElementVisually(element, startX + deltaX, startY + deltaY)
      })
    } else {
      // Single element drag carries its sub-tree
      this._moveElementVisually(this.draggedElement, newX, newY)
      this._moveSubTreeVisually(newX, newY)
      this._highlightDropTarget(point.x, point.y)
    }

    this._updateConnectionsVisually()
    this._showAlignmentGuides(this.draggedElement, newX, newY)
  }

  _handleMouseUp(e) {
    if (this.zoomPanManager.isPanning) {
      this.zoomPanManager.endPan()
      return
    }

    if (this.isResizing) {
      this._handleResizeEnd()
      return
    }

    const point = this._getSVGPoint(e)

    if (this.isSelecting) {
      this._endSelectionRect(e)
      // After selection rect or any mouse up that might change selection
      this.onSelectionChanged?.()
      return
    }

    if (this.isDraggingConnectionEndpoint) {
      this._endConnectionEndpointDrag(point)
      return
    }

    if (this.isDrawingConnection) {
      this._finishConnectionDraw(point)
      return
    }

    if (this.isDragging && this.draggedElement) {
      this._endDrag()
    }
  }

  _handleClick(e) {
    if (e.target.closest("[data-connection-endpoint]")) return

    const hasInteractiveTarget =
      e.target.closest("[data-element-id]") ||
      e.target.closest("[data-connection-id]") ||
      e.target.closest("[data-handle-position]")

    if (!hasInteractiveTarget && this.onCanvasClick) {
      this.onCanvasClick()
    }
  }

  _handleDoubleClick(e) {
    // Check for connection double-click first
    const connectionTarget = e.target.closest("[data-connection-id]")
    if (connectionTarget) {
      const connectionId = connectionTarget.dataset.connectionId
      this.selectConnection(connectionId)
      this.startInlineLabelEdit(connectionId)
      return
    }

    // Find element: direct hit or via handle/resize overlay (handles appear after first click)
    let elementId = null
    const directTarget = e.target.closest("[data-element-id]")
    if (directTarget) {
      elementId = directTarget.dataset.elementId
    } else {
      // Check if double-click landed on a connection handle or resize handle
      const handleTarget = e.target.closest("[data-parent-element-id]")
      const resizeTarget = e.target.closest("[data-resize-element-id]")
      elementId = handleTarget?.dataset.parentElementId || resizeTarget?.dataset.resizeElementId
    }

    if (!elementId) return

    const element = this.elements.find(el => el.id === elementId)
    if (!element) return

    if (this.onElementDoubleClick) {
      this.onElementDoubleClick(element)
    }
  }

  // ===================
  // Keyboard Events
  // ===================

  _handleKeyDown(e) {
    // Save: Ctrl+S from anywhere on the editor page, including property fields
    // (they sync on input), so the browser's Save Page dialog never opens.
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") {
      e.preventDefault()
      this._endNudgeBurst()
      this.onSaveRequested?.()
      return
    }

    if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.tagName === "SELECT" || e.target.isContentEditable) {
      this._endNudgeBurst()
      return
    }

    const inCanvas = e.target === document.body || this.container.contains(e.target)
    if (!inCanvas) return

    const key = e.key.length === 1 ? e.key.toLowerCase() : e.key

    if (key === "Escape" && this.isDragging) {
      e.preventDefault()
      this._endNudgeBurst()
      this._cancelElementDrag()
      return
    }

    if (key === "ArrowLeft" || key === "ArrowRight" || key === "ArrowUp" || key === "ArrowDown") {
      this._handleNudgeKey(e, key)
      return
    }

    this._endNudgeBurst()

    const isMod = e.ctrlKey || e.metaKey

    // Space: enable pan mode
    if (key === " " && !e.repeat) {
      e.preventDefault()
      this.zoomPanManager.isSpaceHeld = true
      this.svg.style.cursor = "grab"
      return
    }

    // Undo: Ctrl+Z
    if (isMod && key === "z" && !e.shiftKey) {
      e.preventDefault()
      this.onundo?.()
      return
    }

    // Redo: Ctrl+Y or Ctrl+Shift+Z
    if (isMod && (key === "y" || (e.shiftKey && key === "z"))) {
      e.preventDefault()
      this.onredo?.()
      return
    }

    // Zoom In: Ctrl+= or Ctrl++
    if (isMod && (key === "=" || key === "+")) {
      e.preventDefault()
      this.zoomPanManager.zoomIn()
      this.onZoomChange?.(this.zoomPanManager.zoomPercent)
      return
    }

    // Zoom Out: Ctrl+-
    if (isMod && key === "-") {
      e.preventDefault()
      this.zoomPanManager.zoomOut()
      this.onZoomChange?.(this.zoomPanManager.zoomPercent)
      return
    }

    // Fit to Content: Ctrl+0
    if (isMod && key === "0") {
      e.preventDefault()
      this.zoomPanManager.fitToContent(this.elements)
      this.onZoomChange?.(this.zoomPanManager.zoomPercent)
      return
    }

    // Copy: Ctrl+C
    if (isMod && key === "c") {
      if (this.selectedElements.length > 0) {
        e.preventDefault()
        this.clipboardManager.copy()
      }
      return
    }

    // Paste: Ctrl+V
    if (isMod && key === "v") {
      if (!this.canMutate()) return
      if (this.clipboardManager.hasContent) {
        e.preventDefault()
        this._pasteElements(this.clipboardManager.paste())
      }
      return
    }

    // Duplicate: Ctrl+D
    if (isMod && key === "d") {
      if (!this.canMutate()) return
      if (this.selectedElements.length > 0) {
        e.preventDefault()
        this._pasteElements(this.clipboardManager.duplicate())
      }
      return
    }

    // Select all: Ctrl+A (never when typing — that path returned above)
    if (isMod && key === "a") {
      e.preventDefault()
      this._selectAllElements()
      return
    }

    // Search: Ctrl+F
    if (isMod && key === "f") {
      e.preventDefault()
      this.onSearchRequested?.()
      return
    }

    // Open properties for selected element: Enter
    if (key === "Enter" && !isMod) {
      if (this.selectedElements.length === 1) {
        e.preventDefault()
        this.onElementDoubleClick?.(this.selectedElements[0])
      }
      return
    }

    // Delete
    if (key === "Delete" || key === "Backspace") {
      if (!this.canMutate()) return
      this._handleDelete(e)
    }
  }

  _handleTouchStart(e) {
    if (e.touches.length !== 1) return
    const touch = e.touches[0]
    const elementTarget = e.target.closest?.("[data-element-id]")
    if (elementTarget) {
      const element = this.elements.find(el => el.id === elementTarget.dataset.elementId)
      if (!element) return
      const now = Date.now()
      this._selectElement(element)
      if (this._lastTapElementId === element.id && now - this._lastTapAt < 350) {
        this._lastTapElementId = null
        this.onElementDoubleClick?.(element)
      } else {
        this._lastTapElementId = element.id
        this._lastTapAt = now
      }
      return
    }
    this._lastTapElementId = null
    this.zoomPanManager.startPan(touch.clientX, touch.clientY)
  }

  _handleTouchMove(e) {
    if (!this.zoomPanManager.isPanning || e.touches.length !== 1) return
    e.preventDefault()
    const touch = e.touches[0]
    this.zoomPanManager.updatePan(touch.clientX, touch.clientY)
    this.onZoomChange?.(this.zoomPanManager.zoomPercent)
  }

  _handleTouchEnd() {
    if (this.zoomPanManager.isPanning) {
      this.zoomPanManager.endPan()
    }
  }

  _handleKeyUp(e) {
    if (e.key === " ") {
      this.zoomPanManager.isSpaceHeld = false
      if (this.zoomPanManager.isPanning) {
        this.zoomPanManager.endPan()
      }
      this.svg.style.cursor = "default"
    }
  }

  // Consecutive arrow nudges share one undo entry via undoCoalesceKey.
  // The burst ends on any other in-canvas key, a 500ms idle, or destroy.
  _handleNudgeKey(e, key) {
    if (!this.canMutate()) return
    if (this.selectedElements.length === 0) return

    e.preventDefault()
    const step = (e.shiftKey ? 5 : 1) * GRID_SIZE
    const dx = key === "ArrowLeft" ? -step : key === "ArrowRight" ? step : 0
    const dy = key === "ArrowUp" ? -step : key === "ArrowDown" ? step : 0
    this._nudgeSelection(dx, dy)
  }

  _nudgeSelection(dx, dy) {
    if (!this._nudgeBurstTimer) this._nudgeBurstSeq += 1
    const ids = this.selectedElements.map(el => el.id).slice().sort().join(",")
    this.undoCoalesceKey = `nudge:${ids}#${this._nudgeBurstSeq}`
    this.onBeforeChange?.()

    this.selectedElements.forEach(el => {
      el.x += dx
      el.y += dy
      this.updateElementPosition(el)
    })
    this.updateConnections()

    if (this.selectedElements.length === 1) {
      this.showResizeHandles(this.selectedElements[0])
    }
    this.showConnectionHandles(this.selectedElements)

    this.onchange?.()
    this._scheduleNudgeBurstEnd()
  }

  _scheduleNudgeBurstEnd() {
    if (this._nudgeBurstTimer) clearTimeout(this._nudgeBurstTimer)
    this._nudgeBurstTimer = setTimeout(() => this._endNudgeBurst(), 500)
  }

  _endNudgeBurst() {
    if (this._nudgeBurstTimer) {
      clearTimeout(this._nudgeBurstTimer)
      this._nudgeBurstTimer = null
    }
    if (typeof this.undoCoalesceKey === "string" && this.undoCoalesceKey.startsWith("nudge:")) {
      this.undoCoalesceKey = null
    }
  }

  _handleWheel(e) {
    e.preventDefault()

    if (e.ctrlKey || e.metaKey) {
      // Ctrl/Cmd + wheel: zoom
      const delta = e.deltaY > 0 ? -ZOOM_STEP : ZOOM_STEP
      this.zoomPanManager.zoomTo(this.zoomPanManager.zoom + delta, e.clientX, e.clientY)
      this.onZoomChange?.(this.zoomPanManager.zoomPercent)
    } else {
      // Plain wheel: pan the canvas
      this.zoomPanManager.panBy(-e.deltaX, -e.deltaY)
    }
  }

  _handleDelete(e) {
    if (this.selectedConnectionId) {
      e.preventDefault()
      this.onBeforeChange?.()
      this.deleteConnection(this.selectedConnectionId)
      this.selectedConnectionId = null
      this.onchange?.()
      this.emitStructureChanged()
      return
    }

    if (this.selectedElements.length > 0) {
      e.preventDefault()
      this.onBeforeChange?.()
      this._deleteSelectedElements()
      this.onchange?.()
      this.emitStructureChanged()
    }
  }

  // ===================
  // Connection Drawing
  // ===================

  _startConnectionDraw(elementGroup, handleElement) {
    const elementId = handleElement.dataset.parentElementId || elementGroup.dataset.elementId
    const element = this.elements.find(el => el.id === elementId)
    if (!element) return

    this.isDrawingConnection = true
    this.connectionStartElement = element
    this.connectionStartHandle = handleElement.dataset.handlePosition

    const startPos = this._getHandlePosition(element, this.connectionStartHandle)

    this.connectionLine = createLine(startPos.x, startPos.y, startPos.x, startPos.y, {
      stroke: "#3b82f6",
      "stroke-width": "2",
      "stroke-dasharray": "5,5"
    })
    this.connectionLayer.appendChild(this.connectionLine)
  }

  _finishConnectionDraw(point) {
    const targetElement = this._findElementAtPoint(point.x, point.y)

    if (targetElement && targetElement.id !== this.connectionStartElement.id) {
      this.onBeforeChange?.()

      const toPosition = this._getClosestHandlePosition(targetElement, point.x, point.y)
      const connection = this.createConnection(
        this.connectionStartElement,
        targetElement,
        this.connectionStartHandle,
        toPosition
      )

      if (connection) {
        // createConnection auto-derives the decision's branches (Yes/No/…).
        this.updateConnections()
      }

      this.onchange?.()
      this.emitStructureChanged()
    }

    this._endConnectionDraw()
  }

  _endConnectionDraw() {
    this.isDrawingConnection = false
    this.connectionStartElement = null
    this.connectionStartHandle = null

    if (this.connectionLine) {
      this.connectionLine.remove()
      this.connectionLine = null
    }

    this._hideConnectionHandles()
  }

  // ===================
  // Connection Endpoint Dragging
  // ===================

  _startConnectionEndpointDrag(endpointElement) {
    const connectionId = endpointElement.dataset.connectionId
    const endpointType = endpointElement.dataset.connectionEndpoint

    const connection = this.connections.find(c => c.id === connectionId)
    if (!connection) return

    this.onBeforeChange?.()

    this.isDraggingConnectionEndpoint = true
    this.draggingConnection = connection
    this.draggingEndpointType = endpointType

    const isFrom = endpointType === "from"
    const fixedId = isFrom ? connection.to : connection.from
    const fixedPos = isFrom ? (connection.toPort || connection.toPosition) : (connection.fromPort || connection.fromPosition)
    const dragId = isFrom ? connection.from : connection.to
    const dragPos = isFrom ? (connection.fromPort || connection.fromPosition) : (connection.toPort || connection.toPosition)

    const fixedElement = this.elements.find(el => el.id === fixedId)
    const dragElement = this.elements.find(el => el.id === dragId)

    if (!fixedElement || !dragElement) return

    const fixedPoint = this._getHandlePosition(fixedElement, fixedPos)
    const dragPoint = this._getHandlePosition(dragElement, dragPos)

    this.connectionDragLine = createLine(
      isFrom ? dragPoint.x : fixedPoint.x,
      isFrom ? dragPoint.y : fixedPoint.y,
      isFrom ? fixedPoint.x : dragPoint.x,
      isFrom ? fixedPoint.y : dragPoint.y,
      {
        stroke: "#3b82f6",
        "stroke-width": "2",
        "stroke-dasharray": "5,5"
      }
    )
    this.handleLayer.appendChild(this.connectionDragLine)

    const group = this.connectionLayer.querySelector(`[data-connection-id="${connectionId}"]`)
    if (group) group.style.opacity = "0.3"

    this.svg.style.cursor = "crosshair"
  }

  _updateConnectionEndpointDrag(point) {
    if (!this.connectionDragLine) return

    const attr = this.draggingEndpointType === "from" ? "x1" : "x2"
    const attrY = this.draggingEndpointType === "from" ? "y1" : "y2"

    this.connectionDragLine.setAttribute(attr, point.x)
    this.connectionDragLine.setAttribute(attrY, point.y)
  }

  _endConnectionEndpointDrag(point) {
    const targetElement = this._findElementAtPoint(point.x, point.y)
    const { draggingConnection: connection, draggingEndpointType: endpointType } = this

    this._clearElementHighlight()

    if (connection) {
      const group = this.connectionLayer.querySelector(`[data-connection-id="${connection.id}"]`)
      if (group) group.style.opacity = "1"
    }

    if (targetElement && connection) {
      const otherId = endpointType === "from" ? connection.to : connection.from

      if (targetElement.id !== otherId) {
        const newFrom = endpointType === "from" ? targetElement.id : otherId
        const newTo = endpointType === "from" ? otherId : targetElement.id
        const duplicate = this.connections.some(c =>
          c.id !== connection.id && c.from === newFrom && c.to === newTo
        )

        const fromEl = endpointType === "from"
          ? targetElement
          : this.elements.find(el => el.id === otherId)
        const toEl = endpointType === "from"
          ? this.elements.find(el => el.id === otherId)
          : targetElement

        if (this._rejectsDirectedEdge(fromEl, toEl)) {
          // leave the connection endpoints unchanged
        } else if (!duplicate) {
          const newPos = this._getClosestHandlePosition(targetElement, point.x, point.y)
          const previousFrom = connection.from

          if (endpointType === "from") {
            connection.from = targetElement.id
            const isPort = typeof newPos === 'string' && newPos.startsWith("port_")
            connection.fromPort = isPort ? newPos : null
            connection.fromPosition = isPort ? null : newPos
          } else {
            connection.to = targetElement.id
            const isPort = typeof newPos === 'string' && newPos.startsWith("port_")
            connection.toPort = isPort ? newPos : null
            connection.toPosition = isPort ? null : newPos
          }

          // Re-derive branches for any decision whose outgoing edges changed,
          // so retargeting keeps branch ports/labels contiguous.
          for (const id of new Set([connection.from, previousFrom])) {
            const src = this.elements.find(el => el.id === id)
            if (!src || src.type !== "decision") continue
            // Only the decision the edge now points out of gained a new branch
            // (connection.to); the old source merely lost one.
            this._syncDecisionBranches(src, src.id === connection.from ? connection.to : null)
          }

          this._alignConnectionElements(connection)
          this.updateConnections()
          this.selectConnection(connection.id)
          this.onchange?.()
          this.emitStructureChanged()
        }
      }
    }

    this.connectionDragLine?.remove()
    this.connectionDragLine = null
    this.isDraggingConnectionEndpoint = false
    this.draggingConnection = null
    this.draggingEndpointType = null
    this.svg.style.cursor = "default"
  }

  _highlightElementAtPoint(x, y) {
    const element = this._findElementAtPoint(x, y)
    this._clearElementHighlight()

    if (element && this.draggingConnection) {
      const otherId = this.draggingEndpointType === "from"
        ? this.draggingConnection.to
        : this.draggingConnection.from

      if (element.id !== otherId) {
        this.highlightedElement = element
        const group = this.elementLayer.querySelector(`[data-element-id="${element.id}"]`)
        group?.classList.add("connection-target-highlight")
      }
    }
  }

  _clearElementHighlight() {
    if (this.highlightedElement) {
      const group = this.elementLayer.querySelector(`[data-element-id="${this.highlightedElement.id}"]`)
      group?.classList.remove("connection-target-highlight")
      this.highlightedElement = null
    }
  }

  _findElementGroupByHandle(handleElement) {
    const parentId = handleElement.dataset.parentElementId
    return parentId ? this.elementLayer.querySelector(`[data-element-id="${parentId}"]`) : null
  }
}

// Apply mixins
Object.assign(FlowchartCanvas.prototype, ElementRendererMixin)
Object.assign(FlowchartCanvas.prototype, ConnectionManagerMixin)
Object.assign(FlowchartCanvas.prototype, SelectionManagerMixin)
Object.assign(FlowchartCanvas.prototype, DragHandlerMixin)
Object.assign(FlowchartCanvas.prototype, ResizeHandlerMixin)
Object.assign(FlowchartCanvas.prototype, ElementManagementMixin)
Object.assign(FlowchartCanvas.prototype, ExternalDropMixin)
Object.assign(FlowchartCanvas.prototype, SerializationMixin)
Object.assign(FlowchartCanvas.prototype, TraceOverlayMixin)

const _mixinDestroy = FlowchartCanvas.prototype.destroy
FlowchartCanvas.prototype.destroy = function destroy() {
  this._endNudgeBurst()
  this._unbindDocumentDragListeners()
  this._hideEdgeInsertButton()
  this.zoomPanManager.destroy()
  this.isDragging = false
  this.draggedElement = null
  this.dropTargetElement = null
  this._pendingDrag = null
  if (typeof _mixinDestroy === "function") _mixinDestroy.call(this)
}

export default FlowchartCanvas
