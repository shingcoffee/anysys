/**
 * RenderingMixin - Handles SVG rendering of connections, labels, and hover effects.
 * Covers connection group creation, label positioning, and hover event wiring.
 */

import {
  createGroup,
  createPath,
  createPolygon,
  createText,
  createRect
} from "utils"
import { ConnectionRenderer, CONNECTION_STYLE } from "flowchart/connection_renderer"
import { measureRenderedTextWidth } from "flowchart/element_renderer"

export const RenderingMixin = {
  /**
   * Render a connection to the canvas.
   */
  _renderConnection(connection) {
    const pathPoints = this._connectionPathPoints(connection)
    if (!pathPoints) return

    const pathData = ConnectionRenderer.pointsToPath(pathPoints)
    const toPoint = pathPoints[pathPoints.length - 1]
    const group = this._createConnectionGroup(connection.id, pathData, toPoint, pathPoints, connection.label)
    this.connectionLayer.appendChild(group)
  },

  /**
   * Routed path points of a connection, or null when an endpoint is missing.
   */
  _connectionPathPoints(connection) {
    const fromEl = this.elements.find(el => el.id === connection.from)
    const toEl = this.elements.find(el => el.id === connection.to)
    if (!fromEl || !toEl) return null

    const fromPosition = connection.fromPort || connection.fromPosition || "bottom"
    const toPosition = connection.toPort || connection.toPosition || "top"
    const fromPoint = this._getHandlePosition(fromEl, fromPosition)
    const toPoint = this._getHandlePosition(toEl, toPosition)

    // For path calculation, map port positions to nearest cardinal direction
    const fromCardinal = this._portToCardinal(fromPosition, fromEl)
    const toCardinal = this._portToCardinal(toPosition, toEl)
    return this._calculatePath(fromPoint, toPoint, fromCardinal, toCardinal)
  },

  /**
   * Point halfway along a connection's routed path (by length).
   */
  _connectionMidpoint(connection) {
    const points = this._connectionPathPoints(connection) || []
    if (points.length === 0) return { x: 0, y: 0 }

    const lengths = points.slice(1).map((point, i) =>
      Math.hypot(point.x - points[i].x, point.y - points[i].y)
    )
    let remaining = lengths.reduce((sum, length) => sum + length, 0) / 2
    for (let i = 0; i < lengths.length; i++) {
      if (remaining <= lengths[i] && lengths[i] > 0) {
        const t = remaining / lengths[i]
        return {
          x: points[i].x + (points[i + 1].x - points[i].x) * t,
          y: points[i].y + (points[i + 1].y - points[i].y) * t
        }
      }
      remaining -= lengths[i]
    }
    return { x: points[0].x, y: points[0].y }
  },

  /**
   * Create the SVG group for a connection.
   */
  _createConnectionGroup(connectionId, pathData, endPoint, pathPoints, label = null) {
    const group = createGroup({ "data-connection-id": connectionId })
    group.style.cursor = "pointer"

    // Invisible hit area for easier clicking
    group.appendChild(createPath(pathData, {
      stroke: "transparent",
      "stroke-width": "16",
      fill: "none"
    }))

    // Visible line
    const line = createPath(pathData, {
      stroke: CONNECTION_STYLE.defaultColor,
      "stroke-width": CONNECTION_STYLE.strokeWidth,
      fill: "none",
      class: "connection-line"
    })
    group.appendChild(line)

    // Arrow head
    const arrowAngle = ConnectionRenderer.calculateArrowAngle(pathPoints)
    const arrow = createPolygon(ConnectionRenderer.getArrowPoints(), {
      fill: CONNECTION_STYLE.defaultColor,
      transform: `translate(${endPoint.x}, ${endPoint.y}) rotate(${arrowAngle})`,
      class: "connection-arrow"
    })
    group.appendChild(arrow)

    // Add label if provided
    if (label) {
      const labelGroup = this._createConnectionLabel(pathPoints, label)
      group.appendChild(labelGroup)
    }

    // Hover effects
    this._attachConnectionHoverEvents(group, connectionId, line, arrow)

    return group
  },

  /**
   * Create a label element for a connection.
   * For orthogonal paths (right-angle connectors), positioned in the middle of the first vertical segment.
   * For straight paths, positioned near the midpoint.
   */
  _createConnectionLabel(pathPoints, label) {
    if (pathPoints.length < 2) return createGroup({})

    let labelX, labelY, offsetX = 0, offsetY = 0
    const offsetDistance = 14

    if (pathPoints.length > 2) {
      // Orthogonal path (right-angle connector)
      // Find the first vertical segment to position the label on the "side" of the right angle
      let verticalSegmentStart = null
      let verticalSegmentEnd = null

      for (let i = 0; i < pathPoints.length - 1; i++) {
        const start = pathPoints[i]
        const end = pathPoints[i + 1]
        const dx = Math.abs(end.x - start.x)
        const dy = Math.abs(end.y - start.y)

        // Check if this segment is vertical (dy > dx)
        if (dy > dx && dy > 5) {  // Minimum length threshold
          verticalSegmentStart = start
          verticalSegmentEnd = end
          break
        }
      }

      if (verticalSegmentStart && verticalSegmentEnd) {
        // Position label in the middle of the first vertical segment
        labelX = (verticalSegmentStart.x + verticalSegmentEnd.x) / 2
        labelY = (verticalSegmentStart.y + verticalSegmentEnd.y) / 2
        // Offset horizontally to the right of vertical segment
        offsetX = offsetDistance
      } else {
        // Fallback: use midpoint of entire path
        const midIndex = Math.floor(pathPoints.length / 2)
        labelX = pathPoints[midIndex].x
        labelY = pathPoints[midIndex].y
        offsetX = offsetDistance
      }
    } else {
      // Straight line (2 points) - position at midpoint
      const startPoint = pathPoints[0]
      const endPoint = pathPoints[1]
      labelX = (startPoint.x + endPoint.x) / 2
      labelY = (startPoint.y + endPoint.y) / 2

      // Determine if segment is vertical or horizontal
      const dx = Math.abs(endPoint.x - startPoint.x)
      const dy = Math.abs(endPoint.y - startPoint.y)
      const isVerticalSegment = dy > dx

      if (isVerticalSegment) {
        // For vertical segments, offset horizontally to the right
        offsetX = offsetDistance
      } else {
        // For horizontal segments, offset vertically above
        offsetY = -offsetDistance
      }
    }

    const finalX = labelX + offsetX
    const finalY = labelY + offsetY

    const labelGroup = createGroup({ class: "connection-label-group" })

    // Measure text width (proportional/CJK-aware)
    const fontSize = 10
    const textWidth = measureRenderedTextWidth(label, fontSize)
    const textHeight = fontSize + 2
    const paddingX = 6
    const paddingY = 3

    // Background pill/badge
    const bgRect = createRect(
      finalX - textWidth / 2 - paddingX,
      finalY - textHeight / 2 - paddingY,
      textWidth + paddingX * 2,
      textHeight + paddingY * 2,
      {
        fill: "#fef3c7",
        stroke: "#f59e0b",
        "stroke-width": "1",
        rx: "10",
        ry: "10",
        class: "connection-label-bg"
      }
    )
    labelGroup.appendChild(bgRect)

    // Label text
    const labelText = createText(label, finalX, finalY + fontSize / 3, {
      "font-size": `${fontSize}px`,
      "font-family": "system-ui, -apple-system, sans-serif",
      "font-weight": "600",
      fill: "#92400e",
      "text-anchor": "middle",
      class: "connection-label-text"
    })
    labelGroup.appendChild(labelText)

    return labelGroup
  },

  /**
   * Attach hover events to a connection group.
   */
  _attachConnectionHoverEvents(group, connectionId, line, arrow) {
    const setStyle = (color, width) => {
      line.setAttribute("stroke", color)
      line.setAttribute("stroke-width", width)
      arrow.setAttribute("fill", color)
    }

    group.addEventListener("mouseenter", () => {
      if (this.selectedConnectionId !== connectionId) {
        setStyle(CONNECTION_STYLE.hoverColor, CONNECTION_STYLE.selectedStrokeWidth)
        line.classList.add("flow-animated")
      }
      this._showEdgeInsertButton?.(connectionId)
    })

    group.addEventListener("mouseleave", () => {
      if (this.selectedConnectionId !== connectionId) {
        setStyle(CONNECTION_STYLE.defaultColor, CONNECTION_STYLE.strokeWidth)
        line.classList.remove("flow-animated")
      }
      this._scheduleHideEdgeInsertButton?.()
    })
  }
}
