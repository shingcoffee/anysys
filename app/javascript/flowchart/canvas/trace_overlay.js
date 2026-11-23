/**
 * TraceOverlayMixin - Handles trace execution overlay visualization on the flowchart canvas.
 * Shows per-element success/failure status and execution-order badges from test run traces.
 */

import { createGroup, createSvgElement } from "utils"

export const TraceOverlayMixin = {
  /**
   * Show trace overlay on canvas elements based on trace execution results.
   * Matches canvas elements only by stable `element_id`. Nodes without an id
   * (e.g. End.failure, collect_errors) do not highlight a box.
   * Elements matched with "success" get a green overlay, "failure" gets red,
   * and unmatched elements get a gray overlay.
   * @param {Array<Object>} traceNodes - Array of trace node objects
   * @param {string} [traceNodes[].element_id] - Stable canvas element id
   * @param {string} traceNodes[].status - Execution status: "success", "failure", or "unknown"
   */
  showTraceOverlay(traceNodes) {
    this.clearTraceOverlay()

    const idStatusMap = new Map()
    // Execution-order map: 1-based index of each DISTINCT element's FIRST
    // occurrence. Repeated nodes (loops) reuse their first number so badges
    // stay 1, 2, 3… with no gaps. Nodes without element_id are skipped.
    const idOrderMap = new Map()
    let nextOrder = 1
    traceNodes.forEach((node) => {
      if (node.element_id == null || node.element_id === "") return
      const status = node.status || "unknown"
      const idKey = String(node.element_id)
      idStatusMap.set(idKey, status)
      if (!idOrderMap.has(idKey)) {
        idOrderMap.set(idKey, nextOrder++)
      }
    })

    // Create a dedicated trace overlay layer (above elements)
    this._traceOverlayLayer = createGroup({ class: "trace-overlay-layer" })
    // Insert after element layer so overlays render on top
    this.svg.insertBefore(this._traceOverlayLayer, this.elementLayer.nextSibling)

    for (const element of this.elements) {
      const status = idStatusMap.get(String(element.id))
      const order = idOrderMap.get(String(element.id))

      let fillColor, fillOpacity
      if (status === "success") {
        fillColor = "#22c55e" // green-500
        fillOpacity = "0.15"
      } else if (status === "failure") {
        fillColor = "#ef4444" // red-500
        fillOpacity = "0.15"
      } else {
        fillColor = "#9ca3af" // gray-400
        fillOpacity = "0.1"
      }

      const hw = element.width / 2
      const hh = element.height / 2
      const overlayRect = createSvgElement("rect", {
        x: element.x - hw - 4,
        y: element.y - hh - 4,
        width: element.width + 8,
        height: element.height + 8,
        rx: "8",
        ry: "8",
        fill: fillColor,
        "fill-opacity": fillOpacity,
        stroke: fillColor,
        "stroke-width": status ? "2.5" : "1",
        "stroke-opacity": status ? "0.6" : "0.2",
        "pointer-events": "none",
        class: "trace-overlay-rect"
      })
      this._traceOverlayLayer.appendChild(overlayRect)

      // Add a small status icon in the top-right corner for matched elements
      if (status === "success" || status === "failure") {
        const iconX = element.x + hw - 2
        const iconY = element.y - hh - 2
        const iconRadius = 8
        const iconBg = createSvgElement("circle", {
          cx: iconX,
          cy: iconY,
          r: iconRadius,
          fill: status === "success" ? "#22c55e" : "#ef4444",
          stroke: "white",
          "stroke-width": "2",
          "pointer-events": "none"
        })
        this._traceOverlayLayer.appendChild(iconBg)

        const iconText = createSvgElement("text", {
          x: iconX,
          y: iconY,
          "text-anchor": "middle",
          "dominant-baseline": "central",
          fill: "white",
          "font-size": "10",
          "font-weight": "bold",
          "pointer-events": "none"
        })
        iconText.textContent = status === "success" ? "✓" : "✗"
        this._traceOverlayLayer.appendChild(iconText)
      }

      // Execution-order badge in the top-left corner for executed elements.
      // Skipped when the element never appeared in the trace (no order).
      if (order !== undefined) {
        const badgeX = element.x - hw + 2
        const badgeY = element.y - hh - 2
        const badgeBg = createSvgElement("circle", {
          cx: badgeX,
          cy: badgeY,
          r: 9,
          fill: "#1e293b", // slate-800
          "fill-opacity": "0.85",
          stroke: "white",
          "stroke-width": "1.5",
          "pointer-events": "none",
          class: "trace-overlay-order-badge"
        })
        this._traceOverlayLayer.appendChild(badgeBg)

        const badgeText = createSvgElement("text", {
          x: badgeX,
          y: badgeY,
          "text-anchor": "middle",
          "dominant-baseline": "central",
          fill: "white",
          "font-size": "10",
          "font-weight": "bold",
          "pointer-events": "none"
        })
        badgeText.textContent = String(order)
        this._traceOverlayLayer.appendChild(badgeText)
      }
    }
  },

  /**
   * Remove all trace overlay elements from the canvas.
   */
  clearTraceOverlay() {
    if (this._traceOverlayLayer) {
      this._traceOverlayLayer.remove()
      this._traceOverlayLayer = null
    }
  }
}
