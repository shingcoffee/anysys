import { Controller } from "@hotwired/stimulus"

/**
 * Panel Resize Controller
 *
 * Provides drag-to-resize functionality for a panel element.
 * Designed for right-side panels where dragging the left edge leftward increases width.
 * Persists panel width to localStorage for restoration across sessions.
 *
 * Usage:
 *   <div data-controller="panel-resize"
 *        data-panel-resize-min-width-value="400"
 *        data-panel-resize-max-width-value="700"
 *        data-panel-resize-default-width-value="500"
 *        data-panel-resize-storage-key-value="flowchart_property_panel_width">
 *     <div data-action="mousedown->panel-resize#startResize" class="drag-handle">
 *       <!-- Drag handle UI -->
 *     </div>
 *     <!-- Panel content -->
 *   </div>
 *
 * Values:
 *   - minWidth: Number (default: 400) - Minimum panel width in pixels
 *   - maxWidth: Number (default: 700) - Maximum panel width in pixels
 *   - defaultWidth: Number (default: 500) - Default panel width in pixels
 *   - storageKey: String (default: "flowchart_property_panel_width") - localStorage key
 */
export default class extends Controller {
  static values = {
    minWidth: { type: Number, default: 400 },
    maxWidth: { type: Number, default: 700 },
    defaultWidth: { type: Number, default: 500 },
    storageKey: { type: String, default: "flowchart_property_panel_width" }
  }

  connect() {
    this._mobileQuery = window.matchMedia?.("(max-width: 639px)") || null
    this._boundOnMediaChange = () => this._syncViewportWidth()
    this._mobileQuery?.addEventListener?.("change", this._boundOnMediaChange)
    this._syncViewportWidth()
    this._setupBoundHandlers()
  }

  disconnect() {
    this._mobileQuery?.removeEventListener?.("change", this._boundOnMediaChange)
    this._removeDocumentListeners()
  }

  _syncViewportWidth() {
    if (this._mobileQuery?.matches) {
      this.element.style.width = ""
      return
    }
    this._restoreWidth()
  }

  /**
   * Start resize operation when drag handle is clicked.
   * Records starting position and sets up document-level event listeners.
   * @param {MouseEvent} event - Mousedown event
   */
  startResize(event) {
    event.preventDefault()

    this.startX = event.clientX
    this.startWidth = this.element.offsetWidth

    document.addEventListener("mousemove", this._boundOnMouseMove)
    document.addEventListener("mouseup", this._boundOnMouseUp)

    // Prevent text selection and set resize cursor during drag
    document.body.style.userSelect = "none"
    document.body.style.cursor = "col-resize"
  }

  /**
   * Restore saved width from localStorage, validating it's within min/max range.
   * Falls back to defaultWidth if no saved value or invalid value.
   * @private
   */
  _restoreWidth() {
    const savedWidth = localStorage.getItem(this.storageKeyValue)

    if (savedWidth) {
      const width = parseInt(savedWidth, 10)
      if (!isNaN(width)) {
        const clampedWidth = this._clampWidth(width)
        this.element.style.width = `${clampedWidth}px`
        return
      }
    }

    // No saved width or invalid value, use default
    this.element.style.width = `${this.defaultWidthValue}px`
  }

  /**
   * Set up bound event handler references for cleanup.
   * @private
   */
  _setupBoundHandlers() {
    this._boundOnMouseMove = this._onMouseMove.bind(this)
    this._boundOnMouseUp = this._onMouseUp.bind(this)
  }

  /**
   * Handle mouse move during resize.
   * Calculates delta and updates panel width within min/max bounds.
   * @param {MouseEvent} event - Mousemove event
   * @private
   */
  _onMouseMove(event) {
    // Panel is on the right, so dragging LEFT (negative delta) increases width
    const delta = this.startX - event.clientX
    const newWidth = this.startWidth + delta
    const clampedWidth = this._clampWidth(newWidth)

    this.element.style.width = `${clampedWidth}px`
  }

  /**
   * Handle mouse up to end resize operation.
   * Cleans up event listeners, resets body styles, and persists width to localStorage.
   * @private
   */
  _onMouseUp() {
    this._removeDocumentListeners()

    // Reset body styles
    document.body.style.userSelect = ""
    document.body.style.cursor = ""

    // Persist current width to localStorage
    const currentWidth = this.element.offsetWidth
    localStorage.setItem(this.storageKeyValue, currentWidth.toString())
  }

  /**
   * Remove document-level event listeners.
   * @private
   */
  _removeDocumentListeners() {
    document.removeEventListener("mousemove", this._boundOnMouseMove)
    document.removeEventListener("mouseup", this._boundOnMouseUp)
  }

  /**
   * Clamp width between minWidth and maxWidth values.
   * @param {number} width - Width to clamp
   * @returns {number} - Clamped width
   * @private
   */
  _clampWidth(width) {
    return Math.max(this.minWidthValue, Math.min(this.maxWidthValue, width))
  }
}
