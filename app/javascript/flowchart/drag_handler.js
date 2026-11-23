/**
 * Drag and drop handling mixin for the flowchart canvas.
 * Handles element dragging, sub-tree movement, drop-to-reconnect, and
 * alignment guides.
 */

import { snapToGrid, generateId, createLine } from "utils"
import {
  GRID_SIZE,
  DEFAULT_ELEMENT_SPACING,
  GUIDE_EXTENT,
  ALIGNMENT_THRESHOLD
} from "flowchart/constants"

// Guide line styling
const GUIDE_STYLE = {
  stroke: "#3b82f6",
  strokeWidth: 1,
  strokeDasharray: "4,4"
}

export const DragHandlerMixin = {
  /**
   * Start dragging an element.
   */
  _startDrag(element, e) {
    if (this.canMutate?.() === false) return
    this.onBeforeChange?.()

    // Hide tooltip when starting drag
    this._hideElementTooltip?.()

    this.isDragging = true
    this.draggedElement = element
    this.dragStartPosition = { x: element.x, y: element.y }
    this._bindDocumentDragListeners?.()

    // Visual drag feedback
    const group = this.elementLayer.querySelector(`[data-element-id="${element.id}"]`)
    if (group) group.style.opacity = "0.7"

    const point = this._getSVGPoint(e)
    this.dragOffset = {
      x: point.x - element.x,
      y: point.y - element.y
    }

    // Multi-select drag, or a single element carrying its sub-tree
    if (this.selectedElements.length > 1 && this._isElementSelected(element)) {
      this.draggedElements = this.selectedElements.map(el => ({
        element: el,
        startX: el.x,
        startY: el.y
      }))
      this.draggedSubTree = null
    } else {
      this.draggedElements = null
      this.draggedSubTree = this._getSubTreeElements(element.id)
      this._selectElement(element)
    }
  },

  /**
   * End element dragging and snap to grid.
   */
  _endDrag() {
    if (!this.draggedElement) return

    if (this.draggedElements?.length > 1) {
      this._finishMultiElementDrag()
    } else {
      this._finishSingleElementDrag()
    }

    this._cleanupDragState()
  },

  /**
   * Finish dragging multiple selected elements.
   */
  _finishMultiElementDrag() {
    const finalX = snapToGrid(this.draggedElement.x, GRID_SIZE)
    const finalY = snapToGrid(this.draggedElement.y, GRID_SIZE)
    const deltaX = finalX - this.dragStartPosition.x
    const deltaY = finalY - this.dragStartPosition.y

    // Apply ONE grid-snapped delta uniformly. Re-snapping each element's
    // absolute position (snapToGrid(startX + deltaX)) drifts the group's
    // relative layout: loaded positions are rarely all congruent mod
    // GRID_SIZE, so each element rounds to a different residue and the
    // figure distorts a few px per drag — cumulative over repeated moves.
    // The anchor element's delta is already grid-aligned (finalX/finalY are
    // snapped), so applying it as-is keeps the group rigid.
    this.draggedElements.forEach(({ element, startX, startY }) => {
      element.x = startX + deltaX
      element.y = startY + deltaY
      this.updateElementPosition(element)
    })

    // Straighten every connection the moved group touches
    this.alignAllElements()
    this.onchange?.()
  },

  /**
   * Finish dragging a single element (with its sub-tree). Dropped onto a box
   * it is placed next to that box and connected; otherwise it snaps into line
   * with its parent connection. Children are realigned behind it.
   */
  _finishSingleElementDrag() {
    // Clicks with a few pixels of jitter must not move or reconnect.
    const movedX = Math.abs(this.draggedElement.x - this.dragStartPosition.x)
    const movedY = Math.abs(this.draggedElement.y - this.dragStartPosition.y)
    const actuallyMoved = movedX >= 8 || movedY >= 8

    if (!actuallyMoved) {
      this.draggedElement.x = this.dragStartPosition.x
      this.draggedElement.y = this.dragStartPosition.y
      this.updateElementPosition(this.draggedElement)
      this.draggedSubTree?.forEach(({ id, originalX, originalY }) => {
        const child = this.elements.find(el => el.id === id)
        if (!child) return
        child.x = originalX
        child.y = originalY
        this.updateElementPosition(child)
      })
      this.updateConnections()
      return
    }

    const { x: finalX, y: finalY } = this.dropTargetElement
      ? this._calculateDropPosition(this.dropTargetElement, this.draggedElement, this.draggedElement)
      : this._parentAlignedPosition(this.draggedElement)

    this.draggedElement.x = finalX
    this.draggedElement.y = finalY
    this.updateElementPosition(this.draggedElement)
    this._updateSubTreePositions(finalX - this.dragStartPosition.x, finalY - this.dragStartPosition.y)

    if (this.dropTargetElement) {
      const dropTarget = this.dropTargetElement
      this._reconnectElement(this.draggedElement, dropTarget)
      this._clearDropTargetHighlight()
      // Dropping onto a decision adds an outgoing edge — turn it into a branch,
      // same as drawing a connection.
      if (dropTarget.type === "decision") this._syncDecisionBranches(dropTarget, this.draggedElement.id)
      this.alignElementWithParent(this.draggedElement)
    }
    this.alignChildElements(this.draggedElement)
    this.updateConnections()

    this.onchange?.()
  },

  /**
   * Grid-snapped release point, pulled into line with the incoming connection:
   * same X as the parent for a vertical edge, same Y for a horizontal one.
   */
  _parentAlignedPosition(element) {
    const x = snapToGrid(element.x, GRID_SIZE)
    const y = snapToGrid(element.y, GRID_SIZE)
    const parentConn = this.connections.find(c => c.to === element.id)
    const parentEl = parentConn && this.elements.find(el => el.id === parentConn.from)
    if (!parentEl) return { x, y }

    const orientation = this._connectionOrientation(parentConn, parentEl, element)
    if (orientation === "vertical") return { x: parentEl.x, y }
    if (orientation === "horizontal") return { x, y: parentEl.y }
    return { x, y }
  },

  /**
   * Move the dragged sub-tree by the anchor's final (grid-aligned) delta.
   * Re-snapping each child's absolute position would drift the sub-tree
   * relative to the dragged element.
   */
  _updateSubTreePositions(deltaX, deltaY) {
    this.draggedSubTree?.forEach(({ id, originalX, originalY }) => {
      const child = this.elements.find(el => el.id === id)
      if (!child) return
      child.x = originalX + deltaX
      child.y = originalY + deltaY
      this.updateElementPosition(child)
    })
  },

  /**
   * Move the dragged sub-tree visually while the anchor follows the pointer.
   */
  _moveSubTreeVisually(newX, newY) {
    if (!this.draggedSubTree || !this.dragStartPosition) return
    this._updateSubTreePositions(newX - this.dragStartPosition.x, newY - this.dragStartPosition.y)
  },

  /**
   * Position for an element dropped onto `target`: one spacing away on the
   * side of the drop, exactly in line with the target on the other axis.
   */
  _calculateDropPosition(target, dropped, dropPoint) {
    const dx = dropPoint.x - target.x
    const dy = dropPoint.y - target.y

    if (Math.abs(dy) > Math.abs(dx)) {
      const offset = target.height / 2 + DEFAULT_ELEMENT_SPACING + dropped.height / 2
      return { x: target.x, y: snapToGrid(dy > 0 ? target.y + offset : target.y - offset, GRID_SIZE) }
    }

    const offset = target.width / 2 + DEFAULT_ELEMENT_SPACING + dropped.width / 2
    return { x: snapToGrid(dx > 0 ? target.x + offset : target.x - offset, GRID_SIZE), y: target.y }
  },

  /**
   * Furthest extent of an element and its sub-tree from the element's centre
   * in `direction`. Used to size the gap opened when inserting a dragged group.
   */
  _getDraggedGroupExtent(element, direction) {
    const vertical = direction === "bottom" || direction === "top"
    const sign = direction === "bottom" || direction === "right" ? 1 : -1
    const axis = vertical ? "y" : "x"
    const half = vertical ? "height" : "width"
    let extent = element[half] / 2

    for (const { id } of this._getSubTreeElements(element.id)) {
      const child = this.elements.find(el => el.id === id)
      if (!child) continue
      const edge = sign * (child[axis] - element[axis]) + child[half] / 2
      if (edge > extent) extent = edge
    }

    return extent
  },

  /**
   * Grid-aligned distance that opens room for the dragged group between
   * `neighbor` and the drop point on `side`.
   */
  _insertGap(draggedElement, neighbor, side) {
    const vertical = side === "top" || side === "bottom"
    const raw = this._getDraggedGroupExtent(draggedElement, side) + DEFAULT_ELEMENT_SPACING +
      (vertical ? neighbor.height : neighbor.width) / 2
    const dist = Math.round(raw / GRID_SIZE) * GRID_SIZE
    return { top: [0, -dist], bottom: [0, dist], left: [-dist, 0], right: [dist, 0] }[side]
  },

  /**
   * Clean up drag state after drag ends.
   */
  _cleanupDragState() {
    this._hideAlignmentGuides()
    this._hideDropSideIndicator()

    // Restore drag opacity
    if (this.draggedElement) {
      const group = this.elementLayer.querySelector(`[data-element-id="${this.draggedElement.id}"]`)
      if (group) group.style.opacity = ""
    }

    if (this.selectedElements.length > 0) {
      this.showConnectionHandles(this.selectedElements)
    }

    this._unbindDocumentDragListeners?.()
    this.isDragging = false
    this.draggedElement = null
    this.dragStartPosition = null
    this.draggedSubTree = null
    this.draggedElements = null
    this.dropTargetElement = null
    this.dragOffset = { x: 0, y: 0 }
  },

  /**
   * Escape / destroy: put every moved element back where the drag started
   * and drop document listeners without persisting (no onchange).
   */
  _cancelElementDrag() {
    if (!this.isDragging) return

    if (this.draggedElements?.length) {
      this.draggedElements.forEach(({ element, startX, startY }) => {
        element.x = startX
        element.y = startY
        this.updateElementPosition?.(element)
      })
    } else if (this.draggedElement && this.dragStartPosition) {
      this.draggedElement.x = this.dragStartPosition.x
      this.draggedElement.y = this.dragStartPosition.y
      this.updateElementPosition?.(this.draggedElement)
      this.draggedSubTree?.forEach(({ id, originalX, originalY }) => {
        const child = this.elements.find(el => el.id === id)
        if (!child) return
        child.x = originalX
        child.y = originalY
        this.updateElementPosition?.(child)
      })
    }

    this._updateConnectionsVisually?.()
    this._cleanupDragState()
  },

  /**
   * Move an element visually during drag.
   */
  _moveElementVisually(element, x, y) {
    element.x = x
    element.y = y
    this.updateElementPosition(element)
  },

  /**
   * Get all child elements connected from an element (recursively).
   */
  _getSubTreeElements(elementId, visited = new Set(), rootId = null) {
    if (rootId === null) rootId = elementId
    if (visited.has(elementId)) return []

    visited.add(elementId)
    const children = []

    for (const conn of this.connections) {
      if (conn.from !== elementId) continue
      if (conn.to === rootId) continue // Prevent cycles back to root

      const child = this.elements.find(el => el.id === conn.to)
      if (child && !visited.has(conn.to)) {
        children.push({
          id: conn.to,
          originalX: child.x,
          originalY: child.y
        })
        children.push(...this._getSubTreeElements(conn.to, visited, rootId))
      }
    }

    return children
  },

  // ===================
  // Drop Target Handling
  // ===================

  /**
   * Highlight potential drop target during drag.
   * Shows both element highlight and drop side indicator for clear visual feedback.
   */
  _highlightDropTarget(x, y) {
    const target = this._findDropTargetElement(x, y)

    // Clear previous highlight if target changed
    if (this.dropTargetElement && target?.id !== this.dropTargetElement.id) {
      this._clearDropTargetHighlight()
      this._hideDropSideIndicator()
    }

    // Apply new highlight
    if (target) {
      if (target.id !== this.dropTargetElement?.id) {
        this.dropTargetElement = target
        this._setDropHighlight(target, true)
      }
      // Show drop side indicator during internal drag too
      const dropSide = this.getDropSide(target, x, y)
      this._showDropSideIndicator(target, dropSide)
    } else {
      this.dropTargetElement = null
      this._hideDropSideIndicator()
    }
  },

  /**
   * Clear drop target highlight and side indicator.
   */
  _clearDropTargetHighlight() {
    if (this.dropTargetElement) {
      this._setDropHighlight(this.dropTargetElement, false)
      this.dropTargetElement = null
    }
    this._hideDropSideIndicator()
  },

  /**
   * Set drop highlight class on element.
   */
  _setDropHighlight(element, highlighted) {
    const group = this.elementLayer.querySelector(`[data-element-id="${element.id}"]`)
    group?.classList.toggle("drop-target-highlight", highlighted)
  },

  /**
   * Find valid drop target at position (excludes dragged element and its sub-tree).
   * Uses a two-tier strategy for better sensitivity:
   *   1. Direct hit with 30px expanded margin
   *   2. Nearest element by connection port proximity within 80px
   */
  _findDropTargetElement(x, y) {
    const excludeIds = new Set([this.draggedElement?.id])
    this.draggedSubTree?.forEach(child => excludeIds.add(child.id))
    const margin = 30

    // Tier 1: Direct hit with expanded margin (reverse order for z-index)
    for (let i = this.elements.length - 1; i >= 0; i--) {
      const el = this.elements[i]
      if (excludeIds.has(el.id)) continue

      const hw = el.width / 2 + margin
      const hh = el.height / 2 + margin

      if (x >= el.x - hw && x <= el.x + hw && y >= el.y - hh && y <= el.y + hh) {
        return el
      }
    }

    // Tier 2: Nearest element by connection port proximity
    const maxDistance = 80
    let nearest = null
    let minDist = maxDistance

    for (const el of this.elements) {
      if (excludeIds.has(el.id)) continue

      const hw = el.width / 2
      const hh = el.height / 2

      // Check distance to connection ports (edge midpoints)
      const ports = [
        { x: el.x, y: el.y - hh },  // top
        { x: el.x, y: el.y + hh },  // bottom
        { x: el.x - hw, y: el.y },  // left
        { x: el.x + hw, y: el.y }   // right
      ]

      for (const port of ports) {
        const dist = Math.sqrt((x - port.x) ** 2 + (y - port.y) ** 2)
        if (dist < minDist) {
          minDist = dist
          nearest = el
        }
      }
    }

    return nearest
  },

  // ===================
  // Element Reconnection
  // ===================

  /**
   * Get parent connection for an element.
   */
  _getParentConnection(elementId) {
    return this.connections.find(c => c.to === elementId)
  },

  /**
   * Drop the dragged element's previous incoming edge and a same-direction
   * newParent→dragged duplicate. The reverse dragged→newParent edge is
   * kept — A→B and B→A may both exist.
   */
  _dropPreviousParentAndSameDirection(draggedElement, newParent) {
    const oldConnection = this._getParentConnection(draggedElement.id)
    if (oldConnection) {
      const index = this.connections.findIndex(c => c.id === oldConnection.id)
      if (index !== -1) this.connections.splice(index, 1)
    }

    const existingDirect = this.connections.find(c =>
      c.from === newParent.id && c.to === draggedElement.id
    )
    if (existingDirect) {
      const idx = this.connections.findIndex(c => c.id === existingDirect.id)
      if (idx !== -1) this.connections.splice(idx, 1)
    }
  },

  /**
   * Reconnect dragged element to new parent.
   * Handles insertion between connected elements: if the drop target already
   * has a child on the drop side, the dragged element is inserted between them.
   */
  _reconnectElement(draggedElement, newParent) {
    // Determine the drop side and check for existing connections on that side
    const { fromPosition, toPosition } = this._calculateBestConnectionPositions(newParent, draggedElement)
    const dropSide = fromPosition  // e.g. "bottom" means we're connecting from parent's bottom

    // Check 1: Outgoing connection on the drop side (inserting between parent and its child)
    const existingChildConn = this.connections.find(c =>
      c.from === newParent.id &&
      (c.fromPosition || "bottom") === dropSide &&
      c.to !== draggedElement.id
    )

    if (existingChildConn) {
      const existingChild = this.elements.find(el => el.id === existingChildConn.to)

      if (existingChild) {
        if (this._rejectsDirectedEdge?.(newParent, draggedElement)) return
        if (this._rejectsDirectedEdge?.(draggedElement, existingChild)) return

        this._dropPreviousParentAndSameDirection(draggedElement, newParent)
        const connIdx = this.connections.findIndex(c => c.id === existingChildConn.id)
        if (connIdx !== -1) this.connections.splice(connIdx, 1)

        // Push the existing child (and its sub-tree) away to make room
        this.shiftElementAndSubTree(existingChild, ...this._insertGap(draggedElement, existingChild, dropSide))

        // Create insertion chain: parent → dragged → existing child
        const childFromPos = existingChildConn.fromPosition || "bottom"
        const childToPos = existingChildConn.toPosition || "top"
        const upstream = {
          id: generateId("conn"),
          from: newParent.id,
          to: draggedElement.id,
          fromPort: existingChildConn.fromPort || null,
          fromPosition: existingChildConn.fromPort ? null : fromPosition,
          toPosition
        }
        if (existingChildConn.label) upstream.label = existingChildConn.label
        if (existingChildConn.matchValue != null && existingChildConn.matchValue !== "") {
          upstream.matchValue = existingChildConn.matchValue
        }
        if (existingChildConn.properties) upstream.properties = existingChildConn.properties

        this.connections.push(upstream)

        this.connections.push({
          id: generateId("conn"),
          from: draggedElement.id,
          to: existingChild.id,
          fromPosition: childFromPos,
          toPosition: childToPos
        })

        if (newParent.type === "decision") this._syncDecisionBranches?.(newParent, draggedElement.id)

        this.updateConnections()
        return
      }
    }

    // Check 2: Incoming connection on the drop side (inserting between parent's parent and parent)
    // e.g. dropping above a target that has a parent connected to its top
    const incomingSide = dropSide  // the side of newParent where the drop occurs
    const existingIncomingConn = this.connections.find(c =>
      c.to === newParent.id &&
      (c.toPosition || "top") === incomingSide &&
      c.from !== draggedElement.id
    )

    if (existingIncomingConn) {
      const grandParent = this.elements.find(el => el.id === existingIncomingConn.from)

      if (grandParent) {
        if (this._rejectsDirectedEdge?.(grandParent, draggedElement)) return
        if (this._rejectsDirectedEdge?.(draggedElement, newParent)) return

        this._dropPreviousParentAndSameDirection(draggedElement, newParent)

        const connIdx = this.connections.findIndex(c => c.id === existingIncomingConn.id)
        if (connIdx !== -1) this.connections.splice(connIdx, 1)

        // Push the parent (and its sub-tree) away from the grandparent to make room
        const awaySide = this._getOppositePosition(incomingSide)
        this.shiftElementAndSubTree(newParent, ...this._insertGap(draggedElement, newParent, awaySide))

        // Create insertion chain: grandParent → dragged → parent
        // Maintain the same connection direction as the original
        const origFromPos = existingIncomingConn.fromPosition || "bottom"
        const origToPos = existingIncomingConn.toPosition || "top"

        const upstream = {
          id: generateId("conn"),
          from: grandParent.id,
          to: draggedElement.id,
          fromPort: existingIncomingConn.fromPort || null,
          fromPosition: existingIncomingConn.fromPort ? null : origFromPos,
          toPosition: origToPos
        }
        if (existingIncomingConn.label) upstream.label = existingIncomingConn.label
        if (existingIncomingConn.matchValue != null && existingIncomingConn.matchValue !== "") {
          upstream.matchValue = existingIncomingConn.matchValue
        }
        if (existingIncomingConn.properties) upstream.properties = existingIncomingConn.properties
        this.connections.push(upstream)

        this.connections.push({
          id: generateId("conn"),
          from: draggedElement.id,
          to: newParent.id,
          fromPosition: origFromPos,
          toPosition: origToPos
        })

        if (grandParent.type === "decision") this._syncDecisionBranches?.(grandParent, draggedElement.id)

        this.updateConnections()
        return
      }
    }

    // No existing connection on the drop side — simple reconnection
    if (this._rejectsDirectedEdge?.(newParent, draggedElement)) return

    this._dropPreviousParentAndSameDirection(draggedElement, newParent)

    this.connections.push({
      id: generateId("conn"),
      from: newParent.id,
      to: draggedElement.id,
      fromPosition,
      toPosition
    })

    this.updateConnections()
  },

  /**
   * Calculate optimal connection positions between elements.
   */
  _calculateBestConnectionPositions(from, to) {
    const dx = to.x - from.x
    const dy = to.y - from.y

    // Prefer vertical connections
    if (Math.abs(dy) > Math.abs(dx)) {
      return dy > 0
        ? { fromPosition: "bottom", toPosition: "top" }
        : { fromPosition: "top", toPosition: "bottom" }
    }

    // Horizontal connections
    return dx > 0
      ? { fromPosition: "right", toPosition: "left" }
      : { fromPosition: "left", toPosition: "right" }
  },

  // ===================
  // Alignment Guides
  // ===================

  /**
   * Show alignment guides for nearby elements.
   */
  _showAlignmentGuides(element, x, y) {
    this._hideAlignmentGuides()

    for (const el of this.elements) {
      if (el.id === element.id) continue

      // Vertical alignment (X-axis)
      if (Math.abs(x - el.x) < ALIGNMENT_THRESHOLD) {
        this._addGuideLine(el.x, 0, el.x, GUIDE_EXTENT)
      }

      // Horizontal alignment (Y-axis)
      if (Math.abs(y - el.y) < ALIGNMENT_THRESHOLD) {
        this._addGuideLine(0, el.y, GUIDE_EXTENT, el.y)
      }
    }
  },

  /**
   * Add a guide line to the canvas.
   */
  _addGuideLine(x1, y1, x2, y2) {
    const line = createLine(x1, y1, x2, y2, {
      stroke: GUIDE_STYLE.stroke,
      "stroke-width": GUIDE_STYLE.strokeWidth,
      "stroke-dasharray": GUIDE_STYLE.strokeDasharray
    })
    this.guideLayer.appendChild(line)
  },

  /**
   * Hide all alignment guides.
   */
  _hideAlignmentGuides() {
    while (this.guideLayer.firstChild) {
      this.guideLayer.removeChild(this.guideLayer.firstChild)
    }
  },

  /**
   * Shift an element and its sub-tree by delta.
   * When delta values are grid-aligned multiples, all elements maintain
   * their relative positions without snap drift.
   */
  shiftElementAndSubTree(element, deltaX, deltaY) {
    const subTree = this._getSubTreeElements(element.id)

    // Snap the delta itself to grid to prevent cumulative drift
    const snappedDX = Math.round(deltaX / GRID_SIZE) * GRID_SIZE
    const snappedDY = Math.round(deltaY / GRID_SIZE) * GRID_SIZE

    // Shift main element
    element.x += snappedDX
    element.y += snappedDY
    this.updateElementPosition(element)

    // Shift sub-tree by the same grid-aligned delta
    for (const { id } of subTree) {
      const child = this.elements.find(el => el.id === id)
      if (child) {
        child.x += snappedDX
        child.y += snappedDY
        this.updateElementPosition(child)
      }
    }

    this.updateConnections()
  }
}

export default DragHandlerMixin
