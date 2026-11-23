// NOTE: showGhost() clones a source card and reads its getBoundingClientRect to
// size the ghost — that sizing needs real layout (Playwright, spec/e2e). We
// test the non-geometry surface here: the chip ghost, ghost show/hide class
// wiring, the insertion indicator (driven off a supplied rect, no layout read),
// container highlighting, and source placeholder marking.
import { describe, it, expect, beforeEach } from "vitest"
import { DragVisuals } from "controllers/page_builder/drag_visuals"
import { makeCtrl } from "../../support/page_builder.js"

const el = () => document.createElement("div")

describe("DragVisuals ghost (chip path)", () => {
  let ctrl, dv
  beforeEach(() => {
    ctrl = makeCtrl()
    ctrl.hasDragPreviewTarget = true
    ctrl.dragPreviewTarget = el()
    dv = new DragVisuals(ctrl)
  })

  it("renders a chip ghost with the label set via textContent (XSS-safe)", () => {
    dv.showGhost(null, "<b>Name</b>")
    const labelEl = ctrl.dragPreviewTarget.querySelector("[data-ghost-label]")
    expect(labelEl.textContent).toBe("<b>Name</b>")
    expect(ctrl.dragPreviewTarget.innerHTML).not.toContain("<b>Name</b>") // escaped, not raw
    expect(ctrl.dragPreviewTarget.classList.contains("opacity-100")).toBe(true)
  })

  it("moveGhost writes a translate transform using the grab offset", () => {
    dv.showGhost(null, "X", { x: 5, y: 6 })
    dv.moveGhost(100, 200, { x: 5, y: 6 })
    expect(ctrl.dragPreviewTarget.style.transform).toBe("translate(95px, 194px)")
  })

  it("defaults the chip label to 'Field' when none is supplied", () => {
    dv.showGhost(null)
    expect(ctrl.dragPreviewTarget.querySelector("[data-ghost-label]").textContent).toBe("Field")
  })

  it("moveGhost falls back to the stored grab, then to the default offset", () => {
    dv.showGhost(null, "X", { x: 5, y: 6 }) // stores _grab
    dv.moveGhost(100, 200) // no grab arg → uses stored _grab {5,6}
    expect(ctrl.dragPreviewTarget.style.transform).toBe("translate(95px, 194px)")
    dv._grab = null
    dv.moveGhost(50, 50) // no grab and no _grab → default {16,16}
    expect(ctrl.dragPreviewTarget.style.transform).toBe("translate(34px, 34px)")
  })

  it("renders a reorder ghost by cloning the source node and stripping dimming classes", () => {
    const node = el()
    node.className = "field-card opacity-40"
    node.innerHTML = "<span>Original</span>"
    dv.showGhost(node, null, { x: 3, y: 4 })
    const clone = ctrl.dragPreviewTarget.firstElementChild
    expect(clone).toBeTruthy()
    expect(clone.classList.contains("opacity-40")).toBe(false) // stripped
    expect(clone.style.width).toBe("0px") // happy-dom zero rect
    expect(ctrl.dragPreviewTarget.classList.contains("scale-[1.02]")).toBe(true)
    expect(dv._grab).toEqual({ x: 3, y: 4 })
  })

  it("hideGhost / hideIndicator no-op without their targets", () => {
    const bare = new DragVisuals(makeCtrl())
    expect(() => { bare.hideGhost(); bare.hideIndicator() }).not.toThrow()
  })

  it("hideGhost clears content and flips opacity classes", () => {
    dv.showGhost(null, "X")
    dv.hideGhost()
    expect(ctrl.dragPreviewTarget.innerHTML).toBe("")
    expect(ctrl.dragPreviewTarget.classList.contains("opacity-0")).toBe(true)
    expect(ctrl.dragPreviewTarget.classList.contains("opacity-100")).toBe(false)
  })

  it("gracefully no-ops without a preview target", () => {
    const bare = new DragVisuals(makeCtrl())
    expect(() => bare.showGhost(null, "X")).not.toThrow()
    expect(() => bare.moveGhost(1, 2)).not.toThrow()
  })
})

describe("DragVisuals insertion indicator", () => {
  let ctrl, dv
  beforeEach(() => {
    ctrl = makeCtrl()
    ctrl.hasDropIndicatorTarget = true
    ctrl.dropIndicatorTarget = el()
    dv = new DragVisuals(ctrl)
  })

  it("writes the supplied rect onto the indicator and shows it", () => {
    dv.showIndicator({ orientation: "vertical", rect: { left: 10, top: 20, width: 2, height: 30 } })
    const s = ctrl.dropIndicatorTarget.style
    expect([s.left, s.top, s.width, s.height]).toEqual(["10px", "20px", "2px", "30px"])
    expect(ctrl.dropIndicatorTarget.classList.contains("opacity-100")).toBe(true)
  })

  it("hides the indicator when there is no rect and resets the cache", () => {
    dv.showIndicator({ orientation: "vertical", rect: { left: 1, top: 1, width: 5, height: 5 } })
    dv.showIndicator(null)
    expect(ctrl.dropIndicatorTarget.classList.contains("opacity-0")).toBe(true)
    expect(dv._indLeft).toBeNull()
  })

  it("renders a swap target as a zone (not a thin line)", () => {
    dv.showIndicator({ mode: "swap", orientation: "vertical", rect: { left: 0, top: 0, width: 100, height: 40 } })
    expect(ctrl.dropIndicatorTarget.classList.contains("ring-2")).toBe(true)
    expect(dv._indMode).toBe("zone")
  })

  it("no-ops without a drop-indicator target", () => {
    const bare = new DragVisuals(makeCtrl())
    expect(() => bare.showIndicator({ rect: { left: 0, top: 0, width: 1, height: 1 } })).not.toThrow()
  })

  it("clamps width/height to a 2px minimum for a zero-size rect", () => {
    dv.showIndicator({ orientation: "vertical", rect: { left: 0, top: 0, width: 0, height: 0 } })
    expect(ctrl.dropIndicatorTarget.style.width).toBe("2px")
    expect(ctrl.dropIndicatorTarget.style.height).toBe("2px")
  })

  it("creates horizontal end-cap dots and toggles them off in zone mode, then back on in line mode", () => {
    // line + horizontal → builds end caps via _ensureEndCaps (horizontal branch)
    dv.showIndicator({ orientation: "horizontal", rect: { left: 0, top: 0, width: 100, height: 2 } })
    expect(dv._capA).toBeTruthy()
    expect(dv._capA.className).toContain("left-0")
    const capADisplay = dv._capA.style.display
    // switch to zone → end caps hidden (this._capA present branch)
    dv.showIndicator({ mode: "swap", orientation: "horizontal", rect: { left: 0, top: 0, width: 100, height: 40 } })
    expect(dv._capA.style.display).toBe("none")
    // back to line → end caps shown again
    dv.showIndicator({ mode: "insert", orientation: "horizontal", rect: { left: 5, top: 5, width: 80, height: 2 } })
    expect(dv._capA.style.display).toBe(capADisplay)
  })

  it("reuses existing end caps across successive line indicators (vertical)", () => {
    dv.showIndicator({ orientation: "vertical", rect: { left: 0, top: 0, width: 2, height: 50 } })
    const capA = dv._capA
    dv.showIndicator({ orientation: "vertical", rect: { left: 1, top: 1, width: 2, height: 60 } })
    expect(dv._capA).toBe(capA) // not recreated
  })
})

describe("DragVisuals container highlight", () => {
  let ctrl, dv
  beforeEach(() => {
    document.body.innerHTML = `
      <div data-group-fields-container="g1"></div>
      <div data-parent-field-id="cols"><div data-column-index="0"></div></div>`
    ctrl = makeCtrl()
    dv = new DragVisuals(ctrl)
  })

  it("adds a ring to a group container and clears it when switching to page", () => {
    dv.highlightContainer("group:g1")
    const group = document.querySelector('[data-group-fields-container="g1"]')
    expect(group.classList.contains("ring-2")).toBe(true)
    dv.highlightContainer("page")
    expect(group.classList.contains("ring-2")).toBe(false)
  })

  it("highlights a column container by parent id + index", () => {
    dv.highlightContainer("column:cols:0")
    expect(document.querySelector('[data-column-index="0"]').classList.contains("ring-2")).toBe(true)
  })

  it("no-ops when the key is unchanged", () => {
    dv.highlightContainer("group:g1")
    const first = dv._highlightedEl
    dv.highlightContainer("group:g1")
    expect(dv._highlightedEl).toBe(first)
  })

  it("clears the highlight and stops for a null / page key", () => {
    dv.highlightContainer("group:g1")
    dv.highlightContainer(null)
    expect(dv._highlightedEl).toBeNull()
  })

  it("does nothing when the container element cannot be found", () => {
    dv.highlightContainer("group:missing") // no matching element
    expect(dv._highlightedEl).toBeFalsy()
    dv.highlightContainer("weird:x") // neither group: nor column: → _findContainerEl returns null
    expect(dv._highlightedEl).toBeFalsy()
  })

  it("resolves a column container via the combined-attribute fallback selector", () => {
    document.body.innerHTML = '<div data-parent-field-id="cols2" data-column-index="1"></div>'
    dv.highlightContainer("column:cols2:1")
    expect(document.querySelector('[data-column-index="1"]').classList.contains("ring-2")).toBe(true)
  })
})

describe("DragVisuals source placeholder", () => {
  let ctrl, dv
  beforeEach(() => {
    ctrl = makeCtrl()
    ctrl.hasFieldsContainerTarget = true
    ctrl.fieldsContainerTarget = el()
    ctrl.fieldsContainerTarget.innerHTML = '<div data-field-id="a"></div><div data-field-id="b"></div>'
    dv = new DragVisuals(ctrl)
  })

  it("marks then clears the dashed placeholder outline on the dragged cards", () => {
    dv.markSource(["a", "b"])
    const a = ctrl.fieldsContainerTarget.querySelector('[data-field-id="a"]')
    expect(a.classList.contains("outline-dashed")).toBe(true)
    dv.clearSource()
    expect(a.classList.contains("outline-dashed")).toBe(false)
    expect(a.classList.contains("opacity-50")).toBe(false)
  })

  it("markSource skips ids with no matching card", () => {
    expect(() => dv.markSource(["ghost"])).not.toThrow()
  })

  it("clearSource also strips legacy flat opacity-40 dimming", () => {
    ctrl.fieldsContainerTarget.innerHTML = '<div class="opacity-40" data-field-id="a"></div>'
    dv.clearSource()
    expect(ctrl.fieldsContainerTarget.querySelector('[data-field-id="a"]').classList.contains("opacity-40")).toBe(false)
  })

  it("markSource / clearSource no-op without a fields container target", () => {
    const bare = new DragVisuals(makeCtrl())
    expect(() => { bare.markSource(["a"]); bare.clearSource() }).not.toThrow()
  })
})
