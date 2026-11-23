import { describe, it, expect, beforeEach, vi } from "vitest"
import { UndoRedoManager } from "controllers/page_builder/undo_redo_manager"
import { makeCtrl } from "../../support/page_builder.js"

function ctrlWith(pages) {
  const ctrl = makeCtrl({
    configuration: { pages },
    activePageValue: pages[0]?.id || "page_1",
    undoStack: [],
    redoStack: [],
    maxHistorySize: 3,
    selectedFieldId: null,
    hasUndoBtnTarget: true,
    undoBtnTarget: document.createElement("button"),
    hasRedoBtnTarget: true,
    redoBtnTarget: document.createElement("button"),
  })
  ctrl.pageManager.renderPageTabs = vi.fn()
  ctrl.pageManager.updateFormFooter = vi.fn()
  ctrl.propertyManager.showFloatingPanel = vi.fn()
  ctrl.propertyManager.hideFloatingPanel = vi.fn()
  Object.defineProperty(ctrl, "currentPageFields", {
    get() {
      return this.configuration.pages.find((p) => p.id === this.activePageValue)?.fields || []
    },
    configurable: true,
  })
  return ctrl
}

describe("UndoRedoManager", () => {
  let ctrl, um
  beforeEach(() => {
    ctrl = ctrlWith([{ id: "page_1", fields: [] }])
    um = new UndoRedoManager(ctrl)
  })

  describe("saveState", () => {
    it("pushes a snapshot, clears redo, marks dirty", () => {
      ctrl.redoStack = [JSON.stringify({ configuration: {}, activePageId: "x" })]
      um.saveState()
      expect(ctrl.undoStack).toHaveLength(1)
      expect(ctrl.redoStack).toEqual([])
      expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
    })

    it("is a no-op when the snapshot equals the top of the stack", () => {
      um.saveState()
      um.saveState()
      expect(ctrl.undoStack).toHaveLength(1)
    })

    it("caps the stack by maxHistorySize (drops the oldest)", () => {
      for (let i = 0; i < 5; i++) {
        ctrl.activePageValue = `page_${i}`
        ctrl.configuration.pages = [{ id: `page_${i}`, fields: [] }]
        um.saveState()
      }
      expect(ctrl.undoStack).toHaveLength(3)
    })

    it("disables the undo button when the stack is empty and enables it otherwise", () => {
      um.updateUndoRedoButtons()
      expect(ctrl.undoBtnTarget.disabled).toBe(true)
      um.saveState()
      expect(ctrl.undoBtnTarget.disabled).toBe(false)
    })

    it("caps the stack by cumulative byte size (drops oldest entries until under budget)", () => {
      // Pre-load two ~3MB entries (6MB total, over the 5MB budget) directly —
      // saveState only cares about .length/shift, not JSON validity.
      ctrl.undoStack = ["x".repeat(3 * 1024 * 1024), "y".repeat(3 * 1024 * 1024)]
      ctrl.maxHistorySize = 10 // high enough that the count cap doesn't fire first
      um.saveState()
      // the oldest (first) entry was evicted to bring the total back under budget
      expect(ctrl.undoStack).not.toContain("x".repeat(3 * 1024 * 1024))
      expect(ctrl.undoStack[ctrl.undoStack.length - 1]).toBe(um._snapshot())
    })

    it("saveHistory delegates to saveState", () => {
      um.saveHistory()
      expect(ctrl.undoStack).toHaveLength(1)
      expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
    })
  })

  describe("undo/redo round trip", () => {
    it("undo restores the previous configuration and pushes onto redo", () => {
      // baseline snapshot
      um.saveState()
      // mutate current document
      ctrl.configuration.pages = [{ id: "page_1", fields: [{ id: "f1" }] }]

      um.undo()
      expect(ctrl.configuration.pages[0].fields).toEqual([])
      expect(ctrl.redoStack).toHaveLength(1)
      expect(ctrl.pageManager.renderPageTabs).toHaveBeenCalled()
    })

    it("redo re-applies the undone change", () => {
      um.saveState()
      ctrl.configuration.pages = [{ id: "page_1", fields: [{ id: "f1" }] }]
      um.undo()
      um.redo()
      expect(ctrl.configuration.pages[0].fields).toEqual([{ id: "f1" }])
    })

    it("undo/redo are no-ops on empty stacks", () => {
      um.undo()
      expect(ctrl.pageManager.renderPageTabs).not.toHaveBeenCalled()
      um.redo()
      expect(ctrl.pageManager.renderPageTabs).not.toHaveBeenCalled()
    })
  })

  describe("_restore", () => {
    it("swallows malformed JSON and leaves state untouched", () => {
      const before = ctrl.configuration
      um._restore("{not json")
      expect(ctrl.configuration).toBe(before)
    })

    it("falls back to first page id when the saved active page no longer exists", () => {
      um._restore(JSON.stringify({
        configuration: { pages: [{ id: "page_9", fields: [] }] },
        activePageId: "gone",
      }))
      expect(ctrl.activePageValue).toBe("page_9")
    })

    it("handles legacy bare-configuration entries", () => {
      um._restore(JSON.stringify({ pages: [{ id: "page_1", fields: [] }] }))
      expect(ctrl.configuration.pages[0].id).toBe("page_1")
    })

    it("falls back to 'page_1' when the saved active page is gone and there are no pages left", () => {
      um._restore(JSON.stringify({
        configuration: { pages: [] },
        activePageId: "gone",
      }))
      expect(ctrl.activePageValue).toBe("page_1")
    })

    it("legacy entries also re-point activePageValue when the current active page no longer exists", () => {
      ctrl.activePageValue = "page_missing"
      um._restore(JSON.stringify({ pages: [{ id: "page_1", fields: [] }] }))
      expect(ctrl.activePageValue).toBe("page_1")
    })

    it("legacy entries fall back to 'page_1' when the current active page is gone and there are no pages left", () => {
      ctrl.activePageValue = "page_missing"
      um._restore(JSON.stringify({ pages: [] }))
      expect(ctrl.activePageValue).toBe("page_1")
    })
  })

  describe("_refreshSelectionAfterRestore", () => {
    it("deselects when nothing is selected", () => {
      ctrl.selectedFieldId = null
      um._refreshSelectionAfterRestore()
      expect(ctrl.selectionManager.deselectAll).toHaveBeenCalled()
    })

    it("refreshes the panel when the selected field survives", () => {
      ctrl.configuration.pages = [{ id: "page_1", fields: [{ id: "f1" }] }]
      ctrl.selectedFieldId = "f1"
      um._refreshSelectionAfterRestore()
      expect(ctrl.propertyManager.showFloatingPanel).toHaveBeenCalledWith("f1")
    })

    it("clears selection and hides panel when the field was removed", () => {
      ctrl.configuration.pages = [{ id: "page_1", fields: [] }]
      ctrl.selectedFieldId = "gone"
      um._refreshSelectionAfterRestore()
      expect(ctrl.selectedFieldId).toBeNull()
      expect(ctrl.propertyManager.hideFloatingPanel).toHaveBeenCalled()
    })

    it("finds the selected field nested inside a columns field's column fields", () => {
      ctrl.configuration.pages = [{
        id: "page_1",
        fields: [{
          id: "col1",
          field_type: "columns",
          columns: [{ fields: [{ id: "nested1" }] }],
        }],
      }]
      ctrl.selectedFieldId = "nested1"
      um._refreshSelectionAfterRestore()
      expect(ctrl.propertyManager.showFloatingPanel).toHaveBeenCalledWith("nested1")
    })

    it("treats a columns field with no columns array as having no nested fields", () => {
      ctrl.configuration.pages = [{
        id: "page_1",
        fields: [{ id: "col1", field_type: "columns" /* no `columns` key */ }],
      }]
      ctrl.selectedFieldId = "gone"
      um._refreshSelectionAfterRestore()
      expect(ctrl.selectedFieldId).toBeNull()
      expect(ctrl.propertyManager.hideFloatingPanel).toHaveBeenCalled()
    })

    it("treats a column with no fields array as having no nested fields", () => {
      ctrl.configuration.pages = [{
        id: "page_1",
        fields: [{ id: "col1", field_type: "columns", columns: [{} /* no `fields` key */] }],
      }]
      ctrl.selectedFieldId = "gone"
      um._refreshSelectionAfterRestore()
      expect(ctrl.selectedFieldId).toBeNull()
      expect(ctrl.propertyManager.hideFloatingPanel).toHaveBeenCalled()
    })
  })
})
