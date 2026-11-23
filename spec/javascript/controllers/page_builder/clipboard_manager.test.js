import { describe, it, expect, vi, beforeEach } from "vitest"
import { ClipboardManager } from "controllers/page_builder/clipboard_manager"
import { makeCtrl, field } from "../../support/page_builder.js"

describe("ClipboardManager", () => {
  let ctrl, cm
  beforeEach(() => {
    ctrl = makeCtrl({ currentPage: { id: "p1", fields: [] } })
    cm = new ClipboardManager(ctrl)
  })

  describe("copy", () => {
    it("does nothing when nothing is selected", () => {
      ctrl.selectionManager.getSelectedFields.mockReturnValue([])
      cm.copy()
      expect(cm.clipboard).toEqual([])
    })

    it("deep-clones the selected fields into the clipboard", () => {
      const a = field({ id: "a", label: "A" })
      ctrl.selectionManager.getSelectedFields.mockReturnValue([a])
      cm.copy()
      expect(cm.clipboard).toHaveLength(1)
      expect(cm.clipboard[0]).toEqual(a)
      expect(cm.clipboard[0]).not.toBe(a) // deep clone
    })
  })

  describe("cut", () => {
    it("copies then removes the selected fields from the page and marks dirty", () => {
      const a = field({ id: "a" })
      const b = field({ id: "b" })
      ctrl.currentPage.fields = [a, b]
      ctrl.selectionManager.getSelectedFields.mockReturnValue([a])
      cm.cut()
      expect(ctrl.currentPage.fields.map((f) => f.id)).toEqual(["b"])
      expect(ctrl.saveState).toHaveBeenCalled()
      expect(ctrl.selectionManager.deselectAll).toHaveBeenCalled()
      expect(ctrl.fieldManager.renderFields).toHaveBeenCalled()
      expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
    })

    it("is a no-op when clipboard ends up empty", () => {
      ctrl.selectionManager.getSelectedFields.mockReturnValue([])
      ctrl.currentPage.fields = [field({ id: "a" })]
      cm.cut()
      expect(ctrl.currentPage.fields).toHaveLength(1)
      expect(ctrl.saveState).not.toHaveBeenCalled()
    })
  })

  describe("paste", () => {
    it("does nothing with an empty clipboard", () => {
      cm.paste()
      expect(ctrl.saveState).not.toHaveBeenCalled()
    })

    it("inserts clones with fresh ids and unique slugs at end when nothing selected", () => {
      ctrl.currentPage.fields = [field({ id: "x", property_slug: "name" })]
      cm.clipboard = [field({ id: "orig", property_slug: "name" })]
      ctrl.selectionManager.getSelectedFieldIds.mockReturnValue([])
      cm.paste()
      expect(ctrl.currentPage.fields).toHaveLength(2)
      const pasted = ctrl.currentPage.fields[1]
      expect(pasted.id).not.toBe("orig")
      expect(pasted.property_slug).toBe("name_copy")
      expect(ctrl.selectionManager.addToSelection).toHaveBeenCalledWith(pasted.id)
    })

    it("inserts right after the last selected field", () => {
      const a = field({ id: "a", property_slug: "a" })
      const b = field({ id: "b", property_slug: "b" })
      ctrl.currentPage.fields = [a, b]
      cm.clipboard = [field({ id: "orig", property_slug: "z" })]
      ctrl.selectionManager.getSelectedFieldIds.mockReturnValue(["a"])
      cm.paste()
      // Inserted at index 1 (after "a")
      expect(ctrl.currentPage.fields.map((f) => f.id).slice(0, 2)).toEqual(["a", ctrl.currentPage.fields[1].id])
      expect(ctrl.currentPage.fields[1].property_slug).toBe("z_copy")
      expect(ctrl.currentPage.fields[2].id).toBe("b")
    })
  })

  describe("duplicateSelected", () => {
    it("clones each selected field in place with a new id + unique slug", () => {
      const a = field({ id: "a", property_slug: "a" })
      ctrl.currentPage.fields = [a]
      ctrl.selectionManager.getSelectedFields.mockReturnValue([a])
      cm.duplicateSelected()
      expect(ctrl.currentPage.fields).toHaveLength(2)
      const dup = ctrl.currentPage.fields[1]
      expect(dup.id).not.toBe("a")
      expect(dup.property_slug).toBe("a_copy")
    })

    it("does nothing when selection is empty", () => {
      ctrl.selectionManager.getSelectedFields.mockReturnValue([])
      cm.duplicateSelected()
      expect(ctrl.saveState).not.toHaveBeenCalled()
    })
  })

  describe("_newFieldId", () => {
    it("produces unique ids across a synchronous loop", () => {
      const ids = new Set([cm._newFieldId(0), cm._newFieldId(1), cm._newFieldId(2)])
      expect(ids.size).toBe(3)
    })
  })

  describe("_uniqueSlug", () => {
    it("passes falsy slugs through unchanged (layout elements have none)", () => {
      expect(cm._uniqueSlug(undefined)).toBeUndefined()
      expect(cm._uniqueSlug("")).toBe("")
    })

    it("appends _copy and increments on collision", () => {
      ctrl.currentPage.fields = [
        field({ id: "1", property_slug: "name_copy" }),
        field({ id: "2", property_slug: "name_copy_2" }),
      ]
      expect(cm._uniqueSlug("name")).toBe("name_copy_3")
    })

    it("strips an existing _copy suffix before re-appending", () => {
      ctrl.currentPage.fields = []
      expect(cm._uniqueSlug("email_copy_5")).toBe("email_copy")
    })
  })
})
