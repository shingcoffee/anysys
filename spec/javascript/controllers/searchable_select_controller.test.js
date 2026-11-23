import { describe, it, expect, beforeEach, vi } from "vitest"
import Controller from "controllers/searchable_select_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

const OPTIONS = [
  { group: "Fruit", items: [["Apple", "apple", { icon: "M1 1", color: "red", description: "a red fruit" }], ["Banana", "banana"]] },
  { group: "Veg", items: [["Carrot", "carrot"], ["Pea", "pea", { disabled: true }]] },
]

async function mount({ expandAll = false, selected = "" } = {}) {
  const html = `
    <div data-controller="searchable-select"
         data-searchable-select-options-value='${JSON.stringify(OPTIONS)}'
         ${expandAll ? 'data-searchable-select-expand-all-value="true"' : ""}
         ${selected ? `data-searchable-select-selected-value="${selected}"` : ""}>
      <input data-searchable-select-target="search">
      <input type="hidden" data-searchable-select-target="hidden">
      <button data-searchable-select-target="clear" class="hidden"></button>
      <div data-searchable-select-target="dropdown" class="hidden"></div>
    </div>`
  const { application, element } = await mountController("searchable-select", Controller, html)
  await tick() // let MutationObserver register the dynamically-rendered targets
  const ctrl = controllerFor(application, element, "searchable-select")
  return { application, element, ctrl }
}

const search = (el) => el.querySelector('[data-searchable-select-target="search"]')
const hidden = (el) => el.querySelector('[data-searchable-select-target="hidden"]')
const options = (el) => [...el.querySelectorAll('[data-searchable-select-target="option"]')]
const optByValue = (el, v) => options(el).find(o => o.dataset.value === v)

describe("searchable-select — rendering", () => {
  let element, ctrl
  beforeEach(async () => { ({ element, ctrl } = await mount()) })

  it("renders groups, headers with counts and options from optionsValue", () => {
    const groups = element.querySelectorAll('[data-searchable-select-target="group"]')
    expect(groups.length).toBe(2)
    const headers = element.querySelectorAll('[data-searchable-select-target="groupHeader"]')
    expect(headers[0].textContent).toContain("Fruit")
    expect(headers[0].textContent).toContain("2") // count badge
    expect(options(element).length).toBe(4)
  })

  it("builds search-text with the description when present", () => {
    expect(optByValue(element, "apple").dataset.search).toBe("apple fruit a red fruit")
    expect(optByValue(element, "banana").dataset.search).toBe("banana fruit")
  })

  it("renders an icon wrapper + title for options with meta.icon/description", () => {
    const apple = optByValue(element, "apple")
    expect(apple.querySelector("svg")).toBeTruthy()
    expect(apple.title).toBe("a red fruit")
    expect(apple.querySelector("svg").getAttribute("class")).toContain("text-red-500")
  })

  it("marks disabled options and excludes them from clicks/visibleOptions", () => {
    const pea = optByValue(element, "pea")
    expect(pea.dataset.disabled).toBe("true")
    expect(pea.classList.contains("cursor-not-allowed")).toBe(true)
    expect(pea.textContent).toContain("(already used)")
    // groups are collapsed by default -> visibleOptions requires expansion
    ctrl.expandAllGroups()
    expect(ctrl.visibleOptions().map(o => o.dataset.value)).not.toContain("pea")
  })

  it("groups start collapsed by default", () => {
    const items = element.querySelectorAll('[data-searchable-select-target="groupItems"]')
    expect(items[0].classList.contains("hidden")).toBe(true)
  })

  it("falls back to the gray icon color class for an unknown/absent meta.color", async () => {
    const opts = [{ group: "G", items: [["X", "x", { icon: "M1 1" }]] }] // no color
    const html = `
      <div data-controller="searchable-select" data-searchable-select-options-value='${JSON.stringify(opts)}'>
        <input data-searchable-select-target="search">
        <input type="hidden" data-searchable-select-target="hidden">
        <div data-searchable-select-target="dropdown" class="hidden"></div>
      </div>`
    const { application, element: el } = await mountController("searchable-select", Controller, html)
    await tick()
    controllerFor(application, el, "searchable-select")
    const svg = el.querySelector('[data-value="x"] svg')
    expect(svg.getAttribute("class")).toContain("text-gray-500")
  })
})

describe("searchable-select — disconnect", () => {
  it("removes the document click-outside listener", async () => {
    const { ctrl } = await mount()
    const spy = vi.spyOn(document, "removeEventListener")
    ctrl.disconnect()
    expect(spy).toHaveBeenCalledWith("click", ctrl.boundClickOutside)
  })
})

describe("searchable-select — expand/collapse", () => {
  it("expandAllValue expands every group on connect", async () => {
    const { element } = await mount({ expandAll: true })
    const items = element.querySelectorAll('[data-searchable-select-target="groupItems"]')
    expect([...items].every(i => !i.classList.contains("hidden"))).toBe(true)
  })

  it("toggleGroup expands then collapses a single group and rotates its chevron", async () => {
    const { element, ctrl } = await mount()
    ctrl.toggleGroup(0)
    const items = element.querySelectorAll('[data-searchable-select-target="groupItems"]')[0]
    const chevron = element.querySelector('[data-searchable-select-target="groupHeader"] [data-chevron]')
    expect(items.classList.contains("hidden")).toBe(false)
    expect(chevron.classList.contains("rotate-90")).toBe(true)
    ctrl.toggleGroup(0)
    expect(items.classList.contains("hidden")).toBe(true)
    expect(chevron.classList.contains("rotate-90")).toBe(false)
  })

  it("toggleGroup is a no-op for an out-of-range group index", async () => {
    const { ctrl } = await mount()
    expect(() => ctrl.toggleGroup(99)).not.toThrow()
  })

  it("clicking a group header toggles that group via the wired click listener and stops propagation", async () => {
    const { element, ctrl } = await mount()
    ctrl.open()
    const header = element.querySelector('[data-searchable-select-target="groupHeader"][data-group-index="0"]')
    const items = element.querySelectorAll('[data-searchable-select-target="groupItems"]')[0]
    header.dispatchEvent(new Event("click", { bubbles: true }))
    expect(items.classList.contains("hidden")).toBe(false)
    // stopPropagation() keeps the click from bubbling to clickOutside and closing the dropdown
    const dd = element.querySelector('[data-searchable-select-target="dropdown"]')
    expect(dd.classList.contains("hidden")).toBe(false)
  })
})

describe("searchable-select — filter", () => {
  it("filters options by query, hides non-matching groups and toggles noResults", async () => {
    const { element, ctrl } = await mount()
    search(element).value = "carrot"
    ctrl.filter()
    expect(optByValue(element, "carrot").classList.contains("hidden")).toBe(false)
    expect(optByValue(element, "apple").classList.contains("hidden")).toBe(true)
    const fruitGroup = element.querySelectorAll('[data-searchable-select-target="group"]')[0]
    expect(fruitGroup.classList.contains("hidden")).toBe(true)
    const noResults = element.querySelector('[data-searchable-select-target="noResults"]')
    expect(noResults.classList.contains("hidden")).toBe(true) // has matches
  })

  it("shows noResults when nothing matches", async () => {
    const { element, ctrl } = await mount()
    search(element).value = "zzzzz"
    ctrl.filter()
    const noResults = element.querySelector('[data-searchable-select-target="noResults"]')
    expect(noResults.classList.contains("hidden")).toBe(false)
  })

  it("matching a group name shows all its options", async () => {
    const { element, ctrl } = await mount()
    search(element).value = "veg"
    ctrl.filter()
    expect(optByValue(element, "carrot").classList.contains("hidden")).toBe(false)
    expect(optByValue(element, "pea").classList.contains("hidden")).toBe(false)
  })

  it("clearing the query resets to show-all and re-collapses groups (default expandAllValue=false)", async () => {
    const { element, ctrl } = await mount()
    search(element).value = "carrot"
    ctrl.filter()
    search(element).value = ""
    ctrl.filter()
    expect(optByValue(element, "apple").classList.contains("hidden")).toBe(false)
    expect(optByValue(element, "carrot").classList.contains("hidden")).toBe(false)
    const fruitGroup = element.querySelectorAll('[data-searchable-select-target="group"]')[0]
    expect(fruitGroup.classList.contains("hidden")).toBe(false)
    const items = element.querySelectorAll('[data-searchable-select-target="groupItems"]')
    expect(items[0].classList.contains("hidden")).toBe(true) // collapsed since expandAllValue is false
  })

  it("clearing the query expands all groups when expandAllValue is true", async () => {
    const { element, ctrl } = await mount({ expandAll: true })
    search(element).value = "carrot"
    ctrl.filter()
    search(element).value = ""
    ctrl.filter()
    const items = element.querySelectorAll('[data-searchable-select-target="groupItems"]')
    expect([...items].every((i) => !i.classList.contains("hidden"))).toBe(true)
  })

  it("falls back to an empty group name when data-group-name is missing", async () => {
    const { element, ctrl } = await mount()
    const group = element.querySelectorAll('[data-searchable-select-target="group"]')[0]
    group.removeAttribute("data-group-name")
    search(element).value = "apple"
    ctrl.filter()
    expect(optByValue(element, "apple").classList.contains("hidden")).toBe(false)
  })
})

describe("searchable-select — selection", () => {
  it("select() sets hidden value, search label, marks option and dispatches change", async () => {
    const { element, ctrl } = await mount()
    const onChange = vi.fn()
    hidden(element).addEventListener("change", onChange)
    ctrl.select("apple", "Apple", "Fruit")
    expect(hidden(element).value).toBe("apple")
    expect(search(element).value).toBe("Apple  —  Fruit")
    expect(optByValue(element, "apple").classList.contains("font-semibold")).toBe(true)
    expect(element.querySelector('[data-searchable-select-target="clear"]').classList.contains("hidden")).toBe(false)
    expect(onChange).toHaveBeenCalled()
  })

  it("clearSelection() resets value, label and clear button", async () => {
    const { element, ctrl } = await mount()
    ctrl.select("apple", "Apple", "Fruit")
    ctrl.clearSelection()
    expect(hidden(element).value).toBe("")
    expect(search(element).value).toBe("")
    expect(element.querySelector('[data-searchable-select-target="clear"]').classList.contains("hidden")).toBe(true)
  })

  it("select() without a groupLabel sets the search value to just the label", async () => {
    const { element, ctrl } = await mount()
    ctrl.select("apple", "Apple")
    expect(search(element).value).toBe("Apple")
  })

  it("preselects from selectedValue on connect (label + expanded group)", async () => {
    const { element } = await mount({ selected: "carrot" })
    expect(search(element).value).toBe("Carrot  —  Veg")
    expect(optByValue(element, "carrot").classList.contains("text-indigo-600")).toBe(true)
  })

  it("setSelectedFromValue falls back to just the label when the option has no group-label", async () => {
    const { element, ctrl } = await mount()
    const apple = optByValue(element, "apple")
    apple.removeAttribute("data-group-label")
    ctrl.setSelectedFromValue("apple")
    expect(search(element).value).toBe("Apple")
  })
})

describe("searchable-select — open/close/keyboard", () => {
  it("open/close toggle the dropdown hidden class", async () => {
    const { element, ctrl } = await mount()
    const dd = element.querySelector('[data-searchable-select-target="dropdown"]')
    ctrl.open()
    expect(dd.classList.contains("hidden")).toBe(false)
    ctrl.close()
    expect(dd.classList.contains("hidden")).toBe(true)
  })

  it("ArrowDown opens the dropdown and highlights the first visible option", async () => {
    const { element, ctrl } = await mount({ expandAll: true })
    const ev = { key: "ArrowDown", preventDefault: vi.fn() }
    ctrl.keydown(ev)
    expect(ev.preventDefault).toHaveBeenCalled()
    const highlighted = element.querySelector(".bg-indigo-50")
    expect(highlighted).toBeTruthy()
    expect(ctrl.highlightIndex).toBe(0)
  })

  it("Enter selects the highlighted option", async () => {
    const { element, ctrl } = await mount({ expandAll: true })
    ctrl.keydown({ key: "ArrowDown", preventDefault: vi.fn() })
    ctrl.keydown({ key: "Enter", preventDefault: vi.fn() })
    expect(hidden(element).value).toBe("apple")
  })

  it("clickOutside closes the dropdown", async () => {
    const { element, ctrl } = await mount()
    ctrl.open()
    document.body.dispatchEvent(new Event("click", { bubbles: true }))
    // clickOutside checks event.target; simulate a target outside the element
    ctrl.clickOutside({ target: document.body })
    expect(element.querySelector('[data-searchable-select-target="dropdown"]').classList.contains("hidden")).toBe(true)
  })

  it("toggle() opens (and focuses search) when closed, closes when open", async () => {
    const { element, ctrl } = await mount()
    const dd = element.querySelector('[data-searchable-select-target="dropdown"]')
    expect(dd.classList.contains("hidden")).toBe(true)
    ctrl.toggle()
    expect(dd.classList.contains("hidden")).toBe(false)
    expect(document.activeElement).toBe(search(element))
    ctrl.toggle()
    expect(dd.classList.contains("hidden")).toBe(true)
  })

  // NOTE (suspected source bug): ArrowDown's handler calls this.open() before
  // computing the new index, and open() unconditionally resets highlightIndex
  // to -1 — so every ArrowDown press recomputes min(-1+1, len-1) = 0. Repeated
  // ArrowDown presses can never advance past the first option. Characterizing
  // actual behavior here, not the presumably-intended "move to next item".
  it("ArrowUp moves the highlight and is clamped at 0", async () => {
    const { element, ctrl } = await mount({ expandAll: true })
    ctrl.keydown({ key: "ArrowDown", preventDefault: vi.fn() }) // highlightIndex -> 0
    const ev = { key: "ArrowUp", preventDefault: vi.fn() }
    ctrl.keydown(ev)
    expect(ev.preventDefault).toHaveBeenCalled()
    expect(ctrl.highlightIndex).toBe(0) // already clamped at the floor
    const highlighted = element.querySelector(".bg-indigo-50")
    expect(highlighted).toBeTruthy()
  })

  it("Escape closes the dropdown and blurs the search input, preventing default only when open", async () => {
    const { element, ctrl } = await mount()
    ctrl.open()
    search(element).focus()
    const openEsc = { key: "Escape", preventDefault: vi.fn() }
    ctrl.keydown(openEsc)
    expect(openEsc.preventDefault).toHaveBeenCalledOnce()
    const dd = element.querySelector('[data-searchable-select-target="dropdown"]')
    expect(dd.classList.contains("hidden")).toBe(true)
    expect(document.activeElement).not.toBe(search(element))

    const closedEsc = { key: "Escape", preventDefault: vi.fn() }
    ctrl.keydown(closedEsc)
    expect(closedEsc.preventDefault).not.toHaveBeenCalled()
  })

  it("Tab closes the dropdown", async () => {
    const { element, ctrl } = await mount()
    ctrl.open()
    ctrl.keydown({ key: "Tab", preventDefault: vi.fn() })
    const dd = element.querySelector('[data-searchable-select-target="dropdown"]')
    expect(dd.classList.contains("hidden")).toBe(true)
  })

  it("Enter with no highlighted option is a no-op", async () => {
    const { element, ctrl } = await mount({ expandAll: true })
    const onChange = vi.fn()
    hidden(element).addEventListener("change", onChange)
    ctrl.keydown({ key: "Enter", preventDefault: vi.fn() }) // highlightIndex still -1
    expect(onChange).not.toHaveBeenCalled()
  })
})

describe("searchable-select — visibleOptions", () => {
  it("excludes options inside collapsed (unexpanded) groups by default", async () => {
    const { ctrl } = await mount()
    expect(ctrl.visibleOptions()).toEqual([])
  })

  it("excludes options that themselves carry the hidden class (e.g. filtered out)", async () => {
    const { element, ctrl } = await mount({ expandAll: true })
    search(element).value = "carrot"
    ctrl.filter()
    const values = ctrl.visibleOptions().map((o) => o.dataset.value)
    expect(values).toEqual(["carrot"])
  })

  it("excludes options whose ancestor group div directly carries the hidden class", async () => {
    const { element, ctrl } = await mount({ expandAll: true })
    const group = element.querySelectorAll('[data-searchable-select-target="group"]')[0]
    group.classList.add("hidden")
    const values = ctrl.visibleOptions().map((o) => o.dataset.value)
    expect(values).not.toContain("apple")
    expect(values).not.toContain("banana")
    expect(values).toEqual(["carrot"]) // pea excluded (disabled), fruit group excluded (hidden)
  })
})
