import { describe, it, expect, beforeEach, vi, afterEach } from "vitest"
import { PageManager } from "controllers/page_builder/page_manager"
import { makeCtrl } from "../../support/page_builder.js"

// Build a ctrl whose currentPageFields getter tracks activePageValue against
// configuration.pages (the real controller resolves it this way).
function pageCtrl(pages, active = pages[0].id, extra = {}) {
  const ctrl = makeCtrl({ configuration: { pages, rules: [], calculations: [] }, activePageValue: active, ...extra })
  Object.defineProperty(ctrl, "currentPageFields", {
    get() { return this.configuration.pages.find((p) => p.id === this.activePageValue)?.fields || [] },
    configurable: true,
  })
  ctrl.propertyManager.hideFloatingPanel = vi.fn()
  return ctrl
}

describe("PageManager", () => {
  afterEach(() => { vi.restoreAllMocks(); document.body.innerHTML = "" })

  describe("addPage", () => {
    it("appends a numbered page, activates it, and re-renders", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "Page 1", order: 1, fields: [] }])
      const pm = new PageManager(ctrl)
      pm.addPage()
      expect(ctrl.configuration.pages).toHaveLength(2)
      expect(ctrl.configuration.pages[1].name).toBe("Page 2")
      expect(ctrl.activePageValue).toBe(ctrl.configuration.pages[1].id)
      expect(ctrl.undoRedoManager.saveHistory).toHaveBeenCalled()
    })
  })

  describe("switchPage", () => {
    it("changes the active page and hides the property panel", () => {
      const ctrl = pageCtrl([
        { id: "page_1", name: "P1", fields: [] },
        { id: "page_2", name: "P2", fields: [] },
      ])
      const pm = new PageManager(ctrl)
      pm.switchPage({ currentTarget: { dataset: { pageId: "page_2" } } })
      expect(ctrl.activePageValue).toBe("page_2")
      expect(ctrl.propertyManager.hideFloatingPanel).toHaveBeenCalled()
    })

    it("ignores a switch to the already-active page", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "P1", fields: [] }])
      const pm = new PageManager(ctrl)
      pm.switchPage({ currentTarget: { dataset: { pageId: "page_1" } } })
      expect(ctrl.propertyManager.hideFloatingPanel).not.toHaveBeenCalled()
    })
  })

  describe("moveFieldsToPage", () => {
    it("relocates a top-level field and reindexes both pages", () => {
      const ctrl = pageCtrl([
        { id: "page_1", name: "P1", fields: [{ id: "a", order: 0 }, { id: "b", order: 1 }] },
        { id: "page_2", name: "P2", fields: [] },
      ])
      const pm = new PageManager(ctrl)
      pm.moveFieldsToPage(["a"], "page_2")
      expect(ctrl.configuration.pages[0].fields.map((f) => f.id)).toEqual(["b"])
      expect(ctrl.configuration.pages[1].fields.map((f) => f.id)).toEqual(["a"])
      expect(ctrl.configuration.pages[1].fields[0].order).toBe(0)
    })

    it("extracts a nested column child into the target page", () => {
      const ctrl = pageCtrl([
        { id: "page_1", name: "P1", fields: [
          { id: "col", field_type: "columns", columns: [{ fields: [{ id: "child" }] }] },
        ] },
        { id: "page_2", name: "P2", fields: [] },
      ])
      const pm = new PageManager(ctrl)
      pm.moveFieldsToPage(["child"], "page_2")
      expect(ctrl.configuration.pages[1].fields.map((f) => f.id)).toEqual(["child"])
      expect(ctrl.configuration.pages[0].fields[0].columns[0].fields).toEqual([])
    })

    it("is a no-op for a missing target page", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "P1", fields: [{ id: "a" }] }])
      const pm = new PageManager(ctrl)
      pm.moveFieldsToPage(["a"], "ghost")
      expect(ctrl.configuration.pages[0].fields).toHaveLength(1)
    })

    it("is a no-op for an empty field-id list", () => {
      const ctrl = pageCtrl([
        { id: "page_1", name: "P1", fields: [{ id: "a" }] },
        { id: "page_2", name: "P2", fields: [] },
      ])
      const pm = new PageManager(ctrl)
      pm.moveFieldsToPage([], "page_2")
      expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
    })

    it("extracts a nested field-group child and leaves an untouched columns container intact", () => {
      const ctrl = pageCtrl([
        { id: "page_1", name: "P1", fields: [
          { id: "grp", type: "field_group", fields: [{ id: "gchild" }, { id: "gkeep" }] },
          { id: "cols", field_type: "columns", columns: [{ fields: [{ id: "cc" }] }, {}] }, // 2nd col has no fields
        ] },
        { id: "page_2", name: "P2", fields: [] },
      ])
      const pm = new PageManager(ctrl)
      pm.moveFieldsToPage(["gchild"], "page_2")
      expect(ctrl.configuration.pages[1].fields.map((f) => f.id)).toEqual(["gchild"])
      // group keeps its non-moved child; columns container survives with its child
      expect(ctrl.configuration.pages[0].fields[0].fields.map((f) => f.id)).toEqual(["gkeep"])
      expect(ctrl.configuration.pages[0].fields[1].columns[0].fields.map((f) => f.id)).toEqual(["cc"])
    })
  })

  describe("deletePage", () => {
    it("refuses to delete the only page", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "P1", fields: [] }])
      const pm = new PageManager(ctrl)
      pm.deletePage({ stopPropagation() {}, currentTarget: { dataset: { pageId: "page_1" } } })
      expect(ctrl.configuration.pages).toHaveLength(1)
    })

    it("deletes a confirmed page and prunes dangling references", () => {
      vi.spyOn(window, "confirm").mockReturnValue(true)
      const ctrl = pageCtrl([
        { id: "page_1", name: "P1", fields: [{ id: "a" }] },
        { id: "page_2", name: "P2", fields: [{ id: "b" }] },
      ], "page_1")
      ctrl.configuration.rules = [
        { id: "r1", conditions: { groups: [{ items: [{ field_id: "b" }] }] }, actions: [{ target_id: "b" }] },
      ]
      ctrl.configuration.calculations = [{ target_field_id: "b" }]
      const pm = new PageManager(ctrl)
      pm.deletePage({ stopPropagation() {}, currentTarget: { dataset: { pageId: "page_2" } } })
      expect(ctrl.configuration.pages.map((p) => p.id)).toEqual(["page_1"])
      expect(ctrl.configuration.calculations).toEqual([])
      expect(ctrl.configuration.rules).toEqual([]) // rule lost all actions -> dropped
    })

    it("aborts when the user cancels the confirm", () => {
      vi.spyOn(window, "confirm").mockReturnValue(false)
      const ctrl = pageCtrl([
        { id: "page_1", name: "P1", fields: [{ id: "a" }] },
        { id: "page_2", name: "P2", fields: [] },
      ])
      const pm = new PageManager(ctrl)
      pm.deletePage({ stopPropagation() {}, currentTarget: { dataset: { pageId: "page_2" } } })
      expect(ctrl.configuration.pages).toHaveLength(2)
    })

    it("pluralizes the field count in the confirm message when a page has multiple fields", () => {
      const confirmSpy = vi.spyOn(window, "confirm").mockReturnValue(false)
      const ctrl = pageCtrl([
        { id: "page_1", name: "P1", fields: [] },
        { id: "page_2", name: "Two", fields: [{ id: "a" }, { id: "b" }] },
      ])
      const pm = new PageManager(ctrl)
      pm.deletePage({ stopPropagation() {}, currentTarget: { dataset: { pageId: "page_2" } } })
      expect(confirmSpy).toHaveBeenCalledWith('Delete "Two" and its 2 fields?')
    })

    it("re-points activePage when the active page itself is deleted", () => {
      vi.spyOn(window, "confirm").mockReturnValue(true)
      const ctrl = pageCtrl([
        { id: "page_1", name: "P1", fields: [] },
        { id: "page_2", name: "P2", fields: [] },
      ], "page_2")
      const pm = new PageManager(ctrl)
      pm.deletePage({ stopPropagation() {}, currentTarget: { dataset: { pageId: "page_2" } } })
      expect(ctrl.configuration.pages.map((p) => p.id)).toEqual(["page_1"])
      expect(ctrl.activePageValue).toBe("page_1")
    })

    it("uses the 'this page' fallback and bails when the target id isn't found (pageIndex -1)", () => {
      vi.spyOn(window, "confirm").mockReturnValue(true)
      const ctrl = pageCtrl([
        { id: "page_1", name: "P1", fields: [] },
        { id: "page_2", name: "P2", fields: [] },
      ])
      const pm = new PageManager(ctrl)
      pm.deletePage({ stopPropagation() {}, currentTarget: { dataset: { pageId: "ghost" } } })
      expect(ctrl.configuration.pages).toHaveLength(2) // nothing removed
      expect(ctrl.undoRedoManager.saveHistory).not.toHaveBeenCalled()
    })

    it("tolerates a deleted page that has no fields array (`page?.fields || []`)", () => {
      vi.spyOn(window, "confirm").mockReturnValue(true)
      const ctrl = pageCtrl([
        { id: "page_1", name: "P1", fields: [] },
        { id: "page_2", name: "P2" }, // no fields key
      ], "page_1")
      const pm = new PageManager(ctrl)
      pm.deletePage({ stopPropagation() {}, currentTarget: { dataset: { pageId: "page_2" } } })
      expect(ctrl.configuration.pages.map((p) => p.id)).toEqual(["page_1"])
    })

    it("drops rule actions that target the deleted page id (`action.target_id === removedPageId`)", () => {
      vi.spyOn(window, "confirm").mockReturnValue(true)
      const ctrl = pageCtrl([
        { id: "page_1", name: "P1", fields: [{ id: "a" }] },
        { id: "page_2", name: "P2", fields: [] },
      ], "page_1")
      ctrl.configuration.rules = [
        { id: "r1", conditions: { groups: [{ items: [{ field_id: "a" }] }] }, actions: [{ target_id: "page_2" }, { target_id: "a" }] },
      ]
      const pm = new PageManager(ctrl)
      pm.deletePage({ stopPropagation() {}, currentTarget: { dataset: { pageId: "page_2" } } })
      // the page-targeted action is dropped; the field-"a" action survives (a not deleted)
      expect(ctrl.configuration.rules[0].actions).toEqual([{ target_id: "a" }])
    })
  })

  describe("_collectAllFieldIds", () => {
    it("walks columns and field groups collecting every id", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "P1", fields: [] }])
      const pm = new PageManager(ctrl)
      const ids = pm._collectAllFieldIds([
        { id: "a" },
        { id: "cols", field_type: "columns", columns: [{ fields: [{ id: "c1" }] }] },
        { id: "grp", type: "field_group", fields: [{ id: "g1" }] },
      ])
      expect([...ids].sort()).toEqual(["a", "c1", "cols", "g1", "grp"])
    })

    it("skips null entries, empty columns, and a columns field with no columns array", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "P1", fields: [] }])
      const pm = new PageManager(ctrl)
      const ids = pm._collectAllFieldIds([
        null,                                                        // !f → continue
        { id: "cols_empty", field_type: "columns" },                // no columns array → (f.columns || [])
        { id: "cols_nofields", field_type: "columns", columns: [{}] }, // col.fields undefined → walk(undefined)
        { id: "z" },
      ])
      expect([...ids].sort()).toEqual(["cols_empty", "cols_nofields", "z"])
    })
  })

  describe("pruneReferencesToDeletedFields null-safety", () => {
    it("tolerates null rules/actions, missing conditions, empty items and empty actions", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "P1", fields: [] }])
      ctrl.configuration.rules = [
        null,                                                          // !rule → returned then filtered
        { id: "r_noconds", actions: [{ target_id: "keep" }] },          // no conditions key
        { id: "r_noactions", conditions: { groups: [{ items: [{ field_id: "keep" }] }] } }, // no actions → filtered out
        { id: "r_nullaction", conditions: { groups: [{}] }, actions: [null, { target_id: "keep" }] }, // null action + group w/o items
      ]
      ctrl.configuration.calculations = [null, { target_field_id: "gone" }, { target_field_id: "keep" }]
      const pm = new PageManager(ctrl)
      pm.pruneReferencesToDeletedFields([{ id: "gone" }])
      // r_noactions dropped (0 actions); null rule dropped; others survive
      expect(ctrl.configuration.rules.map((r) => r.id)).toEqual(["r_noconds", "r_nullaction"])
      // r_nullaction keeps only the non-null surviving action
      const na = ctrl.configuration.rules.find((r) => r.id === "r_nullaction")
      expect(na.actions).toEqual([{ target_id: "keep" }])
      // null calc + orphaned calc dropped
      expect(ctrl.configuration.calculations).toEqual([{ target_field_id: "keep" }])
    })
  })

  describe("pruneReferencesToDeletedFields", () => {
    it("drops calculations and rule items/actions pointing at removed fields", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "P1", fields: [] }])
      ctrl.configuration.rules = [
        { id: "r1", conditions: { groups: [{ items: [{ field_id: "x" }, { field_id: "keep" }] }] }, actions: [{ target_id: "keep" }] },
      ]
      ctrl.configuration.calculations = [{ target_field_id: "x" }, { target_field_id: "keep" }]
      const pm = new PageManager(ctrl)
      pm.pruneReferencesToDeletedFields([{ id: "x" }])
      expect(ctrl.configuration.calculations).toEqual([{ target_field_id: "keep" }])
      expect(ctrl.configuration.rules[0].conditions.groups[0].items).toEqual([{ field_id: "keep" }])
    })
  })

  describe("renderPageTabs", () => {
    it("renders one tab per page plus an add button", () => {
      const ctrl = pageCtrl([
        { id: "page_1", name: "One", fields: [] },
        { id: "page_2", name: "Two", fields: [] },
      ])
      ctrl.hasPageTabsTarget = true
      ctrl.pageTabsTarget = document.createElement("div")
      const pm = new PageManager(ctrl)
      pm.renderPageTabs()
      expect(ctrl.pageTabsTarget.querySelectorAll(".page-tab").length).toBe(2)
      expect(ctrl.pageTabsTarget.innerHTML).toContain("addPage")
    })

    it("omits the rename/delete buttons for a single page (canDelete false)", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "One", fields: [] }])
      ctrl.hasPageTabsTarget = true
      ctrl.pageTabsTarget = document.createElement("div")
      new PageManager(ctrl).renderPageTabs()
      expect(ctrl.pageTabsTarget.querySelectorAll(".page-tab").length).toBe(1)
      expect(ctrl.pageTabsTarget.innerHTML).not.toContain("renamePage")
      expect(ctrl.pageTabsTarget.innerHTML).not.toContain("deletePage")
    })

    it("no-ops without the tabs target", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "One", fields: [] }])
      expect(() => new PageManager(ctrl).renderPageTabs()).not.toThrow()
    })
  })

  describe("renamePage", () => {
    function tabDom(pageName = "Original") {
      const tab = document.createElement("div")
      tab.className = "page-tab"
      const nameSpan = document.createElement("span")
      nameSpan.setAttribute("data-page-name", "")
      nameSpan.textContent = pageName
      const btn = document.createElement("button")
      btn.dataset.pageId = "page_1"
      tab.append(nameSpan, btn)
      document.body.appendChild(tab)
      return { tab, nameSpan, btn }
    }
    function ctrlWithTabs() {
      const ctrl = pageCtrl([{ id: "page_1", name: "Original", fields: [] }])
      ctrl.hasPageTabsTarget = true
      ctrl.pageTabsTarget = document.createElement("div")
      return ctrl
    }

    it("bails when the page id is unknown", () => {
      const ctrl = ctrlWithTabs()
      const pm = new PageManager(ctrl)
      expect(() => pm.renamePage({ stopPropagation() {}, currentTarget: { dataset: { pageId: "ghost" }, closest: () => null } })).not.toThrow()
    })

    it("bails when the tab has no name span", () => {
      const ctrl = ctrlWithTabs()
      const pm = new PageManager(ctrl)
      const btn = { dataset: { pageId: "page_1" }, closest: () => document.createElement("div") }
      expect(() => pm.renamePage({ stopPropagation() {}, currentTarget: btn })).not.toThrow()
    })

    it("commits a new name on blur, snapshotting undo and marking dirty", () => {
      const ctrl = ctrlWithTabs()
      const { btn } = tabDom()
      const pm = new PageManager(ctrl)
      pm.renamePage({ stopPropagation() {}, currentTarget: btn })
      const input = document.querySelector(".page-tab input")
      input.value = "Renamed"
      input.dispatchEvent(new Event("blur"))
      expect(ctrl.configuration.pages[0].name).toBe("Renamed")
      expect(ctrl.undoRedoManager.saveHistory).toHaveBeenCalled()
      expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
    })

    it("does not snapshot when the name is unchanged or blank", () => {
      const ctrl = ctrlWithTabs()
      const { btn } = tabDom()
      const pm = new PageManager(ctrl)
      pm.renamePage({ stopPropagation() {}, currentTarget: btn })
      const input = document.querySelector(".page-tab input")
      input.value = "   " // trims to blank
      input.dispatchEvent(new Event("blur"))
      expect(ctrl.undoRedoManager.saveHistory).not.toHaveBeenCalled()
      expect(ctrl.configuration.pages[0].name).toBe("Original")
    })

    it("Enter triggers a commit and Escape restores the original name before committing", () => {
      const ctrl = ctrlWithTabs()
      const { btn } = tabDom()
      const pm = new PageManager(ctrl)
      pm.renamePage({ stopPropagation() {}, currentTarget: btn })
      const input = document.querySelector(".page-tab input")
      input.value = "New"
      input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter" })) // preventDefault + blur()
      input.dispatchEvent(new Event("blur")) // ensure commit runs in happy-dom
      expect(ctrl.configuration.pages[0].name).toBe("New")

      // Escape resets the input value back to the page name, so the subsequent
      // blur commit is a no-op (value === page.name).
      const { btn: btn2 } = tabDom("New")
      pm.renamePage({ stopPropagation() {}, currentTarget: btn2 })
      const inputs = document.querySelectorAll(".page-tab input")
      const input2 = inputs[inputs.length - 1]
      input2.value = "Discarded"
      input2.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" })) // value → "New"
      input2.dispatchEvent(new Event("blur"))
      expect(ctrl.configuration.pages[0].name).toBe("New") // unchanged
    })
  })

  describe("page-tab drag reordering", () => {
    it("pageTabDragStart records the dragged id and sets transfer data", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "P1", fields: [] }])
      const pm = new PageManager(ctrl)
      const tab = document.createElement("div"); tab.dataset.pageId = "page_1"
      const ev = { currentTarget: tab, dataTransfer: { setData: vi.fn(), effectAllowed: "" } }
      pm.pageTabDragStart(ev)
      expect(pm._draggingPageId).toBe("page_1")
      expect(tab.classList.contains("opacity-50")).toBe(true)
      expect(ev.dataTransfer.setData).toHaveBeenCalledWith("text/plain", "page_1")
    })

    it("pageTabDragEnd clears the state and any drop indicators", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "P1", fields: [] }])
      ctrl.element = document.createElement("div")
      const tab = document.createElement("div")
      tab.className = "page-tab opacity-50 border-l-2 border-l-indigo-500"
      ctrl.element.appendChild(tab)
      const pm = new PageManager(ctrl)
      pm._draggingPageId = "page_1"
      pm.pageTabDragEnd({ currentTarget: tab })
      expect(pm._draggingPageId).toBeNull()
      expect(tab.classList.contains("border-l-2")).toBe(false)
    })

    it("pageTabDragOver shows an indicator on a different tab and bails without a drag / on the same tab", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "P1", fields: [] }])
      ctrl.element = document.createElement("div")
      const target = document.createElement("div"); target.className = "page-tab"; target.dataset.pageId = "page_2"
      ctrl.element.appendChild(target)
      const pm = new PageManager(ctrl)

      // no drag in progress → early return
      pm._draggingPageId = null
      pm.pageTabDragOver({ preventDefault() {}, currentTarget: target, dataTransfer: {} })
      expect(target.classList.contains("border-l-2")).toBe(false)

      // dragging over a different tab → indicator shown
      pm._draggingPageId = "page_1"
      pm.pageTabDragOver({ preventDefault() {}, currentTarget: target, dataTransfer: {} })
      expect(target.classList.contains("border-l-2")).toBe(true)

      // dragging over the SAME tab → early return (no change)
      const same = document.createElement("div"); same.className = "page-tab"; same.dataset.pageId = "page_1"
      pm.pageTabDragOver({ preventDefault() {}, currentTarget: same, dataTransfer: {} })
      expect(same.classList.contains("border-l-2")).toBe(false)
    })

    it("pageTabDrop reorders pages and reindexes order", () => {
      const ctrl = pageCtrl([
        { id: "page_1", name: "P1", order: 1, fields: [] },
        { id: "page_2", name: "P2", order: 2, fields: [] },
        { id: "page_3", name: "P3", order: 3, fields: [] },
      ])
      ctrl.hasPageTabsTarget = true
      ctrl.pageTabsTarget = document.createElement("div")
      const pm = new PageManager(ctrl)
      pm._draggingPageId = "page_3"
      pm.pageTabDrop({ preventDefault() {}, currentTarget: { dataset: { pageId: "page_1" } } })
      expect(ctrl.configuration.pages.map((p) => p.id)).toEqual(["page_3", "page_1", "page_2"])
      expect(ctrl.configuration.pages.map((p) => p.order)).toEqual([1, 2, 3])
      expect(pm._draggingPageId).toBeNull()
    })

    it("pageTabDrop bails without a drag, onto the same tab, or on an unknown index", () => {
      const ctrl = pageCtrl([
        { id: "page_1", name: "P1", fields: [] },
        { id: "page_2", name: "P2", fields: [] },
      ])
      const pm = new PageManager(ctrl)

      pm._draggingPageId = null
      pm.pageTabDrop({ preventDefault() {}, currentTarget: { dataset: { pageId: "page_1" } } })

      pm._draggingPageId = "page_1"
      pm.pageTabDrop({ preventDefault() {}, currentTarget: { dataset: { pageId: "page_1" } } }) // same tab

      pm._draggingPageId = "ghost"
      pm.pageTabDrop({ preventDefault() {}, currentTarget: { dataset: { pageId: "page_2" } } }) // dragIndex -1

      expect(ctrl.configuration.pages.map((p) => p.id)).toEqual(["page_1", "page_2"]) // unchanged
      expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
    })
  })

  describe("_hasInputFields", () => {
    it("is false when every field is layout-only", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "P1", fields: [{ id: "a", property_type: "layout" }] }])
      expect(new PageManager(ctrl)._hasInputFields()).toBe(false)
    })

    it("is true when a data field (or a nested one) exists", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "P1", fields: [
        { id: "cols", field_type: "columns", columns: [{ fields: [{ id: "c", property_type: "string" }] }] },
      ] }])
      expect(new PageManager(ctrl)._hasInputFields()).toBe(true)
    })

    it("tolerates undefined pages / fields / columns (defensive `|| []` fallbacks)", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "P1", fields: [] }])
      const pm = new PageManager(ctrl)
      ctrl.configuration.pages = undefined
      expect(pm._hasInputFields()).toBe(false)

      ctrl.configuration.pages = [
        { id: "p", /* no fields */ },
        { id: "q", fields: [{ id: "cols", field_type: "columns" /* no columns */ }] },
        { id: "r", fields: [{ id: "cols2", field_type: "columns", columns: [{ /* no fields */ }] }] },
      ]
      expect(pm._hasInputFields()).toBe(false)
    })
  })

  describe("updateFormFooter", () => {
    it("hides the footer when there are no input fields", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "P1", fields: [{ id: "a", property_type: "layout" }] }])
      ctrl.hasFormFooterTarget = true
      ctrl.formFooterTarget = document.createElement("div")
      new PageManager(ctrl).updateFormFooter()
      expect(ctrl.formFooterTarget.classList.contains("hidden")).toBe(true)
      expect(ctrl.formFooterTarget.innerHTML).toBe("")
    })

    it("renders a submit button for a single-page form", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "P1", fields: [{ id: "a", property_type: "string" }] }])
      ctrl.hasFormFooterTarget = true
      ctrl.formFooterTarget = document.createElement("div")
      ctrl.configuration.form_settings = { submit_button_text: "Send it" }
      new PageManager(ctrl).updateFormFooter()
      expect(ctrl.formFooterTarget.innerHTML).toContain("Send it")
      expect(ctrl.formFooterTarget.innerHTML).toContain('type="submit"')
    })

    it("shows a step counter and Next for a non-final wizard page", () => {
      const ctrl = pageCtrl([
        { id: "page_1", name: "P1", fields: [{ id: "a", property_type: "string" }] },
        { id: "page_2", name: "P2", fields: [] },
      ], "page_1")
      ctrl.hasFormFooterTarget = true
      ctrl.formFooterTarget = document.createElement("div")
      new PageManager(ctrl).updateFormFooter()
      expect(ctrl.formFooterTarget.innerHTML).toContain("Step 1 of 2")
      expect(ctrl.formFooterTarget.innerHTML).toContain("Next")
    })

    it("shows Previous + submit on the final wizard page", () => {
      const ctrl = pageCtrl([
        { id: "page_1", name: "P1", fields: [{ id: "a", property_type: "string" }] },
        { id: "page_2", name: "P2", fields: [{ id: "b", property_type: "string" }] },
      ], "page_2")
      ctrl.hasFormFooterTarget = true
      ctrl.formFooterTarget = document.createElement("div")
      ctrl.configuration.form_settings = { submit_button_text: "Finish" }
      new PageManager(ctrl).updateFormFooter()
      const html = ctrl.formFooterTarget.innerHTML
      expect(html).toContain("Previous")
      expect(html).toContain("Step 2 of 2")
      expect(html).toContain('type="submit"')
      expect(html).toContain("Finish")
    })
  })

  describe("_escapeHtml", () => {
    it("escapes markup in tenant-supplied strings", () => {
      const ctrl = pageCtrl([{ id: "page_1", name: "P1", fields: [] }])
      expect(new PageManager(ctrl)._escapeHtml("<b>x</b>")).toBe("&lt;b&gt;x&lt;/b&gt;")
    })
  })
})
