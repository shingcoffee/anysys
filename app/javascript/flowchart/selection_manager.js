/**
 * SelectionManager - Handles selection operations for the flowchart canvas.
 * Manages single and multi-selection of elements and drag-to-select.
 */

import { createRect } from "utils"

// Selection rectangle styling
const SELECTION_STYLE = {
  fill: "rgba(99, 102, 241, 0.08)",
  stroke: "#6366f1",
  strokeWidth: 1,
  strokeDasharray: "4,2"
}

/**
 * SelectionManagerMixin - Mixin for selection functionality.
 * Applied to FlowchartCanvas prototype.
 */
export const SelectionManagerMixin = {
  /**
   * Ctrl/Cmd or Shift: add to (or toggle) the selection instead of replacing it.
   */
  _isAdditiveSelect(event) {
    return !!(event.ctrlKey || event.metaKey || event.shiftKey)
  },

  /**
   * Check if an element is selected.
   */
  _isElementSelected(element) {
    return this.selectedElements.some(el => el.id === element.id)
  },

  /**
   * Add an element to the current selection.
   */
  _addToSelection(element) {
    if (this._isElementSelected(element)) return

    const mutable = this.canMutate?.() !== false
    this.selectedElements.push(element)
    this.clearConnectionSelection()
    this._setElementSelected(element, true)
    if (mutable) this.showConnectionHandles(this.selectedElements)

    // Show resize handles only for single selection on mutable canvases
    if (mutable && this.selectedElements.length === 1) {
      this.showResizeHandles?.(element)
    } else {
      this.hideResizeHandles?.()
    }

    if (this.selectedElements.length === 1 && this.onElementSelected) {
      this.onElementSelected(element)
    }
  },

  /**
   * Remove an element from the selection.
   */
  _removeFromSelection(element) {
    const index = this.selectedElements.findIndex(el => el.id === element.id)
    if (index === -1) return

    const mutable = this.canMutate?.() !== false
    this.selectedElements.splice(index, 1)
    this._setElementSelected(element, false)

    if (this.selectedElements.length > 0) {
      if (mutable) this.showConnectionHandles(this.selectedElements)
      if (this.selectedElements.length === 1) {
        if (mutable) this.showResizeHandles?.(this.selectedElements[0])
        if (this.onElementSelected) this.onElementSelected(this.selectedElements[0])
      } else {
        this.hideResizeHandles?.()
      }
    } else {
      this._hideConnectionHandles()
      this.hideResizeHandles?.()
    }
  },

  /**
   * Toggle selection state of an element.
   */
  _toggleElementSelection(element) {
    if (this._isElementSelected(element)) {
      this._removeFromSelection(element)
    } else {
      this._addToSelection(element)
    }
    // Notify listeners that the selection changed. Ctrl/Cmd-click builds a
    // multi-selection through this path, but _addToSelection only fires
    // onElementSelected for a single element — so without this, the alignment
    // toolbar (and any other onSelectionChanged-driven UI) never appears for a
    // Ctrl-click selection, even though it does for a marquee selection.
    this.onSelectionChanged?.()
  },

  /**
   * Select a single element (clears existing selection).
   */
  _selectElement(element) {
    this._clearSelection()
    this._addToSelection(element)
  },

  /**
   * Clear all selections.
   */
  _clearSelection() {
    this.selectedElements.forEach(el => this._setElementSelected(el, false))
    this.selectedElements = []
    this._hideConnectionHandles()
    this._hideConnectionEndpointHandles()
    this.hideResizeHandles?.()
  },

  /**
   * Update visual selection state of an element.
   */
  _setElementSelected(element, selected) {
    const group = this.elementLayer.querySelector(`[data-element-id="${element.id}"]`)
    if (group) {
      group.classList.toggle("selected", selected)
    }
  },

  /**
   * Delete all selected elements.
   */
  _deleteSelectedElements() {
    const toDelete = [...this.selectedElements]
    toDelete.forEach(el => this._deleteElement(el))

    this.selectedElements = []
    this._hideConnectionHandles()
    this.hideResizeHandles?.()
  },

  /**
   * Select every element on the canvas (Ctrl/Cmd+A).
   */
  _selectAllElements() {
    this.elements.forEach(element => this._addToSelection(element))
    if (this.elements.length > 0) this.onSelectionChanged?.()
  },

  // ===================
  // Selection Rectangle
  // ===================

  /**
   * Start drag-to-select rectangle.
   */
  _startSelectionRect(e) {
    const point = this._getSVGPoint(e)

    this.isSelecting = true
    this.selectionStart = { x: point.x, y: point.y }

    this.selectionRect = createRect(point.x, point.y, 0, 0, {
      fill: SELECTION_STYLE.fill,
      stroke: SELECTION_STYLE.stroke,
      "stroke-width": SELECTION_STYLE.strokeWidth,
      "stroke-dasharray": SELECTION_STYLE.strokeDasharray
    })

    this.selectionLayer.appendChild(this.selectionRect)
    this.svg.style.cursor = "crosshair"
  },

  /**
   * Update selection rectangle during drag.
   */
  _updateSelectionRect(point) {
    if (!this.selectionRect || !this.selectionStart) return

    const rect = this._calculateSelectionRect(this.selectionStart, point)

    this.selectionRect.setAttribute("x", rect.x)
    this.selectionRect.setAttribute("y", rect.y)
    this.selectionRect.setAttribute("width", rect.width)
    this.selectionRect.setAttribute("height", rect.height)

    this._highlightElementsInRect(rect)
  },

  /**
   * End selection rectangle and select contained elements.
   */
  _endSelectionRect(e) {
    if (!this.selectionRect || !this.selectionStart) {
      this.isSelecting = false
      return
    }

    const point = this._getSVGPoint(e)
    const rect = this._calculateSelectionRect(this.selectionStart, point)
    const addToExisting = this._isAdditiveSelect(e)

    this._selectElementsInRect(rect, addToExisting)
    this._cleanupSelectionRect()
  },

  /**
   * Calculate rect dimensions from two points.
   */
  _calculateSelectionRect(start, end) {
    return {
      x: Math.min(start.x, end.x),
      y: Math.min(start.y, end.y),
      width: Math.abs(end.x - start.x),
      height: Math.abs(end.y - start.y)
    }
  },

  /**
   * Clean up selection rectangle state.
   */
  _cleanupSelectionRect() {
    this.selectionRect?.remove()
    this.selectionRect = null
    this.isSelecting = false
    this.selectionStart = null
    this.svg.style.cursor = "default"
    this._clearSelectionHighlights()
  },

  /**
   * Highlight elements that would be selected.
   */
  _highlightElementsInRect({ x, y, width, height }) {
    this.elements.forEach(element => {
      const group = this.elementLayer.querySelector(`[data-element-id="${element.id}"]`)
      if (!group) return

      const intersects = this._elementIntersectsRect(element, x, y, width, height)
      group.classList.toggle("selection-preview", intersects)
    })
  },

  /**
   * Clear selection preview highlights.
   */
  _clearSelectionHighlights() {
    this.elementLayer.querySelectorAll(".selection-preview")
      .forEach(el => el.classList.remove("selection-preview"))
  },

  /**
   * Select all elements within rectangle.
   */
  _selectElementsInRect({ x, y, width, height }, addToExisting) {
    if (!addToExisting) {
      this._clearSelection()
    }

    this.elements.forEach(element => {
      if (this._elementIntersectsRect(element, x, y, width, height)) {
        this._addToSelection(element)
      }
    })
  },

  /**
   * Check if element intersects with rectangle (AABB collision).
   */
  _elementIntersectsRect(element, rx, ry, rw, rh) {
    const hw = element.width / 2
    const hh = element.height / 2

    const elLeft = element.x - hw
    const elRight = element.x + hw
    const elTop = element.y - hh
    const elBottom = element.y + hh

    const rectRight = rx + rw
    const rectBottom = ry + rh

    return !(elRight < rx || elLeft > rectRight || elBottom < ry || elTop > rectBottom)
  }
}

/**
 * SelectionManager class - Standalone class for selection operations.
 * Can be used for composition pattern in the future.
 */
export class SelectionManager {
  constructor(canvas) {
    this.canvas = canvas
  }

  isElementSelected(element) {
    return SelectionManagerMixin._isElementSelected.call(this.canvas, element)
  }

  addToSelection(element) {
    SelectionManagerMixin._addToSelection.call(this.canvas, element)
  }

  removeFromSelection(element) {
    SelectionManagerMixin._removeFromSelection.call(this.canvas, element)
  }

  toggleElementSelection(element) {
    SelectionManagerMixin._toggleElementSelection.call(this.canvas, element)
  }

  clearSelection() {
    SelectionManagerMixin._clearSelection.call(this.canvas)
  }

  selectElement(element) {
    this.clearSelection()
    this.addToSelection(element)
  }
}

export default SelectionManager
