/**
 * ResizeHandler - Handles element resize operations for the flowchart canvas.
 * Provides corner-based resize handles and dimension constraints.
 */

import { snapToGrid, createGroup, createRect } from "utils"
import {
  GRID_SIZE,
  MIN_ELEMENT_WIDTH,
  MIN_ELEMENT_HEIGHT,
  MAX_ELEMENT_WIDTH,
  MAX_ELEMENT_HEIGHT
} from "flowchart/constants"

// Resize handle configuration
const RESIZE_HANDLE_SIZE = 6
const RESIZE_HANDLE_STYLE = {
  fill: "#ffffff",
  stroke: "#3b82f6",
  strokeWidth: 1.5
}

// Corner definitions with cursor styles and resize direction multipliers
const CORNERS = {
  "top-left":     { cursor: "nw-resize", dx: -1, dy: -1 },
  "top-right":    { cursor: "ne-resize", dx:  1, dy: -1 },
  "bottom-left":  { cursor: "sw-resize", dx: -1, dy:  1 },
  "bottom-right": { cursor: "se-resize", dx:  1, dy:  1 }
}

/**
 * ResizeHandlerMixin - Mixin for element resize functionality.
 * Applied to FlowchartCanvas prototype.
 */
export const ResizeHandlerMixin = {
  /**
   * Show resize handles at the four corners of an element.
   * Only shown for single-element selection.
   * @param {Object} element - The selected element
   */
  showResizeHandles(element) {
    this.hideResizeHandles()

    const hw = element.width / 2
    const hh = element.height / 2

    const cornerPositions = {
      "top-left":     { x: element.x - hw, y: element.y - hh },
      "top-right":    { x: element.x + hw, y: element.y - hh },
      "bottom-left":  { x: element.x - hw, y: element.y + hh },
      "bottom-right": { x: element.x + hw, y: element.y + hh }
    }

    Object.entries(cornerPositions).forEach(([corner, pos]) => {
      const config = CORNERS[corner]
      const half = RESIZE_HANDLE_SIZE / 2

      const group = createGroup({
        "data-resize-handle": corner,
        "data-resize-element-id": element.id
      })
      group.style.cursor = config.cursor

      // Invisible hit area for easier grabbing
      group.appendChild(createRect(
        pos.x - half - 4, pos.y - half - 4,
        RESIZE_HANDLE_SIZE + 8, RESIZE_HANDLE_SIZE + 8,
        { fill: "transparent" }
      ))

      // Visible handle square
      const handle = createRect(
        pos.x - half, pos.y - half,
        RESIZE_HANDLE_SIZE, RESIZE_HANDLE_SIZE,
        {
          fill: RESIZE_HANDLE_STYLE.fill,
          stroke: RESIZE_HANDLE_STYLE.stroke,
          "stroke-width": RESIZE_HANDLE_STYLE.strokeWidth,
          class: "resize-handle"
        }
      )
      group.appendChild(handle)

      // Hover effect
      group.addEventListener("mouseenter", () => {
        handle.setAttribute("stroke-width", "2")
        handle.setAttribute("stroke", "#2563eb")
      })
      group.addEventListener("mouseleave", () => {
        if (!this.isResizing) {
          handle.setAttribute("stroke-width", RESIZE_HANDLE_STYLE.strokeWidth)
          handle.setAttribute("stroke", RESIZE_HANDLE_STYLE.stroke)
        }
      })

      this.handleLayer.appendChild(group)
    })
  },

  /**
   * Remove all resize handle SVG elements.
   */
  hideResizeHandles() {
    this.handleLayer.querySelectorAll("[data-resize-handle]")
      .forEach(h => h.remove())
  },

  /**
   * Start a resize operation from a specific corner.
   * @param {Object} element - The element being resized
   * @param {string} corner - The corner being dragged (e.g. "bottom-right")
   * @param {MouseEvent} e - The initiating mouse event
   */
  _handleResizeStart(element, corner, e) {
    if (this.canMutate?.() === false) return
    e.stopPropagation()
    e.preventDefault()

    this.onBeforeChange?.()

    const point = this._getSVGPoint(e)

    this.isResizing = true
    this._resizeState = {
      element,
      corner,
      startX: point.x,
      startY: point.y,
      startWidth: element.width,
      startHeight: element.height,
      startCenterX: element.x,
      startCenterY: element.y
    }

    this.svg.style.cursor = CORNERS[corner].cursor
  },

  /**
   * Handle mouse movement during resize.
   * Calculates new dimensions based on which corner is being dragged.
   * @param {MouseEvent} e - The mouse event
   */
  _handleResizeMove(e) {
    if (!this.isResizing || !this._resizeState) return

    const point = this._getSVGPoint(e)
    const state = this._resizeState
    const config = CORNERS[state.corner]

    // Calculate mouse delta from start
    const deltaX = point.x - state.startX
    const deltaY = point.y - state.startY

    // Apply deltas based on corner direction multipliers
    // For dx=1 (right side), positive deltaX increases width
    // For dx=-1 (left side), negative deltaX increases width
    let newWidth = state.startWidth + (deltaX * config.dx)
    let newHeight = state.startHeight + (deltaY * config.dy)

    // Snap dimensions to grid
    newWidth = snapToGrid(newWidth, GRID_SIZE)
    newHeight = snapToGrid(newHeight, GRID_SIZE)

    // Enforce min/max constraints
    newWidth = Math.max(MIN_ELEMENT_WIDTH, Math.min(MAX_ELEMENT_WIDTH, newWidth))
    newHeight = Math.max(MIN_ELEMENT_HEIGHT, Math.min(MAX_ELEMENT_HEIGHT, newHeight))

    // Calculate new center position to keep the opposite corner fixed.
    // When resizing from a corner, the opposite corner should stay in place.
    // The center shifts by half the dimension change, in the direction of the dragged corner.
    const widthDelta = newWidth - state.startWidth
    const heightDelta = newHeight - state.startHeight

    const element = state.element
    element.width = newWidth
    element.height = newHeight
    element.x = state.startCenterX + (widthDelta / 2) * config.dx
    element.y = state.startCenterY + (heightDelta / 2) * config.dy

    // Update the element's position and shape (dimension change triggers shape rebuild)
    this.updateElementPosition(element)

    // Update resize handles to match new position
    this.showResizeHandles(element)

    // Update connections to follow the resized element
    this.updateConnections()

    // Update connection handles if visible
    if (this.selectedElements.length === 1) {
      this.showConnectionHandles(element)
    }
  },

  /**
   * Finalize the resize operation.
   * Snaps final position to grid, updates connections, and fires change callback.
   */
  _handleResizeEnd() {
    if (!this.isResizing || !this._resizeState) return

    const element = this._resizeState.element

    // Snap center position to grid
    element.x = snapToGrid(element.x, GRID_SIZE)
    element.y = snapToGrid(element.y, GRID_SIZE)

    // Final update with snapped position
    this.updateElementPosition(element)
    this.updateConnections()

    // Update handles
    if (this.selectedElements.length === 1) {
      this.showConnectionHandles(element)
      this.showResizeHandles(element)
    }

    this.isResizing = false
    this._resizeState = null
    this.svg.style.cursor = "default"

    this.onchange?.()
  },

}

export default ResizeHandlerMixin
