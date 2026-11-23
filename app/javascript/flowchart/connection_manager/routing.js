/**
 * RoutingMixin - Handles handle position calculation and path routing for connections.
 * Covers handle position lookup, port-to-cardinal mapping, and orthogonal path calculation.
 */

import { distance } from "utils"
import { hasDynamicPorts, getDynamicPortPositions } from "flowchart/dynamic_ports"

// Position mappings
const OPPOSITE_POSITIONS = {
  top: "bottom",
  bottom: "top",
  left: "right",
  right: "left"
}

const HANDLE_ROTATIONS = {
  top: 0,
  right: 90,
  bottom: 180,
  left: 270
}

export const RoutingMixin = {
  _getHandlePositions(element) {
    // Use dynamic ports for Decision elements
    if (hasDynamicPorts(element)) {
      const dynamicPositions = getDynamicPortPositions(element, this.connections)
      if (dynamicPositions) return dynamicPositions
    }

    // Standard 4-handle system for all other elements
    const hw = element.width / 2
    const hh = element.height / 2

    return {
      top: { x: element.x, y: element.y - hh },
      bottom: { x: element.x, y: element.y + hh },
      left: { x: element.x - hw, y: element.y },
      right: { x: element.x + hw, y: element.y }
    }
  },

  /**
   * Get a specific handle position.
   * Falls back to first available position if requested position doesn't exist.
   */
  _getHandlePosition(element, position) {
    const handles = this._getHandlePositions(element)
    if (handles[position]) return handles[position]

    // Fallback: for dynamic port elements, cardinal positions don't exist.
    // Try common fallbacks, then use first available position.
    if (handles.bottom) return handles.bottom
    if (handles.top) return handles.top

    // Last resort: return the first available handle position
    const keys = Object.keys(handles)
    if (keys.length > 0) return handles[keys[0]]

    // Absolute fallback: element center
    return { x: element.x, y: element.y }
  },

  /**
   * Map a port position (e.g. "port_0") to the nearest cardinal direction for path routing.
   */
  _portToCardinal(position, element) {
    if (["top", "bottom", "left", "right"].includes(position)) return position

    const handles = this._getHandlePositions(element)
    const port = handles[position]
    if (!port) return "bottom"

    const dx = port.x - element.x
    const dy = port.y - element.y

    // Determine nearest cardinal based on angle
    if (Math.abs(dy) > Math.abs(dx)) {
      return dy > 0 ? "bottom" : "top"
    }
    return dx > 0 ? "right" : "left"
  },

  /**
   * Find the closest handle position to a point.
   */
  _getClosestHandlePosition(element, x, y) {
    const handles = this._getHandlePositions(element)

    return Object.entries(handles).reduce((closest, [pos, coords]) => {
      const dist = distance(x, y, coords.x, coords.y)
      return dist < closest.dist ? { pos, dist } : closest
    }, { pos: "top", dist: Infinity }).pos
  },

  /**
   * Get the opposite handle position.
   */
  _getOppositePosition(position) {
    return OPPOSITE_POSITIONS[position] || "top"
  },

  /**
   * Calculate path between two points.
   * Routing mode determined by this.connectionRouting:
   * - "straight": straight vertical/horizontal line (no diagonal)
   * - "orthogonal": always right-angle segments (default)
   */
  _calculatePath(from, to, fromPos, toPos) {
    // Routing mode: straight - only for aligned elements (vertical or horizontal)
    if (this.connectionRouting === "straight") {
      const isVertical = (fromPos === "bottom" && toPos === "top") ||
                         (fromPos === "top" && toPos === "bottom")
      const isHorizontal = (fromPos === "right" && toPos === "left") ||
                           (fromPos === "left" && toPos === "right")

      // Only use straight line if elements are aligned (no diagonal)
      if (isVertical && from.x === to.x) {
        return [{ ...from }, { ...to }]
      }
      if (isHorizontal && from.y === to.y) {
        return [{ ...from }, { ...to }]
      }

      // Fall through to orthogonal for non-aligned elements
    }

    // Default: orthogonal - always use right-angle segments
    return this._calculateOrthogonalPath(from, to, fromPos, toPos)
  },

  /**
   * Calculate orthogonal (right-angle) path between two points.
   * Used for horizontal connections in bezier mode, and all connections in orthogonal mode.
   */
  _calculateOrthogonalPath(from, to, fromPos, toPos) {
    const isHorizontalOut = fromPos === "right" || fromPos === "left"

    if (isHorizontalOut) {
      // Determine the path based on relative positions
      if (fromPos === "right" && toPos === "left") {
        // Right to left: go right, then down/up, then right to target
        const midX = (from.x + to.x) / 2
        return [
          { ...from },
          { x: midX, y: from.y },
          { x: midX, y: to.y },
          { ...to }
        ]
      } else if (fromPos === "left" && toPos === "right") {
        // Left to right: go left, then down/up, then left to target
        const midX = (from.x + to.x) / 2
        return [
          { ...from },
          { x: midX, y: from.y },
          { x: midX, y: to.y },
          { ...to }
        ]
      } else if (fromPos === "right" && toPos === "top") {
        // Right to top: path ensures arrow points straight down into target
        // Path: horizontal from source → vertical down to above target → straight down into target
        const minHorizontalTravel = 20
        const verticalSegmentLength = 25  // Length of final vertical segment for straight arrow

        // Determine horizontal extent: go at least minHorizontalTravel past source, or to target's X
        const turnX = Math.max(from.x + minHorizontalTravel, to.x)

        // Vertical turn point: above the target element
        const turnY = to.y - verticalSegmentLength

        return [
          { ...from },
          { x: turnX, y: from.y },   // Horizontal segment
          { x: turnX, y: turnY },    // Vertical segment (goes down)
          { x: to.x, y: turnY },     // Horizontal to align with target
          { ...to }                   // Final vertical segment (straight down arrow)
        ]
      } else if (fromPos === "left" && toPos === "top") {
        // Left to top: path ensures arrow points straight down into target
        // Path: horizontal from source → vertical down to above target → straight down into target
        const minHorizontalTravel = 20
        const verticalSegmentLength = 25  // Length of final vertical segment for straight arrow

        // Determine horizontal extent: go at least minHorizontalTravel past source, or to target's X
        const turnX = Math.min(from.x - minHorizontalTravel, to.x)

        // Vertical turn point: above the target element
        const turnY = to.y - verticalSegmentLength

        return [
          { ...from },
          { x: turnX, y: from.y },   // Horizontal segment
          { x: turnX, y: turnY },    // Vertical segment (goes down)
          { x: to.x, y: turnY },     // Horizontal to align with target
          { ...to }                   // Final vertical segment (straight down arrow)
        ]
      }
    }

    // Default: orthogonal path for other cases (vertical out, then horizontal)
    const isVerticalOut = fromPos === "top" || fromPos === "bottom"
    if (isVerticalOut) {
      const midY = (from.y + to.y) / 2
      return [
        { ...from },
        { x: from.x, y: midY },
        { x: to.x, y: midY },
        { ...to }
      ]
    }

    // Horizontal out fallback
    const midX = (from.x + to.x) / 2
    return [
      { ...from },
      { x: midX, y: from.y },
      { x: midX, y: to.y },
      { ...to }
    ]
  },

  /**
   * Get rotation angle for a port handle.
   * Standard handles use HANDLE_ROTATIONS. Dynamic ports compute angle from element center.
   */
  _getPortRotation(position, element) {
    if (HANDLE_ROTATIONS[position] !== undefined) {
      return HANDLE_ROTATIONS[position]
    }
    // Dynamic port: compute angle from element center to port position
    const handles = this._getHandlePositions(element)
    const port = handles[position]
    if (!port) return 180
    const dx = port.x - element.x
    const dy = port.y - element.y
    return Math.atan2(dy, dx) * (180 / Math.PI) + 90
  }
}
