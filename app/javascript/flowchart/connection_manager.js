/**
 * Connection management mixin for the flowchart canvas.
 * Handles creating, rendering, and manipulating connections between elements.
 *
 * Composed from:
 *   - RoutingMixin   (connection_manager/routing.js)   — handle positions, path routing
 *   - RenderingMixin (connection_manager/rendering.js) — SVG rendering, labels, hover effects
 *   - AlignmentMixin (connection_manager/alignment.js) — keep connector lines straight
 *   - EdgeInsertMixin (connection_manager/edge_insert.js) — hover "+" that inserts a box on an edge
 */

import {
  generateId,
  createGroup,
  createCircle,
  createPolygon,
  createSvgElement
} from "utils"
import { CONNECTION_HANDLE_RADIUS } from "flowchart/constants"
import { CONNECTION_STYLE } from "flowchart/connection_renderer"
import { hasDynamicPorts, orderedDecisionBranches } from "flowchart/dynamic_ports"
import { RoutingMixin } from "flowchart/connection_manager/routing"
import { RenderingMixin } from "flowchart/connection_manager/rendering"
import { AlignmentMixin } from "flowchart/connection_manager/alignment"
import { EdgeInsertMixin } from "flowchart/connection_manager/edge_insert"

export const ConnectionManagerMixin = {
  /**
   * Shared Start/End directed-edge gate used by createConnection, reconnect
   * drops, and connection-endpoint retarget. Toasts and returns true when
   * the pair is illegal so callers leave the graph unchanged.
   */
  _rejectsDirectedEdge(fromElement, toElement) {
    if (toElement?.type === "start") {
      const message = this.labels?.connectionIntoStartRejected
      if (message) this.onToast?.(message)
      return true
    }

    if (fromElement?.type === "end") {
      const message = this.labels?.connectionOutOfEndRejected
      if (message) this.onToast?.(message)
      return true
    }

    return false
  },

  /**
   * Create a connection between two elements.
   * @param {Object} fromElement - Source element
   * @param {Object} toElement - Target element
   * @param {string|null} fromPosition - Source side (`top`/`bottom`/`left`/`right`) or a `port_*` id
   * @param {string|null} toPosition - Target side (`top`/`bottom`/`left`/`right`) or a `port_*` id
   * @param {Object} [options]
   * @param {string} [options.label]
   * @param {string} [options.matchValue]
   * @param {Object} [options.properties]
   * @param {boolean} [options.skipBranchSync] - skip auto-creating a decision port
   * @returns {Object|null} the new connection, or null when the pair is rejected
   */
  createConnection(fromElement, toElement, fromPosition, toPosition, options = {}) {
    if (fromElement.id === toElement.id) return null

    if (this._rejectsDirectedEdge(fromElement, toElement)) return null

    const exists = this.connections.some(c =>
      c.from === fromElement.id && c.to === toElement.id
    )
    if (exists) return null

    const isFromPort = typeof fromPosition === 'string' && fromPosition.startsWith("port_")
    const isToPort = typeof toPosition === 'string' && toPosition.startsWith("port_")

    const connection = {
      id: generateId("conn"),
      from: fromElement.id,
      to: toElement.id,
      fromPort: isFromPort ? fromPosition : null,
      fromPosition: isFromPort ? null : (fromPosition || "bottom"),
      toPort: isToPort ? toPosition : null,
      toPosition: isToPort ? null : (toPosition || "top"),
      label: options.label || null,
      properties: options.properties || { description: "" }
    }
    if (options.matchValue != null && options.matchValue !== "") {
      connection.matchValue = options.matchValue
    }

    this.connections.push(connection)

    // Pull the target into line with the source so the new edge is straight;
    // a moved target's other edges are re-rendered with it.
    if (this._alignConnectionElements(connection)) {
      this.updateConnections()
    } else {
      this._renderConnection(connection)
    }

    // Every edge out of a decision is a branch: connecting an element to a
    // decision (by drawing, dropping a new element, or inserting) auto-creates
    // a numbered port with the translated "Branch {index}" label when blank —
    // see _syncDecisionBranches.
    // The property editor manages its own branch list, so it opts out via
    // options.skipBranchSync.
    if (fromElement.type === "decision" && !options.skipBranchSync) {
      this._syncDecisionBranches(fromElement, toElement.id)
    }

    return connection
  },

  // ===================
  // Connection Operations
  // ===================

  deleteConnection(connectionId) {
    const connection = this.connections.find(c => c.id === connectionId)
    if (!connection) return

    const sourceId = connection.from
    const index = this.connections.findIndex(c => c.id === connectionId)
    this.connections.splice(index, 1)
    // If this edge left a decision, re-derive that decision's branches so the
    // remaining ports/labels stay contiguous (port_0, port_1, …).
    const source = this.elements.find(el => el.id === sourceId)
    if (source && source.type === "decision") this._syncDecisionBranches(source)
    this._hideConnectionEndpointHandles()
    this.updateConnections()
  },

  /**
   * Number outgoing decision edges port_0…port_N and fill a blank label from
   * the translated "Branch {index}" format when one is installed. The edge to
   * `newElementId` is ordered right after the branch of the port it was drawn
   * from (see orderedDecisionBranches), and its box is snapped onto the row of
   * the other branch boxes. Match values stay on the connection;
   * properties.branches is not written.
   */
  _syncDecisionBranches(decisionElement, newElementId = null) {
    if (!decisionElement || decisionElement.type !== "decision") return

    const inserted = newElementId
      ? this.connections.find(c => c.from === decisionElement.id && c.to === newElementId)
      : null
    const outgoing = orderedDecisionBranches(this.connections, decisionElement.id, inserted?.id)
    const format = this.labels?.branchFallbackNameFormat
    outgoing.forEach((conn, i) => {
      conn.fromPort = `port_${i}`
      conn.fromPosition = null
      if (!conn.label || !String(conn.label).trim()) {
        if (format) conn.label = String(format).replace("{index}", String(i + 1))
      }
    })

    this.emitStructureChanged?.({ elementId: decisionElement.id })
    this._alignNewBranchToRow(decisionElement, newElementId)
  },

  removeConnection(connectionId) {
    const connection = this.connections.find(c => c.id === connectionId)
    if (!connection) return

    const index = this.connections.findIndex(c => c.id === connectionId)
    this.connections.splice(index, 1)

    const group = this.connectionLayer.querySelector(`[data-connection-id="${connectionId}"]`)
    if (group) group.remove()

    this.handleLayer.querySelectorAll(`[data-connection-id="${connectionId}"]`)
      .forEach(h => h.remove())
  },

  updateConnections() {
    // Clear and re-render all connections
    while (this.connectionLayer.firstChild) {
      this.connectionLayer.removeChild(this.connectionLayer.firstChild)
    }

    this.connections.forEach(conn => this._renderConnection(conn))
    this._refreshEdgeInsert()

    // Restore selection state
    if (this.selectedConnectionId) {
      const exists = this.connections.some(c => c.id === this.selectedConnectionId)
      if (exists) {
        this._setConnectionStyle(this.selectedConnectionId, CONNECTION_STYLE.selectedColor, CONNECTION_STYLE.selectedStrokeWidth)
        if (this.canMutate?.() !== false) this._showConnectionEndpointHandles(this.selectedConnectionId)
      } else {
        this.selectedConnectionId = null
      }
    }
  },

  // ===================
  // Selection
  // ===================

  selectConnection(connectionId) {
    // Deselect previous
    if (this.selectedConnectionId && this.selectedConnectionId !== connectionId) {
      this._setConnectionStyle(this.selectedConnectionId, CONNECTION_STYLE.defaultColor, CONNECTION_STYLE.strokeWidth)
      this._hideConnectionEndpointHandles()
    }

    this._clearSelection()
    this.selectedConnectionId = connectionId
    this._setConnectionStyle(connectionId, CONNECTION_STYLE.selectedColor, CONNECTION_STYLE.selectedStrokeWidth)
    if (this.canMutate?.() !== false) this._showConnectionEndpointHandles(connectionId)

    const connection = this.connections.find(c => c.id === connectionId)
    if (connection) {
      this.onConnectionSelected?.(connection)
    }
  },

  clearConnectionSelection() {
    if (!this.selectedConnectionId) return

    this._setConnectionStyle(this.selectedConnectionId, CONNECTION_STYLE.defaultColor, CONNECTION_STYLE.strokeWidth)
    this._hideConnectionEndpointHandles()
    this.selectedConnectionId = null
  },

  _setConnectionStyle(connectionId, color, strokeWidth) {
    const group = this.connectionLayer.querySelector(`[data-connection-id="${connectionId}"]`)
    if (!group) return

    const line = group.querySelector(".connection-line")
    const arrow = group.querySelector(".connection-arrow")

    if (line) {
      line.setAttribute("stroke", color)
      line.setAttribute("stroke-width", strokeWidth)
    }
    if (arrow) {
      arrow.setAttribute("fill", color)
    }
  },

  // ===================
  // Endpoint Handles
  // ===================

  _showConnectionEndpointHandles(connectionId) {
    this._hideConnectionEndpointHandles()

    const connection = this.connections.find(c => c.id === connectionId)
    if (!connection) return

    const fromEl = this.elements.find(el => el.id === connection.from)
    const toEl = this.elements.find(el => el.id === connection.to)
    if (!fromEl || !toEl) return

    const fromPoint = this._getHandlePosition(fromEl, connection.fromPort || connection.fromPosition || "bottom")
    const toPoint = this._getHandlePosition(toEl, connection.toPort || connection.toPosition || "top")

    this._createEndpointHandle(fromPoint, connectionId, "from")
    this._createEndpointHandle(toPoint, connectionId, "to")
  },

  _createEndpointHandle(point, connectionId, type) {
    const group = createGroup({
      "data-connection-endpoint": type,
      "data-connection-id": connectionId
    })
    group.style.cursor = "move"

    const r = CONNECTION_HANDLE_RADIUS

    // Hit area
    group.appendChild(createCircle(point.x, point.y, r + 6, { fill: "transparent" }))

    // Outer circle
    const outer = createCircle(point.x, point.y, r, {
      fill: "#ffffff",
      stroke: CONNECTION_STYLE.selectedColor,
      "stroke-width": "2",
      class: "connection-endpoint-handle"
    })
    group.appendChild(outer)

    // Inner circle
    const inner = createCircle(point.x, point.y, r / 2, {
      fill: CONNECTION_STYLE.selectedColor
    })
    group.appendChild(inner)

    // Hover effects
    group.addEventListener("mouseenter", () => {
      outer.setAttribute("r", r + 2)
      outer.setAttribute("stroke-width", "3")
      inner.setAttribute("r", r / 2 + 1)
    })

    group.addEventListener("mouseleave", () => {
      if (!this.isDraggingConnectionEndpoint) {
        outer.setAttribute("r", r)
        outer.setAttribute("stroke-width", "2")
        inner.setAttribute("r", r / 2)
      }
    })

    this.handleLayer.appendChild(group)
  },

  _hideConnectionEndpointHandles() {
    this.handleLayer.querySelectorAll("[data-connection-endpoint]")
      .forEach(h => h.remove())
  },

  // ===================
  // Connection Handles
  // ===================

  showConnectionHandles(elements) {
    this._hideConnectionHandles()

    const elementList = Array.isArray(elements) ? elements : [elements]
    elementList.forEach(el => this._createElementHandles(el))
  },

  _createElementHandles(element) {
    const handles = this._getHandlePositions(element)
    const isDynamic = hasDynamicPorts(element)

    Object.entries(handles).forEach(([position, coords]) => {
      const group = createGroup({
        "data-handle-position": position,
        "data-parent-element-id": element.id
      })
      group.style.cursor = "crosshair"

      // Hit area
      group.appendChild(createCircle(coords.x, coords.y, 14, { fill: "transparent" }))

      // Arrow (use green for dynamic output ports, blue for standard)
      const isOutputPort = position.startsWith("port_")
      const fillColor = isDynamic && isOutputPort ? "#10b981" : "#3b82f6"
      const strokeColor = isDynamic && isOutputPort ? "#059669" : "#1d4ed8"
      const rotation = this._getPortRotation(position, element)

      const arrow = createPolygon("0,-6 6,6 -6,6", {
        fill: fillColor,
        stroke: strokeColor,
        "stroke-width": "1",
        transform: `translate(${coords.x}, ${coords.y}) rotate(${rotation})`
      })
      group.appendChild(arrow)

      // Hover effect
      group.addEventListener("mouseenter", () => {
        arrow.setAttribute("fill", isDynamic && isOutputPort ? "#059669" : "#2563eb")
        arrow.setAttribute("transform", `translate(${coords.x}, ${coords.y}) rotate(${rotation}) scale(1.3)`)
      })

      group.addEventListener("mouseleave", () => {
        if (!this.isDrawingConnection) {
          arrow.setAttribute("fill", fillColor)
          arrow.setAttribute("transform", `translate(${coords.x}, ${coords.y}) rotate(${rotation})`)
        }
      })

      this.handleLayer.appendChild(group)
    })
  },

  _hideConnectionHandles() {
    this.handleLayer.querySelectorAll("[data-handle-position]")
      .forEach(h => h.remove())
  },

  // ===================
  // Connection Properties
  // ===================

  /**
   * Update a connection's label and/or properties.
   * Re-renders the connection to reflect changes.
   * @param {string} connectionId - The connection ID
   * @param {string} [newLabel] - New label (undefined to keep existing)
   * @param {Object} [newProperties] - Properties to merge with existing
   */
  updateConnectionProperties(connectionId, newLabel, newProperties) {
    const connection = this.connections.find(c => c.id === connectionId)
    if (!connection) return

    this.onBeforeChange?.()

    if (newLabel !== undefined) connection.label = newLabel
    if (newProperties !== undefined) {
      connection.properties = { ...(connection.properties || {}), ...newProperties }
    }

    this.updateConnections()
    this.onchange?.()
  },

  // ===================
  // Inline Label Editing
  // ===================

  /**
   * Start inline label editing on a connection.
   * Creates a foreignObject with an HTML input at the connection path midpoint.
   * @param {string} connectionId - The connection ID to edit
   */
  startInlineLabelEdit(connectionId) {
    if (this.canMutate?.() === false) return
    // Remove any existing inline editor
    this._removeInlineLabelEditor()

    const connection = this.connections.find(c => c.id === connectionId)
    if (!connection) return

    const group = this.connectionLayer.querySelector(`[data-connection-id="${connectionId}"]`)
    if (!group) return

    const pathEl = group.querySelector(".connection-line")
    if (!pathEl) return

    // Calculate midpoint of the path
    const pathLength = pathEl.getTotalLength()
    const midpoint = pathEl.getPointAtLength(pathLength / 2)

    const inputWidth = 140
    const inputHeight = 28

    // Create foreignObject to embed HTML input in SVG
    const foreignObject = createSvgElement("foreignObject", {
      x: midpoint.x - inputWidth / 2,
      y: midpoint.y - inputHeight / 2,
      width: inputWidth,
      height: inputHeight,
      class: "connection-inline-editor"
    })

    const input = document.createElement("input")
    input.type = "text"
    input.value = connection.label || ""
    input.placeholder = this.labels?.connectionLabelPlaceholder ?? ""
    input.setAttribute("style", [
      "width: 100%",
      "height: 100%",
      "border: 1px solid #6366f1",
      "border-radius: 6px",
      "padding: 2px 8px",
      "font-size: 11px",
      "font-family: system-ui, -apple-system, sans-serif",
      "text-align: center",
      "outline: none",
      "background: white",
      "box-shadow: 0 1px 3px rgba(0,0,0,0.2)"
    ].join(";"))

    const commitEdit = () => {
      const newLabel = input.value.trim() || null
      this._removeInlineLabelEditor()
      // Reopening the sidebar for an unchanged label would rebuild the form the
      // user just clicked into (blur fires when focus moves to the sidebar).
      if (newLabel === (connection.label || null)) return

      this.onBeforeChange?.()
      connection.label = newLabel
      this.updateConnections()
      this.onchange?.()
      if (this.selectedConnectionId === connectionId) {
        this._setConnectionStyle(connectionId, CONNECTION_STYLE.selectedColor, CONNECTION_STYLE.selectedStrokeWidth)
        if (this.canMutate?.() !== false) this._showConnectionEndpointHandles(connectionId)
        // Notify property editor only while this connection is still selected
        this.onConnectionSelected?.(connection)
      }
    }

    const cancelEdit = () => {
      this._removeInlineLabelEditor()
    }

    input.addEventListener("keydown", (e) => {
      e.stopPropagation()
      if (e.key === "Enter") {
        e.preventDefault()
        commitEdit()
      } else if (e.key === "Escape") {
        e.preventDefault()
        cancelEdit()
      }
    })

    input.addEventListener("blur", () => {
      // Use setTimeout to allow keydown to fire first
      setTimeout(() => {
        if (this._inlineLabelEditor) {
          commitEdit()
        }
      }, 0)
    })

    foreignObject.appendChild(input)
    this.connectionLayer.appendChild(foreignObject)
    this._inlineLabelEditor = foreignObject

    // Focus and select text
    requestAnimationFrame(() => {
      input.focus()
      input.select()
    })
  },

  /**
   * Remove the inline label editor if present.
   */
  _removeInlineLabelEditor() {
    if (this._inlineLabelEditor) {
      this._inlineLabelEditor.remove()
      this._inlineLabelEditor = null
    }
  }
}

// Apply mixins — pure structural composition, zero logic change
Object.assign(ConnectionManagerMixin, RoutingMixin)
Object.assign(ConnectionManagerMixin, RenderingMixin)
Object.assign(ConnectionManagerMixin, AlignmentMixin)
Object.assign(ConnectionManagerMixin, EdgeInsertMixin)

export default ConnectionManagerMixin
