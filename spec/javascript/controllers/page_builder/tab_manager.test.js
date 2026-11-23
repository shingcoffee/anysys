import { describe, it, expect, beforeEach, vi, afterEach } from "vitest"
import { TabManager } from "controllers/page_builder/tab_manager"
import { makeCtrl } from "../../support/page_builder.js"

function tabButton(tab, active = false) {
  const b = document.createElement("button")
  b.dataset.tab = tab
  if (active) b.classList.add("bg-white", "text-gray-900", "shadow-sm")
  else b.classList.add("text-gray-500")
  return b
}
function tabPanel(tab, hidden = true) {
  const p = document.createElement("div")
  p.dataset.tabPanel = tab
  if (hidden) p.classList.add("hidden")
  return p
}

describe("TabManager", () => {
  let ctrl, tm, element
  beforeEach(() => {
    element = document.createElement("div")
    document.body.appendChild(element)
    ctrl = makeCtrl({ element })
    ctrl.fieldManager.updateSidebarFieldStates = vi.fn()
    tm = new TabManager(ctrl)
  })
  afterEach(() => { document.body.innerHTML = "" })

  describe("switchTab", () => {
    it("activates the clicked (inactive) tab and shows its panel, hiding others", () => {
      const btnA = tabButton("a"), btnB = tabButton("b")
      const panelA = tabPanel("a"), panelB = tabPanel("b", false)
      ctrl.tabButtonTargets = [btnA, btnB]
      ctrl.tabPanelTargets = [panelA, panelB]
      tm.switchTab({ currentTarget: btnA })
      expect(btnA.classList.contains("bg-white")).toBe(true)
      expect(btnA.getAttribute("aria-selected")).toBe("true")
      expect(panelA.classList.contains("hidden")).toBe(false)
      expect(panelB.classList.contains("hidden")).toBe(true)
    })

    it("toggles a currently-active tab back off", () => {
      const btnA = tabButton("a", true)
      const panelA = tabPanel("a", false)
      ctrl.tabButtonTargets = [btnA]
      ctrl.tabPanelTargets = [panelA]
      tm.switchTab({ currentTarget: btnA })
      expect(btnA.classList.contains("bg-white")).toBe(false)
      expect(panelA.classList.contains("hidden")).toBe(true)
      expect(btnA.getAttribute("aria-selected")).toBe("false")
    })
  })

  describe("closeAllTabPanels", () => {
    it("deactivates every button and hides every panel", () => {
      const btnA = tabButton("a", true)
      const panelA = tabPanel("a", false)
      ctrl.tabButtonTargets = [btnA]
      ctrl.tabPanelTargets = [panelA]
      tm.closeAllTabPanels()
      expect(btnA.classList.contains("bg-white")).toBe(false)
      expect(panelA.classList.contains("hidden")).toBe(true)
    })
  })

  describe("drawer editor/list", () => {
    beforeEach(() => {
      element.innerHTML = `
        <div data-drawer-list="rules"></div>
        <div data-drawer-editor="rules" class="hidden">seed</div>`
    })
    it("showDrawerEditor hides the list, reveals the editor", () => {
      tm.showDrawerEditor("rules")
      expect(element.querySelector("[data-drawer-list='rules']").classList.contains("hidden")).toBe(true)
      expect(element.querySelector("[data-drawer-editor='rules']").classList.contains("hidden")).toBe(false)
    })
    it("showDrawerList restores the list and clears the editor", () => {
      tm.showDrawerList("rules")
      const editor = element.querySelector("[data-drawer-editor='rules']")
      expect(editor.classList.contains("hidden")).toBe(true)
      expect(editor.innerHTML).toBe("")
      expect(element.querySelector("[data-drawer-list='rules']").classList.contains("hidden")).toBe(false)
    })
  })

  describe("searchComponents", () => {
    it("hides items that match neither label nor type", () => {
      element.innerHTML = `
        <div class="entity-field-item" data-field-label="Email" data-field-type="text"></div>
        <div class="entity-field-item" data-field-label="Phone" data-field-type="tel"></div>`
      tm.searchComponents({ target: { value: "email" } })
      const items = element.querySelectorAll(".entity-field-item")
      expect(items[0].classList.contains("hidden")).toBe(false)
      expect(items[1].classList.contains("hidden")).toBe(true)
    })

    it("shows all items for a blank query", () => {
      element.innerHTML = `<div class="entity-field-item" data-field-label="Email"></div>`
      tm.searchComponents({ target: { value: "" } })
      expect(element.querySelector(".entity-field-item").classList.contains("hidden")).toBe(false)
    })

    it("falls back to propertyName/propertyType when field-label/type are absent", () => {
      element.innerHTML = `
        <div class="entity-field-item" data-property-name="Amount" data-property-type="number"></div>`
      tm.searchComponents({ target: { value: "amount" } })
      expect(element.querySelector(".entity-field-item").classList.contains("hidden")).toBe(false)
    })

    it("treats an item with no label/name/type as an empty string (hides on a non-matching query)", () => {
      element.innerHTML = `<div class="entity-field-item"></div>`
      tm.searchComponents({ target: { value: "anything" } })
      expect(element.querySelector(".entity-field-item").classList.contains("hidden")).toBe(true)
    })
  })

  describe("toggleSubsection bail", () => {
    it("bails when the button is not inside a searchable section", () => {
      const button = document.createElement("button")
      expect(() => tm.toggleSubsection({ currentTarget: button })).not.toThrow()
    })
  })

  describe("toggleCategory", () => {
    function category({ chevron = true } = {}) {
      const cat = document.createElement("div")
      cat.dataset.searchableCategory = ""
      const button = document.createElement("button")
      if (chevron) {
        const chev = document.createElement("span"); chev.dataset.chevron = ""
        button.appendChild(chev)
      }
      const content = document.createElement("div")
      content.setAttribute("data-page-builder-target", "entityFieldsCategory")
      content.classList.add("hidden")
      // a child subsection with its own chevron (sectionContent lookup uses
      // :scope and misses in happy-dom, but the section chevron is reachable)
      const section = document.createElement("div")
      section.dataset.searchableSection = ""
      const secChev = document.createElement("span"); secChev.dataset.chevron = ""
      section.appendChild(secChev)
      content.appendChild(section)
      cat.append(button, content)
      element.appendChild(cat)
      return { cat, button, content, section, secChev }
    }

    it("expands a collapsed category and rotates the chevrons", () => {
      const { button, content, secChev } = category()
      tm.toggleCategory({ currentTarget: button })
      expect(content.classList.contains("hidden")).toBe(false)
      expect(button.querySelector("[data-chevron]").classList.contains("rotate-180")).toBe(true)
      expect(secChev.classList.contains("rotate-180")).toBe(true)
    })

    it("collapses an expanded category (content already visible)", () => {
      const { button, content } = category()
      content.classList.remove("hidden") // start expanded
      tm.toggleCategory({ currentTarget: button })
      expect(content.classList.contains("hidden")).toBe(true)
    })

    it("tolerates a category with no chevron on the button", () => {
      const { button, content } = category({ chevron: false })
      expect(() => tm.toggleCategory({ currentTarget: button })).not.toThrow()
      expect(content.classList.contains("hidden")).toBe(false)
    })

    it("locates content via button.nextElementSibling when no entityFieldsCategory target exists", () => {
      const cat = document.createElement("div")
      cat.dataset.searchableCategory = ""
      const button = document.createElement("button")
      const content = document.createElement("div")
      content.classList.add("hidden")
      cat.append(button, content)
      element.appendChild(cat)
      tm.toggleCategory({ currentTarget: button })
      expect(content.classList.contains("hidden")).toBe(false)
    })
  })

  describe("filterSidebar", () => {
    function sidebar() {
      const root = document.createElement("div")
      const cat = document.createElement("div")
      cat.dataset.searchableCategory = ""
      const catBtn = document.createElement("button")
      const catChev = document.createElement("span"); catChev.dataset.chevron = ""
      catBtn.appendChild(catChev)
      const catContent = document.createElement("div")
      catContent.setAttribute("data-page-builder-target", "entityFieldsCategory")
      const section = document.createElement("div")
      section.dataset.searchableSection = ""
      const item = document.createElement("div")
      item.dataset.searchableItem = ""
      item.dataset.searchText = "email address"
      section.appendChild(item)
      catContent.appendChild(section)
      cat.append(catBtn, catContent)
      root.appendChild(cat)
      ctrl.hasSidebarContentTarget = true
      ctrl.sidebarContentTarget = root
      return { root, cat, catContent, catChev, section, item }
    }

    it("is a no-op without a sidebar-content target", () => {
      expect(() => tm.filterSidebar({ target: { value: "x" } })).not.toThrow()
    })

    it("resets everything visible on an empty term", () => {
      const { cat, catContent, catChev, section, item } = sidebar()
      cat.classList.add("hidden"); section.classList.add("hidden"); item.classList.add("hidden")
      tm.filterSidebar({ target: { value: "  " } })
      expect(cat.classList.contains("hidden")).toBe(false)
      expect(catContent.classList.contains("hidden")).toBe(false)
      expect(catChev.classList.contains("rotate-180")).toBe(true)
      expect(section.classList.contains("hidden")).toBe(false)
      expect(item.classList.contains("hidden")).toBe(false)
    })

    it("shows matching items and expands their parent category, hiding non-matches", () => {
      const { cat, catContent, catChev, item } = sidebar()
      tm.filterSidebar({ target: { value: "email" } })
      expect(item.classList.contains("hidden")).toBe(false)
      expect(cat.classList.contains("hidden")).toBe(false)
      expect(catContent.classList.contains("hidden")).toBe(false)
      expect(catChev.classList.contains("rotate-180")).toBe(true)
    })

    it("hides non-matching items and their categories", () => {
      const { cat, item } = sidebar()
      tm.filterSidebar({ target: { value: "zzzznope" } })
      expect(item.classList.contains("hidden")).toBe(true)
      expect(cat.classList.contains("hidden")).toBe(true)
    })

    it("rotates a matching section's own chevron when expanding it", () => {
      const root = document.createElement("div")
      const cat = document.createElement("div"); cat.dataset.searchableCategory = ""
      const catBtn = document.createElement("button")
      const catContent = document.createElement("div")
      catContent.setAttribute("data-page-builder-target", "entityFieldsCategory")
      const section = document.createElement("div"); section.dataset.searchableSection = ""
      const secChevron = document.createElement("span"); secChevron.dataset.chevron = ""
      const secContent = document.createElement("div")
      const item = document.createElement("div"); item.dataset.searchableItem = ""; item.dataset.searchText = "email"
      secContent.appendChild(item)
      section.append(secChevron, secContent)
      catContent.appendChild(section)
      cat.append(catBtn, catContent)
      root.appendChild(cat)
      ctrl.hasSidebarContentTarget = true
      ctrl.sidebarContentTarget = root
      tm.filterSidebar({ target: { value: "email" } })
      expect(item.classList.contains("hidden")).toBe(false)
      expect(secContent.classList.contains("hidden")).toBe(false)
      expect(secChevron.classList.contains("rotate-180")).toBe(true)
    })

    // A category whose content isn't the entityFieldsCategory target exercises
    // the _lastDivChild fallback (last child div, else null) on both reset and match.
    function sidebarNoTarget(searchText) {
      const root = document.createElement("div")
      const cat = document.createElement("div")
      cat.dataset.searchableCategory = ""
      const catBtn = document.createElement("button")
      const item = document.createElement("div")
      item.dataset.searchableItem = ""
      if (searchText !== undefined) item.dataset.searchText = searchText
      cat.append(catBtn, item)
      root.appendChild(cat)
      ctrl.hasSidebarContentTarget = true
      ctrl.sidebarContentTarget = root
      return { cat, item }
    }

    it("uses the :scope fallback (no entityFieldsCategory target) on an empty term", () => {
      const { cat } = sidebarNoTarget("email")
      cat.classList.add("hidden")
      expect(() => tm.filterSidebar({ target: { value: "" } })).not.toThrow()
      expect(cat.classList.contains("hidden")).toBe(false)
    })

    it("uses the :scope fallback for a matching category with no target, and defaults missing searchText to ''", () => {
      const { cat, item } = sidebarNoTarget(undefined) // no data-searchText → `|| ""`
      // item has no searchText → never matches; the category is hidden as a non-match
      tm.filterSidebar({ target: { value: "x" } })
      expect(item.classList.contains("hidden")).toBe(true)
      expect(cat.classList.contains("hidden")).toBe(true)
    })

    it("expands a matching category that has no entityFieldsCategory target (:scope fallback)", () => {
      const { cat, item } = sidebarNoTarget("phone number")
      tm.filterSidebar({ target: { value: "phone" } })
      expect(item.classList.contains("hidden")).toBe(false)
      expect(cat.classList.contains("hidden")).toBe(false)
    })
  })

  describe("toggleCategory / toggleSubsection", () => {
    // toggleSubsection locates its content panel via _lastDivChild (last element
    // child iff it's a <div>) — a happy-dom-safe stand-in for the browser's
    // `:scope > div:last-child`.
    it("toggleSubsection expands the section's last-child content and rotates the chevron", () => {
      const section = document.createElement("div")
      section.dataset.searchableSection = ""
      const button = document.createElement("button")
      const chevron = document.createElement("span")
      chevron.dataset.chevron = ""
      button.appendChild(chevron)
      const content = document.createElement("div")
      content.classList.add("hidden")
      section.append(button, content)
      element.appendChild(section)
      tm.toggleSubsection({ currentTarget: button })
      // content is the section's last child div -> found -> expanded; chevron rotates
      expect(content.classList.contains("hidden")).toBe(false)
      expect(chevron.classList.contains("rotate-180")).toBe(true)
    })

    it("toggleCategory bails when there is no category wrapper", () => {
      const button = document.createElement("button")
      expect(() => tm.toggleCategory({ currentTarget: button })).not.toThrow()
    })

    it("toggleCategory folds each child subsection's content and chevron to match", () => {
      const cat = document.createElement("div")
      cat.dataset.searchableCategory = ""
      const button = document.createElement("button")
      const catContent = document.createElement("div") // button.nextElementSibling
      const section = document.createElement("div")
      section.dataset.searchableSection = ""
      const secChevron = document.createElement("span"); secChevron.dataset.chevron = ""
      const secContent = document.createElement("div")
      section.append(secChevron, secContent)
      catContent.appendChild(section)
      cat.append(button, catContent)
      element.appendChild(cat)
      tm.toggleCategory({ currentTarget: button })
      // category was visible -> collapses; each child subsection folds to match
      expect(catContent.classList.contains("hidden")).toBe(true)
      expect(secContent.classList.contains("hidden")).toBe(true)
      expect(secChevron.classList.contains("rotate-180")).toBe(false)
    })
  })

  describe("selectEntity", () => {
    it("stores the entity metadata and renders its fields", () => {
      ctrl.hasEntityNameTarget = true
      ctrl.entityNameTarget = document.createElement("span")
      ctrl.hasEntityFieldsListTarget = true
      ctrl.entityFieldsListTarget = document.createElement("div")
      ctrl.hasEntityFieldCountTarget = true
      ctrl.entityFieldCountTarget = document.createElement("span")
      const button = document.createElement("button")
      button.dataset.entityId = "7"
      button.dataset.entityName = "Contact"
      button.dataset.entityProperties = JSON.stringify([{ name: "Email", name_slug: "email", type: "String" }])
      tm.selectEntity({ currentTarget: button })
      expect(ctrl.metadata.entity_id).toBe(7)
      expect(ctrl.entityIdValue).toBe(7)
      expect(ctrl.entityNameTarget.textContent).toBe("Contact")
      expect(ctrl.entityFieldsListTarget.innerHTML).toContain("email")
      expect(ctrl.entityFieldCountTarget.textContent).toBe("1")
      expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
    })

    it("closes the containing dropdown menu and defaults absent entityProperties to []", () => {
      ctrl.hasEntityFieldsListTarget = true
      ctrl.entityFieldsListTarget = document.createElement("div")
      const dropdown = document.createElement("div")
      dropdown.setAttribute("data-controller", "dropdown")
      const menu = document.createElement("div")
      menu.setAttribute("data-dropdown-target", "menu")
      const button = document.createElement("button")
      button.dataset.entityId = "3"
      button.dataset.entityName = "Order"
      // no data-entityProperties → JSON.parse("[]")
      dropdown.append(menu, button)
      element.appendChild(dropdown)
      tm.selectEntity({ currentTarget: button })
      expect(menu.classList.contains("hidden")).toBe(true)
      expect(ctrl.entityFieldsListTarget.innerHTML).toContain("No Fields")
    })
  })

  describe("renderEntityFields", () => {
    it("renders an empty state when there are no properties", () => {
      ctrl.hasEntityFieldsListTarget = true
      ctrl.entityFieldsListTarget = document.createElement("div")
      tm.renderEntityFields([])
      expect(ctrl.entityFieldsListTarget.innerHTML).toContain("No Fields")
      expect(ctrl.fieldManager.updateSidebarFieldStates).toHaveBeenCalled()
    })

    it("is a no-op without an entity-fields-list target", () => {
      expect(() => tm.renderEntityFields([{ name: "X", name_slug: "x", type: "String" }])).not.toThrow()
    })

    it("renders property rows and resolves the icon html_type across all fallbacks", () => {
      ctrl.hasEntityFieldsListTarget = true
      ctrl.entityFieldsListTarget = document.createElement("div")
      ctrl.metadata = { entity_name: "Contact" }
      tm.renderEntityFields([
        { name: "A", name_slug: "a", type: "String", html_type: "email" }, // htmlType truthy
        { name: "B", name_slug: "b", type: "Integer" },                    // raw type → default html
        { name: "C", name_slug: "c", type: "Custom::Nested::Boolean" },    // namespaced → split/pop
        { name: "D", name_slug: "d", type: "TotallyUnknownType" },         // → 'text' fallback
        { name: "E", name_slug: "e" },                                     // no type → rawType?. optional
        { name: "F", name_slug: "f", type: "String", html_type: "bogus" }, // effective not in ICONS/COLORS maps
      ])
      const html = ctrl.entityFieldsListTarget.innerHTML
      expect(html).toContain('data-property-slug="a"')
      expect(html).toContain('data-source-section="Contact"')
      expect(html.match(/entity-field-item/g).length).toBe(6)
    })

    it("uses an empty source-section when metadata has no entity_name", () => {
      ctrl.hasEntityFieldsListTarget = true
      ctrl.entityFieldsListTarget = document.createElement("div")
      ctrl.metadata = {}
      tm.renderEntityFields([{ name: "A", name_slug: "a", type: "String" }])
      expect(ctrl.entityFieldsListTarget.innerHTML).toContain('data-source-section=""')
    })
  })

  describe("onEntityChange", () => {
    it("sets entity metadata when a value is chosen", () => {
      tm.onEntityChange({ target: { value: "3" } })
      expect(ctrl.metadata.entity_id).toBe(3)
      expect(ctrl.entityIdValue).toBe(3)
      expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
    })

    it("clears entity metadata when the selection is emptied", () => {
      ctrl.metadata.entity_id = 9
      tm.onEntityChange({ target: { value: "" } })
      expect(ctrl.metadata.entity_id).toBeUndefined()
      expect(ctrl.entityIdValue).toBeNull()
    })
  })
})
