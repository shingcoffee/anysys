/**
 * DynamicPorts - Calculates dynamic port positions for Decision elements.
 *
 * Decision: input at top, output ports distributed along lower-half diamond perimeter.
 * Ports derive from outgoing connections ordered by fromPort ("port_N").
 */

// i18n overlay for the fallback port labels — English defaults, replaced at
// runtime by the flowchart controller (setPortLabels) with translated copy.
let PORT_LABELS = { default: "Default", branch: "Branch" }

/** Install translated fallback port labels ({ default, branch }). */
export function setPortLabels(labels) {
  if (labels && typeof labels === "object") PORT_LABELS = { ...PORT_LABELS, ...labels }
}

/** Numeric index of a `port_N` handle; unknown ports sort last. */
export function portIndex(fromPort) {
  const match = /^port_(\d+)$/.exec(String(fromPort || ""))
  return match ? Number(match[1]) : Number.MAX_SAFE_INTEGER
}

/** Outgoing connections of a decision, ordered by fromPort. */
export function outgoingDecisionConnections(connections, decisionId) {
  return (connections || [])
    .filter((conn) => conn.from === decisionId)
    .slice()
    .sort((left, right) => portIndex(left.fromPort) - portIndex(right.fromPort))
}

/**
 * Outgoing decision connections in branch order, with `insertedId` placed
 * right after every branch on a lower-or-equal port: a branch drawn from an
 * already-used port_k lands at index k+1 and earlier branches keep their port.
 */
export function orderedDecisionBranches(connections, decisionId, insertedId = null) {
  const outgoing = outgoingDecisionConnections(connections, decisionId)
  const inserted = outgoing.find((conn) => conn.id === insertedId)
  if (!inserted) return outgoing

  const rest = outgoing.filter((conn) => conn !== inserted)
  const port = portIndex(inserted.fromPort)
  const at = rest.findIndex((conn) => portIndex(conn.fromPort) > port)
  rest.splice(at === -1 ? rest.length : at, 0, inserted)
  return rest
}

/**
 * Get dynamic port positions for a Decision element.
 * Ports are placed on the lower-half diamond perimeter following a specific layout:
 *   - Port 0: bottom (center)
 *   - Port 1: right
 *   - Port 2: left
 *   - Port 3+: fill gaps between existing positions (largest gap first)
 *
 * @param {Object} element - The decision element { x, y, width, height }
 * @param {Array<Object>} [connections] - canvas connections (filtered by `from`)
 * @returns {Object} { input: {position, x, y}, outputs: [{position, x, y, label}] }
 */
export function getDecisionPorts(element, connections = []) {
  const hh = element.height / 2
  const outgoing = outgoingDecisionConnections(connections, element.id)
  const count = Math.max(outgoing.length, 1)

  const input = { position: "top", x: element.x, y: element.y - hh }

  const outputs = []
  for (let i = 0; i < count; i++) {
    const t = branchSlotPosition(i)
    const { x: px, y: py } = diamondLowerPerimeterPoint(element, t)
    const conn = outgoing[i]
    outputs.push({
      position: `port_${i}`,
      x: px,
      y: py,
      label: (conn?.label && String(conn.label).trim()) || (outgoing.length === 0 ? PORT_LABELS.default : PORT_LABELS.branch)
    })
  }

  return { input, outputs }
}

/**
 * Compute the slot position [0..1] for a branch index on the lower diamond perimeter.
 * t=0 is left vertex, t=0.5 is bottom vertex, t=1.0 is right vertex.
 *
 * Layout rule:
 *   Index 0 → 0.5  (bottom/center)
 *   Index 1 → 1.0  (right)
 *   Index 2 → 0.0  (left)
 *   Index 3+ → middle of the largest remaining gap (binary subdivision)
 */
export function branchSlotPosition(branchIndex) {
  if (branchIndex === 0) return 0.5
  if (branchIndex === 1) return 1.0
  if (branchIndex === 2) return 0.0

  const placed = [0.0, 0.5, 1.0]
  let lastPlaced = 0.5
  for (let i = 3; i <= branchIndex; i++) {
    placed.sort((a, b) => a - b)
    let maxGap = 0, maxGapIdx = 0
    for (let j = 0; j < placed.length - 1; j++) {
      const gap = placed[j + 1] - placed[j]
      if (gap > maxGap) {
        maxGap = gap
        maxGapIdx = j
      }
    }
    lastPlaced = (placed[maxGapIdx] + placed[maxGapIdx + 1]) / 2
    placed.push(lastPlaced)
  }
  return lastPlaced
}

/**
 * Calculate a point on the lower-half diamond perimeter.
 * t=0 → left vertex, t=0.5 → bottom vertex, t=1 → right vertex.
 */
function diamondLowerPerimeterPoint(element, t) {
  const cx = element.x
  const cy = element.y
  const hw = element.width / 2
  const hh = element.height / 2

  if (t <= 0.5) {
    const s = t / 0.5
    return {
      x: cx - hw + (hw * s),
      y: cy + (hh * s)
    }
  }

  const s = (t - 0.5) / 0.5
  return {
    x: cx + (hw * s),
    y: cy + hh - (hh * s)
  }
}

/**
 * Check if an element uses dynamic ports.
 */
export function hasDynamicPorts(element) {
  return element.type === "decision"
}

/**
 * Get all port positions for an element (unified interface for connection manager).
 * Returns a map of { portKey: { x, y } } compatible with the existing handle system.
 */
export function getDynamicPortPositions(element, connections = []) {
  if (element.type === "decision") {
    const ports = getDecisionPorts(element, connections)
    const result = { top: ports.input }
    ports.outputs.forEach(p => { result[p.position] = { x: p.x, y: p.y } })
    return result
  }

  return null
}
