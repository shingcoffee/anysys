// English defaults only — this plain class has no controller reference, so
// the caller (ValidationMixin, which has `this.<name>Value`) threads the
// translated strings in via the `messages` constructor param, sourced from
// the matching flowchart_canvas_controller.js Values. Falling back to these
// defaults keeps existing `new ValidationService(elements, connections)`
// calls/specs byte-identical when `messages` is omitted. Mirrors the
// `templates/*.js` DEFAULT_LABELS seam used elsewhere in the codebase.
import { runElementRules } from "flowchart/validation/element_rules"
import { elementLabel } from "flowchart/constants/element_registry"

const DEFAULT_MESSAGES = {
  missingStart: "Flowchart must have a Start element",
  duplicateStart: "Only one Start element is allowed",
  missingEnd: "Flowchart should have at least one End element",
  orphanStartFormat: 'Start element "{label}" has no outgoing connections',
  orphanEndFormat: 'End element "{label}" has no incoming connections',
  orphanElementFormat: '"{label}" is not connected to any other element',
  unreachableFormat: '"{label}" is not reachable from Start',
  duplicateLabelFormat: '{count} elements share the label "{label}" — generated step names derive from labels, so duplicates are renamed unpredictably',
  elementProblemFormat: "{label} ({type}): {message}",
  unsupportedStructuralFormat: 'Element "{label}" uses unsupported structural type "{type}"',
  danglingConnectionFromFormat: "Connection references missing element (from: {id})",
  danglingConnectionToFormat: "Connection references missing element (to: {id})",
  selfConnection: "Element cannot connect to itself",
  duplicateConnection: "Duplicate connection between elements",
  cycle: "Potential infinite loop: cycle detected not involving a Loop element"
}

const UNSUPPORTED_STRUCTURAL_TYPES = new Set([
  "fork", "join", "parallel_for_each", "saga", "signal_wait", "transaction", "switch", "timer"
])

export class ValidationService {
  /**
   * @param {Array<Object>} elements
   * @param {Array<Object>} connections
   * @param {Object} [messages] - translated overrides for DEFAULT_MESSAGES
   * @param {Object} [options]
   * @param {string|number} [options.flowchartId] - id of the flowchart being
   *   edited, used to detect a Subflow element pointing back at it
   */
  constructor(elements, connections, messages = {}, options = {}) {
    this.elements = elements
    this.connections = connections
    this.messages = { ...DEFAULT_MESSAGES, ...messages }
    this.flowchartId = options.flowchartId ?? null
    this.errors = []
    this.warnings = []
  }

  validate() {
    this.errors = []
    this.warnings = []
    this._validateStructure()
    this._validateCompleteness()
    this._validateConnections()
    this._detectCycles()
    return { errors: this.errors, warnings: this.warnings }
  }

  get isValid() {
    return this.errors.length === 0
  }

  /**
   * Interpolate a message template. Token values are inserted raw — the
   * Problems panel renderer escapes the finished message exactly once, so
   * escaping here would double-encode labels containing & < > ".
   * @private
   */
  _message(key, tokens = {}) {
    let text = this.messages[key] ?? ""
    Object.entries(tokens).forEach(([token, value]) => {
      text = text.split(`{${token}}`).join(String(value))
    })
    return text
  }

  /**
   * File a rule result into the right bucket. `severity` is the routing key,
   * not part of the stored problem — ValidationMixin re-stamps it from the
   * bucket the problem came out of.
   * @private
   */
  _record({ severity, ...problem }) {
    ;(severity === "error" ? this.errors : this.warnings).push(problem)
  }

  _validateStructure() {
    const startElements = this.elements.filter(el => el.type === "start")
    const endElements = this.elements.filter(el => el.type === "end")

    if (startElements.length === 0) {
      this.errors.push({ elementId: null, type: "missing_start", message: this.messages.missingStart })
    } else {
      startElements.slice(1).forEach(el => {
        this.errors.push({ elementId: el.id, type: "duplicate_start", message: this.messages.duplicateStart })
      })
    }

    if (endElements.length === 0) {
      this.warnings.push({ elementId: null, type: "missing_end", message: this.messages.missingEnd })
    }

    this._validateConnectivity(startElements)
    this._validateDuplicateLabels()
    this._validateUnsupportedStructuralElements()
  }

  _validateUnsupportedStructuralElements() {
    for (const element of this.elements) {
      if (!UNSUPPORTED_STRUCTURAL_TYPES.has(element.type)) continue
      this.errors.push({
        elementId: element.id,
        type: "unsupported_structural_element",
        message: this._message("unsupportedStructuralFormat", {
          label: this._safe(element.label),
          type: element.type
        })
      })
    }
  }

  /** @private */
  _validateConnectivity(startElements) {
    for (const el of this.elements) {
      const hasIncoming = this.connections.some(c => c.to === el.id)
      const hasOutgoing = this.connections.some(c => c.from === el.id)

      if (el.type === "start" && !hasOutgoing) {
        this.errors.push({ elementId: el.id, type: "orphan_start", message: this._message("orphanStartFormat", { label: this._safe(el.label) }) })
      } else if (el.type === "end" && !hasIncoming) {
        this.warnings.push({ elementId: el.id, type: "orphan_end", message: this._message("orphanEndFormat", { label: this._safe(el.label) }) })
      } else if (el.type !== "start" && el.type !== "end" && !hasIncoming && !hasOutgoing) {
        this.errors.push({ elementId: el.id, type: "orphan_element", message: this._message("orphanElementFormat", { label: this._safe(el.label) }) })
      }
    }

    if (startElements.length !== 1) return

    const reachable = this._getReachableElements(startElements[0].id)
    for (const el of this.elements) {
      if (el.type === "start" || reachable.has(el.id)) continue
      // A fully-disconnected node is already reported as an orphan above;
      // reporting it as "unreachable" too double-counts the badge and lists
      // it twice. Only flag unreachable nodes that actually have a connection.
      const hasAnyConnection = this.connections.some(c => c.from === el.id || c.to === el.id)
      if (!hasAnyConnection) continue
      this.errors.push({ elementId: el.id, type: "unreachable", message: this._message("unreachableFormat", { label: this._safe(el.label) }) })
    }
  }

  /**
   * Generated step names derive from labels, so duplicate labels get renamed
   * unpredictably during code generation — flag every member of each group.
   * @private
   */
  _validateDuplicateLabels() {
    const labelGroups = new Map()
    for (const el of this.elements) {
      const key = (el.label || "").trim().toLowerCase()
      if (!key) continue
      if (!labelGroups.has(key)) labelGroups.set(key, [])
      labelGroups.get(key).push(el)
    }

    for (const group of labelGroups.values()) {
      if (group.length < 2) continue
      group.forEach(el => {
        this.errors.push({
          elementId: el.id,
          type: "duplicate_label",
          message: this._message("duplicateLabelFormat", { count: group.length, label: this._safe(el.label) })
        })
      })
    }
  }

  /**
   * Per-element-type completeness, delegated to the ELEMENT_RULES registry
   * in flowchart/validation/element_rules.js.
   * @private
   */
  _validateCompleteness() {
    const msg = (key, tokens) => this._message(key, tokens)

    for (const element of this.elements) {
      const found = runElementRules({
        element,
        properties: element.properties || {},
        incoming: this.connections.filter(c => c.to === element.id),
        outgoing: this.connections.filter(c => c.from === element.id),
        flowchartId: this.flowchartId,
        msg
      })
      const context = { label: this._safe(element.label), type: elementLabel(element.type) || element.type }
      found.forEach(item => this._record({
        ...item,
        message: this._message("elementProblemFormat", { ...context, message: item.message })
      }))
    }
  }

  _validateConnections() {
    const elementIds = new Set(this.elements.map(el => el.id))
    const seen = new Set()

    for (const conn of this.connections) {
      // connectionId is what lets the Problems panel select the offending edge
      // and what the auto-fix uses to delete exactly the right one.
      if (!elementIds.has(conn.from)) {
        this.errors.push({ elementId: null, connectionId: conn.id, type: "dangling_connection", message: this._message("danglingConnectionFromFormat", { id: conn.from }) })
      }
      if (!elementIds.has(conn.to)) {
        this.errors.push({ elementId: null, connectionId: conn.id, type: "dangling_connection", message: this._message("danglingConnectionToFormat", { id: conn.to }) })
      }
      if (conn.from === conn.to) {
        this.errors.push({ elementId: conn.from, connectionId: conn.id, type: "self_connection", message: this.messages.selfConnection })
      }
      const key = `${conn.from}->${conn.to}`
      if (seen.has(key)) {
        this.warnings.push({ elementId: null, connectionId: conn.id, type: "duplicate_connection", message: this.messages.duplicateConnection })
      }
      seen.add(key)
    }
  }

  /**
   * Report back-edges. Iterative so a
   * deep chain can't blow the stack, and deduplicated by target node so a
   * node reachable through several paths is listed once rather than once per
   * path — the old recursive version produced both.
   */
  _detectCycles() {
    const loopIds = new Set(this.elements.filter(el => el.type === "loop").map(el => el.id))
    const adjacency = new Map()
    for (const el of this.elements) adjacency.set(el.id, [])
    for (const conn of this.connections) {
      if (adjacency.has(conn.from)) adjacency.get(conn.from).push(conn.to)
    }

    const visited = new Set()
    const inStack = new Set()
    const reported = new Set()

    for (const el of this.elements) {
      if (visited.has(el.id)) continue

      // Explicit stack of [nodeId, nextNeighborIndex] frames.
      const stack = [[el.id, 0]]
      visited.add(el.id)
      inStack.add(el.id)

      while (stack.length > 0) {
        const frame = stack[stack.length - 1]
        const [nodeId, index] = frame
        // Every id on the stack came from `adjacency`, so this is never missing.
        const neighbors = adjacency.get(nodeId)

        if (index >= neighbors.length) {
          inStack.delete(nodeId)
          stack.pop()
          continue
        }

        frame[1] = index + 1
        const neighbor = neighbors[index]

        if (inStack.has(neighbor) && !loopIds.has(neighbor) && !reported.has(neighbor)) {
          reported.add(neighbor)
          this.warnings.push({ elementId: neighbor, type: "cycle", message: this.messages.cycle })
        }
        if (!visited.has(neighbor) && adjacency.has(neighbor)) {
          visited.add(neighbor)
          inStack.add(neighbor)
          stack.push([neighbor, 0])
        }
      }
    }
  }

  _getReachableElements(startId) {
    const reachable = new Set()
    const queue = [startId]
    while (queue.length > 0) {
      const current = queue.shift()
      if (reachable.has(current)) continue
      reachable.add(current)
      for (const conn of this.connections) {
        if (conn.from === current && !reachable.has(conn.to)) queue.push(conn.to)
      }
    }
    return reachable
  }

  /**
   * Sanitize text for safe use in messages (prevent XSS if rendered as HTML)
   */
  _safe(text) {
    // Return the raw label only. The Problems panel renderer escapes message
    // text once via escapeHtml at render time; escaping here too double-encodes
    // labels containing & < > " (e.g. "Tom & Jerry" → "Tom &amp; Jerry").
    return text == null ? "" : String(text)
  }
}
