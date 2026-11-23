/**
 * ElementReachability — predecessor index over the flowchart element graph.
 *
 * Pure topology over `canvas.connections` (from/to element ids). No
 * universes, no isolateCtx — ctx is a single shared bus.
 *
 * Usage:
 *   const r = new ElementReachability(canvas)
 *   r.predecessors("elem_id")                  // string[] (farthest first)
 *   r.nearestProducer("elem_id", "pin", producerOutputs)  // string|null
 */
export class ElementReachability {
  constructor(canvas) {
    this.elements = (canvas && canvas.elements) || []
    this.connections = (canvas && canvas.connections) || []
    this._predecessors = new Map()
    this._build()
  }

  /** Ordered predecessor ids for `elementId`, farthest first, nearest last. */
  predecessors(elementId) {
    return this._predecessors.get(elementId) || []
  }

  /** Return the nearest predecessor id that emits `pin`, or null. */
  nearestProducer(elementId, pin, producerOutputs) {
    const preds = this.predecessors(elementId)
    for (let i = preds.length - 1; i >= 0; i--) {
      const outs = (producerOutputs && producerOutputs[preds[i]]) || []
      if (outs.includes(pin)) return preds[i]
    }
    return null
  }

  _build() {
    const reverse = new Map()
    for (const el of this.elements) reverse.set(el.id, [])
    for (const c of this._dataflowConnections()) {
      if (!reverse.has(c.to)) continue
      reverse.get(c.to).push(c.from)
    }

    for (const el of this.elements) {
      this._predecessors.set(el.id, this._walk(el.id, reverse))
    }
  }

  /**
   * Connections with loop back-edges redirected to the loop's exit (same
   * purpose as LoopTopology#dataflow_connections). A back-edge is an edge
   * into a `loop` element from an element reachable from that loop.
   */
  _dataflowConnections() {
    const byId = new Map()
    for (const el of this.elements) byId.set(el.id, el)

    const outgoing = new Map()
    for (const edge of this.connections) {
      if (!outgoing.has(edge.from)) outgoing.set(edge.from, [])
      outgoing.get(edge.from).push(edge)
    }

    const reachableFrom = (start, stop) => {
      const seen = new Set()
      const queue = [start]
      while (queue.length) {
        const id = queue.shift()
        if (seen.has(id)) continue
        seen.add(id)
        if (id === stop) continue
        for (const edge of outgoing.get(id) || []) queue.push(edge.to)
      }
      return seen
    }

    const exitOf = (loopId) => {
      const outs = outgoing.get(loopId)
      if (outs.length !== 2) return null
      const heads = outs.filter((edge) => reachableFrom(edge.to, loopId).has(loopId))
      if (heads.length !== 1) return null
      return outs.find((edge) => !heads.includes(edge)).to
    }

    const result = []
    for (const edge of this.connections) {
      const dest = byId.get(edge.to)
      const backEdge = dest?.type === "loop" && reachableFrom(edge.to).has(edge.from)
      if (!backEdge) {
        result.push(edge)
        continue
      }
      const exitId = exitOf(edge.to)
      if (exitId) result.push({ ...edge, to: exitId })
    }
    return result
  }

  _walk(startId, reverse) {
    const visited = new Set()
    const order = []
    const queue = [startId]
    while (queue.length) {
      const cur = queue.shift()
      for (const p of reverse.get(cur) || []) {
        if (visited.has(p)) continue
        visited.add(p)
        order.unshift(p)
        queue.push(p)
      }
    }
    return order
  }
}
