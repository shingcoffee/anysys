/**
 * ExternalDropMixin - Handles external drag-and-drop onto the flowchart canvas.
 * Covers drop target detection, highlighting, side indicators, and inserting a
 * new element next to a target or onto an existing connection (shifting the
 * downstream elements to make room).
 */

import { generateId, createLine, createGroup, createSvgElement, snapToGrid } from "utils"
import {
  GRID_SIZE,
  DEFAULT_ELEMENT_WIDTH,
  DEFAULT_ELEMENT_HEIGHT,
  DEFAULT_ELEMENT_SPACING,
  getDefaultPropertiesForType
} from "flowchart/constants"

export const ExternalDropMixin = {
  /**
   * Get the element at a specific canvas position.
   * @param {number} x - X coordinate on canvas
   * @param {number} y - Y coordinate on canvas
   * @param {number} [margin=0] - Additional margin around element bounds for hit detection
   * @returns {Object|null} The element at position, or null if none found
   */
  getElementAtPosition(x, y, margin = 0) {
    // Search in reverse order (top-most elements first for correct z-order)
    for (let i = this.elements.length - 1; i >= 0; i--) {
      const el = this.elements[i]
      const hw = el.width / 2 + margin
      const hh = el.height / 2 + margin
      if (x >= el.x - hw && x <= el.x + hw && y >= el.y - hh && y <= el.y + hh) {
        return el
      }
    }
    return null
  },

  /**
   * Find the nearest element within a maximum distance.
   * Uses connection-port-aware proximity: prefers elements whose connection
   * ports (top/bottom/left/right midpoints) are close to the cursor,
   * giving a more intuitive "magnetic" feel.
   */
  getNearestElement(x, y, maxDistance = 100) {
    let nearest = null
    let minDist = maxDistance

    for (const el of this.elements) {
      const hw = el.width / 2
      const hh = el.height / 2

      // Check distance to each connection port (midpoint of each edge)
      const ports = [
        { x: el.x, y: el.y - hh },     // top
        { x: el.x, y: el.y + hh },     // bottom
        { x: el.x - hw, y: el.y },     // left
        { x: el.x + hw, y: el.y }      // right
      ]

      // Use the minimum distance to any connection port
      let portDist = Infinity
      for (const port of ports) {
        const d = Math.sqrt((x - port.x) ** 2 + (y - port.y) ** 2)
        if (d < portDist) portDist = d
      }

      // Also check distance to bounding box edge (for when cursor is inside margin)
      const closestX = Math.max(el.x - hw, Math.min(x, el.x + hw))
      const closestY = Math.max(el.y - hh, Math.min(y, el.y + hh))
      const edgeDist = Math.sqrt((x - closestX) ** 2 + (y - closestY) ** 2)

      // Take the lesser of port and edge distance for best sensitivity
      const dist = Math.min(portDist, edgeDist)

      if (dist < minDist) {
        minDist = dist
        nearest = el
      }
    }

    return nearest
  },

  /**
   * Check if the canvas already has a Start element.
   * Used to enforce the single Start element constraint.
   * @returns {boolean} True if a Start element exists
   */
  hasStartElement() {
    return this.elements.some(el => el.type === "start")
  },

  /**
   * Highlight the drop target at a position during external drag operations.
   * Uses a generous two-tier detection strategy:
   *   1. Direct hit with expanded margin (50px) for easy targeting
   *   2. Nearest element by connection port proximity (100px) for magnetic feel
   * Shows visual feedback for which element will receive the drop and on which side.
   * @param {number} x - X coordinate on canvas
   * @param {number} y - Y coordinate on canvas
   */
  highlightDropTargetAt(x, y) {
    // Tier 1: Direct hit with generous margin around element bounds
    // Tier 2: Nearest element via port-aware proximity for magnetic snap
    const target = this.getElementAtPosition(x, y, 50) || this.getNearestElement(x, y, 100)

    if (this.externalDropTarget && target?.id !== this.externalDropTarget.id) {
      this.clearExternalDropHighlight()
    }

    if (target) {
      const dropSide = this.getDropSide(target, x, y)

      if (target.id !== this.externalDropTarget?.id) {
        this.externalDropTarget = target
        const group = this.elementLayer.querySelector(`[data-element-id="${target.id}"]`)
        if (group) {
          group.classList.add("drop-target-highlight")
          // Add proximity-based glow intensity via CSS variable
          const hw = target.width / 2
          const hh = target.height / 2
          const closestX = Math.max(target.x - hw, Math.min(x, target.x + hw))
          const closestY = Math.max(target.y - hh, Math.min(y, target.y + hh))
          const dist = Math.sqrt((x - closestX) ** 2 + (y - closestY) ** 2)
          const intensity = Math.max(0.4, 1 - dist / 100)
          group.style.setProperty("--drop-glow-intensity", intensity)
        }
      } else {
        // Update glow intensity as cursor moves within same target
        const group = this.elementLayer.querySelector(`[data-element-id="${target.id}"]`)
        if (group) {
          const hw = target.width / 2
          const hh = target.height / 2
          const closestX = Math.max(target.x - hw, Math.min(x, target.x + hw))
          const closestY = Math.max(target.y - hh, Math.min(y, target.y + hh))
          const dist = Math.sqrt((x - closestX) ** 2 + (y - closestY) ** 2)
          const intensity = Math.max(0.4, 1 - dist / 100)
          group.style.setProperty("--drop-glow-intensity", intensity)
        }
      }

      this._showDropSideIndicator(target, dropSide)
    } else {
      this.externalDropTarget = null
      this._hideDropSideIndicator()
    }
  },

  /**
   * Get the current external drop target element.
   * @returns {Object|null} The currently highlighted drop target element, or null
   */
  getExternalDropTarget() {
    return this.externalDropTarget
  },

  /**
   * Clear the external drop target highlight.
   * Call this when drag operation ends or leaves the canvas.
   */
  clearExternalDropHighlight() {
    if (this.externalDropTarget) {
      const group = this.elementLayer.querySelector(`[data-element-id="${this.externalDropTarget.id}"]`)
      if (group) {
        group.classList.remove("drop-target-highlight")
        group.style.removeProperty("--drop-glow-intensity")
      }
      this.externalDropTarget = null
    }
    this._hideDropSideIndicator()
  },

  /**
   * Determine which side of an element a point is closest to.
   * Used for deciding connection placement during drop operations.
   * @param {Object} element - The target element
   * @param {number} x - X coordinate
   * @param {number} y - Y coordinate
   * @returns {string} The closest side: 'top', 'bottom', 'left', or 'right'
   */
  getDropSide(element, x, y) {
    const hw = element.width / 2
    const hh = element.height / 2

    // Determine drop side using a quadrant-based approach with strong vertical bias.
    // Flowcharts overwhelmingly flow top-to-bottom, so we heavily prefer vertical
    // connections (top/bottom) over horizontal (left/right).
    const relX = x - element.x
    const relY = y - element.y

    // Normalize by element dimensions so comparison is fair for non-square elements
    const normX = relX / (hw || 1)
    const normY = relY / (hh || 1)

    // Strong vertical bias: only use left/right when the cursor is significantly
    // more to the side than above/below (>2x further horizontally than vertically).
    // This prevents accidental horizontal connections during typical top-down drops.
    const verticalBias = 2.0
    if (Math.abs(normY) * verticalBias >= Math.abs(normX)) {
      return normY < 0 ? "top" : "bottom"
    }
    return normX < 0 ? "left" : "right"
  },

  _showDropSideIndicator(element, side) {
    this._hideDropSideIndicator()

    const hw = element.width / 2
    const hh = element.height / 2
    const indicatorSize = 10
    const offset = 16

    let x, y, rotation
    switch (side) {
      case "top":
        x = element.x
        y = element.y - hh - offset
        rotation = 180
        break
      case "bottom":
        x = element.x
        y = element.y + hh + offset
        rotation = 0
        break
      case "left":
        x = element.x - hw - offset
        y = element.y
        rotation = 90
        break
      case "right":
        x = element.x + hw + offset
        y = element.y
        rotation = -90
        break
    }

    const indicator = createGroup({ class: "drop-side-indicator" })

    // Connection line preview from element edge to indicator
    const edgeX = side === "left" ? element.x - hw : side === "right" ? element.x + hw : element.x
    const edgeY = side === "top" ? element.y - hh : side === "bottom" ? element.y + hh : element.y
    const preview = createLine(edgeX, edgeY, x, y, {
      stroke: "#3b82f6",
      "stroke-width": "2",
      "stroke-dasharray": "4,3",
      opacity: "0.5"
    })
    indicator.appendChild(preview)

    // Arrow indicator (larger, more prominent)
    const arrow = createSvgElement("polygon", {
      points: `0,${-indicatorSize} ${indicatorSize},${indicatorSize} ${-indicatorSize},${indicatorSize}`,
      fill: "#3b82f6",
      stroke: "#1d4ed8",
      "stroke-width": "1.5",
      transform: `translate(${x}, ${y}) rotate(${rotation})`
    })
    indicator.appendChild(arrow)

    // Pulsing ring for visibility
    const pulse = createSvgElement("circle", {
      cx: x,
      cy: y,
      r: indicatorSize + 6,
      fill: "none",
      stroke: "#3b82f6",
      "stroke-width": "2",
      opacity: "0.5",
      class: "drop-indicator-pulse"
    })
    indicator.appendChild(pulse)

    this.guideLayer.appendChild(indicator)
    this._dropSideIndicator = indicator
  },

  _hideDropSideIndicator() {
    if (this._dropSideIndicator) {
      this._dropSideIndicator.remove()
      this._dropSideIndicator = null
    }
  },

  /**
   * Get the connection on a specific side of an element.
   * @param {Object} element - The element to check
   * @param {string} side - The side to check ('top', 'bottom', 'left', 'right')
   * @returns {Object|null} Connection info object with connection, isIncoming, and otherElement, or null
   */
  getConnectionOnSide(element, side) {
    for (const conn of this.connections) {
      if (conn.to === element.id && (conn.toPosition || "top") === side) {
        const other = this.elements.find(el => el.id === conn.from)
        if (other) return { connection: conn, isIncoming: true, otherElement: other }
      }
    }

    for (const conn of this.connections) {
      if (conn.from === element.id && (conn.fromPosition || "bottom") === side) {
        const other = this.elements.find(el => el.id === conn.to)
        if (other) return { connection: conn, isIncoming: false, otherElement: other }
      }
    }

    return null
  },

  /**
   * Add a new element next to an existing element and connect them.
   * The new element sits one spacing away on the drop side, in line with the
   * target. When the target already has a connection on that side, the new
   * element is inserted into it and the far end (with its sub-tree) shifts
   * away to make room.
   * @param {Object} elementData - Element configuration (same as addElement)
   * @param {Object} targetElement - The element to position relative to
   * @param {number} dropX - X coordinate of drop position
   * @param {number} dropY - Y coordinate of drop position
   * @returns {Object} The created element
   */
  addElementRelativeTo(elementData, targetElement, dropX, dropY) {
    if (this.canMutate?.() === false) return null
    // Enforce single Start element constraint
    if (elementData.type === "start" && this.hasStartElement()) {
      this.onToast?.(this.labels?.onlyOneStartAllowedToast, "warning")
      this.clearExternalDropHighlight()
      return null
    }

    this.onBeforeChange?.()
    this.clearExternalDropHighlight()

    const dropSide = this.getDropSide(targetElement, dropX, dropY)
    const connectionInfo = this.getConnectionOnSide(targetElement, dropSide)

    const { x, y } = this._calculateRelativePosition(targetElement, dropSide, connectionInfo)
    const element = this._placeNewElement(elementData, x, y)
    this._reconnectAfterInsert(element, targetElement, dropSide, connectionInfo)
    this._scrollToElement(element)
    this.onchange?.()

    return element
  },

  /**
   * Insert a new element of `type` into a connection A→B, rewiring it to
   * A→new→B (A's edge data stays on the first leg). The new element is placed
   * one spacing from A on the edge's side and B (with its sub-tree) shifts
   * away to make room. Selects the new element and opens its property editor.
   * One undo entry.
   * @param {string} connectionId - The connection to split
   * @param {string} type - Element type to insert
   * @returns {Object|null} The created element
   */
  insertElementOnConnection(connectionId, type) {
    if (this.canMutate ? !this.canMutate() : this.isReadOnly) return null

    const connection = this.connections.find(c => c.id === connectionId)
    if (!connection) return null
    const from = this.elements.find(el => el.id === connection.from)
    const to = this.elements.find(el => el.id === connection.to)
    if (!from || !to) return null

    this.onBeforeChange?.()

    const side = this._portToCardinal(connection.fromPort || connection.fromPosition || "bottom", from)
    const connectionInfo = { connection, isIncoming: false, otherElement: to }
    const { x, y } = this._calculateRelativePosition(from, side, connectionInfo)
    const element = this._placeNewElement({ type }, x, y)
    this._reconnectAfterInsert(element, from, side, connectionInfo)

    this._selectElement(element)
    this.onElementDoubleClick?.(element)
    this.onchange?.()
    this.emitStructureChanged?.({ elementId: element.id })

    return element
  },

  _placeNewElement(elementData, x, y) {
    const defaults = getDefaultPropertiesForType(elementData.type)
    const element = {
      id: elementData.id || generateId(),
      type: elementData.type,
      x,
      y,
      width: DEFAULT_ELEMENT_WIDTH,
      height: DEFAULT_ELEMENT_HEIGHT,
      label: this._newElementLabel(elementData),
      properties: { ...defaults, ...(elementData.properties || {}) }
    }

    this.elements.push(element)
    this.renderElement(element)
    return element
  },

  /**
   * Centre for a new element one spacing from `target` on `side`, exactly in
   * line with the target and a grid multiple away from it. With an
   * existing connection on that side, the element at its far end (and that
   * element's sub-tree) shifts away by the same grid-aligned distance so the
   * new element fits in the gap.
   */
  _calculateRelativePosition(target, side, connectionInfo) {
    const spacing = DEFAULT_ELEMENT_SPACING
    const verticalDist = snapToGrid(target.height / 2 + spacing + DEFAULT_ELEMENT_HEIGHT / 2, GRID_SIZE)
    const horizontalDist = snapToGrid(target.width / 2 + spacing + DEFAULT_ELEMENT_WIDTH / 2, GRID_SIZE)
    const offsets = {
      top: [0, -verticalDist],
      bottom: [0, verticalDist],
      left: [-horizontalDist, 0],
      right: [horizontalDist, 0]
    }
    if (connectionInfo) {
      // Inserting before the target pushes the target itself away from its
      // parent; inserting after it pushes the existing child further out.
      const { isIncoming, otherElement } = connectionInfo
      const pushed = isIncoming ? target : otherElement
      const away = isIncoming ? this._getOppositePosition(side) : side
      this.shiftElementAndSubTree(pushed, ...offsets[away])
    }

    const [dx, dy] = offsets[side]
    return { x: target.x + dx, y: target.y + dy }
  },

  _carriedConnectionOptions(connection) {
    const options = {}
    if (connection.label) options.label = connection.label
    if (connection.matchValue != null && connection.matchValue !== "") options.matchValue = connection.matchValue
    if (connection.properties) options.properties = connection.properties
    return Object.keys(options).length ? options : undefined
  },

  _reconnectAfterInsert(newElement, target, side, connectionInfo) {
    const opposite = this._getOppositePosition(side)
    const isVertical = side === "top" || side === "bottom"

    if (connectionInfo) {
      const { connection, isIncoming, otherElement } = connectionInfo
      const fromPos = connection.fromPort || connection.fromPosition || "bottom"
      const toPos = connection.toPosition || "top"
      const carried = this._carriedConnectionOptions(connection)

      // Keep the far end in line with the new element
      if (isVertical && otherElement.x !== newElement.x) {
        otherElement.x = newElement.x
        this.updateElementPosition(otherElement)
      } else if (!isVertical && otherElement.y !== newElement.y) {
        otherElement.y = newElement.y
        this.updateElementPosition(otherElement)
      }

      this.removeConnection(connection.id)

      if (isIncoming) {
        // Maintain same connection direction through the inserted element.
        // Original: otherElement(fromPos) → target(toPos)
        // New:      otherElement(fromPos) → newElement(toPos), newElement(fromSide) → target(toPos)
        // A decision port id only exists on the decision, so the new element
        // leaves from the matching side instead.
        const fromSide = this._portToCardinal(fromPos, otherElement)
        this.createConnection(otherElement, newElement, fromPos, toPos, ...(carried ? [carried] : []))
        this.createConnection(newElement, target, fromSide, toPos)
      } else {
        this.createConnection(target, newElement, fromPos, opposite, ...(carried ? [carried] : []))
        this.createConnection(newElement, otherElement, side, toPos)
      }
    } else {
      this.createConnection(target, newElement, side, opposite)
    }

    // Straighten everything downstream of the insertion
    this.alignChildElements(target)
    this.alignChildElements(newElement)
    this.updateConnections()
  }
}
