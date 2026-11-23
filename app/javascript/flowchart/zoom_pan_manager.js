import { MIN_ZOOM, MAX_ZOOM, ZOOM_STEP, DEFAULT_ZOOM } from "flowchart/constants"
import { clamp } from "utils"

/**
 * ZoomPanManager - Manages viewBox-based zoom and pan for the SVG canvas.
 *
 * Uses the SVG viewBox attribute to implement zoom (scaling the visible area)
 * and pan (translating the visible area). All coordinate conversions between
 * screen (client) space and SVG space go through this manager.
 */
export class ZoomPanManager {
  constructor(svg) {
    this.svg = svg
    this.zoom = DEFAULT_ZOOM
    this.panX = 0
    this.panY = 0
    this.isPanning = false
    this.isSpaceHeld = false
    this.panStart = null
    this._updateViewBox()
    this._resizeObserver = new ResizeObserver(() => this._updateViewBox())
    this._resizeObserver.observe(svg)
  }

  /**
   * Stop tracking container size changes.
   */
  destroy() {
    this._resizeObserver?.disconnect()
    this._resizeObserver = null
  }

  get viewWidth() {
    return this.svg.clientWidth / this.zoom
  }

  get viewHeight() {
    return this.svg.clientHeight / this.zoom
  }

  /**
   * Convert client (screen) coordinates to SVG coordinates.
   * @param {number} clientX - Client X coordinate
   * @param {number} clientY - Client Y coordinate
   * @returns {{ x: number, y: number }} SVG coordinates
   */
  clientToSVG(clientX, clientY) {
    const rect = this.svg.getBoundingClientRect()
    const relX = clientX - rect.left
    const relY = clientY - rect.top
    return {
      x: this.panX + (relX / rect.width) * this.viewWidth,
      y: this.panY + (relY / rect.height) * this.viewHeight
    }
  }

  /**
   * Zoom to a specific level, keeping the point under the cursor fixed.
   * @param {number} newZoom - Target zoom level
   * @param {number} centerClientX - Client X coordinate of zoom center
   * @param {number} centerClientY - Client Y coordinate of zoom center
   */
  zoomTo(newZoom, centerClientX, centerClientY) {
    const clamped = clamp(newZoom, MIN_ZOOM, MAX_ZOOM)
    if (clamped === this.zoom) return

    const rect = this.svg.getBoundingClientRect()
    const relX = centerClientX - rect.left
    const relY = centerClientY - rect.top
    const svgX = this.panX + (relX / rect.width) * this.viewWidth
    const svgY = this.panY + (relY / rect.height) * this.viewHeight

    this.zoom = clamped

    this.panX = svgX - (relX / rect.width) * this.viewWidth
    this.panY = svgY - (relY / rect.height) * this.viewHeight

    this._updateViewBox()
  }

  /**
   * Zoom in by one step, centered on the SVG viewport center.
   */
  zoomIn() {
    const rect = this.svg.getBoundingClientRect()
    this.zoomTo(this.zoom + ZOOM_STEP, rect.left + rect.width / 2, rect.top + rect.height / 2)
  }

  /**
   * Zoom out by one step, centered on the SVG viewport center.
   */
  zoomOut() {
    const rect = this.svg.getBoundingClientRect()
    this.zoomTo(this.zoom - ZOOM_STEP, rect.left + rect.width / 2, rect.top + rect.height / 2)
  }

  /**
   * Fit the viewport to show all elements with padding.
   * @param {Array} elements - Array of element objects with x, y, width, height
   * @param {number} padding - Padding in SVG units around the content
   */
  fitToContent(elements, padding = 80) {
    if (!elements || elements.length === 0) return

    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    for (const el of elements) {
      const hw = el.width / 2, hh = el.height / 2
      minX = Math.min(minX, el.x - hw)
      minY = Math.min(minY, el.y - hh)
      maxX = Math.max(maxX, el.x + hw)
      maxY = Math.max(maxY, el.y + hh)
    }

    const contentW = maxX - minX + padding * 2
    const contentH = maxY - minY + padding * 2
    const rect = this.svg.getBoundingClientRect()
    const scaleX = rect.width / contentW
    const scaleY = rect.height / contentH
    this.zoom = clamp(Math.min(scaleX, scaleY), MIN_ZOOM, MAX_ZOOM)
    this.panX = minX - padding
    this.panY = minY - padding
    this._updateViewBox()
  }

  /**
   * Reset zoom to 100% and pan to origin.
   */
  resetZoom() {
    this.zoom = DEFAULT_ZOOM
    this.panX = 0
    this.panY = 0
    this._updateViewBox()
  }

  /**
   * Pan by a screen-space delta.
   * @param {number} deltaScreenX - Screen pixels to pan horizontally
   * @param {number} deltaScreenY - Screen pixels to pan vertically
   */
  panBy(deltaScreenX, deltaScreenY) {
    this.panX -= deltaScreenX / this.zoom
    this.panY -= deltaScreenY / this.zoom
    this._updateViewBox()
  }

  /**
   * Start a pan drag operation.
   * @param {number} clientX - Starting client X
   * @param {number} clientY - Starting client Y
   */
  startPan(clientX, clientY) {
    this.isPanning = true
    this.panStart = { x: clientX, y: clientY }
    this.svg.style.cursor = "grabbing"
  }

  /**
   * Update an ongoing pan drag.
   * @param {number} clientX - Current client X
   * @param {number} clientY - Current client Y
   */
  updatePan(clientX, clientY) {
    if (!this.isPanning || !this.panStart) return
    const dx = clientX - this.panStart.x
    const dy = clientY - this.panStart.y
    this.panBy(dx, dy)
    this.panStart = { x: clientX, y: clientY }
  }

  /**
   * End a pan drag operation.
   */
  endPan() {
    this.isPanning = false
    this.panStart = null
    this.svg.style.cursor = this.isSpaceHeld ? "grab" : "default"
  }

  /**
   * Get the current zoom level as a percentage.
   * @returns {number} Zoom percentage (e.g. 100 for 100%)
   */
  get zoomPercent() {
    return Math.round(this.zoom * 100)
  }

  /**
   * Update the SVG viewBox attribute to reflect current zoom and pan state.
   * @private
   */
  _updateViewBox() {
    this.svg.setAttribute("viewBox", `${this.panX} ${this.panY} ${this.viewWidth} ${this.viewHeight}`)
  }
}
