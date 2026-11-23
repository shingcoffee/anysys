import { describe, it, expect, vi, beforeEach } from "vitest"
import { ContextMenuManager } from "controllers/page_builder/context_menu_manager"
import { makeCtrl, field } from "../../support/page_builder.js"

const withMenu = (ctrl) => {
  ctrl.hasContextMenuTarget = true
  ctrl.contextMenuTarget = document.createElement("div")
  ctrl.hasContextMenuContentTarget = true
  ctrl.contextMenuContentTarget = document.createElement("div")
  return ctrl
}
const labelsOf = (items) => items.filter((i) => i.label).map((i) => i.label)

describe("ContextMenuManager._fieldMenuItems", () => {
  let ctrl, cm
  beforeEach(() => {
    ctrl = makeCtrl()
    cm = new ContextMenuManager(ctrl)
  })

  it("lists the standard field actions with a disabled Paste when the clipboard is empty", () => {
    const items = cm._fieldMenuItems(field({ id: "a" }))
    expect(labelsOf(items)).toEqual(
      expect.arrayContaining(["Edit Label", "Duplicate", "Copy", "Cut", "Paste After", "Width", "Save as Template", "Delete"])
    )
    const paste = items.find((i) => i.label === "Paste After")
    expect(paste.disabled).toBe(true)
  })

  it("enables Paste After when the clipboard has content", () => {
    ctrl.clipboardManager.clipboard = [field({ id: "x" })]
    const items = cm._fieldMenuItems(field({ id: "a" }))
    const paste = items.find((i) => i.label === "Paste After")
    expect(paste.disabled).toBeUndefined()
    expect(typeof paste.action).toBe("function")
  })

  it("adds an Ungroup entry for field groups", () => {
    const items = cm._fieldMenuItems(field({ id: "g", type: "field_group" }))
    expect(labelsOf(items)).toContain("Ungroup")
  })

  it("offers a Width submenu with six presets", () => {
    const items = cm._fieldMenuItems(field({ id: "a" }))
    const width = items.find((i) => i.label === "Width")
    expect(width.submenu.map((s) => s.label)).toEqual(["Full", "3/4", "2/3", "Half", "1/3", "1/4"])
  })
})

describe("ContextMenuManager._setWidth", () => {
  it("writes the desktop width explicitly on the desktop viewport", () => {
    const ctrl = makeCtrl()
    withMenu(ctrl)
    ctrl.viewportValue = "desktop"
    const cm = new ContextMenuManager(ctrl)
    const f = field({ id: "a" })
    cm._setWidth(f, "half")
    expect(f.width).toBe("half")
    expect(f.width_explicit).toBe(true)
    expect(ctrl.saveState).toHaveBeenCalled()
    expect(ctrl.fieldManager.renderFields).toHaveBeenCalled()
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
  })

  it("writes a per-breakpoint override on a non-desktop viewport", () => {
    const ctrl = makeCtrl()
    withMenu(ctrl)
    ctrl.viewportValue = "mobile"
    const cm = new ContextMenuManager(ctrl)
    const f = field({ id: "a", width: "full" })
    cm._setWidth(f, "third")
    expect(f.width).toBe("full") // untouched
    expect(f.responsive_widths).toEqual({ mobile: "third" })
  })

  it("defaults to the desktop viewport when viewportValue is unset", () => {
    const ctrl = makeCtrl()
    withMenu(ctrl)
    ctrl.viewportValue = undefined
    const cm = new ContextMenuManager(ctrl)
    const f = field({ id: "a" })
    cm._setWidth(f, "half")
    expect(f.width).toBe("half")
    expect(f.width_explicit).toBe(true)
  })
})

describe("ContextMenuManager.openForCanvas", () => {
  it("offers a disabled Paste with no clipboard, plus Add Field and Select All", () => {
    const ctrl = makeCtrl()
    const cm = new ContextMenuManager(ctrl)
    const showSpy = vi.spyOn(cm, "_show").mockImplementation(() => {})
    const event = {
      preventDefault: vi.fn(),
      clientX: 10, clientY: 20,
      target: { closest: () => null }, // not over a field card
    }
    cm.openForCanvas(event)
    expect(event.preventDefault).toHaveBeenCalled()
    const items = showSpy.mock.calls[0][2]
    expect(labelsOf(items)).toEqual(["Paste", "Add Field", "Select All"])
    expect(items.find((i) => i.label === "Paste").disabled).toBe(true)
  })

  it("bails out when the right-click lands on a field card", () => {
    const ctrl = makeCtrl()
    const cm = new ContextMenuManager(ctrl)
    const showSpy = vi.spyOn(cm, "_show")
    cm.openForCanvas({ preventDefault: vi.fn(), target: { closest: () => ({}) } })
    expect(showSpy).not.toHaveBeenCalled()
  })
})

describe("ContextMenuManager.openForField", () => {
  it("selects the field (if needed) and shows its menu", () => {
    const card = document.createElement("div")
    card.dataset.fieldId = "a"
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a" })] } })
    ctrl.selectionManager.isSelected.mockReturnValue(false)
    const cm = new ContextMenuManager(ctrl)
    const showSpy = vi.spyOn(cm, "_show").mockImplementation(() => {})
    cm.openForField({
      preventDefault: vi.fn(), stopPropagation: vi.fn(),
      clientX: 5, clientY: 6, currentTarget: card,
    })
    expect(ctrl.selectionManager.selectField).toHaveBeenCalledWith("a", { shift: false, meta: false })
    expect(showSpy).toHaveBeenCalled()
  })

  it("bails out when the right-click target isn't inside a field card", () => {
    const ctrl = makeCtrl()
    const cm = new ContextMenuManager(ctrl)
    const showSpy = vi.spyOn(cm, "_show")
    cm.openForField({
      preventDefault: vi.fn(), stopPropagation: vi.fn(),
      currentTarget: { closest: () => null },
    })
    expect(showSpy).not.toHaveBeenCalled()
  })

  it("bails out when the field can't be found in allFields", () => {
    const card = document.createElement("div")
    card.dataset.fieldId = "missing"
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a" })] } })
    const cm = new ContextMenuManager(ctrl)
    const showSpy = vi.spyOn(cm, "_show")
    cm.openForField({
      preventDefault: vi.fn(), stopPropagation: vi.fn(),
      currentTarget: card,
    })
    expect(showSpy).not.toHaveBeenCalled()
  })

  it("skips re-selecting a field that is already selected", () => {
    const card = document.createElement("div")
    card.dataset.fieldId = "a"
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a" })] } })
    ctrl.selectionManager.isSelected.mockReturnValue(true)
    const cm = new ContextMenuManager(ctrl)
    vi.spyOn(cm, "_show").mockImplementation(() => {})
    cm.openForField({
      preventDefault: vi.fn(), stopPropagation: vi.fn(),
      clientX: 1, clientY: 1, currentTarget: card,
    })
    expect(ctrl.selectionManager.selectField).not.toHaveBeenCalled()
  })
})

describe("ContextMenuManager._show / close", () => {
  it("renders menu items into the content target and reveals the menu", () => {
    const ctrl = withMenu(makeCtrl())
    const cm = new ContextMenuManager(ctrl)
    cm._show(10, 10, [
      { label: "Copy", action: vi.fn() },
      { type: "divider" },
      { label: "Delete", danger: true, action: vi.fn() },
    ])
    expect(ctrl.contextMenuContentTarget.innerHTML).toContain("Copy")
    expect(ctrl.contextMenuContentTarget.querySelector("hr")).not.toBeNull()
    expect(ctrl.contextMenuTarget.classList.contains("hidden")).toBe(false)
  })

  it("clicking a rendered item fires its action and closes", () => {
    const ctrl = withMenu(makeCtrl())
    const cm = new ContextMenuManager(ctrl)
    const action = vi.fn()
    cm._show(0, 0, [{ label: "Copy", action }])
    ctrl.contextMenuContentTarget.querySelector("[data-context-action]").dispatchEvent(new Event("click", { bubbles: true }))
    expect(action).toHaveBeenCalled()
    expect(ctrl.contextMenuTarget.classList.contains("hidden")).toBe(true)
  })

  it("close hides the menu", () => {
    const ctrl = withMenu(makeCtrl())
    const cm = new ContextMenuManager(ctrl)
    cm.close()
    expect(ctrl.contextMenuTarget.classList.contains("hidden")).toBe(true)
  })

  it("bails out when neither the menu nor its content target exists", () => {
    const ctrl = makeCtrl() // hasContextMenuTarget/hasContextMenuContentTarget are undefined
    const cm = new ContextMenuManager(ctrl)
    expect(() => cm._show(0, 0, [{ label: "Copy", action: vi.fn() }])).not.toThrow()
  })

  it("bails out when the menu exists but the content target doesn't", () => {
    const ctrl = makeCtrl()
    ctrl.hasContextMenuTarget = true
    ctrl.contextMenuTarget = document.createElement("div")
    ctrl.hasContextMenuContentTarget = false
    const cm = new ContextMenuManager(ctrl)
    expect(() => cm._show(0, 0, [{ label: "Copy", action: vi.fn() }])).not.toThrow()
    expect(ctrl.contextMenuTarget.classList.contains("hidden")).toBe(false)
  })

  it("renders items and disabled entries without a shortcut", () => {
    const ctrl = withMenu(makeCtrl())
    const cm = new ContextMenuManager(ctrl)
    cm._show(0, 0, [
      { label: "Paste", disabled: true },
      { label: "Copy", action: vi.fn() },
    ])
    const html = ctrl.contextMenuContentTarget.innerHTML
    expect(html).toContain("Paste")
    expect(html).toContain("Copy")
  })

  it("renders an enabled item's shortcut", () => {
    const ctrl = withMenu(makeCtrl())
    const cm = new ContextMenuManager(ctrl)
    cm._show(0, 0, [{ label: "Duplicate", shortcut: "Ctrl+D", action: vi.fn() }])
    expect(ctrl.contextMenuContentTarget.innerHTML).toContain("Ctrl+D")
  })

  it("renders a disabled item's shortcut and a submenu with its entries", () => {
    const ctrl = withMenu(makeCtrl())
    const cm = new ContextMenuManager(ctrl)
    const sub = vi.fn()
    cm._show(0, 0, [
      { label: "Paste", shortcut: "Ctrl+V", disabled: true },
      { label: "Width", submenu: [{ label: "Full", action: sub }, { label: "Half", action: vi.fn() }] },
    ])
    const html = ctrl.contextMenuContentTarget.innerHTML
    expect(html).toContain("Paste")
    expect(html).toContain("Ctrl+V")
    expect(html).toContain("cursor-not-allowed")
    expect(html).toContain("Full")
    expect(html).toContain("Half")
    expect(ctrl.contextMenuContentTarget.querySelector('[data-context-action="1_0"]')).not.toBeNull()
  })

  it("clicking a submenu entry fires that entry's action and closes", () => {
    const ctrl = withMenu(makeCtrl())
    const cm = new ContextMenuManager(ctrl)
    const subAction = vi.fn()
    cm._show(0, 0, [
      { label: "Width", submenu: [{ label: "Full", action: subAction }] },
    ])
    ctrl.contextMenuContentTarget
      .querySelector('[data-context-action="0_0"]')
      .dispatchEvent(new Event("click", { bubbles: true }))
    expect(subAction).toHaveBeenCalled()
    expect(ctrl.contextMenuTarget.classList.contains("hidden")).toBe(true)
  })
})

describe("ContextMenuManager._onClickOutside", () => {
  it("closes the menu when the click lands outside the context menu", () => {
    const ctrl = withMenu(makeCtrl())
    const cm = new ContextMenuManager(ctrl)
    const closeSpy = vi.spyOn(cm, "close")
    cm._onClickOutside({ target: { closest: () => null } })
    expect(closeSpy).toHaveBeenCalled()
  })

  it("leaves the menu open when the click lands inside the context menu", () => {
    const ctrl = withMenu(makeCtrl())
    const cm = new ContextMenuManager(ctrl)
    const closeSpy = vi.spyOn(cm, "close")
    cm._onClickOutside({ target: { closest: () => document.createElement("div") } })
    expect(closeSpy).not.toHaveBeenCalled()
  })
})

describe("ContextMenuManager._triggerInlineEdit", () => {
  it("closes the menu and dispatches a dblclick on the field's inline-editable property", () => {
    const ctrl = withMenu(makeCtrl())
    const cm = new ContextMenuManager(ctrl)
    const card = document.createElement("div")
    card.dataset.fieldId = "a"
    const editable = document.createElement("span")
    editable.dataset.inlineEditProperty = "label"
    card.appendChild(editable)
    const container = document.createElement("div")
    container.appendChild(card)
    ctrl.fieldsContainerTarget = container
    const dblclickSpy = vi.fn()
    editable.addEventListener("dblclick", dblclickSpy)

    cm._triggerInlineEdit(field({ id: "a" }))

    expect(ctrl.contextMenuTarget.classList.contains("hidden")).toBe(true)
    expect(dblclickSpy).toHaveBeenCalled()
  })

  it("does nothing when the field card has no inline-editable property", () => {
    const ctrl = withMenu(makeCtrl())
    const cm = new ContextMenuManager(ctrl)
    const card = document.createElement("div")
    card.dataset.fieldId = "a"
    const container = document.createElement("div")
    container.appendChild(card)
    ctrl.fieldsContainerTarget = container

    expect(() => cm._triggerInlineEdit(field({ id: "a" }))).not.toThrow()
  })

  it("does nothing when the field card is not found", () => {
    const ctrl = withMenu(makeCtrl())
    const cm = new ContextMenuManager(ctrl)
    ctrl.fieldsContainerTarget = document.createElement("div")

    expect(() => cm._triggerInlineEdit(field({ id: "missing" }))).not.toThrow()
  })
})

describe("ContextMenuManager _fieldMenuItems action closures", () => {
  it("invokes every non-group field action with the expected side effect", () => {
    const ctrl = makeCtrl()
    const cm = new ContextMenuManager(ctrl)
    const setWidthSpy = vi.spyOn(cm, "_setWidth").mockImplementation(() => {})
    const triggerInlineEditSpy = vi.spyOn(cm, "_triggerInlineEdit").mockImplementation(() => {})
    ctrl.clipboardManager.clipboard = [field({ id: "x" })]
    const f = field({ id: "a" })
    const items = cm._fieldMenuItems(f)

    items.find((i) => i.label === "Edit Label").action()
    expect(triggerInlineEditSpy).toHaveBeenCalledWith(f)

    items.find((i) => i.label === "Duplicate").action()
    expect(ctrl.clipboardManager.duplicateSelected).toHaveBeenCalled()

    items.find((i) => i.label === "Copy").action()
    expect(ctrl.clipboardManager.copy).toHaveBeenCalled()

    items.find((i) => i.label === "Cut").action()
    expect(ctrl.clipboardManager.cut).toHaveBeenCalled()

    items.find((i) => i.label === "Paste After").action()
    expect(ctrl.clipboardManager.paste).toHaveBeenCalled()

    const width = items.find((i) => i.label === "Width")
    const expectedWidths = ["full", "three_quarters", "two_thirds", "half", "third", "quarter"]
    width.submenu.forEach((sub, idx) => {
      sub.action()
      expect(setWidthSpy).toHaveBeenNthCalledWith(idx + 1, f, expectedWidths[idx])
    })

    items.find((i) => i.label === "Save as Template").action()
    expect(ctrl.fieldManager.saveFieldAsTemplate).toHaveBeenCalledWith(
      expect.objectContaining({ currentTarget: { dataset: { fieldId: "a" } } })
    )
    // The action builds a fake event with a no-op stopPropagation; exercise it too.
    expect(() =>
      ctrl.fieldManager.saveFieldAsTemplate.mock.calls[0][0].stopPropagation()
    ).not.toThrow()

    items.find((i) => i.label === "Delete").action()
    expect(ctrl.fieldManager.deleteField).toHaveBeenCalled()
  })

  it("invokes the Ungroup action for a field group", () => {
    const ctrl = makeCtrl()
    const cm = new ContextMenuManager(ctrl)
    const items = cm._fieldMenuItems(field({ id: "g", type: "field_group" }))
    items.find((i) => i.label === "Ungroup").action()
    expect(ctrl.fieldManager.ungroupFields).toHaveBeenCalledWith(
      expect.objectContaining({ currentTarget: { dataset: { groupId: "g" } } })
    )
    expect(() =>
      ctrl.fieldManager.ungroupFields.mock.calls[0][0].stopPropagation()
    ).not.toThrow()
  })
})

describe("ContextMenuManager.openForCanvas action closures", () => {
  it("invokes Paste, Add Field, and Select All", () => {
    const ctrl = makeCtrl()
    ctrl.clipboardManager.clipboard = [field({ id: "x" })]
    const cm = new ContextMenuManager(ctrl)
    const showSpy = vi.spyOn(cm, "_show").mockImplementation(() => {})
    cm.openForCanvas({ preventDefault: vi.fn(), clientX: 1, clientY: 1, target: { closest: () => null } })
    const items = showSpy.mock.calls[0][2]

    items.find((i) => i.label === "Paste").action()
    expect(ctrl.clipboardManager.paste).toHaveBeenCalled()

    items.find((i) => i.label === "Add Field").action()
    expect(ctrl.commandPaletteManager.open).toHaveBeenCalled()

    items.find((i) => i.label === "Select All").action()
    expect(ctrl.selectionManager.selectAll).toHaveBeenCalled()
  })
})
