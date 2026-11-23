/**
 * PositionCalculator - Handles element positioning calculations for subflows.
 *
 * This utility class provides static methods for calculating position offsets
 * and shifts when expanding/folding subflows in the flowchart canvas.
 */
export class PositionCalculator {
  /** Default spacing between elements in pixels */
  static DEFAULT_SPACING = 50

  /** Default element dimensions */
  static DEFAULT_HEIGHT = 45
  static DEFAULT_WIDTH = 100

  /**
   * Calculate position offset for expanding subflow elements.
   * This determines how subflow elements should be positioned relative to
   * the original subflow element's location.
   *
   * @param {Object} subflowElement - The subflow element being expanded
   * @param {number} subflowElement.x - X position of subflow element
   * @param {number} subflowElement.y - Y position of subflow element
   * @param {Array<Object>} subflowElements - Elements from the subflow configuration
   * @returns {Object} Position offset { offsetX, offsetY }
   */
  static calculateExpansionOffset(subflowElement, subflowElements) {
    const minX = Math.min(...subflowElements.map(el => el.x || 0))
    const minY = Math.min(...subflowElements.map(el => el.y || 0))
    return {
      offsetX: subflowElement.x - minX,
      offsetY: subflowElement.y - minY
    }
  }

  /**
   * Calculate child element position shift after expansion.
   * Determines how child elements should be repositioned when a subflow
   * is expanded and the end element needs to connect to children.
   *
   * @param {Object} endElement - The end element of expanded subflow
   * @param {number} endElement.x - X position of end element
   * @param {number} endElement.y - Y position of end element
   * @param {number} [endElement.height] - Height of end element
   * @param {Object} childElement - The child element to adjust
   * @param {number} childElement.x - X position of child element
   * @param {number} childElement.y - Y position of child element
   * @param {number} [childElement.height] - Height of child element
   * @param {Object} conn - The connection object
   * @param {string} [conn.toPosition] - Target connection position (e.g., "top", "bottom")
   * @returns {Object} Position shift { shiftX, shiftY }
   */
  static calculateChildShiftForExpansion(endElement, childElement, conn) {
    const fromPos = "bottom"
    const toPos = conn.toPosition || "top"
    const isVertical = this._isVerticalConnection(fromPos, toPos)

    let shiftY = 0
    const spacing = this.DEFAULT_SPACING
    const endBottom = endElement.y + (endElement.height || this.DEFAULT_HEIGHT) / 2
    const childTop = childElement.y - (childElement.height || this.DEFAULT_HEIGHT) / 2
    const requiredChildTop = endBottom + spacing

    if (childTop < requiredChildTop) {
      shiftY = requiredChildTop - childTop
    }

    let shiftX = 0
    if (isVertical) {
      shiftX = endElement.x - childElement.x
    }

    return { shiftX, shiftY }
  }

  /**
   * Calculate child element position shift for fold operation.
   * Determines how child elements should be repositioned when a subflow
   * is folded back to its collapsed state.
   *
   * @param {Object} restoredElement - The restored/folded subflow element
   * @param {number} restoredElement.x - X position of restored element
   * @param {number} restoredElement.y - Y position of restored element
   * @param {number} [restoredElement.width] - Width of restored element
   * @param {number} [restoredElement.height] - Height of restored element
   * @param {Object} childElement - The child element to adjust
   * @param {number} childElement.x - X position of child element
   * @param {number} childElement.y - Y position of child element
   * @param {number} [childElement.width] - Width of child element
   * @param {number} [childElement.height] - Height of child element
   * @param {Object} conn - The connection object
   * @param {string} [conn.fromPosition] - Source connection position
   * @param {string} [conn.toPosition] - Target connection position
   * @returns {Object} Position shift { shiftX, shiftY }
   */
  static calculateChildShiftForFold(restoredElement, childElement, conn) {
    const fromPos = conn.fromPosition || "bottom"
    const toPos = conn.toPosition || "top"
    const isVertical = this._isVerticalConnection(fromPos, toPos)
    const isHorizontal = this._isHorizontalConnection(fromPos, toPos)

    let shiftX = 0
    let shiftY = 0
    const spacing = this.DEFAULT_SPACING

    if (isVertical) {
      shiftX = restoredElement.x - childElement.x
      const subflowBottom = restoredElement.y + (restoredElement.height || this.DEFAULT_HEIGHT) / 2
      const childTop = childElement.y - (childElement.height || this.DEFAULT_HEIGHT) / 2
      const requiredChildTop = subflowBottom + spacing
      shiftY = requiredChildTop - childTop
    } else if (isHorizontal) {
      shiftY = restoredElement.y - childElement.y

      const subflowRight = restoredElement.x + (restoredElement.width || this.DEFAULT_WIDTH) / 2
      const subflowLeft = restoredElement.x - (restoredElement.width || this.DEFAULT_WIDTH) / 2
      const childLeft = childElement.x - (childElement.width || this.DEFAULT_WIDTH) / 2
      const childRight = childElement.x + (childElement.width || this.DEFAULT_WIDTH) / 2

      if (fromPos === "right") {
        const requiredChildLeft = subflowRight + spacing
        shiftX = requiredChildLeft - childLeft
      } else {
        const requiredChildRight = subflowLeft - spacing
        shiftX = requiredChildRight - childRight
      }
    }

    return { shiftX, shiftY }
  }

  /**
   * Calculate child element position shift for restore operation.
   * Used when restoring expanded subflows from saved configuration.
   *
   * @param {Object} subflowElement - The subflow element being restored
   * @param {number} subflowElement.x - X position of subflow element
   * @param {number} subflowElement.y - Y position of subflow element
   * @param {number} [subflowElement.height] - Height of subflow element
   * @param {Object} childElement - The child element to adjust
   * @param {number} childElement.x - X position of child element
   * @param {number} childElement.y - Y position of child element
   * @param {number} [childElement.height] - Height of child element
   * @param {Object} conn - The connection object
   * @param {string} [conn.fromPosition] - Source connection position
   * @param {string} [conn.toPosition] - Target connection position
   * @returns {Object} Position shift { shiftX, shiftY }
   */
  static calculateChildShiftForRestore(subflowElement, childElement, conn) {
    const fromPos = conn.fromPosition || "bottom"
    const toPos = conn.toPosition || "top"
    const isVertical = this._isVerticalConnection(fromPos, toPos)

    let shiftX = 0
    let shiftY = 0
    const spacing = this.DEFAULT_SPACING

    if (isVertical) {
      shiftX = subflowElement.x - childElement.x
      const subflowBottom = subflowElement.y + (subflowElement.height || this.DEFAULT_HEIGHT) / 2
      const childTop = childElement.y - (childElement.height || this.DEFAULT_HEIGHT) / 2
      const requiredChildTop = subflowBottom + spacing
      shiftY = requiredChildTop - childTop
    }

    return { shiftX, shiftY }
  }

  /**
   * Check if connection positions form a vertical connection.
   * @param {string} fromPos - Source position
   * @param {string} toPos - Target position
   * @returns {boolean} True if connection is vertical
   * @private
   */
  static _isVerticalConnection(fromPos, toPos) {
    return (fromPos === "bottom" || fromPos === "top") &&
           (toPos === "top" || toPos === "bottom")
  }

  /**
   * Check if connection positions form a horizontal connection.
   * @param {string} fromPos - Source position
   * @param {string} toPos - Target position
   * @returns {boolean} True if connection is horizontal
   * @private
   */
  static _isHorizontalConnection(fromPos, toPos) {
    return (fromPos === "right" || fromPos === "left") &&
           (toPos === "left" || toPos === "right")
  }
}

export default PositionCalculator
