/**
 * CanvasStateMixin provides canvas-level state capture/restore and UI utilities.
 * Apply to a class using Object.assign(YourClass.prototype, CanvasStateMixin)
 */
export const CanvasStateMixin = {
  /**
   * Capture complete canvas state for restoration.
   */
  captureCompleteCanvasState() {
    const canvas = this.controller.canvas
    return {
      elements: canvas.elements.map(el => ({
        ...el,
        properties: el.properties ? { ...el.properties } : {}
      })),
      connections: canvas.connections.map(c => ({ ...c })),
      expandedSubflows: { ...this.expandedSubflows }
    }
  },

  /**
   * Restore complete canvas state after save.
   */
  restoreCompleteCanvasState(savedState) {
    if (!savedState) return

    const canvas = this.controller.canvas

    // Clear all current elements
    while (canvas.elementLayer.firstChild) {
      canvas.elementLayer.removeChild(canvas.elementLayer.firstChild)
    }

    // Clear all current connections
    while (canvas.connectionLayer.firstChild) {
      canvas.connectionLayer.removeChild(canvas.connectionLayer.firstChild)
    }

    // Restore elements
    canvas.elements = savedState.elements.map(el => ({
      ...el,
      properties: el.properties ? { ...el.properties } : {}
    }))

    // Restore connections
    canvas.connections = savedState.connections.map(c => ({ ...c }))

    // Restore expandedSubflows
    this.expandedSubflows = { ...savedState.expandedSubflows }

    // Re-render all elements
    canvas.elements.forEach(el => {
      canvas.renderElement(el)
    })

    // Re-render all connections
    canvas.updateConnections()

    // Re-attach fold icons on any Start elements that represent an active
    // expansion. Without this step, after restoring the complete state the
    // user sees expanded content but has no visible control to collapse it
    // again — the only escape is a full page reload.
    Object.entries(this.expandedSubflows).forEach(([subflowId, data]) => {
      const startEl = canvas.elements.find(el => el.id === data.startElementId)
      if (startEl) this.addFoldIconToElement(startEl, subflowId)
    })
  },

  /**
   * Add fold icon to an element.
   */
  addFoldIconToElement(element, originalSubflowId) {
    const canvas = this.controller.canvas
    const group = canvas.elementLayer.querySelector(`[data-element-id="${element.id}"]`)
    if (!group) return

    // Check if fold icon already exists
    const existingIcon = group.querySelector(".fold-icon")
    if (existingIcon) return

    // Create fold icon group
    const foldIcon = document.createElementNS("http://www.w3.org/2000/svg", "g")
    foldIcon.setAttribute("class", "fold-icon")
    foldIcon.setAttribute("data-fold-subflow", originalSubflowId)
    foldIcon.style.cursor = "pointer"

    // Position at top-right
    const iconX = element.width - 8
    const iconY = -8

    // Background circle
    const circle = document.createElementNS("http://www.w3.org/2000/svg", "circle")
    circle.setAttribute("cx", iconX)
    circle.setAttribute("cy", iconY)
    circle.setAttribute("r", "10")
    circle.setAttribute("fill", "#06b6d4")
    circle.setAttribute("stroke", "#0891b2")
    circle.setAttribute("stroke-width", "2")
    foldIcon.appendChild(circle)

    // Fold arrow icon
    const arrow = document.createElementNS("http://www.w3.org/2000/svg", "path")
    arrow.setAttribute("d", `M${iconX - 4} ${iconY + 2} L${iconX} ${iconY - 3} L${iconX + 4} ${iconY + 2}`)
    arrow.setAttribute("fill", "none")
    arrow.setAttribute("stroke", "white")
    arrow.setAttribute("stroke-width", "2")
    arrow.setAttribute("stroke-linecap", "round")
    arrow.setAttribute("stroke-linejoin", "round")
    foldIcon.appendChild(arrow)

    // Add hover effect
    foldIcon.addEventListener("mouseenter", () => {
      circle.setAttribute("fill", "#0891b2")
      circle.setAttribute("r", "12")
    })
    foldIcon.addEventListener("mouseleave", () => {
      circle.setAttribute("fill", "#06b6d4")
      circle.setAttribute("r", "10")
    })

    // Add click handler
    foldIcon.addEventListener("click", (e) => {
      e.stopPropagation()
      this.foldSubflow(originalSubflowId)
    })

    group.appendChild(foldIcon)
  },

  /**
   * Shift an element and its subtree by delta without grid snapping.
   */
  shiftElementAndSubTreeDirect(element, deltaX, deltaY) {
    const canvas = this.controller.canvas
    if (!canvas) return

    const subTree = canvas._getSubTreeElements ? canvas._getSubTreeElements(element.id) : []

    // Shift main element
    element.x = Math.round(element.x + deltaX)
    element.y = Math.round(element.y + deltaY)
    canvas.updateElementPosition(element)

    // Shift subtree elements
    for (const { id } of subTree) {
      const child = canvas.elements.find(el => el.id === id)
      if (child) {
        child.x = Math.round(child.x + deltaX)
        child.y = Math.round(child.y + deltaY)
        canvas.updateElementPosition(child)
      }
    }

    canvas.updateConnections()
  }
}
