import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/industry_mapping_controller"
import { mountController, controllerFor, click } from "../support/stimulus.js"

const html = `
  <div data-controller="industry-mapping" data-industry-mapping-base-url-value="/1/admin/industries">
    <div data-industry-mapping-target="group" data-group-index="0">
      <button data-group-index="0" data-action="click->industry-mapping#toggleGroup" data-role="group-toggle">G0</button>
      <span data-industry-mapping-target="groupChevron" data-group-index="0" data-role="chevron0"></span>
      <div data-industry-mapping-target="groupBody" data-group-index="0" data-role="body0">
        <button data-industry="retail" data-action="click->industry-mapping#toggleIndustry" data-role="ind-retail">Retail</button>
        <span data-industry-mapping-target="industryChevron" data-industry="retail" data-role="ind-chevron-retail"></span>
        <span data-industry-mapping-target="industryBadge" data-industry="retail" data-role="badge-retail"></span>
        <span data-industry-mapping-target="industryCount" data-industry="retail" data-role="count-retail">0</span>
        <div data-industry-mapping-target="industryPanel" data-industry="retail" class="hidden" data-role="panel-retail"></div>

        <button data-industry="tech" data-action="click->industry-mapping#toggleIndustry" data-role="ind-tech">Tech</button>
        <span data-industry-mapping-target="industryChevron" data-industry="tech" data-role="ind-chevron-tech"></span>
        <div data-industry-mapping-target="industryPanel" data-industry="tech" class="hidden" data-role="panel-tech"></div>
      </div>
    </div>
  </div>`

const q = (el, role) => el.querySelector(`[data-role='${role}']`)

describe("industry-mapping controller", () => {
  let element, controller
  beforeEach(async () => {
    const mounted = await mountController("industry-mapping", Controller, html)
    element = mounted.element
    controller = controllerFor(mounted.application, element, "industry-mapping")
  })
  afterEach(() => vi.restoreAllMocks())

  describe("group accordion", () => {
    it("toggleGroup hides/shows the group body and rotates the chevron", () => {
      const body = q(element, "body0"), chevron = q(element, "chevron0")
      expect(body.classList.contains("hidden")).toBe(false)
      click(q(element, "group-toggle"))
      expect(body.classList.contains("hidden")).toBe(true)
      expect(chevron.classList.contains("rotate-90")).toBe(false)
      click(q(element, "group-toggle"))
      expect(body.classList.contains("hidden")).toBe(false)
      expect(chevron.classList.contains("rotate-90")).toBe(true)
    })

    it("toggleGroup is a no-op when no group body matches the clicked index", async () => {
      const orphanHtml = `
        <div data-controller="industry-mapping" data-industry-mapping-base-url-value="/1/admin/industries">
          <button data-group-index="9" data-action="click->industry-mapping#toggleGroup" data-role="group-toggle">G9</button>
        </div>`
      const mounted = await mountController("industry-mapping", Controller, orphanHtml)
      expect(() => click(q(mounted.element, "group-toggle"))).not.toThrow()
    })
  })

  describe("industry accordion + lazy load", () => {
    it("expands an industry, shows a loader, then swaps in fetched cards", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: true, text: async () => "<div>CARDS</div>" })
      click(q(element, "ind-retail"))
      const panel = q(element, "panel-retail")
      expect(panel.classList.contains("hidden")).toBe(false)
      expect(q(element, "ind-chevron-retail").classList.contains("rotate-90")).toBe(true)
      await vi.waitFor(() => expect(panel.innerHTML).toContain("CARDS"))
      expect(global.fetch).toHaveBeenCalledWith(
        "/1/admin/industries/retail/template_cards",
        expect.objectContaining({ headers: { Accept: "text/html" } })
      )
    })

    it("collapses an open industry when clicked again", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: true, text: async () => "<div>CARDS</div>" })
      const panel = q(element, "panel-retail")
      click(q(element, "ind-retail"))
      await vi.waitFor(() => expect(panel.innerHTML).toContain("CARDS"))
      click(q(element, "ind-retail"))
      expect(panel.classList.contains("hidden")).toBe(true)
    })

    it("collapses the previously-expanded industry when a new one opens", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: true, text: async () => "<div>CARDS</div>" })
      click(q(element, "ind-retail"))
      await vi.waitFor(() => expect(q(element, "panel-retail").innerHTML).toContain("CARDS"))
      click(q(element, "ind-tech"))
      expect(q(element, "panel-retail").classList.contains("hidden")).toBe(true)
      expect(q(element, "panel-tech").classList.contains("hidden")).toBe(false)
    })

    it("does not re-fetch a panel that was already loaded", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: true, text: async () => "<div>CARDS</div>" })
      click(q(element, "ind-retail"))
      await vi.waitFor(() => expect(q(element, "panel-retail").innerHTML).toContain("CARDS"))
      click(q(element, "ind-retail")) // collapse
      click(q(element, "ind-retail")) // re-open — should not fetch again
      await Promise.resolve()
      expect(global.fetch).toHaveBeenCalledTimes(1)
    })

    it("renders an error message when the fetch fails", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: false })
      click(q(element, "ind-retail"))
      await vi.waitFor(() => expect(q(element, "panel-retail").innerHTML).toContain("Failed to load templates"))
    })

    it("toggleIndustry is a no-op when no panel matches the clicked industry", async () => {
      const orphanHtml = `
        <div data-controller="industry-mapping" data-industry-mapping-base-url-value="/1/admin/industries">
          <button data-industry="ghost" data-action="click->industry-mapping#toggleIndustry" data-role="ind-ghost">Ghost</button>
        </div>`
      const mounted = await mountController("industry-mapping", Controller, orphanHtml)
      global.fetch = vi.fn()
      expect(() => click(q(mounted.element, "ind-ghost"))).not.toThrow()
      expect(global.fetch).not.toHaveBeenCalled()
    })
  })

  describe("badge counts", () => {
    it("updateBadgeCount sets count text and toggles active/inactive badge classes", () => {
      controller.updateBadgeCount("retail", 3)
      expect(q(element, "count-retail").textContent).toBe("3")
      const badge = q(element, "badge-retail")
      expect(badge.classList.contains("bg-indigo-100")).toBe(true)
      expect(badge.classList.contains("text-indigo-700")).toBe(true)

      controller.updateBadgeCount("retail", 0)
      expect(badge.classList.contains("bg-gray-100")).toBe(true)
      expect(badge.classList.contains("text-gray-400")).toBe(true)
    })

    it("handleCountChanged reads the event detail and updates the badge", () => {
      controller.handleCountChanged({ detail: { industry: "retail", count: 5 } })
      expect(q(element, "count-retail").textContent).toBe("5")
    })
  })
})
