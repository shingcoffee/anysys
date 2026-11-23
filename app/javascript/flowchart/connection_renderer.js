/**
 * ConnectionRenderer - Handles connection path and arrow rendering.
 * Provides utility methods for SVG path generation and arrow calculations.
 */

/**
 * Connection styling configuration.
 * @type {Object}
 */
export const CONNECTION_STYLE = {
  defaultColor: "#94a3b8",
  selectedColor: "#4f46e5",
  hoverColor: "#6366f1",
  strokeWidth: 2,
  selectedStrokeWidth: 3,
  arrowSize: 5,
  cornerRadius: 8
}

/**
 * ConnectionRenderer - Static utility class for connection rendering operations.
 */
export class ConnectionRenderer {
  /**
   * Convert an array of points to an SVG path string.
   * @param {Array<{x: number, y: number}>} points - Array of point objects with x and y coordinates
   * @returns {string} SVG path data string (e.g., "M 0 0 L 100 100")
   * @example
   * ConnectionRenderer.pointsToPath([{x: 0, y: 0}, {x: 100, y: 100}])
   * // Returns: "M 0 0 L 100 100"
   */
  static pointsToPath(points) {
    if (!points || points.length < 2) return ""
    if (points.length === 2) return `M ${points[0].x} ${points[0].y} L ${points[1].x} ${points[1].y}`

    const r = CONNECTION_STYLE.cornerRadius
    let d = `M ${points[0].x} ${points[0].y}`

    for (let i = 1; i < points.length - 1; i++) {
      const prev = points[i - 1]
      const curr = points[i]
      const next = points[i + 1]

      // Direction vectors
      const dx1 = curr.x - prev.x, dy1 = curr.y - prev.y
      const dx2 = next.x - curr.x, dy2 = next.y - curr.y
      const len1 = Math.sqrt(dx1 * dx1 + dy1 * dy1)
      const len2 = Math.sqrt(dx2 * dx2 + dy2 * dy2)

      if (len1 === 0 || len2 === 0) { d += ` L ${curr.x} ${curr.y}`; continue }

      // Clamp radius to half the shorter segment
      const maxR = Math.min(r, len1 / 2, len2 / 2)

      // Points where the curve starts and ends
      const startX = curr.x - (dx1 / len1) * maxR
      const startY = curr.y - (dy1 / len1) * maxR
      const endX = curr.x + (dx2 / len2) * maxR
      const endY = curr.y + (dy2 / len2) * maxR

      d += ` L ${startX} ${startY} Q ${curr.x} ${curr.y} ${endX} ${endY}`
    }

    const last = points[points.length - 1]
    d += ` L ${last.x} ${last.y}`
    return d
  }

  /**
   * Calculate the arrow angle from the last segment of path points.
   * The angle is calculated based on the direction from the second-to-last point
   * to the last point, then rotated 90 degrees for proper arrow orientation.
   * @param {Array<{x: number, y: number}>} points - Array of point objects
   * @returns {number} Angle in degrees for the arrow rotation
   * @example
   * // For a downward-pointing arrow (vertical line going down)
   * ConnectionRenderer.calculateArrowAngle([{x: 0, y: 0}, {x: 0, y: 100}])
   * // Returns: 180
   */
  static calculateArrowAngle(points) {
    if (!points || points.length < 2) return 0

    const last = points[points.length - 1]
    const prev = points[points.length - 2]
    const angle = Math.atan2(last.y - prev.y, last.x - prev.x)
    return (angle * 180 / Math.PI) + 90
  }

  /**
   * Generate the polygon points string for an arrow head.
   * Creates an isoceles triangle pointing upward, centered at origin.
   * @param {number} [size=CONNECTION_STYLE.arrowSize] - Size of the arrow (half-width and height)
   * @returns {string} SVG polygon points string (e.g., "0,-5 5,5 -5,5")
   * @example
   * ConnectionRenderer.getArrowPoints(5)
   * // Returns: "0,-5 5,5 -5,5"
   */
  static getArrowPoints(size = CONNECTION_STYLE.arrowSize) {
    return `0,${-size} ${size},${size} ${-size},${size}`
  }
}

export default ConnectionRenderer
