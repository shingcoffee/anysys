import { describe, it, expect, beforeEach, vi } from "vitest"
import { BottomPanelMixin } from "controllers/flowchart_canvas/bottom_panel_mixin"
import { makeCanvas, mixinHost } from "../../support/flowchart.js"
import { elementLabel } from "flowchart/constants/element_registry"

// Build a bottom-panel DOM: a panel with tab-content sections + tab buttons.
function buildPanelDom() {
  document.body.innerHTML = `
    <div data-panel class="hidden">
      <div data-tab-content="problems"></div>
      <div data-tab-content="elements" class="hidden"></div>
      <div data-tab-content="history" class="hidden"></div>
    </div>
    <button data-tab-btn data-tab="problems"></button>
    <button data-tab-btn data-tab="elements"></button>
    <button data-tab-btn data-tab="history"></button>
    <span data-elements-count></span>
    <table><tbody data-elements-list></tbody></table>
    <div data-toast></div>
  `
  return {
    panel: document.querySelector("[data-panel]"),
    tabs: [...document.querySelectorAll("[data-tab-btn]")],
    elementsCount: document.querySelector("[data-elements-count]"),
    elementsList: document.querySelector("[data-elements-list]"),
    toast: document.querySelector("[data-toast]"),
  }
}

function host(canvasOverrides = {}, extra = {}) {
  const dom = buildPanelDom()
  const canvas = makeCanvas(canvasOverrides)
  const h = mixinHost(BottomPanelMixin, {
    canvas,
    hasBottomPanelTarget: true,
    bottomPanelTarget: dom.panel,
    bottomTabTargets: dom.tabs,
    hasElementsCountTarget: true,
    elementsCountTarget: dom.elementsCount,
    hasElementsListTarget: true,
    elementsListTarget: dom.elementsList,
    hasToastContainerTarget: true,
    toastContainerTarget: dom.toast,
    _activeBottomTab: null,
    loadVersions: vi.fn(),
    _updateZoomDisplay: vi.fn(),
    _updateAlignmentToolbar: vi.fn(),
    _focusElementById: vi.fn(),
    ...extra,
  })
  return { h, dom, canvas }
}

describe("BottomPanelMixin — test-panel delegates", () => {
  it("toggleTestPanel/openTestPanel/closeTestPanel delegate to the tab/panel core", () => {
    const { h, dom } = host({ elements: [], connections: [] })
    h.toggleTestPanel()
    expect(dom.panel.classList.contains("hidden")).toBe(false)
    expect(h._activeBottomTab).toBe("test")
    h.closeTestPanel()
    expect(dom.panel.classList.contains("hidden")).toBe(true)
    h.openTestPanel()
    expect(dom.panel.classList.contains("hidden")).toBe(false)
    expect(h._activeBottomTab).toBe("test")
  })

  it("forwards runner actions to _testRunner", async () => {
    const runner = { run: vi.fn(), clear: vi.fn(), selectHistory: vi.fn(), useHistoryInput: vi.fn(), validateInput: vi.fn() }
    const { h } = host({}, { _testRunner: runner })
    await h.runTest()
    h.clearTraceOverlay()
    h.validateTestInput()
    h.selectTestHistoryRun({ currentTarget: { dataset: { historyIndex: "2" } } })
    h.loadTestHistoryInput({ currentTarget: { dataset: { historyIndex: "0" } } })
    expect(runner.run).toHaveBeenCalled()
    expect(runner.clear).toHaveBeenCalled()
    expect(runner.validateInput).toHaveBeenCalled()
    expect(runner.selectHistory).toHaveBeenCalledWith(2)
    expect(runner.useHistoryInput).toHaveBeenCalledWith(0)
  })

  it("ignores history actions with a non-numeric index", () => {
    const runner = { selectHistory: vi.fn() }
    const { h } = host({}, { _testRunner: runner })
    h.selectTestHistoryRun({ currentTarget: { dataset: { historyIndex: "abc" } } })
    expect(runner.selectHistory).not.toHaveBeenCalled()
  })

  it("focusTraceStep focuses the element id from the dataset", () => {
    const { h } = host()
    h.focusTraceStep({ currentTarget: { dataset: { elementId: "el-7" } } })
    expect(h._focusElementById).toHaveBeenCalledWith("el-7")
  })
})

describe("BottomPanelMixin — elements-panel delegates", () => {
  it("toggleElementsPanel/openElementsPanel/closeElementsPanel delegate to the tab/panel core", () => {
    const { h, dom } = host({ elements: [], connections: [] })
    h.toggleElementsPanel()
    expect(dom.panel.classList.contains("hidden")).toBe(false)
    expect(h._activeBottomTab).toBe("elements")
    h.closeElementsPanel()
    expect(dom.panel.classList.contains("hidden")).toBe(true)
    h.openElementsPanel()
    expect(dom.panel.classList.contains("hidden")).toBe(false)
    expect(h._activeBottomTab).toBe("elements")
  })
})

describe("BottomPanelMixin._renderElementsList", () => {
  it("renders a row per element with type color, label and in/out degree", () => {
    const { h, dom } = host({
      elements: [
        { id: "a", type: "start", label: "Begin" },
        { id: "b", type: "process", label: "" },
      ],
      connections: [{ from: "a", to: "b" }, { from: "a", to: "b" }],
    })
    h._renderElementsList()
    expect(dom.elementsCount.textContent).toBe("(2)")
    const rows = dom.elementsList.querySelectorAll("tr")
    expect(rows.length).toBe(2)
    expect(rows[0].dataset.elementId).toBe("a")
    // start stroke color from ELEMENT_COLORS
    expect(rows[0].innerHTML).toContain("#10b981")
    // element b (unnamed) shows placeholder + "2 in / 0 out"
    expect(rows[1].innerHTML).toContain("(unnamed)")
    expect(rows[1].textContent).toContain("2 in / 0 out")
  })

  it("renders a hostile label as text instead of HTML", () => {
    const { h, dom } = host({
      elements: [{ id: 'xss-"id', type: "process", label: '<img src=x onerror=alert(1)>' }],
      connections: [],
    })
    h._renderElementsList()
    expect(dom.elementsList.querySelector("img")).toBeNull()
    expect(dom.elementsList.innerHTML).not.toContain("<img")
    expect(dom.elementsList.innerHTML).toContain("&lt;img src=x onerror=alert(1)&gt;")
    expect(dom.elementsList.textContent).toContain("<img src=x onerror=alert(1)>")
  })

  it("uses a fallback color for unknown element types", () => {
    const { h, dom } = host({ elements: [{ id: "x", type: "mystery", label: "X" }], connections: [] })
    h._renderElementsList()
    expect(dom.elementsList.innerHTML).toContain("#6b7280")
  })

  it("still updates the count but no-ops the list render without an elements-list target", () => {
    const { h, dom } = host({ elements: [{ id: "a", type: "start", label: "A" }], connections: [] }, { hasElementsListTarget: false })
    expect(() => h._renderElementsList()).not.toThrow()
    expect(dom.elementsCount.textContent).toBe("(1)")
  })
})

describe("P5-6 BottomPanelMixin._renderElementsList — translated type and connection counts", () => {
  it("shows elementLabel(type), the raw key for an uncatalogued type, and the counts via the format value", () => {
    const { h, dom } = host(
      {
        elements: [
          { id: "a", type: "process", label: "A" },
          { id: "b", type: "mystery", label: "B" },
        ],
        connections: [{ from: "a", to: "b" }, { from: "a", to: "b" }],
      },
      { elementConnectionsFormatValue: "入 {incoming} / 出 {outgoing}" }
    )
    h._renderElementsList()
    const rows = dom.elementsList.querySelectorAll("tr")
    const typeCell = (row) => row.querySelector("td span span:last-child")
    expect(typeCell(rows[0]).textContent).toBe(elementLabel("process"))
    expect(typeCell(rows[0]).classList.contains("capitalize")).toBe(false)
    expect(typeCell(rows[1]).textContent).toBe("mystery")
    expect(rows[0].querySelectorAll("td")[2].textContent.trim()).toBe("入 0 / 出 2")
    expect(rows[1].querySelectorAll("td")[2].textContent.trim()).toBe("入 2 / 出 0")
  })
})

describe("BottomPanelMixin.focusElement", () => {
  it("selects the matched element and fits it into view", () => {
    const target = { id: "a" }
    const { h, canvas } = host({ elements: [target], selectedElements: [{ id: "old" }] })
    h.focusElement({ currentTarget: { dataset: { elementId: "a" } } })
    expect(canvas.selectedElements).toEqual([target])
    expect(canvas._setElementSelected).toHaveBeenCalledWith(target, true)
    expect(canvas.zoomPanManager.fitToContent).toHaveBeenCalledWith([target], 300)
    expect(h._updateZoomDisplay).toHaveBeenCalled()
  })

  it("does nothing when the element id is unknown", () => {
    const { h, canvas } = host({ elements: [] })
    h.focusElement({ currentTarget: { dataset: { elementId: "ghost" } } })
    expect(canvas._setElementSelected).not.toHaveBeenCalled()
  })
})

describe("BottomPanelMixin — tabbed panel core", () => {
  it("openBottomPanel un-hides the panel, activates the tab and renders elements list", () => {
    const { h, dom } = host({ elements: [], connections: [] })
    h.openBottomPanel("elements")
    expect(dom.panel.classList.contains("hidden")).toBe(false)
    expect(h._activeBottomTab).toBe("elements")
    // active tab styled, content shown
    const elementsTab = dom.tabs.find(t => t.dataset.tab === "elements")
    expect(elementsTab.classList.contains("text-indigo-600")).toBe(true)
    expect(dom.panel.querySelector('[data-tab-content="elements"]').classList.contains("hidden")).toBe(false)
  })

  it("openBottomPanel('history') triggers loadVersions", () => {
    const { h } = host()
    h.openBottomPanel("history")
    expect(h.loadVersions).toHaveBeenCalled()
  })

  it("closeBottomPanel hides the panel", () => {
    const { h, dom } = host()
    h.openBottomPanel("problems")
    h.closeBottomPanel()
    expect(dom.panel.classList.contains("hidden")).toBe(true)
  })

  it("_toggleBottomTab closes when re-toggling the active open tab, else opens", () => {
    const { h, dom } = host({ elements: [], connections: [] })
    h._toggleBottomTab("elements")
    expect(dom.panel.classList.contains("hidden")).toBe(false)
    h._toggleBottomTab("elements") // same tab while open -> close
    expect(dom.panel.classList.contains("hidden")).toBe(true)
  })

  it("switchBottomTab closes when clicking the already-active tab, else switches", () => {
    const { h, dom } = host({ elements: [], connections: [] })
    h.switchBottomTab({ currentTarget: { dataset: { tab: "elements" } } })
    expect(h._activeBottomTab).toBe("elements")
    h.switchBottomTab({ currentTarget: { dataset: { tab: "problems" } } })
    expect(h._activeBottomTab).toBe("problems")
    h.switchBottomTab({ currentTarget: { dataset: { tab: "problems" } } }) // active + open -> close
    expect(dom.panel.classList.contains("hidden")).toBe(true)
  })

  it("switchBottomTab ignores a target without a tab", () => {
    const { h } = host()
    expect(() => h.switchBottomTab({ currentTarget: { dataset: {} } })).not.toThrow()
  })

  it("openBottomPanel/closeBottomPanel no-op without a bottom-panel target", () => {
    const { h } = host({}, { hasBottomPanelTarget: false })
    expect(() => h.openBottomPanel("problems")).not.toThrow()
    expect(h._activeBottomTab).toBeNull()
    expect(() => h.closeBottomPanel()).not.toThrow()
  })
})

describe("BottomPanelMixin.showToast", () => {
  beforeEach(() => vi.useRealTimers())

  it("appends a toast element with the message and type color", () => {
    const { h, dom } = host()
    h.showToast("Saved!", "warning")
    const toast = dom.toast.firstElementChild
    expect(toast).toBeTruthy()
    expect(toast.textContent).toBe("Saved!")
    expect(toast.className).toContain("bg-amber-500")
  })

  it("falls back to the info style for an unknown type and no-ops without a container", () => {
    const { h, dom } = host()
    h.showToast("Hi", "bogus")
    expect(dom.toast.firstElementChild.className).toContain("bg-blue-600")

    const { h: h2 } = host({}, { hasToastContainerTarget: false })
    expect(() => h2.showToast("x")).not.toThrow()
  })

  it("fades out and removes the toast after the display timeout", () => {
    vi.useFakeTimers()
    const { h, dom } = host()
    h.showToast("Bye")
    const toast = dom.toast.firstElementChild
    vi.advanceTimersByTime(3000)
    expect(toast.classList.contains("opacity-0")).toBe(true)
    expect(toast.classList.contains("-translate-y-2")).toBe(true)
    vi.advanceTimersByTime(300)
    expect(dom.toast.contains(toast)).toBe(false)
    vi.useRealTimers()
  })
})
