import { generateId, generateStepId, snapToGrid } from "utils"
import { GRID_SIZE } from "flowchart/constants"
import { uniqueLabel } from "flowchart/labels"

const PASTE_OFFSET = 30

export class ClipboardManager {
  constructor(canvas) {
    this.canvas = canvas
    this.clipboard = null
    this.pasteCount = 0
  }

  copy() {
    const selected = this.canvas.selectedElements
    if (selected.length === 0) return false

    const selectedIds = new Set(selected.map(el => el.id))
    const elements = selected.map(el => JSON.parse(JSON.stringify(el)))
    const connections = this.canvas.connections
      .filter(c => selectedIds.has(c.from) && selectedIds.has(c.to))
      .map(c => JSON.parse(JSON.stringify(c)))

    this.clipboard = { elements, connections }
    this.pasteCount = 0
    return true
  }

  paste() {
    if (!this.clipboard) return null

    const idMap = new Map()
    this.pasteCount += 1
    const offset = PASTE_OFFSET * this.pasteCount

    const taken = [...this.canvas.elements]
    const newElements = this.clipboard.elements.map(el => {
      const clone = structuredClone(el)
      const newId = generateId("el")
      idMap.set(el.id, newId)
      clone.id = newId
      clone.x = snapToGrid(el.x + offset, GRID_SIZE)
      clone.y = snapToGrid(el.y + offset, GRID_SIZE)
      clone.label = uniqueLabel(taken, el.label, this.canvas.labels?.uniqueLabelFormat)
      taken.push(clone)
      return clone
    })

    newElements.forEach(el => {
      if (!el.properties) return
      const props = el.properties
      delete props._expandedFromSubflow

      // Regenerate step ids on paste so the duplicated steps don't share
      // identity with the originals.
      if (Array.isArray(props.steps)) {
        props.steps = props.steps.map(step => {
          if (!step || typeof step !== "object") return step
          return { ...step, id: generateStepId() }
        })
      }
    })

    const newConnections = this.clipboard.connections.map(c => ({
      ...c,
      id: generateId("conn"),
      from: idMap.get(c.from),
      to: idMap.get(c.to)
    }))

    return { elements: newElements, connections: newConnections }
  }

  duplicate() {
    if (this.copy()) {
      return this.paste()
    }
    return null
  }

  get hasContent() {
    return this.clipboard !== null && this.clipboard.elements.length > 0
  }
}
