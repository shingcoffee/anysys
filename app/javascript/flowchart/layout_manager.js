/**
 * LayoutManager - "Tidy layout": layered top-down layout from Start.
 *
 * - Layers: longest path from Start over the graph with loop back-edges
 *   removed, so a merge point sits below every branch that reaches it.
 * - Order: children follow the source port index (decision branch order).
 * - Placement: branches sit side by side and a parent is centred over its
 *   first and last branch; a merge point is centred under the element where
 *   its branches split.
 * - Elements not reachable from Start go in a row below the layout.
 * Start keeps its position. One undo entry.
 */

import { snapToGrid } from "utils"
import { GRID_SIZE } from "flowchart/constants/canvas"
import { portIndex } from "flowchart/dynamic_ports"

const HORIZONTAL_GAP = 60
const VERTICAL_GAP = 60

export class LayoutManager {
  constructor(canvas) {
    this.canvas = canvas
  }

  autoLayout() {
    if (this.canvas.canMutate?.() === false) return
    const elements = this.canvas.elements
    if (elements.length === 0) return

    this.canvas.onBeforeChange?.()

    const slotWidth = Math.max(...elements.map(el => el.width)) + HORIZONTAL_GAP
    const rowHeight = Math.max(...elements.map(el => el.height)) + VERTICAL_GAP
    const start = elements.find(el => el.type === "start")
    const graph = this._buildGraph(elements, this.canvas.connections, start)
    const slots = this._placeSlots(graph)

    const originX = start ? start.x - slots.get(start.id) * slotWidth : elements[0].x
    const originY = start ? start.y : elements[0].y
    const byId = new Map(elements.map(el => [el.id, el]))
    let lastLayer = -1
    for (const [id, slot] of slots) {
      const el = byId.get(id)
      const layer = graph.layer.get(id)
      lastLayer = Math.max(lastLayer, layer)
      el.x = snapToGrid(originX + slot * slotWidth, GRID_SIZE)
      el.y = snapToGrid(originY + layer * rowHeight, GRID_SIZE)
    }

    const minSlot = Math.min(0, ...slots.values())
    const unreachable = elements.filter(el => !slots.has(el.id))
    unreachable.forEach((el, i) => {
      el.x = snapToGrid(originX + (minSlot + i) * slotWidth, GRID_SIZE)
      el.y = snapToGrid(originY + (lastLayer + 1) * rowHeight, GRID_SIZE)
    })

    elements.forEach(el => this.canvas.updateElementPosition(el))
    this.canvas.updateConnections()
    this.canvas.onchange?.()

    this.canvas.zoomPanManager.fitToContent(elements)
    this.canvas.onZoomChange?.(this.canvas.zoomPanManager.zoomPercent)
  }

  /**
   * Reachable DAG from Start (back-edges dropped), with layers, a placement
   * tree (`branches` side by side, `merges` centred below) and topo order.
   */
  _buildGraph(elements, connections, start) {
    const ids = new Set(elements.map(el => el.id))
    const out = new Map(elements.map(el => [el.id, []]))
    connections
      .filter(c => ids.has(c.from) && ids.has(c.to))
      .map((c, order) => ({ c, order }))
      .sort((a, b) => (portIndex(a.c.fromPort) - portIndex(b.c.fromPort)) || (a.order - b.order))
      .forEach(({ c }) => out.get(c.from).push(c.to))

    const graph = { order: [], layer: new Map(), branches: new Map(), merges: new Map(), root: start?.id }
    if (!start) return graph

    const preds = new Map()
    const state = new Map()
    const postorder = []
    const visit = (id) => {
      state.set(id, "open")
      for (const child of out.get(id)) {
        if (state.get(child) === "open") continue
        if (!preds.has(child)) preds.set(child, [])
        if (!preds.get(child).includes(id)) preds.get(child).push(id)
        if (!state.has(child)) visit(child)
      }
      state.set(id, "done")
      postorder.push(id)
    }
    visit(start.id)
    graph.order = postorder.reverse()

    const parent = new Map()
    const depth = new Map([[start.id, 0]])
    graph.layer.set(start.id, 0)
    for (const id of graph.order) {
      graph.branches.set(id, [])
      graph.merges.set(id, [])
      if (id === start.id) continue

      const from = preds.get(id)
      graph.layer.set(id, Math.max(...from.map(p => graph.layer.get(p) + 1)))
      const owner = from.length === 1 ? from[0] : this._commonAncestor(from, parent, depth)
      parent.set(id, owner)
      depth.set(id, depth.get(owner) + 1)
      graph[from.length === 1 ? "branches" : "merges"].get(owner).push(id)
    }

    // `_out` is already sorted by source port; keep side-by-side children in
    // that order even though the topo walk visits them differently.
    for (const id of graph.order) {
      const rank = new Map(out.get(id).map((child, index) => [child, index]))
      graph.branches.get(id).sort((a, b) => rank.get(a) - rank.get(b))
    }
    return graph
  }

  _commonAncestor(ids, parent, depth) {
    return ids.reduce((a, b) => {
      while (depth.get(a) > depth.get(b)) a = parent.get(a)
      while (depth.get(b) > depth.get(a)) b = parent.get(b)
      while (a !== b) {
        a = parent.get(a)
        b = parent.get(b)
      }
      return a
    })
  }

  /**
   * Horizontal slot (in slot-width units) for every reachable element.
   */
  _placeSlots(graph) {
    const slots = new Map()
    if (!graph.root) return slots

    const width = new Map()
    for (const id of [...graph.order].reverse()) {
      const branchWidth = graph.branches.get(id).reduce((sum, child) => sum + width.get(child), 0)
      const mergeWidth = Math.max(0, ...graph.merges.get(id).map(child => width.get(child)))
      width.set(id, Math.max(1, branchWidth, mergeWidth))
    }

    const place = (id, left) => {
      const branches = graph.branches.get(id)
      let cursor = left + (width.get(id) - branches.reduce((sum, child) => sum + width.get(child), 0)) / 2
      for (const child of branches) {
        place(child, cursor)
        cursor += width.get(child)
      }
      const center = branches.length
        ? (slots.get(branches[0]) + slots.get(branches[branches.length - 1])) / 2
        : left + width.get(id) / 2 - 0.5
      slots.set(id, center)
      for (const child of graph.merges.get(id)) place(child, center + 0.5 - width.get(child) / 2)
    }
    place(graph.root, 0)

    this._separateLayers(slots, graph.layer)
    return slots
  }

  /**
   * Push apart elements that ended up closer than one slot on the same layer.
   */
  _separateLayers(slots, layer) {
    const rows = new Map()
    for (const [id, slot] of slots) {
      const row = layer.get(id)
      if (!rows.has(row)) rows.set(row, [])
      rows.get(row).push({ id, slot })
    }
    for (const row of rows.values()) {
      row.sort((a, b) => a.slot - b.slot)
      for (let i = 1; i < row.length; i++) {
        if (row[i].slot - row[i - 1].slot < 1) row[i].slot = row[i - 1].slot + 1
        slots.set(row[i].id, row[i].slot)
      }
    }
  }
}
