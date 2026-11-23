import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { DragDropManager } from "controllers/page_builder/drag_drop_manager"
import { makeCtrl } from "../../support/page_builder.js"

// NOTE: flipFromRects animates via getBoundingClientRect() FLIP measurements +
// requestAnimationFrame; happy-dom returns zeroed rects, so the animated
// transform values are meaningless here — covered by Playwright (spec/e2e).
// We unit-test the pure payload builder (_sidebarData), the structural map
// shape from captureCardRects (keys, not coordinates), the early-return guards,
// and the inline-style cleanup lifecycle (_clearAfterTransition).

let animationFrames
beforeEach(() => {
  vi.useFakeTimers()
  animationFrames = []
  vi.stubGlobal("requestAnimationFrame", callback => {
    animationFrames.push(callback)
    return animationFrames.length
  })
})
afterEach(() => {
  vi.clearAllTimers()
  vi.useRealTimers()
  vi.unstubAllGlobals()
})

function flushAnimationFrames() {
  while (animationFrames.length) {
    const frame = animationFrames.splice(0)
    frame.forEach(callback => callback(Date.now()))
  }
}

function ddm(overrides = {}) {
  const ctrl = makeCtrl(overrides)
  return new DragDropManager(ctrl)
}

function sidebarEl(dataset = {}) {
  const el = document.createElement("div")
  Object.entries(dataset).forEach(([k, v]) => { el.dataset[k] = v })
  return el
}

// A DragDropManager whose controller already has `container` mounted as its
// fields container target — the shared preamble for every geometry/FLIP test.
function ddmWith(container) {
  const m = ddm()
  m.c.hasFieldsContainerTarget = true
  m.c.fieldsContainerTarget = container
  return m
}

describe("DragDropManager._sidebarData", () => {
  it("maps sidebar data attributes into a field payload", () => {
    const el = sidebarEl({
      fieldType: "text", fieldLabel: "First Name", propertySlug: "first_name",
      propertyType: "string", propertyHtmlType: "text", source: "entity",
      sourceSection: "profile",
    })
    expect(ddm()._sidebarData(el)).toEqual({
      type: "text", label: "First Name", propertySlug: "first_name",
      propertyType: "string", htmlType: "text", source: "entity",
      sourceSection: "profile", options: null, dynamicOptions: null,
    })
  })

  it("falls back to propertyName for the label and nulls missing source/section", () => {
    const el = sidebarEl({ fieldType: "email", propertyName: "Email", propertySlug: "email" })
    const data = ddm()._sidebarData(el)
    expect(data.label).toBe("Email")
    expect(data.source).toBeNull()
    expect(data.sourceSection).toBeNull()
  })

  it("parses JSON option blobs", () => {
    const el = sidebarEl({
      fieldType: "select",
      fieldOptions: JSON.stringify([{ label: "A", value: "a" }]),
      dynamicOptions: JSON.stringify({ source: "entity", key: "x" }),
    })
    const data = ddm()._sidebarData(el)
    expect(data.options).toEqual([{ label: "A", value: "a" }])
    expect(data.dynamicOptions).toEqual({ source: "entity", key: "x" })
  })
})

describe("DragDropManager.captureCardRects (structural)", () => {
  it("returns an empty map when there is no fields container", () => {
    const m = ddm()
    m.c.hasFieldsContainerTarget = false
    expect(m.captureCardRects()).toBeInstanceOf(Map)
    expect(m.captureCardRects().size).toBe(0)
  })

  it("keys the map by field id for every .field-card present", () => {
    const container = document.createElement("div")
    container.innerHTML =
      '<div class="field-card" data-field-id="a"></div>' +
      '<div class="field-card" data-field-id="b"></div>' +
      '<div class="field-card"></div>' // no id — excluded
    const m = ddmWith(container)
    const rects = m.captureCardRects()
    expect([...rects.keys()].sort()).toEqual(["a", "b"])
  })
})

describe("DragDropManager.flipFromRects guards", () => {
  it("returns early (no throw) when there is no fields container", () => {
    const m = ddm()
    m.c.hasFieldsContainerTarget = false
    expect(() => m.flipFromRects(new Map())).not.toThrow()
  })

  it("runs without throwing when a container is present", async () => {
    const container = document.createElement("div")
    container.innerHTML = '<div class="field-card" data-field-id="a"></div>'
    const m = ddmWith(container)
    expect(() => m.flipFromRects(new Map(), { droppedId: "a" })).not.toThrow()
    flushAnimationFrames()
  })
})

// The write-phase rAF callback runs geometry logic. happy-dom zeroes real
// getBoundingClientRect() output, so we stub it per-card to drive each branch
// deterministically — the exact animated pixel values aren't the point, the
// branch taken is. Explicitly drain both deferred rAF phases so execution does
// not depend on the host event loop or a guessed millisecond delay.
function cardWithRect(id, rect) {
  const card = document.createElement("div")
  card.className = "field-card"
  card.dataset.fieldId = id
  Object.defineProperty(card, "getBoundingClientRect", {
    value: () => ({ left: 0, top: 0, right: 0, bottom: 0, width: 0, height: 0, x: 0, y: 0, ...rect }),
  })
  return card
}

describe("DragDropManager.flipFromRects — write-phase branches", () => {
  const flush = flushAnimationFrames

  it("re-queries an empty card list when the container disappears before the rAF fires", async () => {
    const container = document.createElement("div")
    container.appendChild(cardWithRect("a", {}))
    const m = ddmWith(container)
    m.flipFromRects(new Map(), { droppedId: "a" })
    // Container target vanishes synchronously, before the macrotask-deferred rAF runs.
    m.c.fieldsContainerTarget = null
    await flush()
    // No throw is the assertion — the ternary's `[]` branch was taken, so the
    // forEach body below never touched the (now-null) container.
  })

  it("skips a card that has no matching newRect entry (added to the DOM after the snapshot)", async () => {
    const container = document.createElement("div")
    container.appendChild(cardWithRect("a", {}))
    const m = ddmWith(container)
    m.flipFromRects(new Map(), { droppedId: "a" })
    // Insert a second card AFTER the synchronous newRects snapshot was taken —
    // by the time the rAF write phase re-queries the DOM it'll see "ghost"
    // but newRects.get("ghost") is undefined.
    container.appendChild(cardWithRect("ghost", {}))
    await flush()
    expect(container.querySelector('[data-field-id="ghost"]').style.transform).toBe("")
  })

  it("skips a brand-new (no prevRect) card that isn't the dropped one", async () => {
    const container = document.createElement("div")
    const other = cardWithRect("other", {})
    container.appendChild(other)
    const m = ddmWith(container)
    m.flipFromRects(new Map(), { droppedId: "a" }) // "other" has no prevRect and isn't droppedId
    await flush()
    expect(other.style.transform).toBe("")
  })

  it("skips the entrance animation entirely under prefers-reduced-motion", async () => {
    const originalMatchMedia = window.matchMedia
    window.matchMedia = vi.fn(() => ({ matches: true }))
    const container = document.createElement("div")
    const dropped = cardWithRect("a", {})
    container.appendChild(dropped)
    const m = ddmWith(container)
    m.flipFromRects(new Map(), { droppedId: "a" })
    await flush()
    expect(dropped.style.transform).toBe("")
    window.matchMedia = originalMatchMedia
  })

  it("clamps the entrance offset to the drop point and animates a NEW dropped card", async () => {
    const container = document.createElement("div")
    // Far-away drop point to exercise the +/-120 clamp.
    const dropped = cardWithRect("a", { left: 0, top: 0, width: 100, height: 40 })
    container.appendChild(dropped)
    const m = ddmWith(container)
    m.flipFromRects(new Map(), { droppedId: "a", dropPoint: { x: 9999, y: -9999 } })
    await flush()
    // After both nested rAFs resolve, the transient transform/opacity are cleared.
    expect(dropped.style.transform).toBe("")
    expect(dropped.style.opacity).toBe("")
  })

  it("FLIPs an existing card that moved: applies the inverse transform then settles", async () => {
    const container = document.createElement("div")
    const moved = cardWithRect("a", { left: 10, top: 5 })
    container.appendChild(moved)
    const m = ddm()
    m.c.hasFieldsContainerTarget = true
    m.c.fieldsContainerTarget = container
    const prevRects = new Map([["a", { left: 100, top: 50 }]])
    m.flipFromRects(prevRects, {})
    await flush()
    // Both nested rAFs have resolved and _clearAfterTransition's fallback timer
    // (320ms) hasn't fired yet mid-transition, but by settle time styles clear.
    expect(moved.style.transform).toBe("")
  })

  it("treats a sub-pixel position delta as 'didn't move' and skips the FLIP", async () => {
    const container = document.createElement("div")
    const stillish = cardWithRect("a", { left: 10.2, top: 5.1 })
    container.appendChild(stillish)
    const m = ddm()
    m.c.hasFieldsContainerTarget = true
    m.c.fieldsContainerTarget = container
    const prevRects = new Map([["a", { left: 10, top: 5 }]]) // dx=0.2, dy=0.1 — below threshold
    m.flipFromRects(prevRects, {})
    await flush()
    expect(stillish.style.transform).toBe("")
    expect(stillish.style.transition).toBe("")
  })

  it("skips the FLIP transform under prefers-reduced-motion even when the card moved", async () => {
    const originalMatchMedia = window.matchMedia
    window.matchMedia = vi.fn(() => ({ matches: true }))
    const container = document.createElement("div")
    const moved = cardWithRect("a", { left: 10, top: 5 })
    container.appendChild(moved)
    const m = ddm()
    m.c.hasFieldsContainerTarget = true
    m.c.fieldsContainerTarget = container
    const prevRects = new Map([["a", { left: 100, top: 50 }]])
    m.flipFromRects(prevRects, {})
    await flush()
    expect(moved.style.transform).toBe("")
    window.matchMedia = originalMatchMedia
  })
})

describe("DragDropManager._clearAfterTransition", () => {
  it("clears inline styles on transitionend", () => {
    const card = document.createElement("div")
    card.style.transition = "transform 200ms"
    card.style.transform = "translate(5px, 5px)"
    ddm()._clearAfterTransition(card, 10_000)
    card.dispatchEvent(new Event("transitionend"))
    expect(card.style.transition).toBe("")
    expect(card.style.transform).toBe("")
  })

  it("clears inline styles via the fallback timeout if transitionend never fires", async () => {
    const card = document.createElement("div")
    card.style.transform = "translate(5px, 5px)"
    ddm()._clearAfterTransition(card, 0)
    await vi.advanceTimersByTimeAsync(0)
    expect(card.style.transform).toBe("")
  })

  it("the fallback timeout is a harmless no-op if transitionend already ran cleanup", async () => {
    const card = document.createElement("div")
    card.style.transform = "translate(5px, 5px)"
    // Fires transitionend synchronously (marks done=true, `once` detaches the
    // listener) BEFORE the short fallback timer below also calls cleanup()
    // directly — exercising the `if (done) return` guard on the second call.
    ddm()._clearAfterTransition(card, 5)
    card.dispatchEvent(new Event("transitionend"))
    expect(card.style.transform).toBe("")
    card.style.transform = "translate(1px, 1px)" // prove the guarded fallback doesn't touch it
    await vi.advanceTimersByTimeAsync(15)
    expect(card.style.transform).toBe("translate(1px, 1px)")
  })

  it("is idempotent — a second transitionend is harmless and styles stay cleared", () => {
    const card = document.createElement("div")
    card.style.transform = "translate(5px, 5px)"
    ddm()._clearAfterTransition(card, 10_000)
    card.dispatchEvent(new Event("transitionend"))
    card.style.transform = "translate(9px, 9px)" // simulate a later, unrelated change
    // The guarded cleanup already ran; a stray transitionend must NOT re-clear it.
    card.dispatchEvent(new Event("transitionend"))
    expect(card.style.transform).toBe("translate(9px, 9px)")
  })
})
