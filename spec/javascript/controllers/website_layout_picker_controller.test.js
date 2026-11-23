import { describe, it, expect, afterEach } from "vitest"
import Controller from "controllers/website_layout_picker_controller"
import { mountController, click, controllerFor } from "../support/stimulus.js"

const card = ({ key, category, suggested = false, checked = false, search, name = key, description = "", count = "3 sections", sections = "Hero · Contact", radio = true }) =>
  `<label data-website-layout-picker-target="card" data-layout-key="${key}" data-layout-category="${category}" data-layout-suggested="${suggested}"` +
  `${search === undefined ? "" : ` data-layout-search="${search}"`} data-layout-name="${name}" data-layout-description="${description}" data-layout-count="${count}" data-layout-sections="${sections}">` +
  (radio ? `<input type="radio" name="layout_key" value="${key}"${checked ? " checked" : ""}>` : "") +
  `${name}</label>`

const chips = ["suggested", "all", "product", "general"]
  .map((id) => `<button type="button" data-website-layout-picker-target="filter" data-filter="${id}" data-action="click->website-layout-picker#filter">${id}</button>`)
  .join("")

const summary = ({ description = true } = {}) =>
  `<p data-website-layout-picker-target="summaryName"></p>` +
  (description ? `<p data-website-layout-picker-target="summaryDescription"></p>` : "") +
  `<p data-website-layout-picker-target="summaryCount"></p>` +
  `<p data-website-layout-picker-target="summarySections"></p>`

const html = ({ filter = "suggested", formats, search = true, parts = true, description = true, extraChip = "" } = {}) =>
  `<div data-controller="website-layout-picker" data-action="change->website-layout-picker#select"` +
  ` data-website-layout-picker-filter-value="${filter}"` +
  (formats ? ` data-website-layout-picker-count-formats-value='${JSON.stringify(formats)}'` : "") + `>` +
  (search ? `<input type="search" data-website-layout-picker-target="search" data-action="input->website-layout-picker#search keydown.esc->website-layout-picker#clearSearch">` : "") +
  (parts ? `<p data-website-layout-picker-target="count"></p>` : "") +
  chips + extraChip +
  `<section data-website-layout-picker-target="group" data-layout-family="presence">` +
  card({ key: "presence_home", category: "business", suggested: true, checked: true, search: "presence home business hero", name: "Presence home", description: "A calm home page" }) +
  card({ key: "presence_about", category: "business", suggested: true, search: "presence about team" }) +
  `</section>` +
  `<section data-website-layout-picker-target="group" data-layout-family="saas_landing">` +
  card({ key: "saas_home", category: "product", search: "saas pricing product" }) +
  `</section>` +
  `<section data-website-layout-picker-target="group" data-layout-family="standalone">` +
  card({ key: "gallery", category: "general" }) +
  `</section>` +
  (parts ? `<div data-website-layout-picker-target="empty" class="hidden"><button type="button" data-reset data-action="click->website-layout-picker#reset">Show all</button></div>` : "") +
  summary({ description }) +
  `</div>`

const visibleKeys = (el) =>
  [...el.querySelectorAll("[data-website-layout-picker-target='card']")]
    .filter((node) => !node.classList.contains("hidden"))
    .map((node) => node.dataset.layoutKey)

const hiddenGroups = (el) =>
  [...el.querySelectorAll("[data-website-layout-picker-target='group']")]
    .filter((node) => node.classList.contains("hidden"))
    .map((node) => node.dataset.layoutFamily)

const pressed = (el) =>
  [...el.querySelectorAll("[data-website-layout-picker-target='filter']")]
    .filter((node) => node.getAttribute("aria-pressed") === "true")
    .map((node) => node.dataset.filter)

const target = (el, name) => el.querySelector(`[data-website-layout-picker-target='${name}']`)

const typeSearch = (el, value) => {
  const input = target(el, "search")
  input.value = value
  input.dispatchEvent(new Event("input", { bubbles: true }))
}

const escape = (el) => {
  const event = new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true })
  target(el, "search").dispatchEvent(event)
  return event
}

describe("website_layout_picker_controller", () => {
  let application

  afterEach(() => {
    application?.stop()
    application = null
    document.body.innerHTML = ""
  })

  it("applies the initial filter, count and summary on connect", async () => {
    let element
    ;({ application, element } = await mountController("website-layout-picker", Controller, html()))

    expect(visibleKeys(element)).toEqual(["presence_home", "presence_about"])
    expect(hiddenGroups(element)).toEqual(["saas_landing", "standalone"])
    expect(pressed(element)).toEqual(["suggested"])
    expect(target(element, "count").textContent).toBe("2 layouts")
    expect(target(element, "empty").classList.contains("hidden")).toBe(true)
    expect(target(element, "summaryName").textContent).toBe("Presence home")
    expect(target(element, "summaryDescription").textContent).toBe("A calm home page")
    expect(target(element, "summaryDescription").classList.contains("hidden")).toBe(false)
    expect(target(element, "summarySections").textContent).toBe("Hero · Contact")
  })

  it("filters by chip, category and all, falling back to all without a chip id", async () => {
    let element
    ;({ application, element } = await mountController(
      "website-layout-picker",
      Controller,
      html({ extraChip: `<button type="button" data-blank data-action="click->website-layout-picker#filter">blank</button>` })
    ))

    await click(element.querySelector("[data-filter='product']"))
    expect(visibleKeys(element)).toEqual(["saas_home"])
    expect(pressed(element)).toEqual(["product"])
    expect(target(element, "count").textContent).toBe("1 layout")

    await click(element.querySelector("[data-filter='general']"))
    expect(visibleKeys(element)).toEqual(["gallery"])

    await click(element.querySelector("[data-blank]"))
    expect(visibleKeys(element)).toEqual(["presence_home", "presence_about", "saas_home", "gallery"])
    expect(pressed(element)).toEqual(["all"])
    expect(hiddenGroups(element)).toEqual([])
  })

  it("narrows by search text within the active filter and shows the empty state", async () => {
    let element
    ;({ application, element } = await mountController("website-layout-picker", Controller, html({ filter: "all" })))

    typeSearch(element, "  PRICING ")
    expect(visibleKeys(element)).toEqual(["saas_home"])
    expect(hiddenGroups(element)).toEqual(["presence", "standalone"])

    typeSearch(element, "nothing matches")
    expect(visibleKeys(element)).toEqual([])
    expect(target(element, "empty").classList.contains("hidden")).toBe(false)
    expect(target(element, "count").textContent).toBe("0 layouts")

    await click(element.querySelector("[data-reset]"))
    expect(target(element, "search").value).toBe("")
    expect(visibleKeys(element)).toHaveLength(4)
    expect(target(element, "empty").classList.contains("hidden")).toBe(true)
  })

  it("clears the search on Escape only when there is text to clear", async () => {
    let element
    ;({ application, element } = await mountController("website-layout-picker", Controller, html({ filter: "all" })))

    expect(escape(element).defaultPrevented).toBe(false)

    typeSearch(element, "team")
    expect(visibleKeys(element)).toEqual(["presence_about"])
    expect(escape(element).defaultPrevented).toBe(true)
    expect(target(element, "search").value).toBe("")
    expect(visibleKeys(element)).toHaveLength(4)
  })

  it("mirrors the checked radio into the summary and ignores other changes", async () => {
    let element
    ;({ application, element } = await mountController("website-layout-picker", Controller, html({ filter: "all" })))
    const ctrl = controllerFor(application, element, "website-layout-picker")

    const radio = element.querySelector("input[value='saas_home']")
    radio.checked = true
    radio.dispatchEvent(new Event("change", { bubbles: true }))
    expect(target(element, "summaryName").textContent).toBe("saas_home")
    expect(target(element, "summaryDescription").textContent).toBe("")
    expect(target(element, "summaryDescription").classList.contains("hidden")).toBe(true)

    element.querySelector("input[value='presence_home']").checked = true
    target(element, "search").dispatchEvent(new Event("change", { bubbles: true }))
    expect(target(element, "summaryName").textContent).toBe("saas_home")

    ctrl.select({})
    expect(target(element, "summaryName").textContent).toBe("saas_home")
  })

  it("tolerates missing optional targets, radios and checked cards", async () => {
    let element
    ;({ application, element } = await mountController(
      "website-layout-picker",
      Controller,
      html({ search: false, parts: false, description: false })
    ))
    const ctrl = controllerFor(application, element, "website-layout-picker")

    expect(visibleKeys(element)).toEqual(["presence_home", "presence_about"])
    expect(target(element, "summaryName").textContent).toBe("Presence home")
    ctrl.clearSearch(new KeyboardEvent("keydown", { key: "Escape" }))
    ctrl.reset()
    expect(visibleKeys(element)).toHaveLength(4)

    element.querySelectorAll("input[type='radio']").forEach((input) => { input.checked = false })
    element.querySelector("[data-layout-key='gallery']").querySelector("input").remove()
    ctrl.select({ target: { type: "radio" } })
    expect(target(element, "summaryName").textContent).toBe("Presence home")
  })

  it("formats counts from server templates with sensible fallbacks", async () => {
    let element
    ;({ application, element } = await mountController(
      "website-layout-picker",
      Controller,
      html({ filter: "product", formats: { one: "{count} 个版式", other: "{count} 个版式" } })
    ))
    expect(target(element, "count").textContent).toBe("1 个版式")

    ;({ application, element } = await mountController(
      "website-layout-picker",
      Controller,
      html({ filter: "product", formats: { other: "{count} layouts" } })
    ))
    expect(target(element, "count").textContent).toBe("1 layouts")

    ;({ application, element } = await mountController(
      "website-layout-picker",
      Controller,
      html({ filter: "product", formats: {} })
    ))
    expect(target(element, "count").textContent).toBe("")
  })
})
