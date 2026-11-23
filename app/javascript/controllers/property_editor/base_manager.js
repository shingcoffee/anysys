/**
 * Base Manager Module
 * Provides common functionality for all property editor managers.
 * Handles index management and event dispatching.
 */

export class BaseManager {
  /**
   * @param {Object} controller - The property editor controller instance
   * @param {string} indexName - The name of the index property (e.g., 'stepIndex', 'branchIndex')
   */
  constructor(controller, indexName) {
    this.controller = controller
    this._indexName = indexName
    this[indexName] = 0
  }

  // ===================
  // Convenience Getters
  // ===================

  /**
   * Get the canvas instance from the controller.
   * @returns {Object|null} The canvas instance
   */
  get canvas() {
    return this.controller.canvas
  }

  /**
   * Get the currently selected element from the controller.
   * @returns {Object|null} The current element
   */
  get currentElement() {
    return this.controller.currentElement
  }

  /**
   * Get the form fields container. Uses formTarget (the <form> element)
   * which wraps all tab panes, so querySelector calls will find elements
   * regardless of which tab pane they are in.
   * @returns {HTMLElement|null} The form element
   */
  get formFieldsTarget() {
    return this.controller.formFieldsTarget
  }

  // ===================
  // Index Management
  // ===================

  /**
   * Reset the index to 0.
   */
  reset() {
    this[this._indexName] = 0
  }

  /**
   * Get the current index value.
   * @returns {number} The current index
   */
  getIndex() {
    return this[this._indexName]
  }

  /**
   * Set the index to a specific value.
   * @param {number} value - The new index value
   */
  setIndex(value) {
    this[this._indexName] = value
  }

  /**
   * Increment the index by 1.
   */
  incrementIndex() {
    this[this._indexName]++
  }

  // ===================
  // Event Dispatching
  // ===================

  /**
   * Dispatch a custom event to trigger auto-sync to canvas.
   * @param {string} eventName - The name of the event to dispatch
   */
  _dispatchEvent(eventName) {
    const form = this.controller.formTarget
    if (form) {
      form.dispatchEvent(new CustomEvent(eventName, { bubbles: true }))
    }
  }
}

export default BaseManager
