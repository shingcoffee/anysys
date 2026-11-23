import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { EdgeInsertMixin, EDGE_INSERT_TYPES } from "flowchart/connection_manager/edge_insert"

vi.mock("flowchart/constants/element_registry", async (importOriginal) => {
  const actual = await importOriginal()
  return {
    ...actual,
    elementLabel: vi.fn((type) => (type === "process" ? "Process (catalog)" : undefined)),
  }
})

function makeHost(over = {}) {
  const handleLayer = document.createElementNS("http://www.w3.org/2000/svg", "g")
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  svg.appendChild(handleLayer)
  document.body.appendChild(svg)
  return Object.assign(Object.create(EdgeInsertMixin), {
    handleLayer,
    connections: [{ id: "c1", from: "a", to: "b" }],
    isReadOnly: false,
    isDragging: false,
    isDrawingConnection: false,
    isDraggingConnectionEndpoint: false,
    _edgeInsertButton: null,
    _edgeInsertMenu: null,
    _edgeInsertHideTimer: null,
    _connectionMidpoint: vi.fn(() => ({ x: 40, y: 80 })),
    insertElementOnConnection: vi.fn(),
    ...over,
  })
}

describe("EDGE_INSERT_TYPES", () => {
  it("offers palette types except Start and End", () => {
    expect(EDGE_INSERT_TYPES).toEqual(["process", "decision", "loop", "subflow"])
    expect(EDGE_INSERT_TYPES).not.toContain("start")
    expect(EDGE_INSERT_TYPES).not.toContain("end")
  })
})

describe("EdgeInsertMixin", () => {
  let host

  beforeEach(() => {
    document.body.innerHTML = ""
    vi.useFakeTimers()
    host = makeHost()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it("uses the threaded label and has no inline English fallback", () => {
    host.labels = { edgeInsertButtonLabel: "插入元素" }
    expect(host._edgeInsertMessage("edgeInsertButtonLabel")).toBe("插入元素")
    expect(host._edgeInsertMessage("edgeInsertMenuLabel")).toBe("")
    host.labels = undefined
    expect(host._edgeInsertMessage("edgeInsertButtonLabel")).toBe("")
  })

  it.each([
    ["isReadOnly", { isReadOnly: true }],
    ["isDragging", { isDragging: true }],
    ["isDrawingConnection", { isDrawingConnection: true }],
    ["isDraggingConnectionEndpoint", { isDraggingConnectionEndpoint: true }],
  ])("hides the + button when %s", (_name, flags) => {
    Object.assign(host, flags)
    host._showEdgeInsertButton("c1")
    expect(host._edgeInsertButton).toBeNull()
  })

  it("does not replace the button while the menu is open", () => {
    host._edgeInsertMenu = document.createElement("div")
    host._showEdgeInsertButton("c1")
    expect(host.handleLayer.children.length).toBe(0)
  })

  it("is a no-op when the hovered connection is missing", () => {
    host._showEdgeInsertButton("gone")
    expect(host._edgeInsertButton).toBeNull()
  })

  it("does not rebuild the button for the same connection", () => {
    host._showEdgeInsertButton("c1")
    const first = host._edgeInsertButton
    host._showEdgeInsertButton("c1")
    expect(host._edgeInsertButton).toBe(first)
    expect(host.handleLayer.querySelectorAll("[data-edge-insert-for]")).toHaveLength(1)
  })

  it("shows a + button at the midpoint with an accessible label", () => {
    host.labels = { edgeInsertButtonLabel: "Insert an element" }
    host._showEdgeInsertButton("c1")
    const button = host._edgeInsertButton
    expect(button.getAttribute("data-edge-insert-for")).toBe("c1")
    expect(button.getAttribute("role")).toBe("button")
    expect(button.getAttribute("aria-label")).toBe("Insert an element")
    expect(button.querySelector("title").textContent).toBe("Insert an element")
    expect(button.querySelectorAll("circle")).toHaveLength(1)
    expect(button.querySelectorAll("line")).toHaveLength(2)
  })

  it("opens the menu on click, Enter, and Space, and ignores other keys", () => {
    host._showEdgeInsertButton("c1")
    const button = host._edgeInsertButton
    const open = vi.spyOn(host, "_openEdgeInsertMenu")

    button.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }))
    button.dispatchEvent(new MouseEvent("dblclick", { bubbles: true }))
    button.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    expect(open).toHaveBeenCalledWith("c1", 40, 80)

    button.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }))
    button.dispatchEvent(new KeyboardEvent("keydown", { key: " ", bubbles: true }))
    button.dispatchEvent(new KeyboardEvent("keydown", { key: "Tab", bubbles: true }))
    expect(open).toHaveBeenCalledTimes(3)
  })

  it("cancels hide on mouseenter and schedules hide on mouseleave", () => {
    host._showEdgeInsertButton("c1")
    const button = host._edgeInsertButton
    button.dispatchEvent(new MouseEvent("mouseleave", { bubbles: true }))
    expect(host._edgeInsertHideTimer).not.toBeNull()
    button.dispatchEvent(new MouseEvent("mouseenter", { bubbles: true }))
    vi.advanceTimersByTime(200)
    expect(host._edgeInsertButton).toBe(button)
  })

  it("removes the button after the hide delay when the menu is not open", () => {
    host._showEdgeInsertButton("c1")
    host._scheduleHideEdgeInsertButton()
    vi.advanceTimersByTime(200)
    expect(host._edgeInsertButton).toBeNull()
    expect(host.handleLayer.querySelector("[data-edge-insert-for]")).toBeNull()
  })

  it("does not schedule hide while the menu is open", () => {
    host._openEdgeInsertMenu("c1", 40, 80)
    host._scheduleHideEdgeInsertButton()
    expect(host._edgeInsertHideTimer).toBeNull()
  })

  it("lists insertable types labelled via elementLabel, falling back to the type key only when uncatalogued", () => {
    host.labels = { edgeInsertMenuLabel: "选择要插入的元素" }
    host._openEdgeInsertMenu("c1", 40, 80)
    const items = [...host._edgeInsertMenu.querySelectorAll("[data-edge-insert-type]")]
    expect(items.map((item) => item.dataset.edgeInsertType)).toEqual(EDGE_INSERT_TYPES)
    expect(items.map((item) => item.textContent)).toEqual(["Process (catalog)", "decision", "loop", "subflow"])
    expect(host._edgeInsertMenu.querySelector("[role='menu']").getAttribute("aria-label")).toBe("选择要插入的元素")
  })

  it("inserts the chosen type and closes the menu", () => {
    host._openEdgeInsertMenu("c1", 40, 80)
    host._edgeInsertMenu.querySelector('[data-edge-insert-type="loop"]').click()
    expect(host.insertElementOnConnection).toHaveBeenCalledWith("c1", "loop")
    expect(host._edgeInsertMenu).toBeNull()
  })

  it("navigates the menu with arrows, wraps, ignores other keys, and closes on Escape", () => {
    host._openEdgeInsertMenu("c1", 40, 80)
    const items = [...host._edgeInsertMenu.querySelectorAll("[role='menuitem']")]
    expect(document.activeElement).toBe(items[0])

    host._edgeInsertMenu.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true }))
    expect(document.activeElement).toBe(items[1])
    host._edgeInsertMenu.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowUp", bubbles: true }))
    expect(document.activeElement).toBe(items[0])
    host._edgeInsertMenu.dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowUp", bubbles: true }))
    expect(document.activeElement).toBe(items[items.length - 1])
    host._edgeInsertMenu.dispatchEvent(new KeyboardEvent("keydown", { key: "Tab", bubbles: true }))
    expect(document.activeElement).toBe(items[items.length - 1])

    host._edgeInsertMenu.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }))
    host._edgeInsertMenu.dispatchEvent(new MouseEvent("click", { bubbles: true }))
    host._edgeInsertMenu.dispatchEvent(new MouseEvent("dblclick", { bubbles: true }))

    host._edgeInsertMenu.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }))
    expect(host._edgeInsertMenu).toBeNull()
    expect(host._edgeInsertButton).toBeNull()
  })

  it("closes the menu on an outside mousedown", () => {
    host._openEdgeInsertMenu("c1", 40, 80)
    document.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }))
    expect(host._edgeInsertMenu).toBeNull()
  })

  it("_refreshEdgeInsert keeps an open menu whose connection still exists", () => {
    host._openEdgeInsertMenu("c1", 40, 80)
    const menu = host._edgeInsertMenu
    host._refreshEdgeInsert()
    expect(host._edgeInsertMenu).toBe(menu)
  })

  it("_refreshEdgeInsert hides a stale menu or button", () => {
    host._openEdgeInsertMenu("c1", 40, 80)
    host.connections = []
    host._refreshEdgeInsert()
    expect(host._edgeInsertMenu).toBeNull()

    host.connections = [{ id: "c1" }]
    host._showEdgeInsertButton("c1")
    host._refreshEdgeInsert()
    expect(host._edgeInsertButton).toBeNull()
  })

  it("_closeEdgeInsertMenu is safe when nothing is open", () => {
    expect(() => host._closeEdgeInsertMenu()).not.toThrow()
    expect(() => host._removeEdgeInsertButton()).not.toThrow()
  })
})

describe("P5-4 EdgeInsertMixin — canMutate hides the + button", () => {
  let host
  beforeEach(() => { document.body.innerHTML = ""; host = makeHost() })
  afterEach(() => { vi.useRealTimers() })

  it("hides the + button when canMutate is false even if isReadOnly is false", () => {
    host.isReadOnly = false
    host.canMutate = () => false
    host._showEdgeInsertButton("c1")
    expect(host._edgeInsertButton).toBeNull()
  })
})
