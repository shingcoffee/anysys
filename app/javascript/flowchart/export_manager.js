/**
 * ExportManager
 * Handles exporting the flowchart canvas to SVG and PNG formats.
 */
export class ExportManager {
  constructor(canvas) {
    this.canvas = canvas
  }

  /**
   * Export the flowchart as an SVG file
   */
  exportSVG() {
    const svgClone = this._prepareSvgForExport()
    const svgString = new XMLSerializer().serializeToString(svgClone)
    const blob = new Blob([svgString], { type: "image/svg+xml" })
    this._download(blob, this._filename("svg"))
  }

  /**
   * Export the flowchart as a PNG file
   * @param {number} scale - Resolution multiplier (default: 2 for retina quality)
   */
  exportPNG(scale = 2) {
    const svgClone = this._prepareSvgForExport()
    const svgString = new XMLSerializer().serializeToString(svgClone)
    const img = new Image()
    const svgBlob = new Blob([svgString], { type: "image/svg+xml;charset=utf-8" })
    const url = URL.createObjectURL(svgBlob)

    img.onload = () => {
      const canvas = document.createElement("canvas")
      const bounds = this._getContentBounds()
      canvas.width = (bounds.width + 80) * scale
      canvas.height = (bounds.height + 80) * scale

      const ctx = canvas.getContext("2d")
      // Fill with white background
      ctx.fillStyle = "white"
      ctx.fillRect(0, 0, canvas.width, canvas.height)
      ctx.drawImage(img, 0, 0, canvas.width, canvas.height)

      canvas.toBlob(blob => {
        this._download(blob, this._filename("png"))
        URL.revokeObjectURL(url)
      }, "image/png")
    }

    img.src = url
  }

  /**
   * Prepare a clean copy of the SVG for export
   * Removes interactive layers and sets proper viewBox
   * @private
   */
  _prepareSvgForExport() {
    const svg = this.canvas.svg.cloneNode(true)

    // Remove interactive layers
    svg.querySelectorAll(".handle-layer, .guide-layer, .selection-layer").forEach(el => el.remove())

    // Remove any inline editors
    svg.querySelectorAll("foreignObject").forEach(el => el.remove())

    // Remove trace overlay if present
    svg.querySelectorAll(".trace-overlay-layer").forEach(el => el.remove())

    // Set viewBox to fit content with padding
    const bounds = this._getContentBounds()
    const pad = 40
    svg.setAttribute("viewBox", `${bounds.x - pad} ${bounds.y - pad} ${bounds.width + pad*2} ${bounds.height + pad*2}`)
    svg.setAttribute("width", bounds.width + pad * 2)
    svg.setAttribute("height", bounds.height + pad * 2)
    svg.setAttribute("xmlns", "http://www.w3.org/2000/svg")

    // Remove inline styles that might interfere
    svg.style.width = ""
    svg.style.height = ""

    return svg
  }

  /**
   * Calculate the bounding box of all elements in the flowchart
   * @private
   */
  _getContentBounds() {
    const els = this.canvas.elements
    if (!els.length) return { x: 0, y: 0, width: 400, height: 300 }

    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    for (const el of els) {
      minX = Math.min(minX, el.x - el.width/2)
      minY = Math.min(minY, el.y - el.height/2)
      maxX = Math.max(maxX, el.x + el.width/2)
      maxY = Math.max(maxY, el.y + el.height/2)
    }

    return {
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY
    }
  }

  /**
   * Generate a filename with the current date
   * @private
   */
  _filename(ext) {
    const date = new Date().toISOString().slice(0, 10)
    return `flowchart_${date}.${ext}`
  }

  /**
   * Trigger a file download in the browser
   * @private
   */
  _download(blob, filename) {
    const a = document.createElement("a")
    a.href = URL.createObjectURL(blob)
    a.download = filename
    a.click()
    URL.revokeObjectURL(a.href)
  }
}
