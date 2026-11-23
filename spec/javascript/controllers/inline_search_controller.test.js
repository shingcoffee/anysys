import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/inline_search_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = `
  <div data-controller="inline-search" data-inline-search-customer-id-value="7">
    <button data-inline-search-target="trigger" data-role="trigger">Search</button>
    <div data-inline-search-target="expanded" class="hidden" data-role="expanded">
      <input data-inline-search-target="input" data-action="input->inline-search#query keydown->inline-search#navigate" data-role="input" />
      <div data-inline-search-target="results" class="hidden" data-role="results"></div>
      <div data-inline-search-target="empty" data-role="empty"></div>
    </div>
    <div data-inline-search-target="backdrop" class="hidden" data-role="backdrop"></div>
  </div>`

const q = (el, role) => el.querySelector(`[data-role='${role}']`)
const groups = [
  { label: "Pages", items: [{ label: "Home", path: "/home", type: "page" }, { label: "About", path: "/about", type: "page" }] },
  { label: "Entities", items: [{ label: "User", path: "/user", type: "entity" }] },
]

describe("inline-search controller", () => {
  let element, controller
  beforeEach(async () => {
    const m = await mountController("inline-search", Controller, html)
    element = m.element
    controller = controllerFor(m.application, element, "inline-search")
  })
  afterEach(() => vi.restoreAllMocks())

  describe("expand / collapse", () => {
    it("expand shows the expanded panel + backdrop and hides the trigger", () => {
      controller.expand()
      expect(controller.isExpanded).toBe(true)
      expect(q(element, "trigger").classList.contains("hidden")).toBe(true)
      expect(q(element, "expanded").classList.contains("hidden")).toBe(false)
      expect(q(element, "backdrop").classList.contains("hidden")).toBe(false)
    })

    it("expand is a no-op when already expanded", () => {
      controller.expand()
      const announceSpy = vi.fn()
      document.addEventListener("anysys:topbar-menu-open", announceSpy)
      controller.expand()
      expect(announceSpy).not.toHaveBeenCalled()
      document.removeEventListener("anysys:topbar-menu-open", announceSpy)
    })

    it("collapse restores the trigger and clears the input", () => {
      controller.expand()
      q(element, "input").value = "hello"
      controller.collapse()
      expect(controller.isExpanded).toBe(false)
      expect(q(element, "input").value).toBe("")
      expect(q(element, "trigger").classList.contains("hidden")).toBe(false)
    })

    it("Cmd/Ctrl+K expands; Escape collapses", () => {
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "k", metaKey: true }))
      expect(controller.isExpanded).toBe(true)
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))
      expect(controller.isExpanded).toBe(false)
    })

    it("collapse is a no-op when not expanded", () => {
      expect(controller.isExpanded).toBe(false)
      expect(() => controller.collapse()).not.toThrow()
      expect(controller.isExpanded).toBe(false)
    })
  })

  describe("query (debounced)", () => {
    it("debounces and calls fetchResults with the trimmed input after 150ms", () => {
      vi.useFakeTimers()
      try {
        const spy = vi.spyOn(controller, "fetchResults").mockImplementation(() => {})
        q(element, "input").value = "  hello  "
        controller.query()
        expect(spy).not.toHaveBeenCalled()
        vi.advanceTimersByTime(150)
        expect(spy).toHaveBeenCalledWith("hello")
      } finally {
        vi.useRealTimers()
      }
    })
  })

  describe("disconnect", () => {
    it("removes the keydown listener and clears the debounce timer", () => {
      const removeSpy = vi.spyOn(document, "removeEventListener")
      controller.disconnect()
      expect(removeSpy).toHaveBeenCalledWith("keydown", controller.boundKeydown)
      expect(removeSpy).toHaveBeenCalledWith("anysys:topbar-menu-open", controller.boundPeerOpen)
    })
  })

  describe("peer top-bar menus", () => {
    it("announces open on expand and collapses when a peer opens", () => {
      const spy = vi.fn()
      document.addEventListener("anysys:topbar-menu-open", spy)
      controller.expand()
      expect(spy).toHaveBeenCalled()
      expect(spy.mock.calls[0][0].detail.source).toBe(element)
      document.dispatchEvent(new CustomEvent("anysys:topbar-menu-open", {
        detail: { source: document.createElement("div") }
      }))
      expect(controller.isExpanded).toBe(false)
      document.removeEventListener("anysys:topbar-menu-open", spy)
    })
  })

  describe("fetchResults", () => {
    it("short-circuits queries under 2 chars without fetching", async () => {
      global.fetch = vi.fn()
      await controller.fetchResults("a")
      expect(global.fetch).not.toHaveBeenCalled()
      expect(q(element, "results").classList.contains("hidden")).toBe(true)
    })

    it("fetches and renders result groups + links", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ groups }) })
      await controller.fetchResults("ho")
      expect(global.fetch).toHaveBeenCalledWith(
        "/7/admin/search?q=ho",
        expect.objectContaining({ credentials: "same-origin" })
      )
      const results = q(element, "results")
      expect(results.classList.contains("hidden")).toBe(false)
      expect(results.querySelectorAll("a").length).toBe(3)
      expect(controller.currentItems.length).toBe(3)
    })

    it("renders empty on a non-ok response", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: false })
      await controller.fetchResults("ho")
      expect(q(element, "results").classList.contains("hidden")).toBe(true)
    })

    it("renders empty when fetch throws", async () => {
      global.fetch = vi.fn().mockRejectedValue(new Error("net"))
      await controller.fetchResults("ho")
      expect(q(element, "results").classList.contains("hidden")).toBe(true)
    })

    it("defaults to no groups when the response body omits groups", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) })
      await controller.fetchResults("ho")
      expect(q(element, "results").classList.contains("hidden")).toBe(true)
      expect(controller.currentItems.length).toBe(0)
    })
  })

  describe("renderResults empty states", () => {
    it("shows a 'No results' message escaping the query", () => {
      q(element, "input").value = "<script>"
      controller.renderResults([])
      expect(q(element, "empty").classList.contains("hidden")).toBe(false)
      expect(q(element, "empty").innerHTML).toContain("No results for")
      expect(q(element, "empty").innerHTML).toContain("&lt;script&gt;")
    })

    it("shows the prompt hint when the query is short", () => {
      q(element, "input").value = ""
      controller.renderResults([])
      expect(q(element, "empty").innerHTML).toContain("Type to search")
    })
  })

  describe("iconForType", () => {
    it("returns SVG markup for known types, null otherwise", () => {
      expect(controller.iconForType("page")).toContain("<svg")
      expect(controller.iconForType("entity")).toContain("<svg")
      expect(controller.iconForType("module")).toContain("<svg")
      expect(controller.iconForType("bogus")).toBeNull()
    })
  })

  describe("navigate", () => {
    beforeEach(async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ groups }) })
      await controller.fetchResults("ho")
    })

    it("ArrowDown/ArrowUp cycle the active index with wraparound", () => {
      controller.navigate({ key: "ArrowDown", preventDefault() {} })
      expect(controller.activeIndex).toBe(0)
      expect(controller.currentItems[0].classList.contains("bg-indigo-50")).toBe(true)
      controller.navigate({ key: "ArrowUp", preventDefault() {} })
      expect(controller.activeIndex).toBe(controller.currentItems.length - 1) // wrap
    })

    it("Enter clicks the active (or first) item", () => {
      const clicked = vi.spyOn(controller.currentItems[0], "click")
      controller.navigate({ key: "Enter", preventDefault() {} })
      expect(clicked).toHaveBeenCalled()
    })

    it("Enter clicks the active item when one is highlighted", () => {
      controller.navigate({ key: "ArrowDown", preventDefault() {} }) // activeIndex -> 0
      controller.navigate({ key: "ArrowDown", preventDefault() {} }) // activeIndex -> 1
      const clicked = vi.spyOn(controller.currentItems[1], "click")
      controller.navigate({ key: "Enter", preventDefault() {} })
      expect(clicked).toHaveBeenCalled()
    })

    it("ignores non-navigation keys", () => {
      controller.navigate({ key: "a", preventDefault() {} })
      expect(controller.activeIndex).toBe(-1)
    })
  })

  describe("navigate with no items", () => {
    it("returns early when there are no current items", () => {
      expect(controller.currentItems.length).toBe(0)
      controller.navigate({ key: "ArrowDown", preventDefault() {} })
      expect(controller.activeIndex).toBe(-1)
    })
  })
})
