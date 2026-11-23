/**
 * Auto-correct engine for flowchart validation problems.
 *
 * Every entry in AUTO_FIXES turns one validation rule into a concrete canvas
 * mutation. The Problems panel renders a per-problem button for whatever
 * `buildAutoFix` returns, and "Fix all" applies only the entries marked
 * `safe` — the ones whose correction is fully determined by the flowchart
 * itself (clamp a count, number an unlabelled branch, drop an impossible
 * edge). The rest are marked `suggested`: they invent a starting value or
 * remove/add an element, so they stay a deliberate one-click choice.
 *
 * i18n seam: this is a plain module with no controller reference, so labels
 * arrive as a `labels` map threaded in by ValidationMixin from the
 * flowchart_canvas_controller.js `autoFix*` Values. The English defaults below
 * keep direct calls (and specs) working unchanged.
 */

import { DEFAULT_ELEMENT_HEIGHT, DEFAULT_ELEMENT_SPACING } from "flowchart/constants"
import { uniqueLabel } from "flowchart/labels"

export const DEFAULT_AUTO_FIX_LABELS = {
  deleteExtraStart: "Delete this Start",
  renameUnique: "Rename uniquely",
  removeConnection: "Remove connection",
  addEnd: "Add an End element",
  connectToEnd: "Connect from the last step",
  setReturnValue: "Use {value}",
  clearSubflowTarget: "Clear the target"
}

/** Fallback seeds for the "suggested" fixes that need a starting value. */
const SUGGESTED_VALUES = {
  returnValue: "ctx[:result]"
}

// ===================
// Canvas helpers
// ===================

function findElement(canvas, id) {
  return canvas.elements.find(el => el.id === id) || null
}

function findConnection(canvas, id) {
  return canvas.connections.find(c => c.id === id) || null
}

/**
 * Merge properties onto an element through the canvas API when available so
 * undo/redo and the change hooks fire, falling back to a direct write for the
 * lightweight canvases used in tests.
 */
function patchProperties(canvas, elementId, patch) {
  if (typeof canvas.updateElementProperties === "function") {
    return Boolean(canvas.updateElementProperties(elementId, undefined, patch))
  }
  const element = findElement(canvas, elementId)
  if (!element) return false
  element.properties = { ...(element.properties || {}), ...patch }
  return true
}

/** Callers resolve the element first (they need it to build the new label). */
function relabelElement(canvas, element, label) {
  if (typeof canvas.updateElementProperties === "function") {
    return Boolean(canvas.updateElementProperties(element.id, label, undefined))
  }
  element.label = label
  return true
}

function removeConnection(canvas, connectionId) {
  if (!findConnection(canvas, connectionId)) return false
  canvas.onBeforeChange?.()
  canvas.deleteConnection(connectionId)
  canvas.onchange?.()
  return true
}

const NON_TERMINAL_TYPES = new Set(["start", "end", "decision"])

/**
 * Dead ends of the reachable graph — the natural sources for an End: elements
 * reached from Start (breadth-first, in connection order) that are not
 * Start/End/Decision and have no outgoing connection.
 */
function terminalElements(canvas) {
  const start = canvas.elements.find(el => el.type === "start")
  if (!start) return []

  const byId = new Map(canvas.elements.map(el => [el.id, el]))
  const visited = new Set([start.id])
  const queue = [start]
  const terminals = []
  while (queue.length > 0) {
    const element = queue.shift()
    const targets = canvas.connections.filter(c => c.from === element.id).map(c => byId.get(c.to))
    if (targets.length === 0 && !NON_TERMINAL_TYPES.has(element.type)) terminals.push(element)
    targets.forEach(target => {
      if (!target || visited.has(target.id)) return
      visited.add(target.id)
      queue.push(target)
    })
  }
  return terminals
}

const lastTerminal = (canvas) => terminalElements(canvas).at(-1) || null

/** Centre of a default-sized element placed one spacing below `source`. */
function positionBelow(source) {
  return {
    x: source.x,
    y: source.y + source.height / 2 + DEFAULT_ELEMENT_SPACING + DEFAULT_ELEMENT_HEIGHT / 2
  }
}

// ===================
// Fix registry
// ===================

/**
 * Each entry declares:
 *   safe    — included in "Fix all"
 *   label   — (problem, canvas, labels) => button caption
 *   apply   — (problem, canvas) => boolean; false means "nothing to do"
 * `available` (optional) gates whether the fix can be offered at all.
 */
export const AUTO_FIXES = {
  duplicate_start: {
    safe: false,
    label: (_p, _c, labels) => labels.deleteExtraStart,
    apply: (problem, canvas) => {
      const element = findElement(canvas, problem.elementId)
      if (!element || typeof canvas._deleteElement !== "function") return false
      canvas.onBeforeChange?.()
      canvas._deleteElement(element)
      canvas.onchange?.()
      return true
    }
  },

  duplicate_label: {
    safe: true,
    label: (_p, _c, labels) => labels.renameUnique,
    apply: (problem, canvas) => {
      const element = findElement(canvas, problem.elementId)
      if (!element) return false
      const others = canvas.elements.filter(el => el.id !== element.id)
      const label = uniqueLabel(others, element.label, canvas.labels?.uniqueLabelFormat)
      if (label === String(element.label ?? "").trim()) return false
      return relabelElement(canvas, element, label)
    }
  },

  self_connection: {
    safe: true,
    label: (_p, _c, labels) => labels.removeConnection,
    apply: (problem, canvas) => removeConnection(canvas, problem.connectionId)
  },

  duplicate_connection: {
    safe: true,
    label: (_p, _c, labels) => labels.removeConnection,
    apply: (problem, canvas) => removeConnection(canvas, problem.connectionId)
  },

  dangling_connection: {
    safe: true,
    label: (_p, _c, labels) => labels.removeConnection,
    apply: (problem, canvas) => removeConnection(canvas, problem.connectionId)
  },

  end_no_return_value: {
    safe: false,
    label: (_p, _c, labels) => labels.setReturnValue.replace("{value}", SUGGESTED_VALUES.returnValue),
    apply: (problem, canvas) => patchProperties(canvas, problem.elementId, { returnValue: SUGGESTED_VALUES.returnValue })
  },

  subflow_self_reference: {
    safe: false,
    label: (_p, _c, labels) => labels.clearSubflowTarget,
    apply: (problem, canvas) => patchProperties(canvas, problem.elementId, { flowchartId: "" })
  },

  missing_end: {
    safe: false,
    available: (_p, canvas) => lastTerminal(canvas) !== null,
    label: (_p, _c, labels) => labels.addEnd,
    apply: (_problem, canvas) => {
      const source = lastTerminal(canvas)
      if (!source || typeof canvas.addElement !== "function" || typeof canvas.createConnection !== "function") return false
      // Element + connection are one undo entry: both commits share a key.
      const previousKey = canvas.undoCoalesceKey
      canvas.undoCoalesceKey = `autofix:missing_end:${source.id}`
      try {
        const end = canvas.addElement({ type: "end", ...positionBelow(source) })
        if (!end) return false
        canvas.createConnection(source, end, "bottom", "top")
        canvas.updateConnections?.()
        canvas.onchange?.()
        return true
      } finally {
        canvas.undoCoalesceKey = previousKey
      }
    }
  },

  orphan_end: {
    safe: false,
    available: (_p, canvas) => lastTerminal(canvas) !== null,
    label: (_p, _c, labels) => labels.connectToEnd,
    apply: (problem, canvas) => {
      const end = findElement(canvas, problem.elementId)
      const source = lastTerminal(canvas)
      if (!end || !source || typeof canvas.createConnection !== "function") return false
      canvas.onBeforeChange?.()
      canvas.createConnection(source, end, "bottom", "top")
      canvas.updateConnections?.()
      canvas.onchange?.()
      return true
    }
  }
}

/**
 * Resolve the auto-fix for a problem, if one exists and applies right now.
 * @param {Object} problem - a validation problem ({ type, elementId, connectionId, meta })
 * @param {Object} canvas - the flowchart canvas engine
 * @param {Object} [labels] - translated button captions (see DEFAULT_AUTO_FIX_LABELS)
 * @returns {{ type: string, label: string, safe: boolean, apply: function }|null}
 */
export function buildAutoFix(problem, canvas, labels = {}) {
  if (canvas?.canMutate?.() === false) return null
  const entry = AUTO_FIXES[problem?.type]
  if (!entry || !canvas) return null
  if (entry.available && !entry.available(problem, canvas)) return null

  const resolved = { ...DEFAULT_AUTO_FIX_LABELS, ...labels }
  return {
    type: problem.type,
    safe: entry.safe,
    label: entry.label(problem, canvas, resolved),
    apply: () => entry.apply(problem, canvas) === true
  }
}

/**
 * Apply every safe fix among `problems`, newest problems last.
 *
 * Fixes run one at a time and each is re-resolved against the live canvas, so
 * a fix invalidated by an earlier one (a connection already deleted, an
 * element already renamed) simply reports no change instead of throwing.
 * @returns {{ applied: number, skipped: number }}
 */
export function applySafeAutoFixes(problems, canvas, labels = {}) {
  if (canvas?.canMutate?.() === false) {
    return { applied: 0, skipped: (problems || []).length }
  }
  let applied = 0
  let skipped = 0

  for (const problem of problems || []) {
    const fix = buildAutoFix(problem, canvas, labels)
    if (!fix || !fix.safe) {
      skipped += 1
      continue
    }
    if (fix.apply()) applied += 1
    else skipped += 1
  }

  return { applied, skipped }
}

/** How many of `problems` a "Fix all" pass would attempt. */
export function countSafeAutoFixes(problems, canvas, labels = {}) {
  return (problems || []).reduce((count, problem) => {
    const fix = buildAutoFix(problem, canvas, labels)
    return fix && fix.safe ? count + 1 : count
  }, 0)
}
