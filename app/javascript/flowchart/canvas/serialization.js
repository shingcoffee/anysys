/**
 * SerializationMixin - Handles serialization, deserialization, and utility methods
 * for the flowchart canvas. Covers save/load configuration, clear/destroy lifecycle,
 * step/element pin caches, and structure-change events.
 */

import { generateStepId } from "utils"
import { getDefaultPropertiesForType } from "flowchart/constants"

function connectionProperties(connection) {
  const next = { ...(connection.properties || {}) }
  if (next.description == null) next.description = ""
  return next
}

function coerceSubflowProperties(type, properties) {
  const next = { ...properties }
  if (type !== "subflow") return next
  if (next.flowchartId == null || next.flowchartId === "") return next
  const flowchartId = Number(next.flowchartId)
  if (Number.isFinite(flowchartId)) next.flowchartId = flowchartId
  return next
}

export const SerializationMixin = {
  // ===================
  // Utility Methods
  // ===================

  _getSVGPoint(e) {
    return this.zoomPanManager.clientToSVG(e.clientX, e.clientY)
  },

  _findElementAtPoint(x, y) {
    for (let i = this.elements.length - 1; i >= 0; i--) {
      const el = this.elements[i]
      const hw = el.width / 2
      const hh = el.height / 2

      if (x >= el.x - hw && x <= el.x + hw && y >= el.y - hh && y <= el.y + hh) {
        return el
      }
    }
    return null
  },

  _scrollToElement(element) {
    const zpm = this.zoomPanManager
    const padding = 50
    const elRight = element.x + element.width / 2 + padding
    const elBottom = element.y + element.height / 2 + padding
    const viewRight = zpm.panX + zpm.viewWidth
    const viewBottom = zpm.panY + zpm.viewHeight

    let needsUpdate = false
    if (elBottom > viewBottom) {
      zpm.panY = elBottom - zpm.viewHeight + padding
      needsUpdate = true
    }
    if (elRight > viewRight) {
      zpm.panX = elRight - zpm.viewWidth + padding
      needsUpdate = true
    }
    if (needsUpdate) {
      zpm._updateViewBox()
    }
  },

  _updateConnectionsVisually() {
    this.updateConnections()
  },

  // ===================
  // Auto-Layout
  // ===================

  /**
   * Auto-layout all elements in a hierarchical structure.
   * Uses BFS from start element to organize into layers.
   */
  autoLayout() {
    this.layoutManager.autoLayout()
  },

  // ===================
  // Step I/O Pin Cache
  // ===================

  /**
   * Cache the extracted I/O pins for a step action, keyed by step id.
   * @param {string} stepId - The step identifier
   * @param {Object} pins - Pin data with inputs and outputs arrays
   */
  setStepPins(stepId, pins) {
    this.stepPins = { ...this.stepPins, [stepId]: pins }
  },

  /**
   * Retrieve cached I/O pins for a step id. Returns empty pin sets when the
   * cache has not been primed for this step yet, so callers can render
   * safely without guarding the lookup.
   * @param {string} stepId - The step identifier
   * @returns {{inputs: Array, outputs: Array}} Cached pin data
   */
  getStepPins(stepId) {
    return this.stepPins[stepId] || { inputs: [], outputs: [] }
  },

  /**
   * Iterate over every step action nested inside process elements on the
   * canvas, invoking the callback with (step, parentElement) for each.
   * @param {Function} callback - Function invoked as (step, element)
   */
  iterateStepActions(callback) {
    for (const el of this.elements) {
      const steps = el?.properties?.steps || []
      for (const step of steps) {
        callback(step, el)
      }
    }
  },

  /**
   * Cache extracted I/O pins for an element, keyed by element id.
   * @param {string} elementId
   * @param {{inputs: Array, outputs: Array}} pins
   */
  setElementPins(elementId, pins) {
    this.elementPins = { ...this.elementPins, [elementId]: pins }
  },

  /** Retrieve cached I/O pins for an element id, or empty pin sets. */
  getElementPins(elementId) {
    return this.elementPins[elementId] || { inputs: [], outputs: [] }
  },

  /** Iterate over every element on the canvas. */
  iterateElements(callback) {
    for (const el of this.elements) callback(el)
  },

  /**
   * Emit a `flowchartStructureChanged` CustomEvent on the canvas container
   * so listeners (override validator, element pin cache) can react. Callers:
   * element add/remove, connection add/remove, element property edit, step
   * add/remove/edit inside a process element.
   */
  emitStructureChanged(detail = {}) {
    if (!this.svg) return
    this.svg.dispatchEvent(
      new CustomEvent("flowchartStructureChanged", { detail, bubbles: true })
    )
  },

  /**
   * Find a step-action by its stable id across all process elements.
   * Returns { step, element } or null when no step matches.
   * @param {string} stepId - The step identifier to find
   * @returns {{step: Object, element: Object}|null}
   */
  findStepById(stepId) {
    if (!stepId) return null
    for (const el of this.elements) {
      const steps = el?.properties?.steps || []
      for (const step of steps) {
        if (step && step.id === stepId) return { step, element: el }
      }
    }
    return null
  },

  // ===================
  // Connection Routing
  // ===================

  /**
   * Cycle through connection routing modes: straight -> orthogonal -> straight
   */
  cycleConnectionRouting() {
    if (this.canMutate?.() === false) return
    const modes = ["straight", "orthogonal"]
    const currentIndex = modes.indexOf(this.connectionRouting)
    const nextIndex = (currentIndex + 1) % modes.length
    this.connectionRouting = modes[nextIndex]
    this.updateConnections()
  },

  // ===================
  // Serialization
  // ===================

  /**
   * Serialize the canvas state to a JSON-compatible object.
   * Filters out runtime-expanded subflow elements, removes runtime-only properties,
   * and ensures valid output configurations. Used for saving flowchart data.
   * @returns {Object} Serialized canvas state
   * @returns {Array<Object>} returns.elements - Array of element objects with id, type, position, label, and properties
   * @returns {Array<Object>} returns.connections - Array of connection objects with id, from, to, and positions
   * @returns {Object} returns.metadata - Canvas metadata including dimensions and timestamp
   * @example
   * const config = canvas.getConfiguration()
   * // Save to server
   * await fetch('/api/flowcharts', {
   *   method: 'POST',
   *   body: JSON.stringify(config)
   * })
   */
  getConfiguration() {
    // Filter out runtime-expanded subflow elements (marked with _expandedFromSubflow)
    // Keep only original elements and collapsed subflow references
    const filteredElements = this.elements.filter(el => {
      return !el.properties?._expandedFromSubflow
    })

    const elements = filteredElements.map(el => {
      const elementCopy = { ...el }
      const props = { ...(elementCopy.properties || {}) }

      // Remove runtime-only properties
      delete props._expandedFromSubflow
      delete props._originalSubflowData

      elementCopy.properties = coerceSubflowProperties(elementCopy.type, props)
      return elementCopy
    })

    // Filter connections to only include those between saved elements
    const elementIds = new Set(elements.map(el => el.id))
    const connections = this.connections
      .filter(c => elementIds.has(c.from) && elementIds.has(c.to))
      .map(c => ({
        ...c,
        properties: connectionProperties(c)
      }))

    return {
      elements,
      connections,
      metadata: {
        ...this._loadedMetadata,
        connectionRouting: this.connectionRouting
      }
    }
  },

  /**
   * Load a flowchart configuration onto the canvas.
   * Clears existing content, creates elements with default properties merged,
   * establishes connections, and aligns connected elements so lines are straight.
   * @param {Object|string} config - Configuration object or JSON string
   * @param {Array<Object>} config.elements - Array of element definitions
   * @param {Array<Object>} config.connections - Array of connection definitions
   * @example
   * // Load from saved configuration
   * canvas.loadConfiguration({
   *   elements: [
   *     { id: 'e1', type: 'start', x: 400, y: 80 },
   *     { id: 'e2', type: 'process', x: 400, y: 200, label: 'Process' }
   *   ],
   *   connections: [
   *     { id: 'c1', from: 'e1', to: 'e2', fromPosition: 'bottom', toPosition: 'top' }
   *   ]
   * })
   */
  loadConfiguration(config) {
    try {
      const data = typeof config === "string" ? JSON.parse(config) : config
      this.clear()

      // Remember the loaded metadata so keys we don't own (e.g. created_at,
      // canvas size set server-side) round-trip through save untouched.
      // connectionRouting is owned by this class and is overwritten at save.
      this._loadedMetadata = data.metadata ? { ...data.metadata } : {}

      // Restore connection routing mode if saved (migrate legacy "bezier" to "orthogonal")
      if (data.metadata?.connectionRouting) {
        const saved = data.metadata.connectionRouting
        this.connectionRouting = (saved === "bezier") ? "orthogonal" : saved
      }

      data.elements?.forEach(elData => {
        const defaults = getDefaultPropertiesForType(elData.type)
        const element = {
          ...elData,
          x: Math.round(elData.x),
          y: Math.round(elData.y),
          properties: coerceSubflowProperties(elData.type, { ...defaults, ...(elData.properties || {}) })
        }
        // Backfill stable ids on any process steps loaded from legacy
        // flowcharts. The conflict resolver and canvas.stepPins cache both
        // key off step.id — without this, multiple steps would collide
        // under undefined and the cache would be useless.
        if (Array.isArray(element.properties?.steps)) {
          element.properties.steps = element.properties.steps.map(step => (
            step && typeof step === "object" && !step.id
              ? { ...step, id: generateStepId() }
              : step
          ))
        }
        this.elements.push(element)
        this.renderElement(element)
      })

      if (data.connections) {
        this.connections = data.connections.map(c => ({
          ...c,
          properties: connectionProperties(c)
        }))
        this.alignAllElements()
      }
    } catch (error) {
      // A malformed configuration used to silently produce an empty canvas
      // — the user thought their flowchart was deleted. Log + surface a
      // toast so the failure is visible and recoverable (the JSON is still
      // in the DB; the user can refresh after the issue is resolved).
      console.error("[FlowchartCanvas] Failed to load configuration:", error)
      this.onToast?.(this.labels?.loadConfigFailedToast, "error")
    }
  },

  /**
   * Replace the on-canvas graph in place. Used by the property editor to
   * undo a cancelled branch add/remove without resetting zoom/pan, aligning
   * elements, or touching loaded metadata.
   */
  replaceGraph(elements, connections) {
    this.onBeforeChange?.()

    ;[this.elementLayer, this.connectionLayer].forEach(layer => {
      while (layer.firstChild) layer.removeChild(layer.firstChild)
    })

    this.elements = structuredClone(elements || [])
    this.connections = structuredClone(connections || [])
    this.selectedElements = []
    this.selectedConnectionId = null
    this._hideConnectionHandles()
    this._hideConnectionEndpointHandles()
    this.hideResizeHandles?.()

    this.elements.forEach(el => this.renderElement(el))
    this.updateConnections()

    this.onchange?.()
  },

  /**
   * Silently swap in an undo/redo snapshot. Keeps zoom/pan, loaded metadata,
   * connection routing and the selection of elements (and the connection)
   * that still exist. Unlike loadConfiguration it does not realign elements
   * or merge defaults, and unlike replaceGraph it fires no change hooks.
   * @param {{elements: Array<Object>, connections: Array<Object>}} data
   */
  restoreGraph(data) {
    const graph = structuredClone(data || {})
    const selectedIds = new Set(this.selectedElements.map(el => el.id))

    ;[this.elementLayer, this.connectionLayer].forEach(layer => {
      while (layer.firstChild) layer.removeChild(layer.firstChild)
    })

    this.elements = graph.elements || []
    this.connections = graph.connections || []
    this.elements.forEach(el => this.renderElement(el))

    const mutable = this.canMutate?.() !== false
    this.selectedElements = this.elements.filter(el => selectedIds.has(el.id))
    this.selectedElements.forEach(el => this._setElementSelected(el, true))
    if (mutable && this.selectedElements.length > 0) {
      this.showConnectionHandles(this.selectedElements)
    } else {
      this._hideConnectionHandles()
    }
    if (mutable && this.selectedElements.length === 1) {
      this.showResizeHandles?.(this.selectedElements[0])
    } else {
      this.hideResizeHandles?.()
    }

    if (this.selectedConnectionId && !this.connections.some(c => c.id === this.selectedConnectionId)) {
      this.selectedConnectionId = null
    }

    this._hideConnectionEndpointHandles()
    this.updateConnections()

    if (this.selectedElements.length !== selectedIds.size) this.onSelectionChanged?.()
  },

  /**
   * Clear all elements, connections, and selections from the canvas.
   * Resets the canvas to an empty state and scrolls to top-left position.
   */
  clear() {
    ;[this.elementLayer, this.connectionLayer].forEach(layer => {
      while (layer.firstChild) layer.removeChild(layer.firstChild)
    })

    this.elements = []
    this.connections = []
    this.selectedElements = []
    this.selectedConnectionId = null
    this._hideConnectionHandles()
    this._hideConnectionEndpointHandles()

    this.zoomPanManager.resetZoom()
  },

  /**
   * Clean up event listeners and any in-progress interaction state when
   * the canvas is destroyed. Without removing the in-progress drag/draw
   * SVG nodes here, navigating away mid-gesture leaks a dangling SVG
   * element that the next mount sees as a "ghost" connection line.
   */
  destroy() {
    document.removeEventListener("keydown", this._keyDownHandler)
    document.removeEventListener("keyup", this._keyUpHandler)

    this.connectionLine?.remove()
    this.connectionLine = null
    this.connectionDragLine?.remove()
    this.connectionDragLine = null
    this._traceOverlayLayer?.remove()
    this._traceOverlayLayer = null
  },

  render() {
    // No-op - SVG updates immediately
  }
}
