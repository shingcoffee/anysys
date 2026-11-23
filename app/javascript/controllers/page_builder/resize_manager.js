import { BaseManager } from "controllers/page_builder/base_manager"

const WIDTH_SNAP_POINTS = [
  { cols: 3,  name: "quarter",        label: "1/4" },
  { cols: 4,  name: "third",          label: "1/3" },
  { cols: 6,  name: "half",           label: "Half" },
  { cols: 8,  name: "two_thirds",     label: "2/3" },
  { cols: 9,  name: "three_quarters", label: "3/4" },
  { cols: 12, name: "full",           label: "Full" }
]

export class ResizeManager extends BaseManager {
  constructor(controller) {
    super(controller)
    this.isResizing = false
    this.resizingFieldId = null
    this.startX = 0
    this.containerWidth = 0
    this.tooltip = null
  }

  startResize(event) {
    event.preventDefault()
    event.stopPropagation()

    const card = event.currentTarget.closest("[data-field-id]")
    if (!card) return

    this.isResizing = true
    this.resizingFieldId = card.dataset.fieldId
    this.startX = event.clientX

    const container = this.c.fieldsContainerTarget
    this.containerWidth = container.getBoundingClientRect().width
    this.colWidth = this.containerWidth / 12

    this.c.saveState()
    this._showGridLines()
    this._createTooltip()

    this._onMouseMove = (e) => this._handleMouseMove(e)
    this._onMouseUp = (e) => this._handleMouseUp(e)
    document.addEventListener("mousemove", this._onMouseMove)
    document.addEventListener("mouseup", this._onMouseUp)
  }

  _handleMouseMove(event) {
    if (!this.isResizing) return

    const card = this.c.fieldsContainerTarget.querySelector(`[data-field-id="${this.resizingFieldId}"]`)
    if (!card) return

    const cardLeft = card.getBoundingClientRect().left
    const newWidth = event.clientX - cardLeft
    const cols = Math.round(newWidth / this.colWidth)

    const snap = WIDTH_SNAP_POINTS.reduce((closest, point) =>
      Math.abs(point.cols - cols) < Math.abs(closest.cols - cols) ? point : closest
    )

    const snapLabel = this.c.resizeSnapLabelsValue[snap.name] || snap.label
    this._updateTooltip(event.clientX, event.clientY, `${snap.cols}/12 (${snapLabel})`)

    const field = this.c.currentPageFields.find(f => f.id === this.resizingFieldId)
    if (field) {
      const viewport = this.c.viewportValue || "desktop"
      const currentWidth = viewport === "desktop" ? field.width : (field.responsive_widths?.[viewport] || field.width)
      if (currentWidth !== snap.name) {
        if (viewport === "desktop") {
          field.width = snap.name
          field.width_explicit = true
        } else {
          if (!field.responsive_widths) field.responsive_widths = {}
          field.responsive_widths[viewport] = snap.name
        }
        this.c.fieldManager.renderFields()
      }
    }
  }

  _handleMouseUp(_event) {
    if (!this.isResizing) return

    this.isResizing = false
    this._removeGridLines()
    this._removeTooltip()

    document.removeEventListener("mousemove", this._onMouseMove)
    document.removeEventListener("mouseup", this._onMouseUp)

    const field = this.c.currentPageFields.find(f => f.id === this.resizingFieldId)
    if (field) {
      this.c.propertyManager.syncToolbarWidth(field)
    }
    this.c.saveManager.markDirty()
    this.resizingFieldId = null
  }

  _showGridLines() {
    const container = this.c.fieldsContainerTarget
    const overlay = document.createElement("div")
    overlay.className = "resize-grid-overlay absolute inset-0 pointer-events-none z-10"
    overlay.style.display = "grid"
    overlay.style.gridTemplateColumns = "repeat(12, 1fr)"
    overlay.style.gap = "0"
    for (let i = 0; i < 12; i++) {
      const line = document.createElement("div")
      line.className = i < 11 ? "border-r border-dashed border-indigo-200/40" : ""
      overlay.appendChild(line)
    }
    container.style.position = "relative"
    container.appendChild(overlay)
  }

  _removeGridLines() {
    this.c.fieldsContainerTarget.querySelector(".resize-grid-overlay")?.remove()
  }

  _createTooltip() {
    this.tooltip = document.createElement("div")
    this.tooltip.className = "fixed z-50 bg-gray-900 text-white text-xs px-2 py-1 rounded shadow-lg pointer-events-none"
    document.body.appendChild(this.tooltip)
  }

  _updateTooltip(x, y, text) {
    if (!this.tooltip) return
    this.tooltip.textContent = text
    this.tooltip.style.left = `${x + 12}px`
    this.tooltip.style.top = `${y - 28}px`
  }

  _removeTooltip() {
    this.tooltip?.remove()
    this.tooltip = null
  }
}
