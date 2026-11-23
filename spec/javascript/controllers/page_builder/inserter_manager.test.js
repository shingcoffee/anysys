// NOTE: _showPopover's viewport-clamping math reads getBoundingClientRect (zeroed in
// happy-dom) — the *positioning* is Playwright's job. The structural behaviour it drives
// (building the catalog, toggling .hidden, tracking the insert index) is unit-tested here.
import { describe, it, expect, beforeEach, vi } from "vitest"
import { InserterManager, COMPONENT_CATALOG } from "controllers/page_builder/inserter_manager"
import { makeCtrl, field } from "../../support/page_builder.js"

function popoverCtrl(overrides = {}) {
  const popover = document.createElement("div")
  popover.classList.add("hidden")
  const content = document.createElement("div")
  const search = document.createElement("input")
  return makeCtrl({
    hasInserterPopoverTarget: true,
    inserterPopoverTarget: popover,
    hasInserterPopoverContentTarget: true,
    inserterPopoverContentTarget: content,
    hasInserterPopoverSearchTarget: true,
    inserterPopoverSearchTarget: search,
    ...overrides,
  })
}

describe("COMPONENT_CATALOG", () => {
  it("groups items with a category, color, and non-empty items list", () => {
    expect(COMPONENT_CATALOG.length).toBeGreaterThan(0)
    COMPONENT_CATALOG.forEach((group) => {
      expect(group.category).toBeTruthy()
      expect(group.color).toBeTruthy()
      expect(Array.isArray(group.items)).toBe(true)
      group.items.forEach((item) => {
        expect(item.type).toBeTruthy()
        expect(item.label).toBeTruthy()
        expect(item.icon).toBeTruthy()
      })
    })
  })
})

describe("InserterManager", () => {
  let ctrl, im
  beforeEach(() => {
    ctrl = popoverCtrl()
    im = new InserterManager(ctrl)
  })

  describe("openPopover", () => {
    it("reads the insert index from the button and reveals the popover", () => {
      const button = document.createElement("button")
      button.dataset.insertIndex = "2"
      im.openPopover({ currentTarget: button, stopPropagation() {} })
      expect(im._currentInsertIndex).toBe(2)
      expect(ctrl.inserterPopoverTarget.classList.contains("hidden")).toBe(false)
      expect(ctrl.inserterPopoverContentTarget.innerHTML).toContain("data-component-type")
    })

    it("falls back to the end of the field list for a NaN index", () => {
      ctrl.fields = [field(), field()]
      const button = document.createElement("button")
      im.openPopover({ currentTarget: button, stopPropagation() {} })
      expect(im._currentInsertIndex).toBe(2)
    })
  })

  describe("_showPopover", () => {
    it("no-ops when there is no popover target", () => {
      ctrl = popoverCtrl({ hasInserterPopoverTarget: false })
      im = new InserterManager(ctrl)
      const button = document.createElement("button")
      expect(() => im.openPopover({ currentTarget: button, stopPropagation() {} })).not.toThrow()
      expect(ctrl.inserterPopoverContentTarget.innerHTML).toBe("")
    })

    it("clamps left/top when the popover would overflow the viewport", () => {
      const anchor = document.createElement("button")
      Object.defineProperty(anchor, "getBoundingClientRect", {
        value: () => ({ top: 10, bottom: 20, left: 990, right: 1000, width: 10, height: 10 }),
      })
      Object.defineProperty(ctrl.inserterPopoverTarget, "getBoundingClientRect", {
        value: () => ({ top: 0, bottom: 0, left: 0, right: 0, width: 300, height: 900 }),
      })
      vi.stubGlobal("innerWidth", 1000)
      vi.stubGlobal("innerHeight", 500)
      im._showPopover(anchor)
      // left overflowed the right edge -> clamped to innerWidth - popoverWidth - 8
      expect(ctrl.inserterPopoverTarget.style.left).toBe("692px")
      // top + popoverHeight overflowed innerHeight -> flipped above the anchor
      expect(ctrl.inserterPopoverTarget.style.top).toBe("-898px")
      vi.unstubAllGlobals()
    })
  })

  describe("openFullCatalog", () => {
    it("inserts after the selected field", () => {
      ctrl.fields = [field({ id: "a" }), field({ id: "b" })]
      ctrl.selectedFieldId = "a"
      im.openFullCatalog({ currentTarget: document.createElement("button"), stopPropagation() {} })
      expect(im._currentInsertIndex).toBe(1)
    })

    it("inserts at the end when nothing is selected", () => {
      ctrl.fields = [field(), field()]
      ctrl.selectedFieldId = null
      im.openFullCatalog({ currentTarget: document.createElement("button"), stopPropagation() {} })
      expect(im._currentInsertIndex).toBe(2)
    })
  })

  describe("closePopover / isPopoverOpen", () => {
    it("hides the popover and clears the index", () => {
      im._currentInsertIndex = 3
      ctrl.inserterPopoverTarget.classList.remove("hidden")
      im.closePopover()
      expect(ctrl.inserterPopoverTarget.classList.contains("hidden")).toBe(true)
      expect(im._currentInsertIndex).toBeNull()
    })

    it("reports open state from the hidden class", () => {
      expect(im.isPopoverOpen()).toBe(false)
      ctrl.inserterPopoverTarget.classList.remove("hidden")
      expect(im.isPopoverOpen()).toBe(true)
    })

    it("closePopover no-ops when there is no popover target", () => {
      ctrl.hasInserterPopoverTarget = false
      im._currentInsertIndex = 3
      expect(() => im.closePopover()).not.toThrow()
      expect(im._currentInsertIndex).toBe(3) // untouched — the guard returned early
    })
  })

  describe("filterPopover", () => {
    it("hides non-matching items and empties out their category", () => {
      ctrl.inserterPopoverContentTarget.innerHTML = `
        <div data-catalog-category="Structure">
          <button data-component-type="section" data-component-label="Section"></button>
          <button data-component-type="card" data-component-label="Card"></button>
        </div>`
      im.filterPopover({ target: { value: "sect" } })
      const items = ctrl.inserterPopoverContentTarget.querySelectorAll("[data-component-type]")
      expect(items[0].classList.contains("hidden")).toBe(false) // section matches
      expect(items[1].classList.contains("hidden")).toBe(true)  // card hidden
      const cat = ctrl.inserterPopoverContentTarget.querySelector("[data-catalog-category]")
      expect(cat.classList.contains("hidden")).toBe(false) // still has a visible item
    })

    it("hides a category whose items all vanish", () => {
      ctrl.inserterPopoverContentTarget.innerHTML = `
        <div data-catalog-category="Structure">
          <button data-component-type="section" data-component-label="Section"></button>
        </div>`
      im.filterPopover({ target: { value: "zzz" } })
      const cat = ctrl.inserterPopoverContentTarget.querySelector("[data-catalog-category]")
      expect(cat.classList.contains("hidden")).toBe(true)
    })

    it("no-ops when there is no popover content target", () => {
      ctrl.hasInserterPopoverContentTarget = false
      expect(() => im.filterPopover({ target: { value: "x" } })).not.toThrow()
    })

    it("treats items missing label/type datasets as empty strings rather than matching", () => {
      ctrl.inserterPopoverContentTarget.innerHTML =
        `<button data-component-type="section"></button>`
      const item = ctrl.inserterPopoverContentTarget.querySelector("[data-component-type]")
      // strip the type dataset too, so both `|| ""` fallbacks are exercised
      delete item.dataset.componentType
      item.setAttribute("data-component-type", "") // keep the selector matching
      im.filterPopover({ target: { value: "sect" } })
      expect(item.classList.contains("hidden")).toBe(true)
    })
  })

  describe("insertFromPopover", () => {
    it("adds a field at the tracked index and closes the popover", () => {
      im._currentInsertIndex = 1
      const el = document.createElement("button")
      el.dataset.componentType = "heading"
      el.dataset.componentLabel = "Heading"
      im.insertFromPopover({ currentTarget: el, stopPropagation() {} })
      expect(ctrl.fieldManager.addFieldAtIndex).toHaveBeenCalledWith(
        expect.objectContaining({ type: "heading", label: "Heading", propertyType: "layout" }),
        1,
      )
      expect(ctrl.inserterPopoverTarget.classList.contains("hidden")).toBe(true)
    })

    it("ignores an element without a component type", () => {
      im.insertFromPopover({ currentTarget: document.createElement("button"), stopPropagation() {} })
      expect(ctrl.fieldManager.addFieldAtIndex).not.toHaveBeenCalled()
    })

    it("leaves propertyType undefined for a non-layout component type", () => {
      const el = document.createElement("button")
      el.dataset.componentType = "entity"
      el.dataset.componentLabel = "Entity"
      im.insertFromPopover({ currentTarget: el, stopPropagation() {} })
      expect(ctrl.fieldManager.addFieldAtIndex).toHaveBeenCalledWith(
        expect.objectContaining({ type: "entity", propertyType: undefined }),
        expect.any(Number),
      )
    })

    it("falls back to the end of the field list when no insert index was tracked", () => {
      ctrl.fields = [field(), field(), field()]
      im._currentInsertIndex = null
      const el = document.createElement("button")
      el.dataset.componentType = "heading"
      el.dataset.componentLabel = "Heading"
      im.insertFromPopover({ currentTarget: el, stopPropagation() {} })
      expect(ctrl.fieldManager.addFieldAtIndex).toHaveBeenCalledWith(expect.anything(), 3)
    })
  })

  describe("insertFromToolbar", () => {
    it("inserts after the selected field", () => {
      ctrl.fields = [field({ id: "a" }), field({ id: "b" })]
      ctrl.selectedFieldId = "a"
      const el = document.createElement("button")
      el.dataset.componentType = "divider"
      el.dataset.componentLabel = "Divider"
      im.insertFromToolbar({ currentTarget: el, stopPropagation() {} })
      expect(ctrl.fieldManager.addFieldAtIndex).toHaveBeenCalledWith(
        expect.objectContaining({ type: "divider" }),
        1,
      )
    })

    it("inserts at the end when nothing is selected", () => {
      ctrl.fields = [field(), field()]
      ctrl.selectedFieldId = null
      const el = document.createElement("button")
      el.dataset.componentType = "divider"
      el.dataset.componentLabel = "Divider"
      im.insertFromToolbar({ currentTarget: el, stopPropagation() {} })
      expect(ctrl.fieldManager.addFieldAtIndex).toHaveBeenCalledWith(expect.anything(), 2)
    })

    it("leaves propertyType undefined for a non-layout component type", () => {
      const el = document.createElement("button")
      el.dataset.componentType = "entity"
      el.dataset.componentLabel = "Entity"
      im.insertFromToolbar({ currentTarget: el, stopPropagation() {} })
      expect(ctrl.fieldManager.addFieldAtIndex).toHaveBeenCalledWith(
        expect.objectContaining({ type: "entity", propertyType: undefined }),
        expect.any(Number),
      )
    })

    it("ignores an element without a component type", () => {
      im.insertFromToolbar({ currentTarget: document.createElement("button"), stopPropagation() {} })
      expect(ctrl.fieldManager.addFieldAtIndex).not.toHaveBeenCalled()
    })
  })

  describe("_isLayoutType", () => {
    it("recognizes catalog layout types and rejects data types", () => {
      expect(im._isLayoutType("section")).toBe(true)
      expect(im._isLayoutType("columns")).toBe(true)
      expect(im._isLayoutType("entity")).toBe(false)
    })
  })

  describe("_buildCatalogHtml", () => {
    it("renders every catalog item as an insert button", () => {
      const html = im._buildCatalogHtml()
      const totalItems = COMPONENT_CATALOG.reduce((n, g) => n + g.items.length, 0)
      const matches = html.match(/data-component-type=/g) || []
      expect(matches.length).toBe(totalItems)
    })

    it("falls back to the indigo color set for an unrecognized group color", () => {
      const fakeGroup = { category: "Fake", color: "not-a-real-color", items: [{ type: "x", label: "X", icon: "i" }] }
      COMPONENT_CATALOG.push(fakeGroup)
      try {
        const html = im._buildCatalogHtml()
        expect(html).toContain("text-indigo-600")
      } finally {
        COMPONENT_CATALOG.pop()
      }
    })
  })
})
