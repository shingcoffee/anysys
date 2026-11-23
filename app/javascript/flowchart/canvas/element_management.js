/**
 * ElementManagementMixin - Handles element CRUD operations for the flowchart canvas.
 * Covers add, delete, paste, update, and auto-connection logic.
 */

import { generateId, snapToGrid } from "utils"
import {
  GRID_SIZE,
  DEFAULT_ELEMENT_WIDTH,
  DEFAULT_ELEMENT_HEIGHT,
  DEFAULT_ELEMENT_SPACING,
  SUPPORTED_ELEMENT_TYPES,
  getDefaultPropertiesForType
} from "flowchart/constants"
import { uniqueLabel } from "flowchart/labels"

export const ElementManagementMixin = {
  /**
   * Add a new element to the canvas.
   * Automatically positions the element below the last element if no position specified,
   * creates a connection from the previous element, and scrolls to show the new element.
   * @param {Object} elementData - Element configuration
   * @param {string} elementData.type - Supported element type
   * @param {string} [elementData.id] - Optional element ID (auto-generated if not provided)
   * @param {string} [elementData.label] - Display label (defaults to type-specific label)
   * @param {number} [elementData.x] - X position (auto-calculated if not provided)
   * @param {number} [elementData.y] - Y position (auto-calculated if not provided)
   * @param {Object} [elementData.properties] - Element-specific properties
   * @returns {Object} The created element with generated id, position, and dimensions
   * @example
   * // Add a process element
   * canvas.addElement({ type: 'process', label: 'My Process' })
   *
   * // Add a decision element with custom properties
   * canvas.addElement({
   *   type: 'decision',
   *   properties: { condition: { expression: 'ctx.valid?' } }
   * })
   */
  addElement(elementData) {
    if (this.canMutate?.() === false) return null
    if (!SUPPORTED_ELEMENT_TYPES.includes(elementData.type)) return null

    // Enforce single Start element constraint
    if (elementData.type === "start" && this.hasStartElement()) {
      this.onToast?.(this.labels?.onlyOneStartAllowedToast, "warning")
      return null
    }

    this.onBeforeChange?.()

    const position = this._calculateElementPosition(elementData)
    const defaults = getDefaultPropertiesForType(elementData.type)
    const properties = { ...defaults, ...(elementData.properties || {}) }

    const element = {
      id: elementData.id || generateId(),
      type: elementData.type,
      x: Math.round(position.x),
      y: Math.round(position.y),
      width: DEFAULT_ELEMENT_WIDTH,
      height: DEFAULT_ELEMENT_HEIGHT,
      label: this._newElementLabel(elementData),
      properties
    }

    const previousElement = this.elements[this.elements.length - 1]
    const positioned = Number.isFinite(elementData.x) && Number.isFinite(elementData.y)
    this.elements.push(element)
    this.renderElement(element)

    if (previousElement && !positioned && this._shouldAutoConnect(previousElement)) {
      this._autoConnectElements(previousElement, element)
    }

    this._scrollToElement(element)
    this.onchange?.()

    return element
  },

  /** The requested or type-default label, numbered when another element already uses it. */
  _newElementLabel(elementData) {
    const base = elementData.label || this.labels?.elementDefaultLabels?.[elementData.type] || elementData.type
    return uniqueLabel(this.elements, base, this.labels?.uniqueLabelFormat)
  },

  _calculateElementPosition(elementData) {
    const previousElement = this.elements[this.elements.length - 1]

    // Honor an explicit drop position. Drag-and-drop onto empty canvas passes
    // the resolved SVG coordinates (see element_palette_controller#_handleDrop);
    // without this they were discarded and the element snapped below the last
    // one regardless of where the user dropped it. Callers that append
    // programmatically omit x/y and still fall through to auto-stacking.
    if (Number.isFinite(elementData.x) && Number.isFinite(elementData.y)) {
      return {
        x: snapToGrid(elementData.x, GRID_SIZE),
        y: snapToGrid(elementData.y, GRID_SIZE)
      }
    }

    if (previousElement) {
      // Position directly below previous element with consistent spacing.
      // Center-to-center distance = half heights + spacing
      const centerToCenter = previousElement.height / 2 + DEFAULT_ELEMENT_SPACING + DEFAULT_ELEMENT_HEIGHT / 2
      return {
        x: snapToGrid(previousElement.x, GRID_SIZE),
        y: snapToGrid(previousElement.y + centerToCenter, GRID_SIZE)
      }
    } else {
      return {
        x: snapToGrid(elementData.x || 400, GRID_SIZE),
        y: snapToGrid(elementData.y || 80, GRID_SIZE)
      }
    }
  },

  /**
   * An End has no outgoing edge, and an element that already leads somewhere
   * keeps its edge (a decision's next branch would land on its first one).
   */
  _shouldAutoConnect(from) {
    if (!from || from.type === "end") return false
    return !this.connections.some(c => c.from === from.id)
  },

  _autoConnectElements(from, to) {
    let fromPos = "bottom"
    let toPos = "top"

    if (Math.abs(from.y - to.y) < 30) {
      fromPos = to.x > from.x ? "right" : "left"
      toPos = to.x > from.x ? "left" : "right"
    }

    this.createConnection(from, to, fromPos, toPos)
  },

  /**
   * Delete an element from the canvas.
   * Removes the element, its visual representation, all associated connections,
   * and removes it from selection if selected.
   * @param {Object} element - The element object to delete
   * @param {string} element.id - The element's unique identifier
   * @private
   */
  _deleteElement(element) {
    const index = this.elements.findIndex(el => el.id === element.id)
    if (index === -1) return

    this.elements.splice(index, 1)

    const group = this.elementLayer.querySelector(`[data-element-id="${element.id}"]`)
    group?.remove()

    this.connections = this.connections.filter(
      c => c.from !== element.id && c.to !== element.id
    )
    this.updateConnections()

    const selIndex = this.selectedElements.findIndex(el => el.id === element.id)
    if (selIndex !== -1) this.selectedElements.splice(selIndex, 1)

    this._hideConnectionHandles()
  },

  /**
   * Paste elements and connections from clipboard manager results.
   * Adds pasted elements to canvas, updates connections, and selects the pasted elements.
   * @param {Object|null} pasteResult - Result from ClipboardManager paste/duplicate
   * @param {Array<Object>} pasteResult.elements - Elements to paste
   * @param {Array<Object>} pasteResult.connections - Connections to paste
   * @private
   */
  _pasteElements(pasteResult) {
    if (this.canMutate?.() === false) return
    if (!pasteResult) return

    // Enforce the single-Start invariant: if the canvas already has a Start
    // element, silently drop any Start elements in the paste payload (and
    // the connections that referenced them) so the paste does not create a
    // second root that the validator would flag — or worse, ship a broken
    // flowchart to the server because save() does not block on validation.
    let elements = pasteResult.elements
    let connections = pasteResult.connections
    const droppedElementIds = new Set(
      elements
        .filter(el => !SUPPORTED_ELEMENT_TYPES.includes(el.type))
        .map(el => el.id)
    )

    if (this.hasStartElement()) {
      elements
        .filter(el => el.type === "start")
        .forEach(el => droppedElementIds.add(el.id))
    }

    if (droppedElementIds.size > 0) {
      elements = elements.filter(el => !droppedElementIds.has(el.id))
      connections = connections.filter(
        c => !droppedElementIds.has(c.from) && !droppedElementIds.has(c.to)
      )
    }

    if (elements.length === 0) return

    this.onBeforeChange?.()
    this._clearSelection()

    for (const el of elements) {
      this.elements.push(el)
      this.renderElement(el)
      this._addToSelection(el)
    }

    for (const conn of connections) {
      this.connections.push(conn)
    }

    this.updateConnections()
    this.onchange?.()
    this.onElementSelected?.(elements[elements.length - 1])
  },

  /**
   * Update an existing element's label and/or properties.
   * Triggers change callbacks and propagates output changes to connected child elements.
   * @param {string} elementId - The ID of the element to update
   * @param {string} [newLabel] - New display label (undefined to keep existing)
   * @param {Object} [newProperties] - Properties to merge with existing properties
   * @param {boolean} [replaceProperties=false] - Full editor snapshot; omitted keys are deletions
   * @returns {Object|undefined} The updated element, or undefined if element not found
   * @example
   * // Update element label
   * canvas.updateElementProperties('elem-123', 'New Label')
   *
   * // Update element properties
   * canvas.updateElementProperties('elem-123', undefined, {
   *   steps: [{ action: 'validate_contract' }],
   *   outputs: [{ value: 'result' }]
   * })
   */
  updateElementProperties(elementId, newLabel, newProperties, replaceProperties = false) {
    const element = this.elements.find(el => el.id === elementId)
    if (!element) return

    this.onBeforeChange?.()

    if (newLabel !== undefined) element.label = newLabel
    if (newProperties !== undefined) {
      element.properties = replaceProperties ? { ...newProperties } : { ...element.properties, ...newProperties }
    }

    this._rerenderElement(element)

    this.onchange?.()
    this.emitStructureChanged({ elementId })

    return element
  },

  /**
   * Replace an element's rendered group with a fresh render (shape, label,
   * comment dot, subflow toggle, size), keeping its stacking position, its
   * state classes (selection, search highlight), its validation ring and a
   * subflow fold icon.
   */
  _rerenderElement(element) {
    const selector = `[data-element-id="${CSS.escape(String(element.id))}"]`
    const group = this.elementLayer.querySelector(selector)
    if (!group) return

    const anchor = group.nextSibling
    const className = group.getAttribute("class")
    const severity = group.querySelector("[data-validation-ring]")?.dataset.validationSeverity
    const foldIcon = group.querySelector(".fold-icon")
    group.remove()

    this.renderElement(element)
    const fresh = this.elementLayer.querySelector(selector)
    this.elementLayer.insertBefore(fresh, anchor)
    if (className) fresh.setAttribute("class", className)
    if (foldIcon) fresh.appendChild(foldIcon)
    if (severity) this.setValidationState(element.id, severity)
  }
}
