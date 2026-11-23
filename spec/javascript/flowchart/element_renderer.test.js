import { describe, it, expect, beforeEach, vi } from "vitest"
import { ElementRendererMixin, ElementRenderer, estimateTextWidth, measureRenderedTextWidth, resetTextMeasureContext, truncateLabel } from "flowchart/element_renderer"
import { ELEMENT_COLORS } from "flowchart/constants"

// renderElement builds SVG shapes from element DATA (x/width/height), so the
// structure is fully assertable in happy-dom. Tooltip positioning uses
// getBoundingClientRect (zeros here) but the tooltip DOM node + text are real.

function makeHost() {
  const elementLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
  document.body.appendChild(elementLayer)
  return Object.assign(Object.create(ElementRendererMixin), { elementLayer, isDragging: false })
}

const el = (over = {}) => ({ id: "e1", type: "process", label: "Hello", x: 100, y: 100, width: 100, height: 45, properties: {}, ...over })
const groupOf = (host) => host.elementLayer.querySelector("[data-element-id]")

describe("ElementRendererMixin.renderElement", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("appends a group tagged with element id + type and a translate transform", () => {
    host.renderElement(el())
    const g = groupOf(host)
    expect(g.getAttribute("data-element-id")).toBe("e1")
    expect(g.getAttribute("data-element-type")).toBe("process")
    // translate = (x - w/2, y - h/2) = (50, 77.5)
    expect(g.getAttribute("transform")).toBe("translate(50, 77.5)")
    // renderedWidth/Height stamped for change detection
    expect(g.dataset.renderedWidth).toBe("100")
    expect(g.dataset.renderedHeight).toBe("45")
  })

  it("renders a rect for process, ellipse for start/end, polygon for decision", () => {
    host.renderElement(el({ id: "p", type: "process" }))
    host.renderElement(el({ id: "s", type: "start" }))
    host.renderElement(el({ id: "d", type: "decision" }))
    const q = (id, tag) => host.elementLayer.querySelector(`[data-element-id="${id}"] ${tag}`)
    expect(q("p", "rect")).not.toBeNull()
    expect(q("s", "ellipse")).not.toBeNull()
    expect(q("d", "polygon")).not.toBeNull()
  })

  it("uses custom style fill/stroke when both are present", () => {
    host.renderElement(el({ properties: { style: { fill: "#123456", stroke: "#654321" } } }))
    const rect = groupOf(host).querySelector("rect")
    expect(rect.getAttribute("fill")).toBe("#123456")
    expect(rect.getAttribute("stroke")).toBe("#654321")
  })

  it("adds a comment indicator dot when comments are present", () => {
    host.renderElement(el({ properties: { comments: "note" } }))
    const dot = groupOf(host).querySelector("circle")
    expect(dot).not.toBeNull()
    expect(dot.getAttribute("fill")).toBe("#fbbf24")
  })

  it("falls back to the process palette for an unknown element type", () => {
    host.renderElement(el({ type: "not-a-real-type" }))
    const rect = groupOf(host).querySelector("rect")
    expect(rect.getAttribute("fill")).toBe(ELEMENT_COLORS.process.fill)
  })

  it("does not render a legacy join shape for the unsupported join element", () => {
    host.renderElement(el({ id: "join", type: "join" }))
    const group = host.elementLayer.querySelector('[data-element-id="join"]')
    expect(group.querySelector("rect")).not.toBeNull()
    expect(group.querySelector("polygon")).toBeNull()
  })

  it("renders the Loop element as a hexagon polygon", () => {
    host.renderElement(el({ id: "loop", type: "loop" }))
    const group = host.elementLayer.querySelector('[data-element-id="loop"]')
    expect(group.querySelector("polygon")).not.toBeNull()
  })

  it("draws a subflow expand toggle only when the node has a flowchartId", () => {
    host.labels = { expandSubflowTitle: "Expand sub-flow", collapseSubflowTitle: "Collapse sub-flow" }
    host.renderElement(el({ type: "subflow", properties: {} }))
    expect(host.elementLayer.querySelector("[data-subflow-toggle]")).toBeNull()

    host.renderElement(el({ id: "sf", type: "subflow", properties: { flowchartId: "fc-1" } }))
    const toggle = host.elementLayer.querySelector("[data-element-id='sf'] [data-subflow-toggle]")
    expect(toggle).not.toBeNull()
    expect(toggle.getAttribute("title")).toBe("Expand sub-flow")
  })

  it("does not draw the subflow toggle when the canvas is read-only", () => {
    host.isReadOnly = true
    host.renderElement(el({ id: "sf", type: "subflow", properties: { flowchartId: "fc-1" } }))
    expect(host.elementLayer.querySelector("[data-subflow-toggle]")).toBeNull()
  })

  it("does not rebuild the subflow toggle when the canvas is read-only", () => {
    host.isReadOnly = true
    const e = el({ id: "sf", type: "subflow", properties: { flowchartId: "fc-1" } })
    host.renderElement(e)
    e.width = 180
    e.height = 70
    host.updateElementPosition(e)
    expect(host.elementLayer.querySelector("[data-subflow-toggle]")).toBeNull()
  })

  it("leaves the expand toggle title empty when labels are absent", () => {
    host.renderElement(el({ id: "sf", type: "subflow", properties: { flowchartId: "fc-1" } }))
    expect(host.elementLayer.querySelector("[data-subflow-toggle]").getAttribute("title")).toBe("")
  })

  it("titles the toggle as collapse when the subflow is marked expanded", () => {
    host.labels = { expandSubflowTitle: "Expand sub-flow", collapseSubflowTitle: "Collapse sub-flow" }
    host.renderElement(el({
      id: "sf",
      type: "subflow",
      properties: { flowchartId: "fc-1", _subflowExpanded: true }
    }))
    expect(host.elementLayer.querySelector("[data-subflow-toggle]").getAttribute("title")).toBe("Collapse sub-flow")
  })

  it("leaves the collapse toggle title empty when labels omit it", () => {
    host.labels = {}
    host.renderElement(el({
      id: "sf",
      type: "subflow",
      properties: { flowchartId: "fc-1", _subflowExpanded: true }
    }))
    expect(host.elementLayer.querySelector("[data-subflow-toggle]").getAttribute("title")).toBe("")
  })

  it("stamps data-expanded-subflow when the element was expanded from a subflow", () => {
    host.renderElement(el({ properties: { _expandedFromSubflow: "sf-1" } }))
    expect(groupOf(host).getAttribute("data-expanded-subflow")).toBe("sf-1")
  })

  it("renders the label text (truncating overly long labels)", () => {
    host.renderElement(el({ id: "short", label: "Hi" }))
    expect(host.elementLayer.querySelector('[data-element-id="short"] text').textContent).toBe("Hi")
    expect(host.elementLayer.querySelector('[data-element-id="short"] title')).toBeNull()

    const full = "A very long label that overflows the element box"
    host.renderElement(el({ id: "long", label: full }))
    const t = host.elementLayer.querySelector('[data-element-id="long"] text').textContent
    expect(t.endsWith("…")).toBe(true)
    expect(t.length).toBeLessThan(full.length)
    expect(host.elementLayer.querySelector('[data-element-id="long"] [data-element-label] title').textContent).toBe(full)
  })

  it("renders an empty label when the element has none", () => {
    host.renderElement(el({ id: "nolabel", label: undefined }))
    expect(host.elementLayer.querySelector('[data-element-id="nolabel"] text').textContent).toBe("")
  })

})

describe("P5-6 label readability — width estimate and truncation", () => {
  it("estimateTextWidth counts CJK / full-width characters as 1 em and others as 0.6 em", () => {
    expect(estimateTextWidth("abc", 10)).toBeCloseTo(18)
    expect(estimateTextWidth("流程图", 10)).toBe(30)
    expect(estimateTextWidth("Ａ１", 10)).toBe(20)
    expect(estimateTextWidth("가", 10)).toBe(10)
    expect(estimateTextWidth("𠀀", 10)).toBe(10)
    expect(estimateTextWidth("a流", 11)).toBeCloseTo(17.6)
    expect(estimateTextWidth("", 11)).toBe(0)
  })

  it("truncateLabel keeps text that fits and leaves an empty label alone", () => {
    expect(truncateLabel("Hello", 80, 11)).toEqual({ text: "Hello", truncated: false })
    expect(truncateLabel("", -5, 11)).toEqual({ text: "", truncated: false })
  })

  it("truncateLabel shortens to the width with a single-character ellipsis", () => {
    // 10 px per character under the injected measure: "abc…" = 40 px fits 45.
    const measure = (text, fontSize) => Array.from(text).length * fontSize
    expect(truncateLabel("abcdefgh", 45, 10, measure)).toEqual({ text: "abc…", truncated: true })
    expect(truncateLabel("abcdefgh", 5, 10, measure)).toEqual({ text: "…", truncated: true })
  })

  it("truncates a zh-CN label by its full-width estimate, not its character count", () => {
    // Process box 100 px − 2×10 padding = 80 px; 11 px per CJK character → 7 fit with "…" (0.6 em).
    const label = "这是一个非常长的中文流程标签名称"
    const { text, truncated } = truncateLabel(label, 80, 11)
    expect(truncated).toBe(true)
    expect(text).toBe("这是一个非常…")
    expect(estimateTextWidth(text, 11)).toBeLessThanOrEqual(80)
  })

  it("renders 11 px labels, 10 px on decisions with a wider inset", () => {
    const host = makeHost()
    host.renderElement(el({ id: "p", label: "Process" }))
    host.renderElement(el({ id: "d", type: "decision", label: "abcdefghijklmn" }))
    expect(host.elementLayer.querySelector('[data-element-id="p"] text').getAttribute("font-size")).toBe("11")
    const decisionText = host.elementLayer.querySelector('[data-element-id="d"] text')
    expect(decisionText.getAttribute("font-size")).toBe("10")
    // 100 − 2×20 = 60 px at 6 px per Latin character: 9 characters + "…" (6 px) = 60.
    expect(decisionText.textContent).toBe("abcdefghi…")
  })
})

describe("P5-8 cleanup — _createPortLabels removed", () => {
  it("does not expose _createPortLabels; decision labels live on connections", () => {
    expect(ElementRendererMixin._createPortLabels).toBeUndefined()
    const host = makeHost()
    host.renderElement(el({ type: "decision" }))
    expect(groupOf(host).querySelector("[data-port-labels]")).toBeNull()
  })
})

describe("ElementRendererMixin.updateElementPosition", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("updates the transform without rebuilding when dimensions are unchanged", () => {
    const e = el()
    host.renderElement(e)
    const g = groupOf(host)
    const shapeBefore = g.querySelector("rect")
    e.x = 200; e.y = 150
    host.updateElementPosition(e)
    expect(g.getAttribute("transform")).toBe("translate(150, 127.5)")
    // Same shape node — not rebuilt.
    expect(g.querySelector("rect")).toBe(shapeBefore)
  })

  it("rebuilds shape + label when dimensions change", () => {
    const e = el()
    host.renderElement(e)
    const g = groupOf(host)
    e.width = 200; e.height = 80
    host.updateElementPosition(e)
    expect(g.dataset.renderedWidth).toBe("200")
    const rect = g.querySelector("rect")
    expect(rect.getAttribute("width")).toBe("200")
  })

  it("rebuilds the subflow toggle when dimensions change", () => {
    const e = el({ type: "subflow", properties: { flowchartId: "fc-1" } })
    host.renderElement(e)
    e.width = 180; e.height = 70
    host.updateElementPosition(e)
    expect(groupOf(host).querySelector("[data-subflow-toggle]")).not.toBeNull()
  })

  it("no-ops for an unknown element id", () => {
    expect(() => host.updateElementPosition(el({ id: "missing" }))).not.toThrow()
  })

  it("rebuild path also re-adds Decision port labels and the comment dot", () => {
    const e = el({ type: "decision", properties: { comments: "note" } })
    host.renderElement(e)
    const g = groupOf(host)
    e.width = 150; e.height = 90
    host.updateElementPosition(e)
    // decision → polygon shape rebuilt, plus comment dot re-appended
    expect(g.querySelector("polygon")).not.toBeNull()
    expect(g.querySelector("circle")).not.toBeNull()
  })

  it("rebuild path uses custom style colors and the process fallback for an unknown type", () => {
    const e = el({ properties: { style: { fill: "#111111", stroke: "#222222" } } })
    host.renderElement(e)
    e.width = 300; e.height = 120; e.type = "not-a-real-type"
    host.updateElementPosition(e)
    const rect = groupOf(host).querySelector("rect")
    // Custom style still wins on rebuild even though the type is unrecognized
    // (falls to the process shape creator, and colors come from properties.style).
    expect(rect.getAttribute("fill")).toBe("#111111")
  })

  it("treats a group with no recorded renderedWidth/Height as changed (dataset fallback to 0)", () => {
    const e = el()
    // Build a bare group manually, WITHOUT the renderedWidth/Height dataset that
    // renderElement normally stamps, to exercise the `|| 0` dataset fallback.
    const bareGroup = document.createElementNS("http://www.w3.org/2000/svg", "g")
    bareGroup.setAttribute("data-element-id", e.id)
    host.elementLayer.appendChild(bareGroup)
    host.updateElementPosition(e)
    expect(bareGroup.dataset.renderedWidth).toBe(String(e.width))
    expect(bareGroup.querySelector("rect")).not.toBeNull()
  })
})

describe("ElementRendererMixin — validation rings", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("appends an error ring rect tagged with severity", () => {
    host.renderElement(el())
    host.setValidationState("e1", "error")
    const ring = groupOf(host).querySelector("[data-validation-ring]")
    expect(ring).not.toBeNull()
    expect(ring.getAttribute("stroke")).toBe("#ef4444")
    expect(ring.dataset.validationSeverity).toBe("error")
  })

  it("warning uses amber; error is never downgraded to warning", () => {
    host.renderElement(el())
    host.setValidationState("e1", "warning")
    expect(groupOf(host).querySelector("[data-validation-ring]").getAttribute("stroke")).toBe("#eab308")

    // Upgrade warning -> error replaces it
    host.setValidationState("e1", "error")
    expect(groupOf(host).querySelector("[data-validation-ring]").dataset.validationSeverity).toBe("error")
    // error stays error even if a warning comes later
    host.setValidationState("e1", "warning")
    expect(groupOf(host).querySelector("[data-validation-ring]").dataset.validationSeverity).toBe("error")
    // only one ring
    expect(groupOf(host).querySelectorAll("[data-validation-ring]")).toHaveLength(1)
  })

  it("clearValidationStates removes all rings", () => {
    host.renderElement(el())
    host.setValidationState("e1", "error")
    host.clearValidationStates()
    expect(groupOf(host).querySelector("[data-validation-ring]")).toBeNull()
  })

  it("is a no-op for a falsy elementId", () => {
    host.renderElement(el())
    expect(() => host.setValidationState(null, "error")).not.toThrow()
    expect(groupOf(host).querySelector("[data-validation-ring]")).toBeNull()
  })

  it("is a no-op when no group matches the elementId", () => {
    host.renderElement(el())
    expect(() => host.setValidationState("does-not-exist", "error")).not.toThrow()
  })

  it("is a no-op when there is no recorded size and getBBox reports a zero-size bbox", () => {
    // Same "no dataset size" starting point as the test below, but leaves
    // happy-dom's real getBBox in place (rather than stubbing it away) — this
    // exercises the branch where `group.getBBox?.()` actually gets called
    // (as opposed to being skipped because the method is missing).
    const bareGroup = document.createElementNS("http://www.w3.org/2000/svg", "g")
    bareGroup.setAttribute("data-element-id", "bare2")
    host.elementLayer.appendChild(bareGroup)
    host.setValidationState("bare2", "error")
    expect(bareGroup.querySelector("[data-validation-ring]")).toBeNull()
  })

  it("is a no-op when the group has no recorded size and getBBox is unavailable", () => {
    // Bare group with no renderedWidth/Height dataset → width/height fall
    // through to `group.getBBox?.()`. Force getBBox itself to be absent (as it
    // would be on a non-SVGGraphicsElement) to exercise BOTH the optional-call
    // skip (`?.()`) and the `?? 0` nullish fallback in one shot — happy-dom's
    // own getBBox always returns a zeroed-but-defined DOMRect, so it can't
    // reach these branches on its own.
    const bareGroup = document.createElementNS("http://www.w3.org/2000/svg", "g")
    bareGroup.setAttribute("data-element-id", "bare")
    bareGroup.getBBox = undefined
    host.elementLayer.appendChild(bareGroup)
    host.setValidationState("bare", "error")
    expect(bareGroup.querySelector("[data-validation-ring]")).toBeNull()
  })
})

describe("ElementRendererMixin — tooltip text (pure)", () => {
  const host = Object.create(ElementRendererMixin)

  it("_getStepDisplayNames prefers selectionLabels, appends modelName", () => {
    expect(host._getStepDisplayNames([{ selectionLabels: ["Validate", "Contract"] }]))
      .toEqual(["Validate Contract"])
    expect(host._getStepDisplayNames([{ selectionLabels: ["Save"], modelName: "User" }]))
      .toEqual(["Save: User"])
  })

  it("_getStepDisplayNames falls back to the action-label map", () => {
    expect(host._getStepDisplayNames([{ action: "find_model" }])).toEqual(["Find record"])
    expect(host._getStepDisplayNames([{ action: "find_model", modelName: "User", subAction: "upsert" }]))
      .toEqual(["Find record: User (upsert)"])
  })

  it("_getStepDisplayNames falls back to the raw action string when it's not in the label map", () => {
    expect(host._getStepDisplayNames([{ action: "custom_thing" }])).toEqual(["custom_thing"])
  })

  it("_getStepDisplayNames falls back to an empty string when there is no action at all", () => {
    expect(host._getStepDisplayNames([{}])).toEqual([""])
  })

  it("_getTooltipText joins step names for a process with steps, else the label", () => {
    const find = host._getTooltipText(el({ type: "process", properties: { steps: [{ action: "find_model" }] } }))
    const assign = host._getTooltipText(el({ type: "process", properties: { steps: [{ action: "assign_value" }] } }))
    expect([find, assign].join("\n")).toBe("Find record\nAssign Value")
    expect(host._getTooltipText(el({ type: "decision", label: "Branch", properties: {} }))).toBe("Branch")
  })
})

describe("ElementRendererMixin — tooltip DOM", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })

  it("_showElementTooltip appends a tooltip div; _hideElementTooltip removes it", () => {
    host._showElementTooltip(el({ label: "Tip text" }), { clientX: 10, clientY: 10 })
    const tip = document.querySelector(".flowchart-tooltip")
    expect(tip).not.toBeNull()
    expect(tip.textContent).toBe("Tip text")
    expect(host._activeTooltip).toBe(tip)
    host._hideElementTooltip()
    expect(document.querySelector(".flowchart-tooltip")).toBeNull()
    expect(host._activeTooltip).toBeNull()
  })

  it("_showElementTooltip is a no-op when there is no tooltip text", () => {
    // _getTooltipText falls back to `label || type` — force both empty.
    host._showElementTooltip(el({ type: "", label: "" }), { clientX: 0, clientY: 0 })
    expect(document.querySelector(".flowchart-tooltip")).toBeNull()
    expect(host._activeTooltip).toBeFalsy()
  })

  it("_updateTooltipPosition repositions the active tooltip and no-ops without one", () => {
    // No active tooltip → no-op, does not throw.
    expect(() => host._updateTooltipPosition({ clientX: 5, clientY: 5 })).not.toThrow()

    host._showElementTooltip(el({ label: "Tip" }), { clientX: 10, clientY: 10 })
    const tip = host._activeTooltip
    host._updateTooltipPosition({ clientX: 20, clientY: 30 })
    // happy-dom returns a zeroed rect, so maxX/maxY collapse to window size - 10;
    // just assert the style was written (structural — real placement is Playwright's job).
    expect(tip.style.left).toMatch(/px$/)
    expect(tip.style.top).toMatch(/px$/)
  })
})

describe("ElementRendererMixin._attachElementEvents", () => {
  let host, canvas, element, group

  beforeEach(() => {
    document.body.innerHTML = ""
    canvas = Object.assign(makeHost(), {
      isDragging: false,
      _isElementSelected: () => false,
      _clearSelection: vi.fn(),
      _addToSelection: vi.fn(),
      _hideElementTooltip: vi.fn(),
      _showElementTooltip: vi.fn(),
      _updateTooltipPosition: vi.fn(),
    })
    host = canvas
    element = el()
    host.renderElement(element)
    group = groupOf(host)
  })

  it("mousedown selects the element when not already selected, then hides the tooltip", () => {
    group.dispatchEvent(new MouseEvent("mousedown"))
    expect(canvas._clearSelection).toHaveBeenCalled()
    expect(canvas._addToSelection).toHaveBeenCalledWith(element)
    expect(canvas._hideElementTooltip).toHaveBeenCalled()
  })

  it("mousedown does not reselect an already-selected element", () => {
    canvas._isElementSelected = () => true
    group.dispatchEvent(new MouseEvent("mousedown"))
    expect(canvas._clearSelection).not.toHaveBeenCalled()
    expect(canvas._addToSelection).not.toHaveBeenCalled()
    expect(canvas._hideElementTooltip).toHaveBeenCalled()
  })

  it("mousedown ignores clicks on a resize handle", () => {
    const handle = document.createElementNS("http://www.w3.org/2000/svg", "circle")
    handle.setAttribute("data-handle-position", "se")
    group.appendChild(handle)
    const evt = new MouseEvent("mousedown", { bubbles: true })
    Object.defineProperty(evt, "target", { value: handle })
    handle.dispatchEvent(evt)
    expect(canvas._addToSelection).not.toHaveBeenCalled()
  })

  it("mousedown ignores ctrl/meta-click (multi-select gesture handled elsewhere)", () => {
    group.dispatchEvent(new MouseEvent("mousedown", { ctrlKey: true }))
    expect(canvas._addToSelection).not.toHaveBeenCalled()
    group.dispatchEvent(new MouseEvent("mousedown", { metaKey: true }))
    expect(canvas._addToSelection).not.toHaveBeenCalled()
    group.dispatchEvent(new MouseEvent("mousedown", { shiftKey: true }))
    expect(canvas._addToSelection).not.toHaveBeenCalled()
  })

  it("mouseenter shows the tooltip unless already dragging", () => {
    group.dispatchEvent(new MouseEvent("mouseenter"))
    expect(canvas._showElementTooltip).toHaveBeenCalledWith(element, expect.anything())

    canvas._showElementTooltip.mockClear()
    canvas.isDragging = true
    group.dispatchEvent(new MouseEvent("mouseenter"))
    expect(canvas._showElementTooltip).not.toHaveBeenCalled()
  })

  it("mousemove forwards to _updateTooltipPosition; mouseleave hides the tooltip", () => {
    group.dispatchEvent(new MouseEvent("mousemove"))
    expect(canvas._updateTooltipPosition).toHaveBeenCalled()

    group.dispatchEvent(new MouseEvent("mouseleave"))
    expect(canvas._hideElementTooltip).toHaveBeenCalled()
  })

  it("clicking [data-subflow-toggle] calls onSubflowToggle and does not start a drag", () => {
    canvas.onSubflowToggle = vi.fn()
    const sub = el({ id: "sf", type: "subflow", properties: { flowchartId: "fc-1" } })
    host.renderElement(sub)
    const toggle = host.elementLayer.querySelector("[data-element-id='sf'] [data-subflow-toggle]")
    const down = new MouseEvent("mousedown", { bubbles: true })
    Object.defineProperty(down, "target", { value: toggle })
    toggle.dispatchEvent(down)
    expect(canvas._addToSelection).not.toHaveBeenCalled()

    const click = new MouseEvent("click", { bubbles: true })
    Object.defineProperty(click, "target", { value: toggle })
    toggle.dispatchEvent(click)
    expect(canvas.onSubflowToggle).toHaveBeenCalledWith(sub)

    canvas.onSubflowToggle = undefined
    expect(() => toggle.dispatchEvent(new MouseEvent("click", { bubbles: true }))).not.toThrow()
  })

  it("ignores a click that is not on the subflow toggle", () => {
    canvas.onSubflowToggle = vi.fn()
    group.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    expect(canvas.onSubflowToggle).not.toHaveBeenCalled()
  })

  it("does not invoke onSubflowToggle when the canvas is read-only", () => {
    canvas.isReadOnly = true
    canvas.onSubflowToggle = vi.fn()
    const sub = el({ id: "sf-ro", type: "subflow", properties: { flowchartId: "fc-1" } })
    host.renderElement(sub)
    expect(host.elementLayer.querySelector("[data-element-id='sf-ro'] [data-subflow-toggle]")).toBeNull()

    const groupRo = host.elementLayer.querySelector("[data-element-id='sf-ro']")
    const fake = document.createElementNS("http://www.w3.org/2000/svg", "g")
    fake.setAttribute("data-subflow-toggle", "true")
    groupRo.appendChild(fake)
    const click = new MouseEvent("click", { bubbles: true })
    Object.defineProperty(click, "target", { value: fake })
    fake.dispatchEvent(click)
    expect(canvas.onSubflowToggle).not.toHaveBeenCalled()
  })
})

describe("ElementRendererMixin — shape creators", () => {
  const host = Object.create(ElementRendererMixin)
  const colors = { fill: "#fff", stroke: "#000" }
  const shapeEl = (over = {}) => ({ id: "s1", width: 100, height: 50, ...over })

  it("_createSubflowShape builds a gradient-filled card with side bands and dashed insets", () => {
    const g = host._createSubflowShape(shapeEl(), colors)
    expect(g.querySelector("defs linearGradient")).not.toBeNull()
    expect(g.querySelectorAll("rect").length).toBe(4) // shadow, main, 2 side bands
    expect(g.querySelectorAll("line").length).toBe(2)
  })
})

describe("ElementRenderer class delegates to the mixin", () => {
  it("renderElement + updateElementPosition proxy to the wrapped canvas", () => {
    const canvas = makeHost()
    const r = new ElementRenderer(canvas)
    r.renderElement(el())
    expect(canvas.elementLayer.querySelector("[data-element-id]")).not.toBeNull()
    const e = el(); e.x = 300
    r.updateElementPosition(e)
    expect(canvas.elementLayer.querySelector("[data-element-id]").getAttribute("transform")).toBe("translate(250, 77.5)")
  })

  it("uses pointer cursor when canMutate returns false", () => {
    const host = Object.assign(makeHost(), { canMutate: () => false })
    host.renderElement(el({ id: "ro" }))
    expect(host.elementLayer.querySelector("[data-element-id='ro']").style.cursor).toBe("pointer")
  })

  it("measureRenderedTextWidth uses 2D canvas measureText when available and falls back otherwise", () => {
    resetTextMeasureContext()
    const fakeCtx = { font: "", measureText: vi.fn(() => ({ width: 71.2 })) }
    const origCreate = document.createElement.bind(document)
    const spy = vi.spyOn(document, "createElement").mockImplementation((tag) => {
      if (tag === "canvas") return { getContext: () => fakeCtx }
      return origCreate(tag)
    })
    expect(measureRenderedTextWidth("Build Contract", 11)).toBe(71.2)
    expect(fakeCtx.font).toContain("11px")
    // Second call reuses the cached context without re-creating canvas
    expect(measureRenderedTextWidth("Save Model", 11, "Inter")).toBe(71.2)
    expect(fakeCtx.font).toBe("11px Inter")

    spy.mockRestore()
    resetTextMeasureContext()
    expect(measureRenderedTextWidth("abc", 10)).toBeCloseTo(18)
  })
})
