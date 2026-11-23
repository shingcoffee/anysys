import { snapToGrid } from "utils"
import { GRID_SIZE } from "flowchart/constants"

export class AlignmentManager {
  constructor(canvas) {
    this.canvas = canvas
  }

  alignLeft() {
    const elements = this.canvas.selectedElements
    if (elements.length < 2) return
    const minX = Math.min(...elements.map(el => el.x - el.width / 2))
    this._applyAlignment(elements, el => { el.x = snapToGrid(minX + el.width / 2, GRID_SIZE) })
  }

  alignCenterH() {
    const elements = this.canvas.selectedElements
    if (elements.length < 2) return
    const avgX = elements.reduce((sum, el) => sum + el.x, 0) / elements.length
    this._applyAlignment(elements, el => { el.x = snapToGrid(avgX, GRID_SIZE) })
  }

  alignRight() {
    const elements = this.canvas.selectedElements
    if (elements.length < 2) return
    const maxX = Math.max(...elements.map(el => el.x + el.width / 2))
    this._applyAlignment(elements, el => { el.x = snapToGrid(maxX - el.width / 2, GRID_SIZE) })
  }

  alignTop() {
    const elements = this.canvas.selectedElements
    if (elements.length < 2) return
    const minY = Math.min(...elements.map(el => el.y - el.height / 2))
    this._applyAlignment(elements, el => { el.y = snapToGrid(minY + el.height / 2, GRID_SIZE) })
  }

  alignCenterV() {
    const elements = this.canvas.selectedElements
    if (elements.length < 2) return
    const avgY = elements.reduce((sum, el) => sum + el.y, 0) / elements.length
    this._applyAlignment(elements, el => { el.y = snapToGrid(avgY, GRID_SIZE) })
  }

  alignBottom() {
    const elements = this.canvas.selectedElements
    if (elements.length < 2) return
    const maxY = Math.max(...elements.map(el => el.y + el.height / 2))
    this._applyAlignment(elements, el => { el.y = snapToGrid(maxY - el.height / 2, GRID_SIZE) })
  }

  distributeH() {
    const elements = this.canvas.selectedElements
    if (elements.length < 3) return
    const sorted = [...elements].sort((a, b) => a.x - b.x)
    const first = sorted[0].x
    const last = sorted[sorted.length - 1].x
    const step = (last - first) / (sorted.length - 1)
    this._applyAlignment(sorted, (el, i) => { el.x = snapToGrid(first + step * i, GRID_SIZE) })
  }

  distributeV() {
    const elements = this.canvas.selectedElements
    if (elements.length < 3) return
    const sorted = [...elements].sort((a, b) => a.y - b.y)
    const first = sorted[0].y
    const last = sorted[sorted.length - 1].y
    const step = (last - first) / (sorted.length - 1)
    this._applyAlignment(sorted, (el, i) => { el.y = snapToGrid(first + step * i, GRID_SIZE) })
  }

  _applyAlignment(elements, transform) {
    if (this.canvas.canMutate?.() === false) return
    this.canvas.onBeforeChange?.()
    elements.forEach((el, i) => {
      transform(el, i)
      this.canvas.updateElementPosition(el)
    })
    this.canvas.updateConnections()
    this.canvas.onchange?.()
  }
}
