import { PositionCalculator } from "controllers/flowchart_canvas/position_calculator"

/**
 * FoldRestoreMixin provides subflow fold-back and configuration-restore logic.
 * Apply to a class using Object.assign(YourClass.prototype, FoldRestoreMixin)
 */
export const FoldRestoreMixin = {
  /**
   * Fold an expanded subflow back to its collapsed state.
   */
  foldSubflow(originalSubflowId) {
    const expandedData = this.expandedSubflows[originalSubflowId]
    if (!expandedData) {
      return
    }

    const remaining = Object.keys(this.expandedSubflows).length
    if (remaining === 1) {
      delete this.expandedSubflows[originalSubflowId]
      this.controller._leavePreviewMode?.({ restore: true })
      return
    }

    const { elements, originalElement, incomingConnections, outgoingConnections } = expandedData
    const canvas = this.controller.canvas

    // Remove all expanded elements
    elements.forEach(el => {
      const index = canvas.elements.findIndex(e => e.id === el.id)
      if (index !== -1) {
        canvas.elements.splice(index, 1)
      }
      const group = canvas.elementLayer.querySelector(`[data-element-id="${el.id}"]`)
      if (group) group.remove()
    })

    // Remove connections related to expanded elements
    const expandedElementIds = elements.map(el => el.id)
    canvas.connections = canvas.connections.filter(conn => {
      return !expandedElementIds.includes(conn.from) && !expandedElementIds.includes(conn.to)
    })

    // Restore the original subflow element from the expand-time snapshot.
    // Preview mode is read-only, so there are no live edits to copy back.
    const restoredElement = {
      ...originalElement,
      x: originalElement.x,
      y: originalElement.y,
      properties: { ...(originalElement.properties || {}) }
    }

    canvas.elements.push(restoredElement)
    canvas.renderElement(restoredElement)

    // Restore incoming connections
    incomingConnections.forEach(conn => {
      const restoredConn = {
        ...conn,
        to: originalSubflowId
      }
      canvas.connections.push(restoredConn)
    })

    // Restore outgoing connections and adjust child positions
    outgoingConnections.forEach(conn => {
      const childElement = canvas.elements.find(el => el.id === conn.to)

      if (childElement) {
        this._adjustChildElementPositionForFold(restoredElement, childElement, conn)
      }

      const restoredConn = {
        ...conn,
        from: originalSubflowId
      }
      canvas.connections.push(restoredConn)
    })

    canvas.updateConnections()

    // Clean up expanded state
    delete this.expandedSubflows[originalSubflowId]
  },

  /**
   * Restore expanded subflows from saved configuration.
   */
  restoreExpandedSubflowsFromConfiguration() {
    const canvas = this.controller.canvas

    // Group elements by their _expandedFromSubflow property
    const subflowGroups = {}
    canvas.elements.forEach(el => {
      const subflowId = el.properties?._expandedFromSubflow
      if (subflowId) {
        if (!subflowGroups[subflowId]) {
          subflowGroups[subflowId] = []
        }
        subflowGroups[subflowId].push(el)
      }
    })

    const subflowCount = Object.keys(subflowGroups).length
    if (subflowCount === 0) return

    // Fold each expanded subflow back to its collapsed state
    Object.entries(subflowGroups).forEach(([subflowId, elements]) => {
      const startElement = elements.find(el => el.type === "start")
      const endElement = elements.find(el => el.type === "end")

      if (!startElement) return

      const originalData = startElement.properties?._originalSubflowData || {}

      // Find incoming connections to Start element
      const incomingConnections = canvas.connections
        .filter(c => c.to === startElement.id)
        .map(c => ({
          ...c,
          id: c.id.replace(/_to_start$/, ''),
          to: subflowId
        }))

      // Find outgoing connections from End element
      const outgoingConnections = endElement ? canvas.connections
        .filter(c => c.from === endElement.id)
        .map(c => ({
          ...c,
          id: c.id.replace(/_from_end$/, ''),
          from: subflowId
        })) : []

      // Remove expanded elements
      elements.forEach(el => {
        const index = canvas.elements.findIndex(e => e.id === el.id)
        if (index !== -1) {
          canvas.elements.splice(index, 1)
        }
        const group = canvas.elementLayer.querySelector(`[data-element-id="${el.id}"]`)
        if (group) group.remove()
      })

      // Remove connections related to expanded elements
      const expandedElementIds = elements.map(el => el.id)
      canvas.connections = canvas.connections.filter(conn => {
        return !expandedElementIds.includes(conn.from) && !expandedElementIds.includes(conn.to)
      })

      // Get End element's signalWiring/dataMappings + Start element's
      // varMappings to use for the folded subflow. varMappings live on the
      // Start element of the expanded inner flow and must round-trip through
      // `restoreExpandedSubflowsFromConfiguration` or they'd be lost on
      // page reload.
      const signalWiring = endElement?.properties?.signalWiring
      const dataMappings = endElement?.properties?.dataMappings
      const varMappings  = startElement?.properties?.varMappings

      // Build subflow properties
      const subflowProperties = {
        flowchartId: originalData.flowchartId,
        inputs: [],
        description: ""
      }

      // Save signalWiring and dataMappings with their own property names (like varMappings)
      // Deep clone to ensure all entries are preserved
      if (signalWiring !== undefined) {
        subflowProperties.signalWiring = JSON.parse(JSON.stringify(signalWiring))
        subflowProperties.dataMappings = JSON.parse(JSON.stringify(dataMappings || []))
      } else {
        // Default: empty arrays
        subflowProperties.signalWiring = []
        subflowProperties.dataMappings = []
      }

      if (varMappings !== undefined) {
        subflowProperties.varMappings = JSON.parse(JSON.stringify(varMappings))
      }

      // Create folded subflow element
      const subflowElement = {
        id: subflowId,
        type: "subflow",
        x: startElement.x,
        y: startElement.y,
        width: originalData.width || 100,
        height: originalData.height || 45,
        label: originalData.label || this.controller.elementDefaultLabelsValue.subflow,
        properties: subflowProperties
      }

      canvas.elements.push(subflowElement)
      canvas.renderElement(subflowElement)

      // Restore incoming connections
      incomingConnections.forEach(conn => {
        canvas.connections.push({
          ...conn,
          to: subflowId
        })
      })

      // Restore outgoing connections
      outgoingConnections.forEach(conn => {
        const childElement = canvas.elements.find(el => el.id === conn.to)

        if (childElement) {
          const { shiftX, shiftY } = PositionCalculator.calculateChildShiftForRestore(subflowElement, childElement, conn)

          if (shiftX !== 0 || shiftY !== 0) {
            this.shiftElementAndSubTreeDirect(childElement, shiftX, shiftY)
          }
        }

        canvas.connections.push({
          ...conn,
          from: subflowId
        })
      })
    })

    if (subflowCount > 0) {
      canvas.updateConnections()
    }
  }
}
