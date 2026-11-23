import { describe, it, expect, afterEach } from "vitest"
import {
  setPortLabels,
  getDecisionPorts,
  branchSlotPosition,
  hasDynamicPorts,
  getDynamicPortPositions,
  portIndex,
  outgoingDecisionConnections,
  orderedDecisionBranches
} from "flowchart/dynamic_ports"

const decision = (id = "d", extra = {}) => ({
  id,
  type: "decision",
  x: 100,
  y: 100,
  width: 80,
  height: 60,
  properties: {},
  ...extra
})

describe("portIndex / outgoingDecisionConnections", () => {
  it("sorts port_N numerically and sends unknown ports last", () => {
    expect(portIndex("port_2")).toBe(2)
    expect(portIndex("bottom")).toBe(Number.MAX_SAFE_INTEGER)
    const outgoing = outgoingDecisionConnections([
      { id: "b", from: "d", to: "2", fromPort: "port_2" },
      { id: "a", from: "d", to: "0", fromPort: "port_0" },
      { id: "other", from: "x", to: "y" }
    ], "d")
    expect(outgoing.map((c) => c.id)).toEqual(["a", "b"])
  })

  it("treats a missing connections list as empty", () => {
    expect(outgoingDecisionConnections(undefined, "d")).toEqual([])
  })
})

describe("orderedDecisionBranches", () => {
  it("returns outgoing order when no inserted id is given", () => {
    const connections = [
      { id: "b", from: "d", to: "2", fromPort: "port_1" },
      { id: "a", from: "d", to: "1", fromPort: "port_0" },
    ]
    expect(orderedDecisionBranches(connections, "d").map((c) => c.id)).toEqual(["a", "b"])
    expect(orderedDecisionBranches(connections, "d", "missing").map((c) => c.id)).toEqual(["a", "b"])
  })

  it("inserts a new branch drawn from port_k at index k+1 and keeps earlier ports", () => {
    const connections = [
      { id: "a", from: "d", to: "yes", fromPort: "port_0" },
      { id: "b", from: "d", to: "no", fromPort: "port_1" },
      { id: "fresh", from: "d", to: "new", fromPort: "port_0" },
    ]
    expect(orderedDecisionBranches(connections, "d", "fresh").map((c) => c.id)).toEqual(["a", "fresh", "b"])
  })

  it("appends a branch drawn from the last existing port", () => {
    const connections = [
      { id: "a", from: "d", to: "yes", fromPort: "port_0" },
      { id: "b", from: "d", to: "no", fromPort: "port_1" },
      { id: "fresh", from: "d", to: "new", fromPort: "port_1" },
    ]
    expect(orderedDecisionBranches(connections, "d", "fresh").map((c) => c.id)).toEqual(["a", "b", "fresh"])
  })
})

describe("branchSlotPosition", () => {
  it("uses the fixed slots for the first three branches", () => {
    expect(branchSlotPosition(0)).toBe(0.5)
    expect(branchSlotPosition(1)).toBe(1.0)
    expect(branchSlotPosition(2)).toBe(0.0)
  })

  it("places later branches in the largest remaining gap", () => {
    expect(branchSlotPosition(3)).toBe(0.25)
    expect(branchSlotPosition(4)).toBe(0.75)
    for (let i = 0; i <= 8; i++) {
      const t = branchSlotPosition(i)
      expect(t).toBeGreaterThanOrEqual(0)
      expect(t).toBeLessThanOrEqual(1)
    }
  })
})

describe("setPortLabels", () => {
  afterEach(() => setPortLabels({ default: "Default", branch: "Branch" }))

  it("installs translated fallback port labels", () => {
    setPortLabels({ default: "默认", branch: "分支" })
    expect(getDecisionPorts(decision()).outputs[0].label).toBe("默认")
  })

  it("ignores a nullish or non-object argument", () => {
    setPortLabels({ default: "默认" })
    setPortLabels(null)
    setPortLabels("nope")
    expect(getDecisionPorts(decision()).outputs[0].label).toBe("默认")
  })
})

describe("getDecisionPorts", () => {
  it("input is always the top vertex", () => {
    const { input } = getDecisionPorts(decision())
    expect(input).toEqual({ position: "top", x: 100, y: 100 - 30 })
  })

  it("returns a single Default output when there are no outgoing connections", () => {
    const { outputs } = getDecisionPorts(decision())
    expect(outputs).toHaveLength(1)
    expect(outputs[0]).toMatchObject({ position: "port_0", label: "Default", x: 100, y: 130 })
    expect(outputs[0]).not.toHaveProperty("branchKey")
  })

  it("maps each outgoing connection to a numbered port on the lower perimeter", () => {
    const connections = [
      { id: "c0", from: "d", to: "a", fromPort: "port_0", label: "Yes" },
      { id: "c1", from: "d", to: "b", fromPort: "port_1", label: "No" },
      { id: "c2", from: "d", to: "c", fromPort: "port_2", label: "Maybe" }
    ]
    const { outputs } = getDecisionPorts(decision(), connections)
    expect(outputs.map((o) => o.position)).toEqual(["port_0", "port_1", "port_2"])
    expect(outputs.map((o) => o.label)).toEqual(["Yes", "No", "Maybe"])
    expect(outputs[0]).toMatchObject({ x: 100, y: 130 })
    expect(outputs[1]).toMatchObject({ x: 140, y: 100 })
    expect(outputs[2]).toMatchObject({ x: 60, y: 100 })
  })

  it("falls back to the Branch label when a connection has no label", () => {
    const connections = [{ id: "c0", from: "d", to: "a", fromPort: "port_0" }]
    expect(getDecisionPorts(decision(), connections).outputs[0].label).toBe("Branch")
  })
})

describe("hasDynamicPorts", () => {
  it("is true only for decision", () => {
    expect(hasDynamicPorts({ type: "decision" })).toBe(true)
    expect(hasDynamicPorts({ type: "process" })).toBe(false)
  })
})

describe("getDynamicPortPositions", () => {
  it("returns {top, port_N...} for a decision", () => {
    const connections = [{ id: "c0", from: "d", to: "a", fromPort: "port_0", label: "Yes" }]
    const map = getDynamicPortPositions(decision(), connections)
    expect(map.top).toMatchObject({ x: 100, y: 70 })
    expect(map.port_0).toEqual({ x: 100, y: 130 })
  })

  it("returns null for non-dynamic element types", () => {
    expect(getDynamicPortPositions({ type: "process" })).toBeNull()
  })
})
