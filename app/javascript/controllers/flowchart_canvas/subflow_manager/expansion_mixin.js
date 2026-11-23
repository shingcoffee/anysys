import { getCSRFToken } from "utils"
import { flowchartShowUrl } from "flowchart/urls"
import { PositionCalculator } from "controllers/flowchart_canvas/position_calculator"

/**
 * ExpansionMixin provides the core subflow expand/fold-build logic.
 * Apply to a class using Object.assign(YourClass.prototype, ExpansionMixin)
 */
export const ExpansionMixin = {
  /**
   * Internal method that handles subflow expansion with configurable options.
   * @param {Object} subflowElement - The subflow element to expand
   * @param {Object} options - Configuration options
   * @param {boolean} options.checkInvokeActivity - Whether to check parent for invoke_activity step
   * @param {boolean} options.dispatchEvents - Whether to dispatch configuration change events
   * @private
   */
  async _expandSubflowInternal(subflowElement, options = {}) {
    const { checkInvokeActivity = true } = options
    const flowchartId = subflowElement.properties?.flowchartId

    if (!flowchartId) {
      return
    }

    // Refuse to expand a subflow that references the current flowchart
    // (self-reference). Expanding would duplicate the same subflow element
    // inside itself, which on each subsequent click would compound — and
    // during expandAllSubflowsForSave, a single pass would still inline a
    // flowchart that's already on the canvas. Saving and editing both
    // become unrecoverable. Compare as strings so number/string equality
    // works regardless of how the canvas stored the value.
    const currentFlowchartId = this.controller.idValue
    if (currentFlowchartId && String(flowchartId) === String(currentFlowchartId)) {
      this.controller.canvas.onToast?.(this.controller.subflowSelfReferenceToastValue, "error")
      return
    }

    try {
      // Fetch the subflow's flowchart configuration from the server
      const configuration = await this._fetchSubflowConfiguration(flowchartId)
      if (!configuration || !configuration.elements || configuration.elements.length === 0) {
        return
      }

      const canvas = this.controller.canvas

      if (Object.keys(this.expandedSubflows).length === 0) {
        this.controller._enterPreviewMode?.()
      }

      // Find incoming and outgoing connections
      const incomingConnections = canvas.connections.filter(c => c.to === subflowElement.id)
      const outgoingConnections = canvas.connections.filter(c => c.from === subflowElement.id)

      // Calculate position offset
      const subflowElements = configuration.elements
      const { offsetX, offsetY } = PositionCalculator.calculateExpansionOffset(subflowElement, subflowElements)

      // Find parent outputs (used to detect invoke_activity chains) and optionally check invoke_activity
      const { parentOutputs, parentHasInvokeActivity } = this._getParentInfo(
        incomingConnections,
        canvas,
        checkInvokeActivity
      )

      // Create expanded elements
      const expandedElements = this._createExpandedElements(
        subflowElements,
        subflowElement,
        flowchartId,
        offsetX,
        offsetY,
        parentOutputs,
        parentHasInvokeActivity,
        canvas
      )

      // Create internal connections
      this._createInternalConnections(configuration.connections, subflowElement.id, canvas)

      // Find Start and End elements
      const startElement = expandedElements.find(el => el.type === "start") || expandedElements[0]
      const endElement = expandedElements.find(el => el.type === "end") || expandedElements[expandedElements.length - 1]

      // Reconnect incoming connections to Start element
      this._reconnectIncomingConnections(incomingConnections, startElement, canvas)

      // Reconnect outgoing connections from End element (captures original positions before shifting)
      const shiftedElementPositions = this._reconnectOutgoingConnections(outgoingConnections, endElement, canvas)

      // Remove the original subflow element
      this._removeSubflowElement(subflowElement)

      // Update connections
      canvas.updateConnections()

      // Store expanded state including original positions of shifted elements
      this.expandedSubflows[subflowElement.id] = {
        elements: expandedElements,
        originalElement: { ...subflowElement },
        incomingConnections: incomingConnections.map(c => ({ ...c })),
        outgoingConnections: outgoingConnections.map(c => ({ ...c })),
        startElementId: startElement?.id,
        endElementId: endElement?.id,
        shiftedElementPositions
      }

      // Add fold icon to Start element
      if (startElement) {
        this.addFoldIconToElement(startElement, subflowElement.id)
      }

    } catch (error) {
      console.error("SubflowManager: Failed to expand subflow", error)
    }
  },

  /**
   * Fetch and parse subflow configuration from the server.
   * @param {string} flowchartId - The flowchart ID to fetch
   * @returns {Object|null} The parsed configuration or null if failed
   * @private
   */
  async _fetchSubflowConfiguration(flowchartId) {
    const url = flowchartShowUrl(this.controller, flowchartId)
    if (!url) return null
    const response = await fetch(url, {
      method: "GET",
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": getCSRFToken()
      },
      credentials: "same-origin"
    })

    if (!response.ok) {
      console.error(`SubflowManager: Failed to fetch flowchart ${flowchartId}, status: ${response.status}`)
      return null
    }

    const data = await response.json()
    let configuration = data.configuration

    if (typeof configuration === "string") {
      try {
        configuration = JSON.parse(configuration)
      } catch (parseError) {
        console.error("SubflowManager: Failed to parse configuration JSON", parseError)
        return null
      }
    }

    return configuration
  },

  /**
   * Get parent element information including outputs and invoke_activity status.
   * @private
   */
  _getParentInfo(incomingConnections, canvas, checkInvokeActivity) {
    let parentOutputs = []
    let parentHasInvokeActivity = false

    if (incomingConnections.length > 0) {
      const parentElementId = incomingConnections[0].from
      const parentElement = canvas.elements.find(el => el.id === parentElementId)

      if (parentElement?.properties?.outputs) {
        parentOutputs = parentElement.properties.outputs
      }

      if (checkInvokeActivity && parentElement?.type === "process") {
        const steps = parentElement.properties?.steps || []
        parentHasInvokeActivity = steps.some(step => step.action === "invoke_activity")
      }
    }

    return { parentOutputs, parentHasInvokeActivity }
  },

  /**
   * Create expanded elements from subflow configuration.
   * @private
   */
  _createExpandedElements(subflowElements, subflowElement, flowchartId, offsetX, offsetY, parentOutputs, parentHasInvokeActivity, canvas) {
    const expandedElements = []

    // Extract keyword parameters from all Process element steps in the subflow
    const keywordParams = this._extractKeywordParamsFromSubflow(subflowElements)

    subflowElements.forEach((el) => {
      const newElement = {
        id: `${subflowElement.id}_sub_${el.id}`,
        type: el.type,
        x: (el.x || 0) + offsetX,
        y: (el.y || 0) + offsetY,
        width: el.width || 100,
        height: el.height || 45,
        label: el.label || el.type,
        properties: { ...(el.properties || {}), _expandedFromSubflow: subflowElement.id }
      }

      // Store original subflow data in Start element
      if (el.type === "start") {
        newElement.properties._originalSubflowData = {
          label: subflowElement.label,
          flowchartId: flowchartId,
          width: subflowElement.width,
          height: subflowElement.height,
          keywordParams: keywordParams
        }
        // Copy varMappings from subflow element to Start element (restore saved mappings)
        if (subflowElement.properties?.varMappings) {
          newElement.properties.varMappings = [...subflowElement.properties.varMappings]
        }
      }

      // Copy signalWiring and dataMappings to End element
      if (el.type === "end") {
        // Copy signalWiring from subflow element (new structure)
        // Deep clone to ensure all entries are preserved
        if (subflowElement.properties?.signalWiring) {
          newElement.properties.signalWiring = JSON.parse(JSON.stringify(subflowElement.properties.signalWiring))
        }
        // Copy dataMappings if they exist on the subflow element
        if (subflowElement.properties?.dataMappings) {
          newElement.properties.dataMappings = JSON.parse(JSON.stringify(subflowElement.properties.dataMappings))
        }
      }


      expandedElements.push(newElement)
      canvas.elements.push(newElement)
      canvas.renderElement(newElement)
    })

    return expandedElements
  },

  /**
   * Create internal connections within the expanded subflow.
   * @private
   */
  _createInternalConnections(connections, subflowId, canvas) {
    if (!connections || connections.length === 0) return

    connections.forEach(conn => {
      const newConnection = {
        id: `${subflowId}_conn_${conn.id}`,
        from: `${subflowId}_sub_${conn.from}`,
        to: `${subflowId}_sub_${conn.to}`,
        fromPosition: conn.fromPosition || "bottom",
        toPosition: conn.toPosition || "top"
      }
      canvas.connections.push(newConnection)
    })
  },

  /**
   * Reconnect incoming connections to the Start element.
   * @private
   */
  _reconnectIncomingConnections(incomingConnections, startElement, canvas) {
    if (!startElement) return

    incomingConnections.forEach(conn => {
      const newConnection = {
        id: `${conn.id}_to_start`,
        from: conn.from,
        to: startElement.id,
        fromPosition: conn.fromPosition || "bottom",
        toPosition: "top"
      }
      canvas.connections.push(newConnection)
    })
  },

  /**
   * Reconnect outgoing connections from the End element.
   * Returns the original positions of shifted elements for save restoration.
   * @private
   */
  _reconnectOutgoingConnections(outgoingConnections, endElement, canvas) {
    const shiftedElementPositions = {}

    if (!endElement) return shiftedElementPositions

    outgoingConnections.forEach(conn => {
      const childElement = canvas.elements.find(el => el.id === conn.to)

      if (childElement) {
        // Store original position before shifting
        this._captureSubtreePositions(childElement, canvas, shiftedElementPositions)
        this._adjustChildElementPosition(endElement, childElement, conn)
      }

      const newConnection = {
        id: `${conn.id}_from_end`,
        from: endElement.id,
        to: conn.to,
        fromPosition: "bottom",
        toPosition: conn.toPosition || "top"
      }
      canvas.connections.push(newConnection)
    })

    return shiftedElementPositions
  },

  /**
   * Capture positions of an element and its subtree before shifting.
   * @private
   */
  _captureSubtreePositions(element, canvas, positions) {
    // Store main element position if not already captured
    if (!positions[element.id]) {
      positions[element.id] = { x: element.x, y: element.y }
    }

    // Store subtree positions
    const subTree = canvas._getSubTreeElements ? canvas._getSubTreeElements(element.id) : []
    for (const { id } of subTree) {
      if (!positions[id]) {
        const child = canvas.elements.find(el => el.id === id)
        if (child) {
          positions[id] = { x: child.x, y: child.y }
        }
      }
    }
  },

  _removeSubflowElement(subflowElement) {
    const canvas = this.controller.canvas

    // Remove connections
    canvas.connections = canvas.connections.filter(
      c => c.from !== subflowElement.id && c.to !== subflowElement.id
    )

    // Remove element from array
    const index = canvas.elements.findIndex(e => e.id === subflowElement.id)
    if (index !== -1) {
      canvas.elements.splice(index, 1)
    }

    // Remove visual element
    const group = canvas.elementLayer.querySelector(`[data-element-id="${subflowElement.id}"]`)
    if (group) {
      group.remove()
    }
  },

  _adjustChildElementPosition(endElement, childElement, conn) {
    const { shiftX, shiftY } = PositionCalculator.calculateChildShiftForExpansion(endElement, childElement, conn)

    if (shiftX !== 0 || shiftY !== 0) {
      this.shiftElementAndSubTreeDirect(childElement, shiftX, shiftY)
    }
  },

  _adjustChildElementPositionForFold(restoredElement, childElement, conn) {
    const { shiftX, shiftY } = PositionCalculator.calculateChildShiftForFold(restoredElement, childElement, conn)

    if (shiftX !== 0 || shiftY !== 0) {
      this.shiftElementAndSubTreeDirect(childElement, shiftX, shiftY)
    }
  },

  /**
   * Extract keyword parameters from all Process element steps in the subflow.
   * @param {Array} subflowElements - The elements from the subflow configuration
   * @returns {Array} Array of unique keyword parameter names
   * @private
   */
  _extractKeywordParamsFromSubflow(subflowElements) {
    const keywordParams = []

    // Find all Process elements in the subflow
    const processElements = subflowElements.filter(el => el.type === "process")

    // Extract keyword parameters from each Process element's steps
    processElements.forEach(processEl => {
      const steps = processEl.properties?.steps || []
      steps.forEach(step => {
        const stepKeywordParams = step.keywordParams || []
        // Handle both array of strings and array of objects
        stepKeywordParams.forEach(param => {
          const paramValue = typeof param === "string" ? param : param.value || param
          if (paramValue && !keywordParams.includes(paramValue)) {
            keywordParams.push(paramValue)
          }
        })
      })
    })

    return keywordParams
  }
}
