import { ELEMENT_COLORS } from "flowchart/constants/elements"

const CONTENT_PADDING = 40

/**
 * Scale and offset that fit `bounds` (padded) centred into a width × height box.
 * @param {{x: number, y: number, width: number, height: number}} bounds
 * @param {number} width
 * @param {number} height
 * @param {number} [padding]
 * @returns {{scale: number, offsetX: number, offsetY: number}}
 */
export function fitTransform(bounds, width, height, padding = CONTENT_PADDING) {
  const totalW = bounds.width + padding * 2
  const totalH = bounds.height + padding * 2
  const scale = Math.min(width / totalW, height / totalH)
  return {
    scale,
    offsetX: (width - totalW * scale) / 2 - (bounds.x - padding) * scale,
    offsetY: (height - totalH * scale) / 2 - (bounds.y - padding) * scale
  }
}

/**
 * Canvas coordinates of a point given in minimap pixels.
 * @param {{x: number, y: number}} point
 * @param {{scale: number, offsetX: number, offsetY: number}} transform
 * @returns {{x: number, y: number}}
 */
export function minimapToCanvas(point, { scale, offsetX, offsetY }) {
  return { x: (point.x - offsetX) / scale, y: (point.y - offsetY) / scale }
}

/**
 * MinimapManager
 *
 * Provides a small overview panel showing all elements and the current viewport.
 * The SVG takes its size from the container (observed), so a responsive
 * container never clips it. Supports click and drag to navigate the main canvas.
 */
export class MinimapManager {
  constructor(canvas, container) {
    this.canvas = canvas
    this.container = container
    this.width = 0
    this.height = 0
    this.isDragging = false
    this._createMinimap()
    this._measure()
    this._resizeObserver = new ResizeObserver(() => {
      if (this._measure()) this.update()
    })
    this._resizeObserver.observe(container)
  }

  destroy() {
    this._resizeObserver?.disconnect()
    this._resizeObserver = null
    this.svg.remove()
  }

  _createMinimap() {
    this.svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    this.svg.style.display = "block"
    this.svg.style.background = "#f8fafc"
    this.svg.style.borderRadius = "4px"

    // Background layer
    this.bgLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
    // Elements layer
    this.elementLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
    // Viewport rect
    this.viewportRect = document.createElementNS("http://www.w3.org/2000/svg", "rect")
    this.viewportRect.setAttribute("fill", "rgba(59, 130, 246, 0.15)")
    this.viewportRect.setAttribute("stroke", "#3b82f6")
    this.viewportRect.setAttribute("stroke-width", "1.5")
    this.viewportRect.setAttribute("rx", "2")

    this.svg.appendChild(this.bgLayer)
    this.svg.appendChild(this.elementLayer)
    this.svg.appendChild(this.viewportRect)
    this.container.appendChild(this.svg)

    // Click/drag handlers
    this.svg.addEventListener("mousedown", e => this._handleMouseDown(e))
    this.svg.addEventListener("mousemove", e => this._handleMouseMove(e))
    this.svg.addEventListener("mouseup", () => this._handleMouseUp())
    this.svg.addEventListener("mouseleave", () => this._handleMouseUp())
  }

  /**
   * Adopt the container's inner size. A hidden container measures 0 × 0 and
   * keeps the last size. Returns true when the size changed.
   */
  _measure() {
    const width = this.container.clientWidth
    const height = this.container.clientHeight
    if (!width || !height) return false
    if (width === this.width && height === this.height) return false
    this.width = width
    this.height = height
    this.svg.setAttribute("width", width)
    this.svg.setAttribute("height", height)
    return true
  }

  update() {
    const elements = this.canvas.elements
    if (elements.length === 0) {
      this._hide()
      return
    }

    this._show()
    this._measure()
    if (!this.width) return

    const { scale, offsetX, offsetY } = fitTransform(this._getContentBounds(elements), this.width, this.height)
    this._scale = scale
    this._offsetX = offsetX
    this._offsetY = offsetY

    // Draw elements
    this.elementLayer.innerHTML = ""
    for (const el of elements) {
      const colors = el.properties?.style?.fill
        ? { fill: el.properties.style.fill, stroke: el.properties.style.stroke }
        : (ELEMENT_COLORS[el.type] || ELEMENT_COLORS.process)
      const rect = document.createElementNS("http://www.w3.org/2000/svg", "rect")
      const x = (el.x - el.width / 2) * scale + offsetX
      const y = (el.y - el.height / 2) * scale + offsetY
      const w = el.width * scale
      const h = el.height * scale
      rect.setAttribute("x", x)
      rect.setAttribute("y", y)
      rect.setAttribute("width", Math.max(w, 3))
      rect.setAttribute("height", Math.max(h, 2))
      rect.setAttribute("fill", colors.stroke)
      rect.setAttribute("rx", "1")
      this.elementLayer.appendChild(rect)
    }

    // Draw viewport
    this._updateViewport()
  }

  _updateViewport() {
    const zpm = this.canvas.zoomPanManager
    if (!zpm || !this._scale) return
    const x = zpm.panX * this._scale + this._offsetX
    const y = zpm.panY * this._scale + this._offsetY
    const w = zpm.viewWidth * this._scale
    const h = zpm.viewHeight * this._scale
    this.viewportRect.setAttribute("x", x)
    this.viewportRect.setAttribute("y", y)
    this.viewportRect.setAttribute("width", w)
    this.viewportRect.setAttribute("height", h)
  }

  _handleMouseDown(e) {
    this.isDragging = true
    this._navigateTo(e)
  }

  _handleMouseMove(e) {
    if (!this.isDragging) return
    this._navigateTo(e)
  }

  _handleMouseUp() {
    this.isDragging = false
  }

  _navigateTo(e) {
    if (!this._scale) return
    const rect = this.svg.getBoundingClientRect()
    const target = minimapToCanvas(
      { x: e.clientX - rect.left, y: e.clientY - rect.top },
      { scale: this._scale, offsetX: this._offsetX, offsetY: this._offsetY }
    )
    // Center viewport on this point
    const zpm = this.canvas.zoomPanManager
    zpm.panX = target.x - zpm.viewWidth / 2
    zpm.panY = target.y - zpm.viewHeight / 2
    zpm._updateViewBox()
    this._updateViewport()
    this.canvas.onZoomChange?.(zpm.zoomPercent)
  }

  _getContentBounds(elements) {
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    for (const el of elements) {
      minX = Math.min(minX, el.x - el.width / 2)
      minY = Math.min(minY, el.y - el.height / 2)
      maxX = Math.max(maxX, el.x + el.width / 2)
      maxY = Math.max(maxY, el.y + el.height / 2)
    }
    return { x: minX, y: minY, width: maxX - minX, height: maxY - minY }
  }

  _show() {
    this.container.classList.remove("hidden")
  }

  _hide() {
    this.container.classList.add("hidden")
  }
}
