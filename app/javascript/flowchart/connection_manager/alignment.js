/**
 * AlignmentMixin - Keeps connector lines straight by moving the elements at
 * their ends: a vertical edge (bottom→top / top→bottom) shares one X, a
 * horizontal edge (right→left / left→right) shares one Y.
 */

export const AlignmentMixin = {
  /**
   * "vertical", "horizontal", or null for an edge between `fromEl` and `toEl`.
   */
  _connectionOrientation(connection, fromEl, toEl) {
    const fromPos = this._portToCardinal(connection.fromPort || connection.fromPosition || "bottom", fromEl)
    const toPos = this._portToCardinal(connection.toPort || connection.toPosition || "top", toEl)

    if ((fromPos === "bottom" && toPos === "top") || (fromPos === "top" && toPos === "bottom")) return "vertical"
    if ((fromPos === "right" && toPos === "left") || (fromPos === "left" && toPos === "right")) return "horizontal"
    return null
  },

  /**
   * Move `element` into line with `anchor` across `connection`.
   * Returns true when it moved.
   */
  _alignAcross(connection, fromEl, toEl, anchor, element) {
    const orientation = this._connectionOrientation(connection, fromEl, toEl)
    if (orientation === "vertical" && element.x !== anchor.x) {
      element.x = anchor.x
    } else if (orientation === "horizontal" && element.y !== anchor.y) {
      element.y = anchor.y
    } else {
      return false
    }

    this.updateElementPosition(element)
    return true
  },

  /**
   * Align every connected pair, then re-render the connections.
   */
  alignAllElements() {
    this.connections.forEach(conn => this._alignConnectionElements(conn))
    this.updateConnections()
  },

  /**
   * Move a connection's target into line with its source.
   * Returns true when it moved.
   */
  _alignConnectionElements(connection) {
    const fromEl = this.elements.find(el => el.id === connection.from)
    const toEl = this.elements.find(el => el.id === connection.to)
    if (!fromEl || !toEl) return false

    return this._alignAcross(connection, fromEl, toEl, fromEl, toEl)
  },

  /**
   * Move `element` into line with its parent (first incoming connection).
   * Returns true when it moved.
   */
  alignElementWithParent(element) {
    const parentConn = this.connections.find(c => c.to === element.id)
    const parentEl = parentConn && this.elements.find(el => el.id === parentConn.from)
    if (!parentEl) return false

    return this._alignAcross(parentConn, parentEl, element, parentEl, element)
  },

  /**
   * Move every child of `element` into line with it, recursively down each
   * child that moved.
   */
  alignChildElements(element, visited = new Set()) {
    if (visited.has(element.id)) return
    visited.add(element.id)

    this.connections.filter(c => c.from === element.id).forEach(conn => {
      const childEl = this.elements.find(el => el.id === conn.to)
      if (!childEl) return
      if (this._alignAcross(conn, element, childEl, element, childEl)) {
        this.alignChildElements(childEl, visited)
      }
    })
  },

  /**
   * Snap a newly-connected decision branch box onto the row shared by the
   * decision's other branch boxes (most common Y; ties go to the topmost).
   * Only the new box moves. No-op for the first branch.
   */
  _alignNewBranchToRow(decisionElement, newElementId) {
    if (!newElementId) return
    const newEl = this.elements.find(el => el.id === newElementId)
    if (!newEl) return

    const otherYs = this.connections
      .filter(c => c.from === decisionElement.id && c.to !== newElementId)
      .map(c => this.elements.find(el => el.id === c.to))
      .filter(Boolean)
      .map(el => el.y)
    if (otherYs.length === 0) return

    const counts = new Map()
    for (const y of otherYs) counts.set(y, (counts.get(y) || 0) + 1)
    let rowY = otherYs[0]
    let bestCount = 0
    for (const [y, count] of counts) {
      if (count > bestCount || (count === bestCount && y < rowY)) {
        rowY = y
        bestCount = count
      }
    }

    if (newEl.y === rowY) return
    newEl.y = rowY
    this.updateElementPosition(newEl)
  }
}
