import { describe, it, expect, beforeEach, vi } from "vitest"
import { Controller as StimulusController } from "@hotwired/stimulus"
import Controller from "controllers/property_palette_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

const props = [
  { name: "First Name", name_slug: "first_name", type: "string" },
  { name: "Age", name_slug: "age", type: "integer" },
]

const html = (json = "[]") => `
  <div data-controller="property-palette" data-property-palette-entity-properties-value='${json}'>
    <input data-property-palette-target="searchInput" data-action="input->property-palette#searchProperties">
    <div data-property-palette-target="propertiesList"></div>
  </div>`

const list = (el) => el.querySelector("[data-property-palette-target='propertiesList']")
const items = (el) => el.querySelectorAll(".property-item")

describe("property-palette controller", () => {
  describe("initial render", () => {
    it("renders a placeholder when there are no properties", async () => {
      const { element } = await mountController("property-palette", Controller, html("[]"))
      expect(items(element).length).toBe(0)
      expect(list(element).textContent).toContain("Select an entity to see properties")
    })

    it("renders one draggable item per property with data attributes", async () => {
      const { element } = await mountController("property-palette", Controller, html(JSON.stringify(props)))
      const rendered = items(element)
      expect(rendered.length).toBe(2)
      expect(rendered[0].dataset.propertySlug).toBe("first_name")
      expect(rendered[0].dataset.propertyName).toBe("First Name")
      expect(rendered[0].dataset.propertyType).toBe("string")
      expect(rendered[0].draggable).toBe(true)
    })
  })

  describe("updateProperties", () => {
    it("replaces the rendered list", async () => {
      const { application, element } = await mountController("property-palette", Controller, html("[]"))
      const ctrl = controllerFor(application, element, "property-palette")
      ctrl.updateProperties(props)
      expect(items(element).length).toBe(2)
    })
  })

  describe("search", () => {
    let application, element, ctrl
    beforeEach(async () => {
      ;({ application, element } = await mountController("property-palette", Controller, html(JSON.stringify(props))))
      ctrl = controllerFor(application, element, "property-palette")
    })

    it("filters by name (case-insensitive)", () => {
      ctrl.searchProperties({ target: { value: "age" } })
      expect(items(element).length).toBe(1)
      expect(items(element)[0].dataset.propertySlug).toBe("age")
    })

    it("filters by slug", () => {
      ctrl.searchProperties({ target: { value: "first_" } })
      expect(items(element).length).toBe(1)
      expect(items(element)[0].dataset.propertyName).toBe("First Name")
    })

    it("empty search re-renders the full list", () => {
      ctrl.searchProperties({ target: { value: "age" } })
      ctrl.searchProperties({ target: { value: "  " } })
      expect(items(element).length).toBe(2)
    })
  })

  describe("html escaping", () => {
    it("escapes property names to prevent injection", async () => {
      const { application, element } = await mountController("property-palette", Controller, html("[]"))
      const ctrl = controllerFor(application, element, "property-palette")
      ctrl.updateProperties([{ name: "<img src=x>", name_slug: "x", type: "string" }])
      // The raw name span text is escaped; no <img> element is injected.
      expect(list(element).querySelector("img")).toBeNull()
      expect(list(element).innerHTML).toContain("&lt;img")
    })
  })

  describe("drag handlers", () => {
    it("dragStart writes JSON to dataTransfer and dims the element", async () => {
      const { application, element } = await mountController("property-palette", Controller, html(JSON.stringify(props)))
      const ctrl = controllerFor(application, element, "property-palette")
      const item = items(element)[0]
      const store = {}
      const dt = { setData: (t, v) => (store[t] = v), effectAllowed: null }
      ctrl.dragStart({ target: item, dataTransfer: dt })
      expect(JSON.parse(store["application/json"]).propertySlug).toBe("first_name")
      expect(dt.effectAllowed).toBe("copy")
      expect(item.style.opacity).toBe("0.5")
    })

    it("dragEnd resets opacity/cursor", async () => {
      const { application, element } = await mountController("property-palette", Controller, html(JSON.stringify(props)))
      const ctrl = controllerFor(application, element, "property-palette")
      const item = items(element)[0]
      item.style.opacity = "0.5"
      ctrl.dragEnd({ target: item })
      expect(item.style.opacity).toBe("")
    })
  })

  describe("addToCanvas", () => {
    it("is a safe no-op when no page-canvas controller is present", async () => {
      const { application, element } = await mountController("property-palette", Controller, html(JSON.stringify(props)))
      const ctrl = controllerFor(application, element, "property-palette")
      const item = items(element)[0]
      expect(() => ctrl.addToCanvas({ preventDefault() {}, target: item })).not.toThrow()
    })

    it("is a no-op when the target is not a property item", async () => {
      const { application, element } = await mountController("property-palette", Controller, html(JSON.stringify(props)))
      const ctrl = controllerFor(application, element, "property-palette")
      const stray = document.createElement("div")
      expect(() => ctrl.addToCanvas({ preventDefault() {}, target: stray })).not.toThrow()
    })

    it("delegates to the canvas controller and flashes click feedback", async () => {
      const addField = vi.fn()
      class Canvas extends StimulusController {
        addFieldFromPalette(...a) { addField(...a) }
      }
      const { application, element } = await mountController("property-palette", Controller, html(JSON.stringify(props)))
      const ctrl = controllerFor(application, element, "property-palette")
      const canvasEl = document.createElement("div")
      canvasEl.setAttribute("data-controller", "page-canvas")
      document.body.appendChild(canvasEl)
      application.register("page-canvas", Canvas)
      await tick()

      const item = items(element)[0]
      vi.useFakeTimers()
      try {
        ctrl.addToCanvas({ preventDefault() {}, target: item })
        expect(addField).toHaveBeenCalledWith(expect.objectContaining({ propertySlug: "first_name" }))
        expect(item.classList.contains("ring-2")).toBe(true)
        vi.advanceTimersByTime(150)
        expect(item.classList.contains("ring-2")).toBe(false)
      } finally {
        vi.useRealTimers()
      }
    })
  })

  describe("edge branches", () => {
    it("dragStart is a no-op when the target is not a property item", async () => {
      const { application, element } = await mountController("property-palette", Controller, html(JSON.stringify(props)))
      const ctrl = controllerFor(application, element, "property-palette")
      const stray = document.createElement("div")
      expect(() => ctrl.dragStart({ target: stray, dataTransfer: { setData() {} } })).not.toThrow()
    })

    it("_renderProperties is a safe no-op without a propertiesList target", async () => {
      const bare = `<div data-controller="property-palette" data-property-palette-entity-properties-value='[]'></div>`
      const { application, element } = await mountController("property-palette", Controller, bare)
      const ctrl = controllerFor(application, element, "property-palette")
      expect(ctrl.hasPropertiesListTarget).toBe(false)
      expect(() => ctrl.updateProperties(props)).not.toThrow()
    })

    // connect() and entityPropertiesValueChanged() defensively fall back to []
    // when the value getter yields a nullish result. Stimulus guarantees an Array
    // (it throws on a "null" attribute), so we exercise this guard by stubbing the
    // getter to return null, which is exactly the condition the `|| []` protects.
    it("connect falls back to an empty list when the value getter is nullish", async () => {
      const { application, element } = await mountController("property-palette", Controller, html("[]"))
      const ctrl = controllerFor(application, element, "property-palette")
      Object.defineProperty(ctrl, "entityPropertiesValue", { configurable: true, get: () => null })
      ctrl.connect()
      expect(ctrl.properties).toEqual([])
      expect(list(element).textContent).toContain("Select an entity to see properties")
    })

    it("entityPropertiesValueChanged falls back to an empty list when the value getter is nullish", async () => {
      const { application, element } = await mountController("property-palette", Controller, html("[]"))
      const ctrl = controllerFor(application, element, "property-palette")
      Object.defineProperty(ctrl, "entityPropertiesValue", { configurable: true, get: () => null })
      ctrl.entityPropertiesValueChanged()
      expect(ctrl.properties).toEqual([])
    })
  })
})
