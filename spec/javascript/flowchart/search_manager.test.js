import { describe, it, expect, vi, beforeEach } from "vitest"
import { SearchManager } from "flowchart/search_manager"

// SearchManager filters canvas.elements by text and toggles highlight classes on
// the matching [data-element-id] SVG groups. Geometry (fitToContent zoom/pan) is
// stubbed — the focus math is Tier C / Playwright; here we assert the pure
// filtering + highlight-class behavior only.

const el = (id, over = {}) => ({ id, label: id, properties: {}, x: 0, y: 0, width: 100, height: 45, ...over })

function makeCanvas(elements) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  for (const e of elements) {
    const g = document.createElementNS("http://www.w3.org/2000/svg", "g")
    g.setAttribute("data-element-id", e.id)
    svg.appendChild(g)
  }
  document.body.appendChild(svg)
  return {
    svg,
    elements,
    zoomPanManager: { fitToContent: vi.fn(), zoomPercent: 100 },
    onZoomChange: vi.fn(),
  }
}

const groupFor = (canvas, id) => canvas.svg.querySelector(`[data-element-id="${id}"]`)

describe("SearchManager.search", () => {
  let canvas, sm
  beforeEach(() => {
    document.body.innerHTML = ""
    canvas = makeCanvas([
      el("Alpha", { label: "Alpha Process" }),
      el("Beta", { label: "Other", properties: { description: "beta description here" } }),
      el("Gamma", { label: "Third", properties: { steps: [{ action: "validate", selectionLabels: ["Check", "Model"] }] } }),
      el("Delta", { label: "Fourth", properties: { condition: { expression: "ctx.valid?" } } }),
    ])
    sm = new SearchManager(canvas)
  })

  it("returns [] and resets index for a blank query", () => {
    expect(sm.search("   ")).toEqual([])
    expect(sm.currentIndex).toBe(-1)
  })

  it("matches by label (case-insensitive)", () => {
    const r = sm.search("alpha")
    expect(r.map(e => e.id)).toEqual(["Alpha"])
    expect(sm.currentIndex).toBe(0)
  })

  it("matches by description", () => {
    expect(sm.search("description").map(e => e.id)).toEqual(["Beta"])
  })

  it("matches by step action and selectionLabels", () => {
    expect(sm.search("validate").map(e => e.id)).toEqual(["Gamma"])
    expect(sm.search("check model").map(e => e.id)).toEqual(["Gamma"])
  })

  it("tolerates steps missing action or selectionLabels", () => {
    canvas.elements.push(
      el("NoAction", { label: "no-action", properties: { steps: [{ selectionLabels: ["Weird"] }] } }),
      el("NoLabels", { label: "no-labels", properties: { steps: [{ action: "weird_step" }] } })
    )
    expect(sm.search("weird").map(e => e.id).sort()).toEqual(["NoAction", "NoLabels"])
  })

  it("falls through a non-matching action to the selectionLabels default when there are none", () => {
    // action doesn't match, so the step check must reach the selectionLabels
    // fallback (`s.selectionLabels || []`) with selectionLabels absent.
    canvas.elements.push(el("PlainStep", { label: "plain-step", properties: { steps: [{ action: "keep" }] } }))
    expect(sm.search("nonmatching-term-zzz").map(e => e.id)).toEqual([])
  })

  it("returns [] with index -1 when nothing matches", () => {
    expect(sm.search("nonexistent-zzz")).toEqual([])
    expect(sm.currentIndex).toBe(-1)
  })

  it("matches by condition expression", () => {
    expect(sm.search("ctx.valid").map(e => e.id)).toEqual(["Delta"])
  })

  it("applies highlight + current classes to matched groups", () => {
    sm.search("a") // Alpha, Beta("Other"? no)... check which match
    // 'a' appears in "Alpha Process", "beta description", "Gamma"'s labels? label "Third" no.
    // Beta desc has 'a'? "beta description here" contains 'a'. Gamma steps "validate" has 'a'.
    // Delta expression "ctx.valid?" has 'a'.
    for (const e of sm.results) {
      expect(groupFor(canvas, e.id).classList.contains("search-highlight")).toBe(true)
    }
    const current = sm.results[sm.currentIndex]
    expect(groupFor(canvas, current.id).classList.contains("search-current")).toBe(true)
    expect(canvas.zoomPanManager.fitToContent).toHaveBeenCalled()
  })

  it("clearing removes all highlight classes and resets state", () => {
    sm.search("alpha")
    sm.clear()
    expect(sm.results).toEqual([])
    expect(sm.currentIndex).toBe(-1)
    expect(canvas.svg.querySelectorAll(".search-highlight, .search-current")).toHaveLength(0)
  })
})

describe("SearchManager.next / prev", () => {
  let canvas, sm
  beforeEach(() => {
    document.body.innerHTML = ""
    canvas = makeCanvas([el("m1", { label: "match one" }), el("m2", { label: "match two" }), el("m3", { label: "match three" })])
    sm = new SearchManager(canvas)
    sm.search("match")
  })

  it("wraps forward with next()", () => {
    expect(sm.currentIndex).toBe(0)
    sm.next(); expect(sm.currentIndex).toBe(1)
    sm.next(); expect(sm.currentIndex).toBe(2)
    sm.next(); expect(sm.currentIndex).toBe(0) // wraps
  })

  it("wraps backward with prev()", () => {
    sm.prev(); expect(sm.currentIndex).toBe(2) // wraps from 0
    sm.prev(); expect(sm.currentIndex).toBe(1)
  })

  it("next/prev are no-ops with no results", () => {
    sm.clear()
    sm.next()
    sm.prev()
    expect(sm.currentIndex).toBe(-1)
  })

  it("moves the .search-current marker as index changes", () => {
    sm.next()
    expect(groupFor(canvas, "m2").classList.contains("search-current")).toBe(true)
    expect(groupFor(canvas, "m1").classList.contains("search-current")).toBe(false)
  })
})
