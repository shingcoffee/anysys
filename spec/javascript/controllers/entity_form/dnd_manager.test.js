// NOTE: dnd_manager uses native HTML5 drag-and-drop. The actual drag positioning
// (cursor coordinates, drop-target geometry) is Playwright's job, not happy-dom's.
// These tests cover the pure event-guard + delegation logic: which drags are
// accepted, and that accepted drops delegate to schemaManager.moveRowTo /
// moveGroupTo with the right ids. schemaManager is stubbed with spies.
import { describe, it, expect, vi, beforeEach } from "vitest"
import { DndManager } from "controllers/entity_form/dnd_manager"
import { buildController, fakeDataTransfer } from "./support.js"

let controller, dnd, moveRowTo, moveGroupTo

beforeEach(() => {
  ;({ controller } = buildController(""))
  moveRowTo = vi.fn()
  moveGroupTo = vi.fn()
  controller.schemaManager = { moveRowTo, moveGroupTo }
  dnd = new DndManager(controller)
})

const dragEvent = (currentTarget, extra = {}) => ({
  currentTarget,
  dataTransfer: fakeDataTransfer(),
  preventDefault: vi.fn(),
  ...extra,
})

describe("DndManager row drag lifecycle", () => {
  it("dragStartRow arms row state + marks the row semi-transparent", () => {
    const row = document.createElement("tr")
    row.setAttribute("data-attribute-item", "")
    row.setAttribute("data-attr-name-slug", "email")
    const ev = dragEvent(row)
    dnd.dragStartRow(ev)
    expect(dnd.dragKind).toBe("row")
    expect(dnd.dragRowEl).toBe(row)
    expect(ev.dataTransfer.effectAllowed).toBe("move")
    expect(ev.dataTransfer.getData("text/plain")).toBe("email")
    expect(row.classList.contains("opacity-50")).toBe(true)
  })

  it("dragStartRow ignores an element that is not an attribute row", () => {
    const notRow = document.createElement("div")
    dnd.dragStartRow(dragEvent(notRow))
    expect(dnd.dragKind).toBeNull()
  })

  it("dragStartRow defaults to an empty slug when the attribute is missing", () => {
    const row = document.createElement("tr")
    row.setAttribute("data-attribute-item", "")
    const ev = dragEvent(row)
    dnd.dragStartRow(ev)
    expect(ev.dataTransfer.getData("text/plain")).toBe("")
  })

  it("dragOverRow preventDefaults + sets dropEffect only while dragging a row", () => {
    dnd.dragKind = "row"
    const ev = dragEvent(document.createElement("tr"))
    dnd.dragOverRow(ev)
    expect(ev.preventDefault).toHaveBeenCalled()
    expect(ev.dataTransfer.dropEffect).toBe("move")

    dnd.dragKind = null
    const ev2 = dragEvent(document.createElement("tr"))
    dnd.dragOverRow(ev2)
    expect(ev2.preventDefault).not.toHaveBeenCalled()
  })

  it("dropRow delegates to schemaManager.moveRowTo with the target's group id", () => {
    const dragRow = document.createElement("tr")
    dnd.dragKind = "row"
    dnd.dragRowEl = dragRow
    const target = document.createElement("tr")
    target.setAttribute("data-attr-group-id", "g7")
    dnd.dropRow(dragEvent(target))
    expect(moveRowTo).toHaveBeenCalledWith(dragRow, { groupId: "g7", beforeRow: target })
  })

  it("dropRow is a no-op when dropping onto the dragged row itself", () => {
    const dragRow = document.createElement("tr")
    dnd.dragKind = "row"
    dnd.dragRowEl = dragRow
    dnd.dropRow(dragEvent(dragRow))
    expect(moveRowTo).not.toHaveBeenCalled()
  })

  it("dropRow treats a missing group-id attribute as null", () => {
    const dragRow = document.createElement("tr")
    dnd.dragKind = "row"
    dnd.dragRowEl = dragRow
    const target = document.createElement("tr")
    dnd.dropRow(dragEvent(target))
    expect(moveRowTo).toHaveBeenCalledWith(dragRow, { groupId: null, beforeRow: target })
  })

  it("dropRow ignores drops when a group (not a row) is being dragged", () => {
    dnd.dragKind = "group"
    dnd.dropRow(dragEvent(document.createElement("tr")))
    expect(moveRowTo).not.toHaveBeenCalled()
  })

  it("dragEndRow clears state and the opacity marker", () => {
    const row = document.createElement("tr")
    row.classList.add("opacity-50")
    dnd.dragRowEl = row
    dnd.dragKind = "row"
    dnd.dragEndRow()
    expect(row.classList.contains("opacity-50")).toBe(false)
    expect(dnd.dragKind).toBeNull()
    expect(dnd.dragRowEl).toBeNull()
  })
})

describe("DndManager group drag lifecycle", () => {
  it("dragStartGroup arms group state from the header's group id", () => {
    const header = document.createElement("tr")
    header.setAttribute("data-attribute-group-header", "")
    header.setAttribute("data-group-id", "g3")
    const ev = dragEvent(header)
    dnd.dragStartGroup(ev)
    expect(dnd.dragKind).toBe("group")
    expect(dnd.dragGroupId).toBe("g3")
    expect(ev.dataTransfer.effectAllowed).toBe("move")
  })

  it("dropGroup delegates to moveGroupTo with source + target group ids", () => {
    dnd.dragKind = "group"
    dnd.dragGroupId = "src"
    const header = document.createElement("tr")
    header.setAttribute("data-attribute-group-header", "")
    header.setAttribute("data-group-id", "dst")
    dnd.dropGroup(dragEvent(header))
    expect(moveGroupTo).toHaveBeenCalledWith("src", "dst")
  })

  it("dropGroup is a no-op when dropping a group onto itself", () => {
    dnd.dragKind = "group"
    dnd.dragGroupId = "same"
    const header = document.createElement("tr")
    header.setAttribute("data-attribute-group-header", "")
    header.setAttribute("data-group-id", "same")
    dnd.dropGroup(dragEvent(header))
    expect(moveGroupTo).not.toHaveBeenCalled()
  })

  it("dropGroup ignores drops when a row (not a group) is being dragged", () => {
    dnd.dragKind = "row"
    dnd.dropGroup(dragEvent(document.createElement("tr")))
    expect(moveGroupTo).not.toHaveBeenCalled()
  })

  it("dropGroup treats a missing group-id attribute as null and no-ops", () => {
    dnd.dragKind = "group"
    dnd.dragGroupId = "src"
    const header = document.createElement("tr")
    header.setAttribute("data-attribute-group-header", "")
    dnd.dropGroup(dragEvent(header))
    expect(moveGroupTo).not.toHaveBeenCalled()
  })

  it("dropGroup falls back to the raw currentTarget when it has no closest()", () => {
    dnd.dragKind = "group"
    dnd.dragGroupId = "src"
    const fakeHeader = { getAttribute: () => "dst" }
    dnd.dropGroup(dragEvent(fakeHeader))
    expect(moveGroupTo).toHaveBeenCalledWith("src", "dst")
  })

  it("dropGroup is a no-op when closest() finds no group header", () => {
    dnd.dragKind = "group"
    dnd.dragGroupId = "src"
    const orphan = document.createElement("tr")
    dnd.dropGroup(dragEvent(orphan))
    expect(moveGroupTo).not.toHaveBeenCalled()
  })

  it("dragOverGroupHeader only responds while dragging a group", () => {
    dnd.dragKind = "row"
    const ev = dragEvent(document.createElement("tr"))
    dnd.dragOverGroupHeader(ev)
    expect(ev.preventDefault).not.toHaveBeenCalled()
  })

  it("dragOverGroupHeader preventDefaults + sets dropEffect while dragging a group", () => {
    dnd.dragKind = "group"
    const ev = dragEvent(document.createElement("tr"))
    dnd.dragOverGroupHeader(ev)
    expect(ev.preventDefault).toHaveBeenCalled()
    expect(ev.dataTransfer.dropEffect).toBe("move")
  })

  it("dragStartGroup falls back to the raw currentTarget when it has no closest()", () => {
    const fakeHeader = { getAttribute: () => "g9" }
    const ev = dragEvent(fakeHeader)
    dnd.dragStartGroup(ev)
    expect(dnd.dragKind).toBe("group")
    expect(dnd.dragGroupId).toBe("g9")
  })

  it("dragStartGroup is a no-op when closest() finds no group header", () => {
    const orphan = document.createElement("tr")
    dnd.dragStartGroup(dragEvent(orphan))
    expect(dnd.dragKind).toBeNull()
  })
})
