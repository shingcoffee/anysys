import { generateId } from "utils"
import { branchSlotPosition, outgoingDecisionConnections } from "flowchart/dynamic_ports"

function outgoingCountFor(manager, decisionElement) {
  const fromCanvas = outgoingDecisionConnections(manager.controller.canvas?.connections, decisionElement?.id).length
  if (fromCanvas > 0) return fromCanvas
  const container = manager.controller.formFieldsTarget?.querySelector("[data-branches-container]")
  const fromDom = container?.querySelectorAll("[data-branch-item]").length || 0
  return fromDom || 1
}

function branchItemId(manager, elementId) {
  const container = manager.controller.formFieldsTarget?.querySelector("[data-branches-container]")
  if (!container || !elementId) return false
  return Boolean(container.querySelector(`[data-branch-element-id="${elementId}"]`))
}

/**
 * CanvasOperationsMixin provides branch element creation, removal, repositioning,
 * and refresh methods on the flowchart canvas.
 * Apply to a class using Object.assign(BranchManager.prototype, CanvasOperationsMixin)
 */
export const CanvasOperationsMixin = {
  _createBranchElement(branchLabel, conditionOption, explicitBranchIndex = null) {
    if (!this.controller.canvas || !this.controller.currentElement) return null
    if (this.controller.currentElement.type !== "decision") return null

    // Use explicit index if provided, otherwise count DOM items
    const container = this.controller.formFieldsTarget?.querySelector("[data-branches-container]")
    const existingBranches = container?.querySelectorAll("[data-branch-item]") || []
    const branchIndex = explicitBranchIndex == null ? existingBranches.length : explicitBranchIndex

    const fallbackName = this._defaultBranchName(branchIndex + 1)
    const processLabel = branchLabel || conditionOption?.label || fallbackName
    const elementData = {
      type: "process",
      label: processLabel,
      properties: {
        description: ""
      }
    }

    // Create the element using canvas method
    const branchElement = this._addBranchElementToCanvas(
      elementData,
      this.controller.currentElement,
      branchIndex,
      processLabel
    )

    return branchElement
  },

  _addBranchElementToCanvas(elementData, decisionElement, branchIndex, connectionLabel) {
    if (!this.controller.canvas) return null

    // Calculate position using the slot-based layout
    const { x, y } = this._calculateBranchCanvasPosition(decisionElement, branchIndex)

    // Determine connection positions for the connector line
    // Decision elements use dynamic ports (port_0, port_1, ...) not cardinal positions
    const fromPos = `port_${branchIndex}`
    const toPos = "top"

    // Create element directly
    const newId = generateId()

    const element = {
      id: newId,
      type: elementData.type,
      x: Math.round(x),
      y: Math.round(y),
      width: 100,
      height: 45,
      label: elementData.label,
      properties: {
        inputs: [],
        outputs: [],
        description: elementData.properties?.description || "",
        ...(elementData.properties || {})
      }
    }

    this.controller.canvas.elements.push(element)
    this.controller.canvas.renderElement(element)

    // Create connection with branch label on the connection line
    // The branch manager owns the branch list here, so skip the canvas-side
    // auto-branch derivation (it would fight the editor's own indexing).
    this.controller.canvas.createConnection(decisionElement, element, fromPos, toPos, { label: connectionLabel, skipBranchSync: true })

    // NOTE: Do NOT call canvas.onchange() here — the caller (addBranch/removeBranch)
    // handles the complete change cycle including repositioning and undo commit.

    return element
  },

  _removeBranchConnectionFromCanvas(connectionId, elementId) {
    const canvas = this.controller.canvas
    if (!canvas) return

    const decisionId = this.controller.currentElement?.id
    const connections = canvas.connections || []
    const target = connections.find((conn) => (
      (connectionId && conn.id === connectionId) ||
      (decisionId && elementId && conn.from === decisionId && conn.to === elementId)
    ))
    if (!target) return

    if (typeof canvas.deleteConnection === "function") {
      canvas.deleteConnection(target.id)
      return
    }

    canvas.connections = connections.filter((conn) => conn !== target)
    canvas.updateConnections?.()
  },

  /**
   * Remap fromPort values on connections from the Decision to match re-indexed branch order.
   * After a branch is removed, remaining connections may have stale port indices.
   */
  _remapBranchConnections(decisionElement) {
    if (!this.controller.canvas) return

    const canvas = this.controller.canvas
    const container = this.controller.formFieldsTarget?.querySelector("[data-branches-container]")
    if (!container) return

    const branchItems = container.querySelectorAll("[data-branch-item]")

    // Build a map: branchElementId → new port index
    const elementIdToPort = {}
    branchItems.forEach((item, i) => {
      const elementId = item.dataset.branchElementId
      if (elementId) {
        elementIdToPort[elementId] = `port_${i}`
      }
    })

    // Update connections from the Decision element
    ;(canvas.connections || []).forEach(conn => {
      if (conn.from === decisionElement.id && elementIdToPort[conn.to]) {
        conn.fromPort = elementIdToPort[conn.to]
        conn.fromPosition = null
      }
    })
  },

  /**
   * Lay the decision's branch boxes out in a single horizontal row, ordered
   * left-to-right to match their diamond OUTPUT PORTS (slot order: port_0
   * center, port_1 right, port_2 left, then gap-fills — see branchSlotPosition).
   * Ordering the boxes by the same slot makes every connector fan out
   * monotonically, so branch lines never cross.
   *
   * Only X is laid out by slot. The row's Y is the one the branches ALREADY
   * sit on (most common current Y) — never a recomputed Y that could drop a
   * branch on top of the elements below it (that was the earlier overlap bug).
   * branch_0 is always slot 0.5 (center == decision.x), so a centered branch
   * with a downstream chain stays exactly put. Each box that
   * does move carries its own downstream subtree with it.
   */
  _layoutDecisionBranches(decisionElement) {
    const canvas = this.controller.canvas
    if (!canvas) return

    // Read the ordered branch element IDs from the DOM (the source of truth,
    // and the only place the just-added branch's elementId is reliably set —
    // properties.branches is collected before it). Same source as
    // _remapBranchConnections, so slot indices line up with the ports.
    const container = this.controller.formFieldsTarget?.querySelector("[data-branches-container]")
    if (!container) return
    const boxes = Array.from(container.querySelectorAll("[data-branch-item]"))
      .map(item => canvas.elements.find(el => el.id === item.dataset.branchElementId))
      .filter(Boolean)
      .map(box => ({ box }))
    if (boxes.length === 0) return

    // Preserve the row the branches already occupy (most common Y; ties -> top).
    const ys = boxes.map(e => e.box.y)
    const counts = new Map()
    for (const y of ys) counts.set(y, (counts.get(y) || 0) + 1)
    let rowY = ys[0]
    let bestCount = 0
    for (const [y, count] of counts) {
      if (count > bestCount || (count === bestCount && y < rowY)) {
        rowY = y
        bestCount = count
      }
    }

    boxes.forEach(({ box }, i) => {
      // _calculateBranchCanvasPosition gives the slot-based X (and a formula Y
      // we deliberately ignore in favor of the preserved row).
      const { x } = this._calculateBranchCanvasPosition(decisionElement, i)
      const dx = x - box.x
      const dy = rowY - box.y
      if (dx === 0 && dy === 0) return

      box.x = x
      box.y = rowY
      canvas.updateElementPosition(box)

      // Carry the branch's own downstream chain along so it stays attached.
      for (const { id } of canvas._getSubTreeElements(box.id)) {
        const child = canvas.elements.find(el => el.id === id)
        if (!child) continue
        child.x += dx
        child.y += dy
        canvas.updateElementPosition(child)
      }
    })
  },

  /**
   * Keep the branch row from landing on top of the decision's existing
   * downstream chain. A decision placed mid-flow
   * has elements already sitting ~120px below it — exactly where branch boxes
   * are dropped — so a freshly added branch overlaps them. Shift any non-branch
   * downstream subtree that intrudes into the branch row down to clear it.
   * Idempotent: a subtree already below the row is left alone, so adding more
   * branches doesn't keep pushing it further.
   */
  _ensureBranchRowClearance(decisionElement) {
    const canvas = this.controller.canvas
    if (!canvas) return

    const hh = (decisionElement.height || 45) / 2
    const verticalSpacing = 120
    const boxHalf = 45 / 2
    const gap = 40
    const rowCenterY = decisionElement.y + hh + verticalSpacing
    const rowTop = rowCenterY - boxHalf
    const rowBottom = rowCenterY + boxHalf

    const branchIds = new Set(
      (canvas.connections || [])
        .filter(c => c.from === decisionElement.id && (c.fromPort || branchItemId(this, c.to)))
        .map(c => c.to)
        .filter(Boolean)
    )

    // Non-branch (cardinal-port) children sitting below the decision.
    const cardinalChildren = (canvas.connections || [])
      .filter(c => c.from === decisionElement.id && !c.fromPort && !branchIds.has(c.to))
      .map(c => canvas.elements.find(el => el.id === c.to))
      .filter(child => child && child.y > decisionElement.y)

    for (const child of cardinalChildren) {
      const subtreeIds = [child.id, ...canvas._getSubTreeElements(child.id).map(s => s.id)]
      const subtree = subtreeIds.map(id => canvas.elements.find(el => el.id === id)).filter(Boolean)
      if (subtree.length === 0) continue

      const minTop = Math.min(...subtree.map(el => el.y - (el.height || 45) / 2))
      const maxBottom = Math.max(...subtree.map(el => el.y + (el.height || 45) / 2))

      // Shift only when the subtree actually intrudes into the branch row band.
      if (minTop < rowBottom + gap && maxBottom > rowTop) {
        const shift = (rowBottom + gap) - minTop
        if (shift > 0) canvas.shiftElementAndSubTree(child, 0, shift)
      }
    }
  },

  /**
   * Calculate the canvas position for a branch element based on the slot layout rule.
   * The slot position (0..1) maps directly to the horizontal offset:
   *   slot 0.0 (left) → decision.x - spread
   *   slot 0.5 (center/bottom) → decision.x
   *   slot 1.0 (right) → decision.x + spread
   *
   * This matches the port positions on the diamond, so connections never cross.
   */
  _calculateBranchCanvasPosition(decisionElement, branchIndex) {
    const decisionHeight = decisionElement.height || 45
    const hh = decisionHeight / 2
    const minSpacing = 140  // minimum center-to-center distance (100px width + 40px gap)
    const verticalSpacing = 120

    const totalBranches = outgoingCountFor(this, decisionElement)
    const y = Math.round(decisionElement.y + hh + verticalSpacing)
    const slot = branchSlotPosition(branchIndex)

    // Calculate spread so the smallest gap between adjacent branches >= minSpacing.
    // Collect all slot positions, sort, find the smallest gap.
    let spread = minSpacing  // default for 1-2 branches
    if (totalBranches >= 2) {
      const allSlots = []
      for (let i = 0; i < totalBranches; i++) {
        allSlots.push(branchSlotPosition(i))
      }
      allSlots.sort((a, b) => a - b)

      let minGap = 1
      for (let j = 0; j < allSlots.length - 1; j++) {
        const gap = allSlots[j + 1] - allSlots[j]
        if (gap > 0 && gap < minGap) minGap = gap
      }
      // spread = minSpacing / (2 * minGap) ensures the smallest gap maps to minSpacing
      spread = Math.max(minSpacing, minSpacing / (2 * minGap))
    }

    // Map slot [0..1] to x offset: slot 0.5 = center, 0.0 = -spread, 1.0 = +spread
    const x = Math.round(decisionElement.x + (slot - 0.5) * 2 * spread)

    return { x, y }
  },

  _refreshDecisionElement(element) {
    if (!this.controller.canvas) return

    const group = this.controller.canvas.elementLayer?.querySelector(`[data-element-id="${element.id}"]`)
    if (group) {
      group.remove()
      this.controller.canvas.renderElement(element)
    }
  }
}
