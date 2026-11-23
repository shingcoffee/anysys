import { describe, it, expect, beforeEach, vi } from "vitest"
import { makeBranchManager, makeCanvas, makeController } from "./_support.js"

function branchesContainer({ items = "", emptyHidden = true } = {}) {
  const div = document.createElement("div")
  div.innerHTML = `
    <div data-branches-section>
      <span data-section-count>0</span>
      <div data-route-by-notice class="hidden"></div>
      <div data-branches-container>
        <div data-branches-empty class="${emptyHidden ? "hidden" : ""}"></div>
        ${items}
      </div>
    </div>
    <select name="routeBy"><option value="condition" selected>condition</option><option value="value">value</option></select>
  `
  return div
}

function row({ id = "c0", to = "be0", name = "Yes", match = "true", otherwise = false } = {}) {
  return `
    <div data-branch-item data-connection-id="${id}" data-branch-element-id="${to}">
      <input data-branch-name value="${name}">
      <input data-branch-match-value value="${match}">
      <input type="checkbox" data-branch-otherwise ${otherwise ? "checked" : ""}>
    </div>`
}

describe("BranchManager", () => {
  describe("collectBranches", () => {
    it("returns null when there is no branches container", () => {
      const { mgr } = makeBranchManager()
      expect(mgr.collectBranches()).toBeNull()
    })

    it("reads name, match, otherwise, and ids from data attributes", () => {
      const formFieldsTarget = branchesContainer({
        items: row({ otherwise: true, match: "ignored" }) + row({ id: "c1", to: "be1", name: "No", match: "false" })
      })
      const { mgr } = makeBranchManager({ formFieldsTarget })
      expect(mgr.collectBranches()).toEqual([
        { name: "Yes", matchValue: "", elementId: "be0", connectionId: "c0" },
        { name: "No", matchValue: "false", elementId: "be1", connectionId: "c1" }
      ])
    })

    it("defaults missing name, match, and ids on a sparse row", () => {
      const formFieldsTarget = branchesContainer({
        items: `<div data-branch-item></div>`
      })
      const { mgr } = makeBranchManager({ formFieldsTarget })
      expect(mgr.collectBranches()).toEqual([
        { name: "", matchValue: "", elementId: null, connectionId: "" }
      ])
    })
  })

  describe("buildBranchesFieldHTML", () => {
    it("renders one row per outgoing connection in port order", () => {
      const currentElement = { id: "d", type: "decision", properties: { routeBy: "value" } }
      const canvas = makeCanvas({
        connections: [
          { id: "c1", from: "d", to: "b", fromPort: "port_1", label: "B", matchValue: "b" },
          { id: "c0", from: "d", to: "a", fromPort: "port_0", label: "A", matchValue: "a" }
        ]
      })
      const form = branchesContainer()
      const { mgr } = makeBranchManager({ canvas, currentElement, formFieldsTarget: form, formTarget: form })
      const html = mgr.buildBranchesFieldHTML("branches", { label: "Routes" })
      expect(html).toContain("data-element-field=\"branches\"")
      expect(html).toContain("data-branch-name")
      expect(html).toContain("property-editor#addBranch")
      expect(html).toContain("Add Branch")
      expect(html).toContain("value=\"A\"")
      expect(html).toContain("value=\"B\"")
      expect(mgr.branchIndex).toBe(2)
    })

    it("keeps the empty-state visible when there are no outgoing connections", () => {
      const { mgr } = makeBranchManager({ canvas: makeCanvas({ connections: [] }) })
      const html = mgr.buildBranchesFieldHTML("branches")
      expect(html).toMatch(/data-branches-empty class="\s*"/)
    })

    it("renders a blank connectionId when the outgoing connection has no id", () => {
      const currentElement = { id: "d", type: "decision", properties: {} }
      const canvas = makeCanvas({
        connections: [{ from: "d", to: "a", fromPort: "port_0", label: "A" }]
      })
      const { mgr } = makeBranchManager({ canvas, currentElement })
      const html = mgr.buildBranchesFieldHTML("branches", {})
      expect(html).toContain('data-connection-id=""')
    })

    it("treats a connection without label or target as blank row fields", () => {
      const currentElement = { id: "d", type: "decision", properties: {} }
      const canvas = makeCanvas({
        connections: [{ from: "d", fromPort: "port_0" }]
      })
      const { mgr } = makeBranchManager({ canvas, currentElement })
      const html = mgr.buildBranchesFieldHTML("branches", {})
      expect(html).toContain('data-branch-name')
      expect(html).not.toContain("data-branch-element-id=")
    })
  })

  describe("addBranch / removeBranch", () => {
    it("returns early when there is no branches container", () => {
      const { mgr } = makeBranchManager()
      mgr.addBranch({ preventDefault: vi.fn() })
      expect(mgr.branchIndex).toBe(0)
    })

    it("treats a connection without an id as a blank connectionId", () => {
      const currentElement = { id: "d", type: "decision", x: 200, y: 100, height: 45, properties: {} }
      const canvas = makeCanvas({ elements: [] })
      canvas.createConnection = vi.fn((from, to, fromSide, toSide, opts = {}) => {
        const conn = { from: from.id, to: to.id, fromPort: fromSide, ...opts }
        canvas.connections.push(conn)
        return conn
      })
      const form = branchesContainer()
      const { mgr } = makeBranchManager({ canvas, currentElement, formFieldsTarget: form, formTarget: form })
      mgr.addBranch({ preventDefault: vi.fn() })
      expect(form.querySelector("[data-branch-item]").dataset.connectionId).toBe("")
    })

    it("creates a connection + box and appends a row", () => {
      const currentElement = { id: "d", type: "decision", x: 200, y: 100, height: 45, properties: {} }
      const canvas = makeCanvas({ elements: [] })
      const form = branchesContainer()
      const { mgr, controller } = makeBranchManager({ canvas, currentElement, formFieldsTarget: form, formTarget: form })
      let added = false
      controller.formTarget.addEventListener("branchAdded", () => { added = true })

      mgr.addBranch({ preventDefault: vi.fn() })

      expect(added).toBe(true)
      expect(form.querySelector("[data-branch-item]")).not.toBeNull()
      expect(canvas.elements).toHaveLength(1)
      expect(canvas.elements[0].label).toBe("Branch 1")
      expect(canvas.elements[0].properties.description).toBe("")
      const conn = canvas.connections.find((c) => c.from === "d")
      expect(conn.label).toBe("Branch 1")
      expect(conn.matchValue).toBeUndefined()
      expect(form.querySelector("[data-branches-empty]").classList.contains("hidden")).toBe(true)
    })

    it("skips box creation without a decision or canvas", () => {
      const form = branchesContainer()
      const { mgr } = makeBranchManager({ canvas: null, currentElement: { id: "p", type: "process" }, formFieldsTarget: form })
      mgr.addBranch({ preventDefault: vi.fn() })
      expect(form.querySelector("[data-branch-item]")).not.toBeNull()
      expect(form.querySelector("[data-branch-item]").dataset.branchElementId).toBeUndefined()

      const form2 = branchesContainer()
      const { mgr: mgr2 } = makeBranchManager({
        canvas: makeCanvas({ elements: [] }),
        currentElement: { id: "p", type: "process", x: 0, y: 0, height: 45, properties: {} },
        formFieldsTarget: form2
      })
      mgr2.addBranch({ preventDefault: vi.fn() })
      expect(form2.querySelector("[data-branch-item]").dataset.branchElementId).toBeUndefined()
    })

    it("removeBranch no-ops when the click is not on a row", () => {
      const { mgr } = makeBranchManager()
      expect(() => mgr.removeBranch({ preventDefault: vi.fn(), target: document.createElement("button") })).not.toThrow()
    })

    it("removes only the connection and keeps the box", () => {
      const box = { id: "be0", type: "process", x: 0, y: 0 }
      const currentElement = { id: "d", type: "decision", x: 200, y: 100, height: 45, properties: {} }
      const canvas = makeCanvas({
        elements: [box],
        connections: [{ id: "c0", from: "d", to: "be0", fromPort: "port_0" }]
      })
      const form = branchesContainer({ items: row() })
      const { mgr, controller } = makeBranchManager({ canvas, currentElement, formFieldsTarget: form, formTarget: form })
      let removed = false
      controller.formTarget.addEventListener("branchRemoved", () => { removed = true })

      mgr.removeBranch({ preventDefault: vi.fn(), target: form.querySelector("[data-branch-item]") })

      expect(removed).toBe(true)
      expect(form.querySelector("[data-branch-item]")).toBeNull()
      expect(canvas.elements).toContain(box)
      expect(canvas.deleteConnection).toHaveBeenCalledWith("c0")
      expect(form.querySelector("[data-branches-empty]").classList.contains("hidden")).toBe(false)
    })

    it("keeps the empty state hidden when other rows remain", () => {
      const currentElement = { id: "d", type: "decision", x: 0, y: 0, height: 45, properties: {} }
      const canvas = makeCanvas({ connections: [] })
      const form = branchesContainer({ items: row() + row({ id: "c1", to: "be1" }) })
      const { mgr } = makeBranchManager({ canvas, currentElement, formFieldsTarget: form })
      mgr.removeBranch({ preventDefault: vi.fn(), target: form.querySelector("[data-branch-item]") })
      expect(form.querySelectorAll("[data-branch-item]")).toHaveLength(1)
      expect(form.querySelector("[data-branches-empty]").classList.contains("hidden")).toBe(true)
    })

    it("skips canvas work when there is no canvas or no current element", () => {
      const form = branchesContainer({ items: row() })
      const { mgr } = makeBranchManager({ canvas: null, formFieldsTarget: form })
      mgr.removeBranch({ preventDefault: vi.fn(), target: form.querySelector("[data-branch-item]") })
      expect(form.querySelector("[data-branch-item]")).toBeNull()

      const canvas = makeCanvas()
      const form2 = branchesContainer({ items: row() })
      const { mgr: mgr2 } = makeBranchManager({ canvas, currentElement: null, formFieldsTarget: form2 })
      mgr2.removeBranch({ preventDefault: vi.fn(), target: form2.querySelector("[data-branch-item]") })
      expect(canvas.updateConnections).not.toHaveBeenCalled()
    })
  })

  describe("routeBy switch (D5)", () => {
    it("clears match values except Otherwise and Undo restores them", () => {
      const currentElement = { id: "d", type: "decision", properties: { routeBy: "value" } }
      const conns = [
        { id: "c0", from: "d", to: "a", fromPort: "port_0", label: "A", matchValue: "active" },
        { id: "c1", from: "d", to: "b", fromPort: "port_1", label: "B", matchValue: null }
      ]
      const canvas = makeCanvas({ connections: conns })
      const form = branchesContainer({ items: row({ match: "active" }) + row({ id: "c1", to: "b", name: "B", match: "", otherwise: true }) })
      const { mgr } = makeBranchManager({ canvas, currentElement, formFieldsTarget: form, formTarget: form })

      form.querySelector('[name="routeBy"]').value = "condition"
      mgr._handleRouteByChange({ target: form.querySelector('[name="routeBy"]') })
      expect(conns[0].matchValue).toBeUndefined()
      expect(conns[1].matchValue).toBeNull()
      expect(form.querySelector("[data-route-by-notice]").classList.contains("hidden")).toBe(false)

      mgr._handleRouteByChange({ target: { value: "condition" } })
      expect(conns[0].matchValue).toBeUndefined()

      mgr.undoRouteByChange({ preventDefault: vi.fn() })
      expect(conns[0].matchValue).toBe("active")
      expect(form.querySelector("[data-route-by-notice]").classList.contains("hidden")).toBe(true)

      mgr.undoRouteByChange({ preventDefault: vi.fn() })
    })
  })

  describe("form watch + row apply", () => {
    it("applies name/match edits and exclusive Otherwise", () => {
      const currentElement = { id: "d", type: "decision", properties: {} }
      const conns = [
        { id: "c0", from: "d", to: "a", matchValue: "true", label: "Yes" },
        { id: "c1", from: "d", to: "b", matchValue: "false", label: "No" }
      ]
      const canvas = makeCanvas({ connections: conns })
      const form = branchesContainer({
        items: row({ match: "true" }) + row({ id: "c1", to: "b", name: "No", match: "false" })
      })
      const { mgr } = makeBranchManager({ canvas, currentElement, formFieldsTarget: form, formTarget: form })
      mgr.buildBranchesFieldHTML("branches", {})

      const first = form.querySelector("[data-branch-item]")
      first.querySelector("[data-branch-name]").value = "Renamed"
      first.querySelector("[data-branch-otherwise]").checked = true
      mgr._onFormEvent({ target: first.querySelector("[data-branch-otherwise]") })
      expect(conns[0].label).toBe("Renamed")
      expect(conns[0].matchValue).toBe("")

      const second = form.querySelectorAll("[data-branch-item]")[1]
      second.querySelector("[data-branch-otherwise]").checked = true
      mgr._onFormEvent({ target: second.querySelector("[data-branch-otherwise]") })
      expect(first.querySelector("[data-branch-otherwise]").checked).toBe(false)

      second.querySelector("[data-branch-otherwise]").checked = false
      second.querySelector("[data-branch-match-value]").value = "false"
      mgr._onFormEvent({ target: second.querySelector("[data-branch-match-value]") })
      expect(conns[1].matchValue).toBe("false")

      mgr._onFormEvent({ target: form.querySelector('[name="routeBy"]') })
      mgr._onFormEvent({ target: form.querySelector("[data-section-count]") })
    })

    it("_applyBranchRow no-ops without a matching connection", () => {
      const { mgr } = makeBranchManager({ canvas: makeCanvas({ connections: [] }) })
      const item = document.createElement("div")
      item.dataset.connectionId = "missing"
      expect(() => mgr._applyBranchRow(item)).not.toThrow()
      expect(() => mgr._applyBranchRow(null)).not.toThrow()
    })

    it("finds a connection by element id when connectionId is absent", () => {
      const currentElement = { id: "d", type: "decision", properties: {} }
      const conn = { id: "c0", from: "d", to: "be0", label: "old" }
      const canvas = makeCanvas({ connections: [conn] })
      const { mgr } = makeBranchManager({ canvas, currentElement })
      const item = document.createElement("div")
      item.dataset.branchElementId = "be0"
      item.innerHTML = `<input data-branch-name value="New"><input data-branch-match-value value="x">`
      mgr._applyBranchRow(item)
      expect(conn.label).toBe("New")
      expect(conn.matchValue).toBe("x")
    })

    it("returns null when the row does not match any connection", () => {
      const { mgr } = makeBranchManager({
        canvas: makeCanvas({ connections: [] }),
        currentElement: { id: "d", type: "decision", properties: {} }
      })
      const item = document.createElement("div")
      item.dataset.branchElementId = "missing"
      expect(mgr._connectionForRow(item)).toBeNull()
    })

    it("treats a canvas without a connections array as empty", () => {
      const canvas = makeCanvas({ connections: [] })
      delete canvas.connections
      const { mgr } = makeBranchManager({
        canvas,
        currentElement: { id: "d", type: "decision", properties: {} }
      })
      const item = document.createElement("div")
      item.dataset.branchElementId = "be0"
      expect(mgr._connectionForRow(item)).toBeNull()
    })

    it("clears the label when the row has no name input", () => {
      const conn = { id: "c0", from: "d", to: "be0", label: "old", matchValue: "x" }
      const { mgr } = makeBranchManager({
        canvas: makeCanvas({ connections: [conn] }),
        currentElement: { id: "d", type: "decision", properties: {} }
      })
      const item = document.createElement("div")
      item.dataset.connectionId = "c0"
      item.innerHTML = `<input data-branch-match-value value="y">`
      mgr._applyBranchRow(item)
      expect(conn.label).toBe("")
      expect(conn.matchValue).toBe("y")
    })

    it("adds a row without a connection id when canvas.connections is missing", () => {
      const currentElement = { id: "d", type: "decision", x: 200, y: 100, height: 45, properties: {} }
      const canvas = makeCanvas({ elements: [] })
      canvas.connections = null
      canvas.createConnection = vi.fn()
      const form = branchesContainer()
      const { mgr } = makeBranchManager({ canvas, currentElement, formFieldsTarget: form, formTarget: form })
      mgr.addBranch({ preventDefault: vi.fn() })
      const item = form.querySelector("[data-branch-item]")
      expect(item).not.toBeNull()
      expect(item.dataset.connectionId).toBe("")
    })
  })

  describe("helpers", () => {
    it("_routeBy prefers the form, then properties, then condition", () => {
      const form = branchesContainer()
      form.querySelector('[name="routeBy"]').value = "value"
      const { mgr, controller } = makeBranchManager({ formFieldsTarget: form, formTarget: form })
      expect(mgr._routeBy()).toBe("value")
      form.querySelector('[name="routeBy"]').value = ""
      controller.currentElement.properties.routeBy = "value"
      expect(mgr._routeBy()).toBe("value")
      controller.currentElement.properties = {}
      expect(mgr._routeBy()).toBe("condition")
    })

    it("_defaultBranchName substitutes {index}", () => {
      const { mgr, controller } = makeBranchManager()
      expect(mgr._defaultBranchName(2)).toBe("Branch 2")
      controller.branchFallbackNameFormatValue = "Route {index}"
      expect(mgr._defaultBranchName(1)).toBe("Route 1")
      controller.branchFallbackNameFormatValue = null
      expect(mgr._defaultBranchName(4)).toBe("")
    })

    it("_updateBranchSectionCount writes the live count and no-ops without a section", () => {
      const form = branchesContainer({ items: row() })
      const { mgr } = makeBranchManager({ formFieldsTarget: form })
      mgr._updateBranchSectionCount()
      expect(form.querySelector("[data-section-count]").textContent).toBe("1")
      const { mgr: empty } = makeBranchManager()
      expect(() => empty._updateBranchSectionCount()).not.toThrow()
    })

    it("_rebuildBranchRows no-ops without a container and toggles empty state", () => {
      const { mgr } = makeBranchManager()
      expect(() => mgr._rebuildBranchRows()).not.toThrow()

      const currentElement = { id: "d", type: "decision", properties: {} }
      const canvas = makeCanvas({ connections: [] })
      const form = branchesContainer({ items: row(), emptyHidden: true })
      const { mgr: mgr2 } = makeBranchManager({ canvas, currentElement, formFieldsTarget: form })
      mgr2._rebuildBranchRows()
      expect(form.querySelector("[data-branch-item]")).toBeNull()
      expect(form.querySelector("[data-branches-empty]").classList.contains("hidden")).toBe(false)

      const form3 = document.createElement("div")
      form3.innerHTML = `<div data-branches-container></div>`
      const { mgr: mgr3 } = makeBranchManager({
        canvas: makeCanvas({ connections: [{ from: "d", to: "" }] }),
        currentElement: { id: "d", type: "decision", properties: {} },
        formFieldsTarget: form3
      })
      mgr3._rebuildBranchRows()
      expect(form3.querySelector("[data-branch-item]")).not.toBeNull()
    })

    it("_clearOtherOtherwise no-ops without a container", () => {
      const { mgr } = makeBranchManager()
      expect(() => mgr._clearOtherOtherwise(document.createElement("div"))).not.toThrow()
    })

    it("_ensureFormWatch binds once and no-ops without a form", () => {
      const { mgr, controller } = makeBranchManager()
      controller.formTarget = null
      mgr._formWatchBound = false
      mgr._ensureFormWatch()
      expect(mgr._formWatchBound).toBe(false)

      const form = branchesContainer()
      const { mgr: mgr2 } = makeBranchManager({ formTarget: form, formFieldsTarget: form })
      mgr2._ensureFormWatch()
      mgr2._ensureFormWatch()
      expect(mgr2._formWatchBound).toBe(true)
    })

    it("threads controller Values into labels and the routeBy notice", () => {
      const { mgr, controller } = makeBranchManager()
      controller.otherwiseLabelValue = "Alt"
      controller.routeByClearedNoticeValue = "Cleared"
      controller.undoLabelValue = "Revert"
      expect(mgr._branchLabels().otherwiseLabel).toBe("Alt")
      const html = mgr.buildBranchesFieldHTML("branches", {})
      expect(html).toContain("Cleared")
      expect(html).toContain("Revert")
    })
  })
})
