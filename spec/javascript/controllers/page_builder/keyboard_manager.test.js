import { describe, it, expect, beforeEach, vi } from "vitest"
import { KeyboardManager } from "controllers/page_builder/keyboard_manager"
import { makeCtrl, field } from "../../support/page_builder.js"

function kbCtrl(overrides = {}) {
  const ctrl = makeCtrl(overrides)
  ctrl.zoomManager = { openSearch: vi.fn(), zoomIn: vi.fn(), zoomOut: vi.fn(), zoomReset: vi.fn() }
  ctrl.commandPaletteManager = { open: vi.fn(), close: vi.fn() }
  ctrl.contextMenuManager = { close: vi.fn() }
  ctrl.inserterManager = { isPopoverOpen: vi.fn(() => false), closePopover: vi.fn() }
  ctrl.tabPanelTargets = []
  ctrl.saveManager.save = vi.fn()
  ctrl.fieldManager.deleteField = vi.fn()
  ctrl.fieldManager.selectFieldById = vi.fn()
  ctrl.fieldManager.deselectField = vi.fn()
  ctrl.selectionManager.selectAll = vi.fn()
  ctrl.selectionManager.isEmpty = true
  return ctrl
}

// A keydown event with sensible defaults; target defaults to a DIV (not an input).
function keyEvent(props = {}) {
  return {
    key: "", ctrlKey: false, metaKey: false, shiftKey: false,
    target: document.createElement("div"),
    preventDefault: vi.fn(),
    ...props,
  }
}

describe("KeyboardManager", () => {
  let ctrl, km
  beforeEach(() => {
    ctrl = kbCtrl()
    km = new KeyboardManager(ctrl)
  })

  describe("bind/unbind", () => {
    it("registers and removes the keydown handler on document", () => {
      const add = vi.spyOn(document, "addEventListener")
      const remove = vi.spyOn(document, "removeEventListener")
      km.bindKeyboardShortcuts()
      expect(add).toHaveBeenCalledWith("keydown", expect.any(Function))
      expect(ctrl.boundHandleKeydown).toBeTypeOf("function")
      km.unbindKeyboardShortcuts()
      expect(remove).toHaveBeenCalledWith("keydown", ctrl.boundHandleKeydown)
      add.mockRestore(); remove.mockRestore()
    })

    it("registers and removes the click-outside handler on document", () => {
      const add = vi.spyOn(document, "addEventListener")
      const remove = vi.spyOn(document, "removeEventListener")
      km.bindClickOutside()
      expect(add).toHaveBeenCalledWith("click", expect.any(Function))
      expect(ctrl.boundHandleClickOutside).toBeTypeOf("function")
      km.unbindClickOutside()
      expect(remove).toHaveBeenCalledWith("click", ctrl.boundHandleClickOutside)
      add.mockRestore(); remove.mockRestore()
    })
  })

  describe("handleClickOutside", () => {
    const clickEvent = (target) => ({ target })

    beforeEach(() => {
      ctrl.tabPanelTargets = []
      ctrl.selectionManager.isEmpty = true
      ctrl.propertyManager.isFloatingPanelVisible = vi.fn(() => false)
    })

    it("closes the inserter popover when the click lands outside both the popover and its trigger button", () => {
      ctrl.inserterManager.isPopoverOpen.mockReturnValue(true)
      ctrl.hasInserterPopoverTarget = false
      const target = document.createElement("div")
      km.handleClickOutside(clickEvent(target))
      expect(ctrl.inserterManager.closePopover).toHaveBeenCalled()
    })

    it("leaves the inserter popover open when the click is inside it", () => {
      ctrl.inserterManager.isPopoverOpen.mockReturnValue(true)
      const popover = document.createElement("div")
      const inner = document.createElement("span")
      popover.appendChild(inner)
      ctrl.hasInserterPopoverTarget = true
      ctrl.inserterPopoverTarget = popover
      km.handleClickOutside(clickEvent(inner))
      expect(ctrl.inserterManager.closePopover).not.toHaveBeenCalled()
    })

    it("leaves the inserter popover open when the click is on its trigger button", () => {
      ctrl.inserterManager.isPopoverOpen.mockReturnValue(true)
      ctrl.hasInserterPopoverTarget = false
      const button = document.createElement("button")
      button.setAttribute("data-action", "click->page-builder#openInserterPopover")
      km.handleClickOutside(clickEvent(button))
      expect(ctrl.inserterManager.closePopover).not.toHaveBeenCalled()

      const catalogButton = document.createElement("button")
      catalogButton.setAttribute("data-action", "click->page-builder#openFullCatalog")
      km.handleClickOutside(clickEvent(catalogButton))
      expect(ctrl.inserterManager.closePopover).not.toHaveBeenCalled()
    })

    it("closes all tab panels when a click lands outside the active panel and its tab button", () => {
      const panel = document.createElement("div")
      ctrl.tabPanelTargets = [panel] // visible (no "hidden" class)
      const outside = document.createElement("div")
      km.handleClickOutside(clickEvent(outside))
      expect(ctrl.tabManager.closeAllTabPanels).toHaveBeenCalled()
    })

    it("leaves tab panels open when the click lands on a tab button", () => {
      const panel = document.createElement("div")
      ctrl.tabPanelTargets = [panel]
      const tabButton = document.createElement("button")
      tabButton.setAttribute("data-page-builder-target", "tabButton")
      km.handleClickOutside(clickEvent(tabButton))
      expect(ctrl.tabManager.closeAllTabPanels).not.toHaveBeenCalled()
    })

    it("leaves tab panels open when the click lands inside the visible panel itself", () => {
      const panel = document.createElement("div")
      const inner = document.createElement("span")
      panel.appendChild(inner)
      ctrl.tabPanelTargets = [panel]
      km.handleClickOutside(clickEvent(inner))
      expect(ctrl.tabManager.closeAllTabPanels).not.toHaveBeenCalled()
    })

    it("does nothing to tab panels when none is active", () => {
      const hiddenPanel = document.createElement("div")
      hiddenPanel.classList.add("hidden")
      ctrl.tabPanelTargets = [hiddenPanel]
      km.handleClickOutside(clickEvent(document.createElement("div")))
      expect(ctrl.tabManager.closeAllTabPanels).not.toHaveBeenCalled()
    })

    it("deselects the field when clicking outside the floating panel, toolbar, move modal, sidebar, and quick-add toolbar", () => {
      ctrl.selectionManager.isEmpty = false
      ctrl.propertyManager.isFloatingPanelVisible = vi.fn(() => true)
      ctrl.hasFloatingPanelTarget = false
      ctrl.hasToolbarWidthGroupTarget = false
      ctrl.hasLeftSidebarTarget = false
      ctrl.hasQuickAddToolbarTarget = false
      const outside = document.createElement("div")
      km.handleClickOutside(clickEvent(outside))
      expect(ctrl.fieldManager.deselectField).toHaveBeenCalled()
    })

    it.each([
      ["field card", (t) => t.classList.add("field-card")],
      ["move modal content", (t) => t.setAttribute("data-move-modal-content", "")],
    ])("keeps the selection when the click lands inside a %s", (_label, mark) => {
      ctrl.selectionManager.isEmpty = false
      ctrl.propertyManager.isFloatingPanelVisible = vi.fn(() => true)
      const target = document.createElement("div")
      mark(target)
      km.handleClickOutside(clickEvent(target))
      expect(ctrl.fieldManager.deselectField).not.toHaveBeenCalled()
    })

    it.each([
      ["floating panel", "hasFloatingPanelTarget", "floatingPanelTarget"],
      ["toolbar width group", "hasToolbarWidthGroupTarget", "toolbarWidthGroupTarget"],
      ["left sidebar", "hasLeftSidebarTarget", "leftSidebarTarget"],
      ["quick add toolbar", "hasQuickAddToolbarTarget", "quickAddToolbarTarget"],
    ])("keeps the selection when the click lands inside the %s", (_label, hasFlag, targetKey) => {
      ctrl.selectionManager.isEmpty = false
      ctrl.propertyManager.isFloatingPanelVisible = vi.fn(() => true)
      const container = document.createElement("div")
      const inner = document.createElement("span")
      container.appendChild(inner)
      ctrl[hasFlag] = true
      ctrl[targetKey] = container
      km.handleClickOutside(clickEvent(inner))
      expect(ctrl.fieldManager.deselectField).not.toHaveBeenCalled()
    })

    it("does not touch selection when nothing is selected, or the floating panel is hidden", () => {
      ctrl.selectionManager.isEmpty = true
      ctrl.propertyManager.isFloatingPanelVisible = vi.fn(() => true)
      km.handleClickOutside(clickEvent(document.createElement("div")))
      expect(ctrl.fieldManager.deselectField).not.toHaveBeenCalled()

      ctrl.selectionManager.isEmpty = false
      ctrl.propertyManager.isFloatingPanelVisible = vi.fn(() => false)
      km.handleClickOutside(clickEvent(document.createElement("div")))
      expect(ctrl.fieldManager.deselectField).not.toHaveBeenCalled()
    })
  })

  describe("handleKeydown routing", () => {
    it("Ctrl+S triggers save even inside an input", () => {
      km.handleKeydown(keyEvent({ key: "s", ctrlKey: true, target: document.createElement("input") }))
      expect(ctrl.saveManager.save).toHaveBeenCalled()
    })

    it("skips clipboard shortcuts while focus is in an input", () => {
      km.handleKeydown(keyEvent({ key: "c", ctrlKey: true, target: document.createElement("input") }))
      expect(ctrl.clipboardManager.copy).not.toHaveBeenCalled()
    })

    it("routes copy/cut/paste/duplicate to the clipboard manager", () => {
      km.handleKeydown(keyEvent({ key: "c", metaKey: true }))
      km.handleKeydown(keyEvent({ key: "x", metaKey: true }))
      km.handleKeydown(keyEvent({ key: "v", metaKey: true }))
      km.handleKeydown(keyEvent({ key: "d", metaKey: true }))
      expect(ctrl.clipboardManager.copy).toHaveBeenCalled()
      expect(ctrl.clipboardManager.cut).toHaveBeenCalled()
      expect(ctrl.clipboardManager.paste).toHaveBeenCalled()
      expect(ctrl.clipboardManager.duplicateSelected).toHaveBeenCalled()
    })

    it("routes zoom shortcuts", () => {
      km.handleKeydown(keyEvent({ key: "k", ctrlKey: true }))
      km.handleKeydown(keyEvent({ key: "=", ctrlKey: true }))
      km.handleKeydown(keyEvent({ key: "-", ctrlKey: true }))
      km.handleKeydown(keyEvent({ key: "0", ctrlKey: true }))
      expect(ctrl.zoomManager.openSearch).toHaveBeenCalled()
      expect(ctrl.zoomManager.zoomIn).toHaveBeenCalled()
      expect(ctrl.zoomManager.zoomOut).toHaveBeenCalled()
      expect(ctrl.zoomManager.zoomReset).toHaveBeenCalled()
    })

    it("routes undo/redo (Ctrl+Z, Ctrl+Shift+Z, Ctrl+Y)", () => {
      km.handleKeydown(keyEvent({ key: "z", ctrlKey: true }))
      km.handleKeydown(keyEvent({ key: "z", ctrlKey: true, shiftKey: true }))
      km.handleKeydown(keyEvent({ key: "y", ctrlKey: true }))
      expect(ctrl.undoRedoManager.undo).toHaveBeenCalledOnce()
      expect(ctrl.undoRedoManager.redo).toHaveBeenCalledTimes(2)
    })

    it("Ctrl+A selects all", () => {
      km.handleKeydown(keyEvent({ key: "a", ctrlKey: true }))
      expect(ctrl.selectionManager.selectAll).toHaveBeenCalled()
    })

    it("Delete removes the field only when a selection exists", () => {
      ctrl.selectionManager.isEmpty = true
      km.handleKeydown(keyEvent({ key: "Delete" }))
      expect(ctrl.fieldManager.deleteField).not.toHaveBeenCalled()

      ctrl.selectionManager.isEmpty = false
      km.handleKeydown(keyEvent({ key: "Backspace" }))
      expect(ctrl.fieldManager.deleteField).toHaveBeenCalled()
    })

    it("'/' opens the command palette and '?' shows shortcuts", () => {
      km.handleKeydown(keyEvent({ key: "/" }))
      expect(ctrl.commandPaletteManager.open).toHaveBeenCalled()

      const modal = document.createElement("div")
      ctrl.hasShortcutsModalTarget = true
      ctrl.shortcutsModalTarget = modal
      modal.classList.add("hidden")
      km.handleKeydown(keyEvent({ key: "?" }))
      expect(modal.classList.contains("hidden")).toBe(false)
    })

    it("Escape closes the context menu first when open", () => {
      ctrl.hasContextMenuTarget = true
      ctrl.contextMenuTarget = document.createElement("div") // no "hidden" class -> visible
      km.handleKeydown(keyEvent({ key: "Escape" }))
      expect(ctrl.contextMenuManager.close).toHaveBeenCalled()
      expect(ctrl.fieldManager.deselectField).not.toHaveBeenCalled()
    })

    it("Escape closes the command palette when the context menu isn't open", () => {
      ctrl.hasCommandPaletteTarget = true
      ctrl.commandPaletteTarget = document.createElement("div") // visible
      km.handleKeydown(keyEvent({ key: "Escape" }))
      expect(ctrl.commandPaletteManager.close).toHaveBeenCalled()
      expect(ctrl.fieldManager.deselectField).not.toHaveBeenCalled()
    })

    it("Escape closes the move-to-page modal when nothing else takes priority", () => {
      ctrl.hasMoveToPageModalTarget = true
      ctrl.moveToPageModalTarget = document.createElement("div")
      ctrl.moveToPageModalTarget.innerHTML = "<p>Move to…</p>"
      ctrl.selectionManager.closeMoveToPageModal = vi.fn()
      km.handleKeydown(keyEvent({ key: "Escape" }))
      expect(ctrl.selectionManager.closeMoveToPageModal).toHaveBeenCalled()
      expect(ctrl.fieldManager.deselectField).not.toHaveBeenCalled()
    })

    it("Escape closes an active tab panel when nothing else takes priority", () => {
      const panel = document.createElement("div") // visible
      ctrl.tabPanelTargets = [panel]
      km.handleKeydown(keyEvent({ key: "Escape" }))
      expect(ctrl.tabManager.closeAllTabPanels).toHaveBeenCalled()
      expect(ctrl.fieldManager.deselectField).not.toHaveBeenCalled()
    })

    it("Escape closes the inserter popover first when open", () => {
      ctrl.inserterManager.isPopoverOpen.mockReturnValue(true)
      km.handleKeydown(keyEvent({ key: "Escape" }))
      expect(ctrl.inserterManager.closePopover).toHaveBeenCalled()
      expect(ctrl.fieldManager.deselectField).not.toHaveBeenCalled()
    })

    it("Escape with nothing open deselects the field", () => {
      km.handleKeydown(keyEvent({ key: "Escape" }))
      expect(ctrl.fieldManager.deselectField).toHaveBeenCalled()
    })

    it("ArrowDown/ArrowUp navigate fields when a selection exists or the canvas has focus", () => {
      ctrl.fields = [field({ id: "a" }), field({ id: "b" })]
      ctrl.hasFieldsContainerTarget = true
      ctrl.fieldsContainerTarget = document.createElement("div")
      ctrl.selectionManager.isEmpty = false
      ctrl.selectionManager.lastSelectedFieldId = "a"
      ctrl.selectionManager.selectedFieldIds = new Set(["a"])
      km.handleKeydown(keyEvent({ key: "ArrowDown" }))
      expect(ctrl.fieldManager.selectFieldById).toHaveBeenCalledWith("b")
    })

    it("ArrowUp navigates to the previous field (the `-1` side of the direction ternary)", () => {
      ctrl.fields = [field({ id: "a" }), field({ id: "b" })]
      ctrl.hasFieldsContainerTarget = true
      ctrl.fieldsContainerTarget = document.createElement("div")
      ctrl.selectionManager.isEmpty = false
      ctrl.selectionManager.lastSelectedFieldId = "b"
      ctrl.selectionManager.selectedFieldIds = new Set(["b"])
      km.handleKeydown(keyEvent({ key: "ArrowUp" }))
      expect(ctrl.fieldManager.selectFieldById).toHaveBeenCalledWith("a")
    })

    it("ArrowDown/ArrowUp are ignored when there is no selection and the canvas isn't focused", () => {
      ctrl.selectionManager.isEmpty = true
      ctrl.hasCanvasAreaTarget = false
      km.handleKeydown(keyEvent({ key: "ArrowDown" }))
      expect(ctrl.fieldManager.selectFieldById).not.toHaveBeenCalled()
    })

    it("ArrowDown navigates when the canvas area itself has focus even with no selection", () => {
      ctrl.fields = [field({ id: "a" })]
      ctrl.hasFieldsContainerTarget = true
      ctrl.fieldsContainerTarget = document.createElement("div")
      ctrl.selectionManager.isEmpty = true
      const canvas = document.createElement("div")
      document.body.appendChild(canvas)
      canvas.tabIndex = 0
      canvas.focus()
      ctrl.hasCanvasAreaTarget = true
      ctrl.canvasAreaTarget = canvas
      km.handleKeydown(keyEvent({ key: "ArrowDown" }))
      expect(ctrl.fieldManager.selectFieldById).toHaveBeenCalledWith("a")
      canvas.remove()
    })
  })

  describe("showShortcuts / hideShortcuts", () => {
    it("does nothing when there is no shortcuts modal target", () => {
      ctrl.hasShortcutsModalTarget = false
      expect(() => km.showShortcuts()).not.toThrow()
      expect(() => km.hideShortcuts()).not.toThrow()
    })

    it("shows and hides the shortcuts modal", () => {
      ctrl.hasShortcutsModalTarget = true
      ctrl.shortcutsModalTarget = document.createElement("div")
      ctrl.shortcutsModalTarget.classList.add("hidden")
      km.showShortcuts()
      expect(ctrl.shortcutsModalTarget.classList.contains("hidden")).toBe(false)
      km.hideShortcuts()
      expect(ctrl.shortcutsModalTarget.classList.contains("hidden")).toBe(true)
    })
  })

  describe("navigateFields", () => {
    beforeEach(() => {
      ctrl.fields = [field({ id: "a" }), field({ id: "b" }), field({ id: "c" })]
      ctrl.hasFieldsContainerTarget = true
      ctrl.fieldsContainerTarget = document.createElement("div")
    })

    it("selects the first field when nothing is selected and moving down", () => {
      ctrl.selectionManager.isEmpty = true
      km.navigateFields(1)
      expect(ctrl.fieldManager.selectFieldById).toHaveBeenCalledWith("a")
    })

    it("selects the last field when nothing is selected and moving up", () => {
      ctrl.selectionManager.isEmpty = true
      km.navigateFields(-1)
      expect(ctrl.fieldManager.selectFieldById).toHaveBeenCalledWith("c")
    })

    it("moves to the next field relative to the anchor", () => {
      ctrl.selectionManager.isEmpty = false
      ctrl.selectionManager.lastSelectedFieldId = "a"
      ctrl.selectionManager.selectedFieldIds = new Set(["a"])
      km.navigateFields(1)
      expect(ctrl.fieldManager.selectFieldById).toHaveBeenCalledWith("b")
    })

    it("does nothing past the last field", () => {
      ctrl.selectionManager.isEmpty = false
      ctrl.selectionManager.lastSelectedFieldId = "c"
      ctrl.selectionManager.selectedFieldIds = new Set(["c"])
      km.navigateFields(1)
      expect(ctrl.fieldManager.selectFieldById).not.toHaveBeenCalled()
    })

    it("does nothing when there are no fields at all", () => {
      ctrl.fields = []
      km.navigateFields(1)
      expect(ctrl.fieldManager.selectFieldById).not.toHaveBeenCalled()
    })

    it("falls back to the first selected field id as the anchor when lastSelectedFieldId is unset", () => {
      ctrl.selectionManager.isEmpty = false
      ctrl.selectionManager.lastSelectedFieldId = null
      ctrl.selectionManager.selectedFieldIds = new Set(["b"])
      km.navigateFields(1)
      expect(ctrl.fieldManager.selectFieldById).toHaveBeenCalledWith("c")
    })

    it("scrolls the newly-selected card into view when it is rendered", () => {
      ctrl.selectionManager.isEmpty = false
      ctrl.selectionManager.lastSelectedFieldId = "a"
      ctrl.selectionManager.selectedFieldIds = new Set(["a"])
      const card = document.createElement("div")
      card.dataset.fieldId = "b"
      const scrollSpy = vi.fn()
      card.scrollIntoView = scrollSpy
      ctrl.fieldsContainerTarget.appendChild(card)
      km.navigateFields(1)
      expect(scrollSpy).toHaveBeenCalledWith({ behavior: "smooth", block: "nearest" })
    })
  })

  describe("_isInInput", () => {
    it("recognizes form fields and contenteditable", () => {
      expect(km._isInInput({ target: document.createElement("input") })).toBe(true)
      expect(km._isInInput({ target: document.createElement("textarea") })).toBe(true)
      expect(km._isInInput({ target: document.createElement("select") })).toBe(true)
      const div = document.createElement("div")
      expect(km._isInInput({ target: div })).toBe(false)
      // contenteditable path: happy-dom's isContentEditable is read-only, so
      // assert against a plain target carrying the flag (matches the runtime shape).
      expect(km._isInInput({ target: { tagName: "DIV", isContentEditable: true } })).toBe(true)
    })
  })
})
