import { describe, it, expect, beforeEach, vi } from "vitest"
import TabManager from "controllers/property_editor/tab_manager"
import { setElementCatalog } from "flowchart/constants/element_registry"
import { installSampleElementCatalog } from "../../support/element_catalog.js"

installSampleElementCatalog()

const makePanes = () => ({
  general: document.createElement("div"),
  steps: document.createElement("div"),
  io: document.createElement("div"),
  advanced: document.createElement("div"),
})

const TAB_LABEL_DEFAULTS = {
  tabGeneralLabelValue: "General",
  tabStepsLabelValue: "Step",
  tabBranchesLabelValue: "Branches",
  tabIoLabelValue: "I/O",
  tabAdvancedLabelValue: "Advanced",
}

const makeManager = (currentElement = null) => {
  const controller = { onTabActivated: vi.fn(), currentElement, ...TAB_LABEL_DEFAULTS }
  const tm = new TabManager(controller)
  const bar = document.createElement("div")
  document.body.appendChild(bar)
  const panes = makePanes()
  Object.values(panes).forEach((p) => document.body.appendChild(p))
  tm.init(bar, panes)
  return { tm, bar, panes, controller }
}

describe("static config", () => {
  it("exposes tab order including branches", () => {
    expect(TabManager.TAB_ORDER).toEqual(["general", "steps", "branches", "io", "advanced"])
  })
})

describe("_labelFor", () => {
  it("uses distinct Steps / Branches labels", () => {
    const { tm } = makeManager()
    expect(tm._labelFor("steps", "process")).toBe("Step")
    expect(tm._labelFor("branches", "decision")).toBe("Branches")
  })

  it("resolves the static labels for general/io/advanced from the controller", () => {
    const { tm } = makeManager()
    expect(tm._labelFor("general", "process")).toBe("General")
    expect(tm._labelFor("io", "process")).toBe("I/O")
    expect(tm._labelFor("advanced", "process")).toBe("Advanced")
  })
})

describe("_getVisibleTabs", () => {
  it("follows catalog tabs and hides Advanced when no advanced field applies", () => {
    const { tm } = makeManager()
    expect(tm._getVisibleTabs("process")).toEqual(["general", "steps", "io"])
    expect(tm._getVisibleTabs("start")).toEqual(["general", "io"])
    expect(tm._getVisibleTabs("decision")).toEqual(["general", "branches", "io"])
    expect(tm._getVisibleTabs("loop")).toEqual(["general", "io", "advanced"])
  })

  it("falls back to general when the catalog has no tabs", () => {
    const { tm } = makeManager()
    expect(tm._getVisibleTabs("nope")).toEqual(["general"])
  })

  it("keeps a declared Advanced tab only when an advanced field applies", () => {
    setElementCatalog({
      types: {
        custom: {
          type: "custom",
          tabs: ["io", "advanced"],
          fields: [{ name: "secret", group: "advanced", visibleWhen: { mode: "on" } }],
        },
      },
    })
    const hidden = makeManager({ properties: { mode: "off" } })
    expect(hidden.tm._getVisibleTabs("custom")).toEqual(["io"])
    expect(hidden.tm._defaultTab("custom", ["io"])).toBe("io")
    expect(hidden.tm._defaultTab("custom", [])).toBe("general")

    const shown = makeManager({ properties: { mode: "on" } })
    expect(shown.tm._getVisibleTabs("custom")).toEqual(["io", "advanced"])
    installSampleElementCatalog()
  })

  it("uses empty properties when the controller or current element is missing", () => {
    const { tm } = makeManager()
    expect(tm._hasVisibleAdvancedField("process")).toBe(false)
    expect(tm._hasVisibleAdvancedField("loop")).toBe(true)
    tm.controller.currentElement = { properties: { loopType: "while" } }
    expect(tm._hasVisibleAdvancedField("loop")).toBe(true)
    tm.controller.currentElement = {}
    expect(tm._hasVisibleAdvancedField("loop")).toBe(true)
    tm.controller = null
    expect(tm._hasVisibleAdvancedField("loop")).toBe(true)
  })

  it("keeps declared tabs that are outside TAB_ORDER and skips a missing pane", () => {
    setElementCatalog({ types: { custom: { type: "custom", tabs: ["extra"], fields: [] } } })
    const { tm, panes } = makeManager()
    tm.tabPanes.missing = null
    expect(tm._getVisibleTabs("custom")).toEqual(["extra"])
    expect(() => tm._showPane("general")).not.toThrow()
    expect(panes.general.classList.contains("hidden")).toBe(false)
    installSampleElementCatalog()
  })
})

describe("configureForElementType", () => {
  it("builds a button per visible tab and opens Steps for Process", () => {
    const { tm, bar } = makeManager()
    tm.configureForElementType("process")
    expect([...bar.querySelectorAll("button[data-tab]")].map((b) => b.dataset.tab)).toEqual([
      "general", "steps", "io",
    ])
    expect(tm.activeTab).toBe("steps")
  })

  it("opens Branches for Decision and General otherwise", () => {
    const decision = makeManager()
    decision.tm.configureForElementType("decision")
    expect(decision.tm.activeTab).toBe("branches")
    expect([...decision.bar.querySelectorAll("button[data-tab]")].map((b) => b.dataset.tab)).toEqual([
      "general", "branches", "io",
    ])

    const loop = makeManager()
    loop.tm.configureForElementType("loop")
    expect(loop.tm.activeTab).toBe("general")
  })

  it("shows the active pane and notifies the controller", () => {
    const { tm, panes, controller } = makeManager()
    tm.configureForElementType("process")
    expect(panes.steps.classList.contains("hidden")).toBe(false)
    expect(panes.general.classList.contains("hidden")).toBe(true)
    expect(controller.onTabActivated).toHaveBeenCalledWith("steps")
  })

  it("keeps a shared steps/branches pane visible for Process and Decision", () => {
    const { tm, bar, panes } = makeManager()
    const shared = document.createElement("div")
    shared.classList.add("hidden")
    document.body.appendChild(shared)
    tm.init(bar, {
      general: panes.general,
      steps: shared,
      branches: shared,
      io: panes.io,
      advanced: panes.advanced
    })
    tm.configureForElementType("process")
    expect(shared.classList.contains("hidden")).toBe(false)
    expect(panes.general.classList.contains("hidden")).toBe(true)
    tm.configureForElementType("decision")
    expect(shared.classList.contains("hidden")).toBe(false)
    expect(tm.activeTab).toBe("branches")
  })

  it("reuses the inner pill container across reconfigures", () => {
    const { tm, bar } = makeManager()
    tm.configureForElementType("process")
    const pill1 = bar.querySelector("[data-tab-pills]")
    tm.configureForElementType("decision")
    expect(bar.querySelector("[data-tab-pills]")).toBe(pill1)
  })

  it("no-ops pane/controller notification when there is no tabBarContainer", () => {
    const { tm, panes, controller } = makeManager()
    tm.tabBarContainer = null
    expect(() => tm.configureForElementType("process")).not.toThrow()
    expect(tm.activeTab).toBe("steps")
    expect(panes.steps.classList.contains("hidden")).toBe(false)
    expect(controller.onTabActivated).not.toHaveBeenCalled()
  })
})

describe("switchTo", () => {
  it("changes active tab, re-styles buttons, shows pane, notifies controller", () => {
    const { tm, bar, panes, controller } = makeManager()
    tm.configureForElementType("process")
    controller.onTabActivated.mockClear()

    tm.switchTo("io")
    expect(tm.activeTab).toBe("io")
    expect(panes.io.classList.contains("hidden")).toBe(false)
    expect(panes.steps.classList.contains("hidden")).toBe(true)
    expect(bar.querySelector('button[data-tab="io"]').classList.contains("bg-white")).toBe(true)
    expect(controller.onTabActivated).toHaveBeenCalledWith("io")
  })

  it("no-ops when switching to the already-active tab", () => {
    const { tm, controller } = makeManager()
    tm.configureForElementType("process")
    controller.onTabActivated.mockClear()
    tm.switchTo("steps")
    expect(controller.onTabActivated).not.toHaveBeenCalled()
  })

  it("clicking a tab button switches to that tab", () => {
    const { tm, bar } = makeManager()
    tm.configureForElementType("process")
    bar.querySelector('button[data-tab="io"]').click()
    expect(tm.activeTab).toBe("io")
  })

  it("no-ops the button re-style when there is no tabBarContainer", () => {
    const { tm } = makeManager()
    tm.configureForElementType("process")
    tm.tabBarContainer = null
    expect(() => tm.switchTo("io")).not.toThrow()
    expect(tm.activeTab).toBe("io")
  })
})

describe("updateBadges", () => {
  it("appends a count only to the decision Branches tab", () => {
    const { tm, bar } = makeManager()
    tm.configureForElementType("decision")
    tm.updateBadges({ branches: 3, inputs: 1, outputs: 2 })
    expect(bar.querySelector('button[data-tab="branches"]').textContent).toBe("Branches (3)")
  })

  it("shows no badge for process steps or the I/O tab", () => {
    const { tm, bar } = makeManager()
    tm.configureForElementType("process")
    tm.updateBadges({ steps: 5, inputs: 2, outputs: 2 })
    expect(bar.querySelector('button[data-tab="steps"]').textContent).toBe("Step")
    expect(bar.querySelector('button[data-tab="io"]').textContent).toBe("I/O")
  })

  it("omits the count when branch count is 0", () => {
    const { tm, bar } = makeManager()
    tm.configureForElementType("decision")
    tm.updateBadges({ branches: 0 })
    expect(bar.querySelector('button[data-tab="branches"]').textContent).toBe("Branches")
  })

  it("no-ops when there is no tabBarContainer", () => {
    const { tm } = makeManager()
    tm.configureForElementType("decision")
    tm.tabBarContainer = null
    expect(() => tm.updateBadges({ branches: 3 })).not.toThrow()
  })

  it("falls back to the button's textContent when data-tab-label is absent", () => {
    const { tm, bar } = makeManager()
    tm.configureForElementType("decision")
    const btn = bar.querySelector('button[data-tab="branches"]')
    delete btn.dataset.tabLabel
    btn.textContent = "  Branches  "
    tm.updateBadges({ branches: 4 })
    expect(btn.textContent).toBe("Branches (4)")
  })
})

describe("getPane", () => {
  it("maps branches onto the shared steps pane", () => {
    const { tm, panes } = makeManager()
    expect(tm.getPane("io")).toBe(panes.io)
    expect(tm.getPane("branches")).toBe(panes.steps)
    expect(tm.getPane("nope")).toBeNull()
  })
})
