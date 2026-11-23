import { describe, it, expect, beforeEach } from "vitest"
import { TraceOverlayMixin } from "flowchart/canvas/trace_overlay"

// Overlays are built from element DATA coordinates (element.x/width), not real
// layout, so the DOM structure is fully assertable in happy-dom.

function makeHost(elements = []) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  const elementLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
  elementLayer.setAttribute("class", "element-layer")
  svg.appendChild(elementLayer)
  document.body.appendChild(svg)
  return Object.assign(Object.create(TraceOverlayMixin), { svg, elementLayer, elements })
}

const el = (id, over = {}) => ({ id, label: id, x: 100, y: 100, width: 100, height: 45, ...over })
const layer = (host) => host.svg.querySelector(".trace-overlay-layer")

function badgeNumber(host, element) {
  const badgeX = String(element.x - element.width / 2 + 2)
  const badge = [...layer(host).querySelectorAll("circle.trace-overlay-order-badge")]
    .find((c) => c.getAttribute("cx") === badgeX)
  return badge?.nextSibling?.textContent
}

function fills(host) {
  return [...layer(host).querySelectorAll("rect.trace-overlay-rect")].map((r) => r.getAttribute("fill"))
}

describe("TraceOverlayMixin.showTraceOverlay", () => {
  let host
  beforeEach(() => { document.body.innerHTML = "" })

  it("creates a trace-overlay-layer inserted after the element layer", () => {
    host = makeHost([el("a")])
    host.showTraceOverlay([{ element_id: "a", status: "success" }])
    const l = layer(host)
    expect(l).not.toBeNull()
    expect(host.elementLayer.nextSibling).toBe(l)
  })

  it("matches a process step by element_id: success -> green rect + check icon + order badge", () => {
    host = makeHost([el("step-1", { label: "Save record" })])
    host.showTraceOverlay([{ element_id: "step-1", label: "save_record", status: "success" }])
    const l = layer(host)
    const rect = l.querySelector("rect.trace-overlay-rect")
    expect(rect.getAttribute("fill")).toBe("#22c55e")
    expect(rect.getAttribute("stroke-width")).toBe("2.5")
    const texts = [...l.querySelectorAll("text")].map(t => t.textContent)
    expect(texts).toContain("✓")
    expect(texts).toContain("1")
    expect(l.querySelector("circle.trace-overlay-order-badge")).not.toBeNull()
  })

  it("matches a decision by element_id (branch is ignored for overlay colour)", () => {
    const decision = el("dec-1", { label: "Is large?", x: 200 })
    host = makeHost([decision])
    host.showTraceOverlay([{ element_id: "dec-1", label: "is_large", status: "success", branch: "yes" }])
    expect(layer(host).querySelector("rect.trace-overlay-rect").getAttribute("fill")).toBe("#22c55e")
    expect(badgeNumber(host, decision)).toBe("1")
  })

  it("matches Start and End by element_id", () => {
    const start = el("start-1", { label: "Start", x: 100 })
    const end = el("end-1", { label: "End", x: 300 })
    host = makeHost([start, end])
    host.showTraceOverlay([
      { element_id: "start-1", label: "start", status: "success" },
      { element_id: "end-1", label: "end", status: "success" },
    ])
    expect(fills(host).every((f) => f === "#22c55e")).toBe(true)
    expect(badgeNumber(host, start)).toBe("1")
    expect(badgeNumber(host, end)).toBe("2")
  })

  it("failure -> red rect and ✗ icon", () => {
    host = makeHost([el("a")])
    host.showTraceOverlay([{ element_id: "a", status: "failure" }])
    const rect = layer(host).querySelector("rect.trace-overlay-rect")
    expect(rect.getAttribute("fill")).toBe("#ef4444")
    expect([...layer(host).querySelectorAll("text")].map(t => t.textContent)).toContain("✗")
  })

  it("unmatched element -> gray rect, no icon, no order badge", () => {
    host = makeHost([el("a"), el("b")])
    host.showTraceOverlay([{ element_id: "a", status: "success" }])
    const l = layer(host)
    const rects = [...l.querySelectorAll("rect.trace-overlay-rect")]
    expect(rects).toHaveLength(2)
    expect(rects.some(r => r.getAttribute("fill") === "#9ca3af")).toBe(true)
    expect(l.querySelectorAll("circle.trace-overlay-order-badge")).toHaveLength(1)
  })

  it("does not highlight a canvas box for a label-only node (no element_id)", () => {
    host = makeHost([el("x", { label: "Check Status" })])
    host.showTraceOverlay([{ label: "Check Status", status: "success" }])
    const rect = layer(host).querySelector("rect.trace-overlay-rect")
    expect(rect.getAttribute("fill")).toBe("#9ca3af")
    expect(layer(host).querySelector("circle.trace-overlay-order-badge")).toBeNull()
    expect([...layer(host).querySelectorAll("text")].map((t) => t.textContent)).not.toContain("✓")
  })

  it("does not highlight End.failure or helper nodes that carry no element_id, even when a canvas label matches", () => {
    const end = el("end-1", { label: "End", x: 100 })
    host = makeHost([end])
    host.showTraceOverlay([
      { label: "End.failure", status: "failure" },
      { label: "end", status: "failure" },
      { label: "collect_errors", status: "failure" },
    ])
    expect(layer(host).querySelector("rect.trace-overlay-rect").getAttribute("fill")).toBe("#9ca3af")
    expect(badgeNumber(host, end)).toBeUndefined()
  })

  it("assigns execution-order badges by first occurrence order", () => {
    host = makeHost([el("a"), el("b")])
    host.showTraceOverlay([
      { element_id: "b", status: "success" },
      { element_id: "a", status: "success" },
    ])
    const texts = [...layer(host).querySelectorAll("text")].map(t => t.textContent)
    expect(texts).toContain("1")
    expect(texts).toContain("2")
  })

  it("numbers distinct elements 1, 2, 3… in first-execution order (repeats do not skip)", () => {
    const start = el("start", { x: 100 })
    const proc = el("proc", { x: 300 })
    const end = el("end", { x: 500 })
    host = makeHost([start, proc, end])
    host.showTraceOverlay([
      { element_id: "start", status: "success" },
      { element_id: "proc", status: "success" },
      { element_id: "proc", status: "success" },
      { element_id: "end", status: "success" },
    ])
    expect(badgeNumber(host, start)).toBe("1")
    expect(badgeNumber(host, proc)).toBe("2")
    expect(badgeNumber(host, end)).toBe("3")
    expect(layer(host).querySelectorAll("circle.trace-overlay-order-badge")).toHaveLength(3)
  })

  it("does not consume an order number for a node without element_id", () => {
    const start = el("start", { x: 100 })
    const proc = el("proc", { x: 300 })
    host = makeHost([start, proc])
    host.showTraceOverlay([
      { element_id: "start", status: "success" },
      { label: "End.failure", status: "failure" },
      { element_id: "proc", status: "success" },
    ])
    expect(badgeNumber(host, start)).toBe("1")
    expect(badgeNumber(host, proc)).toBe("2")
  })

  it("uses an element's last status for colour and icon when it appears more than once", () => {
    host = makeHost([el("a")])
    host.showTraceOverlay([
      { element_id: "a", status: "success" },
      { element_id: "a", status: "failure" },
    ])
    const l = layer(host)
    expect(l.querySelector("rect.trace-overlay-rect").getAttribute("fill")).toBe("#ef4444")
    expect([...l.querySelectorAll("text")].map((t) => t.textContent)).toContain("✗")
    expect([...l.querySelectorAll("text")].map((t) => t.textContent)).not.toContain("✓")
  })

  it("does not match a later canvas element by label when the node already has element_id", () => {
    host = makeHost([el("a", { label: "Process" }), el("b", { label: "Process" })])
    host.showTraceOverlay([{ element_id: "a", label: "Process", status: "success" }])
    const rects = [...layer(host).querySelectorAll("rect.trace-overlay-rect")]
    expect(rects.filter((r) => r.getAttribute("fill") === "#22c55e")).toHaveLength(1)
    expect(rects.filter((r) => r.getAttribute("fill") === "#9ca3af")).toHaveLength(1)
    expect(layer(host).querySelectorAll("circle.trace-overlay-order-badge")).toHaveLength(1)
  })

  it("ignores a no-id node and empty element_id so only a later id match highlights", () => {
    const a = el("a", { x: 100 })
    host = makeHost([a])
    host.showTraceOverlay([
      { status: "success" },
      { label: "!!!", status: "failure" },
      { element_id: "", status: "success" },
      { element_id: "a", status: "success" },
    ])
    expect(layer(host).querySelector("rect.trace-overlay-rect").getAttribute("fill")).toBe("#22c55e")
    expect(badgeNumber(host, a)).toBe("1")
  })

  it("defaults a trace node's status to 'unknown' when the server omits it", () => {
    host = makeHost([el("a")])
    host.showTraceOverlay([{ element_id: "a" }])
    const rect = layer(host).querySelector("rect.trace-overlay-rect")
    expect(rect.getAttribute("fill")).toBe("#9ca3af")
  })

  it("clearTraceOverlay removes the layer, and re-showing replaces it", () => {
    host = makeHost([el("a")])
    host.showTraceOverlay([{ element_id: "a", status: "success" }])
    host.clearTraceOverlay()
    expect(layer(host)).toBeNull()
    expect(host._traceOverlayLayer).toBeNull()

    host.showTraceOverlay([{ element_id: "a", status: "success" }])
    host.showTraceOverlay([{ element_id: "a", status: "failure" }])
    expect(host.svg.querySelectorAll(".trace-overlay-layer")).toHaveLength(1)
  })
})
