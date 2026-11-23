/**
 * Subflow Manager Module
 * Handles subflow expansion, folding, and related operations for the Flowchart Canvas.
 */

import { ExpansionMixin } from "controllers/flowchart_canvas/subflow_manager/expansion_mixin"
import { FoldRestoreMixin } from "controllers/flowchart_canvas/subflow_manager/fold_restore_mixin"
import { CanvasStateMixin } from "controllers/flowchart_canvas/subflow_manager/canvas_state_mixin"

export class SubflowManager {
  constructor(controller) {
    this.controller = controller
    this.expandedSubflows = {} // Track expanded subflows: { elementId: { elements: [], connections: [] } }
  }

  // ===================
  // Public API
  // ===================

  /**
   * Toggle subflow expansion state (expand or fold).
   */
  async toggleSubflowExpansion(subflowElement) {
    const flowchartId = subflowElement.properties?.flowchartId

    if (!flowchartId) {
      return
    }

    // Expand the subflow (replaces the subflow element with its contents)
    await this.expandSubflow(subflowElement)
  }

  /**
   * Expand a subflow element to show its contents.
   * @param {Object} subflowElement - The subflow element to expand
   */
  async expandSubflow(subflowElement) {
    return this._expandSubflowInternal(subflowElement, {
      checkInvokeActivity: true,
      dispatchEvents: true
    })
  }

  /**
   * Expand a subflow for saving (without dispatching change events).
   * @param {Object} subflowElement - The subflow element to expand
   */
  async expandSubflowForSave(subflowElement) {
    return this._expandSubflowInternal(subflowElement, {
      checkInvokeActivity: false,
      dispatchEvents: false
    })
  }

  /**
   * Expand all collapsed subflows for save operation.
   */
  async expandAllSubflowsForSave() {
    const canvas = this.controller.canvas
    const subflowElements = canvas.elements.filter(
      el => el.type === "subflow" && el.properties?.flowchartId
    )

    if (subflowElements.length === 0) {
      return
    }

    for (const subflowElement of subflowElements) {
      await this.expandSubflowForSave(subflowElement)
    }
  }

}

Object.assign(SubflowManager.prototype, ExpansionMixin)
Object.assign(SubflowManager.prototype, FoldRestoreMixin)
Object.assign(SubflowManager.prototype, CanvasStateMixin)

export default SubflowManager
