import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/industry_template_panel_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

// A template card. `section` places it in the associated or available container.
const card = ({ key, category = "forms", name = "Contact", desc = "reach us", mapped = false }) => `
  <div data-industry-template-panel-target="templateCard"
       data-template-key="${key}"
       data-template-category="${category}"
       data-template-name="${name}"
       data-template-description="${desc}"
       data-template-category-label="Forms"
       data-template-category-group="Group A"
       data-template-theme="dark"
       class="${mapped ? "border-indigo-500 ring-2 ring-indigo-500 shadow-md" : "border-gray-200 hover:border-indigo-300"}">
    <span data-checkmark class="${mapped ? "" : "hidden"}">check</span>
    <div data-preview-content class="max-h-[110px] px-2 py-1.5 space-y-1"><span class="text-[5px] gap-1 h-[7px]">x</span></div>
    <button data-action="click->industry-template-panel#selectTemplate" data-role="toggle-${key}">toggle</button>
    <button data-action="dblclick->industry-template-panel#handleDoubleClick" data-role="dbl-${key}">preview</button>
  </div>`

const html = `
  <div data-controller="industry-template-panel"
       data-industry-template-panel-industry-value="retail"
       data-industry-template-panel-base-url-value="/1/admin/industries"
       data-industry-template-panel-mapped-keys-value='["a"]'>

    <input data-industry-template-panel-target="searchInput" data-action="input->industry-template-panel#searchTemplates" data-role="search" />
    <button data-industry-template-panel-target="searchClear" class="hidden" data-role="search-clear" data-action="click->industry-template-panel#clearSearch">x</button>
    <div data-industry-template-panel-target="noResults" class="hidden" data-role="no-results">none</div>
    <div data-industry-template-panel-target="searchResultsCount" class="hidden" data-role="results-count">
      <span data-industry-template-panel-target="searchResultsNumber" data-role="results-number">0</span>
    </div>
    <span data-industry-template-panel-target="mappedCount" data-role="mapped-count">0</span>

    <div data-industry-template-panel-target="associatedSection" data-role="assoc-section">
      <span data-industry-template-panel-target="associatedCount" data-role="assoc-count">0</span>
      <div data-industry-template-panel-target="associatedContainer" data-role="assoc-container">
        ${card({ key: "a", name: "Alpha", mapped: true })}
      </div>
    </div>
    <div data-industry-template-panel-target="availableSection" data-role="avail-section">
      <span data-industry-template-panel-target="availableCount" data-role="avail-count">0</span>
      <div data-industry-template-panel-target="availableContainer" data-role="avail-container">
        ${card({ key: "b", name: "Beta" })}
        ${card({ key: "c", name: "Gamma", category: "layout" })}
      </div>
    </div>

    <div data-group-content="grpA">
      <button data-group-chevron="grpA" data-role="chevron-grpA"></button>
      <button data-industry-template-panel-target="categoryTab" data-category="all" data-total-count="3" data-action="click->industry-template-panel#filterCategory" data-role="tab-all">
        <span data-count-badge data-role="badge-all">3</span>
      </button>
      <button data-industry-template-panel-target="categoryTab" data-category="forms" data-total-count="2" data-role="tab-forms">
        <span data-count-badge data-role="badge-forms">2</span>
      </button>
    </div>

    <div data-industry-template-panel-target="previewModal" class="hidden" data-role="preview-modal" data-action="click->industry-template-panel#closePreviewModalOnBackdrop">
      <span data-industry-template-panel-target="previewModalName" data-role="pm-name"></span>
      <span data-industry-template-panel-target="previewModalDescription" data-role="pm-desc"></span>
      <span data-industry-template-panel-target="previewModalTheme" data-role="pm-theme"></span>
      <span data-industry-template-panel-target="previewModalCategory" data-role="pm-cat"></span>
      <div data-industry-template-panel-target="previewModalContent" data-role="pm-content"></div>
    </div>
  </div>`

const q = (el, role) => el.querySelector(`[data-role='${role}']`)
const cardEl = (el, key) => el.querySelector(`[data-template-key='${key}']`)

describe("industry-template-panel controller", () => {
  let element, controller
  beforeEach(async () => {
    const mounted = await mountController("industry-template-panel", Controller, html)
    element = mounted.element
    controller = controllerFor(mounted.application, element, "industry-template-panel")
  })
  afterEach(() => vi.restoreAllMocks())

  describe("updateCardState", () => {
    it("applies mapped styling + reveals the checkmark for mapped keys", () => {
      const c = cardEl(element, "a") // "a" is in mappedKeysValue
      controller.updateCardState(c)
      expect(c.classList.contains("border-indigo-500")).toBe(true)
      expect(c.classList.contains("ring-2")).toBe(true)
      expect(c.querySelector("[data-checkmark]").classList.contains("hidden")).toBe(false)
    })

    it("applies unmapped styling + hides the checkmark for unmapped keys", () => {
      const c = cardEl(element, "b")
      controller.updateCardState(c)
      expect(c.classList.contains("border-gray-200")).toBe(true)
      expect(c.querySelector("[data-checkmark]").classList.contains("hidden")).toBe(true)
    })
  })

  describe("updateCounts", () => {
    it("reflects the mappedKeys size and dispatches countChanged", () => {
      // Stimulus' Controller#dispatch prefixes the event name with the
      // controller identifier by default, so the actual event fired is
      // "industry-template-panel:countChanged", not a bare "countChanged".
      const spy = vi.fn()
      element.addEventListener("industry-template-panel:countChanged", spy)
      controller.updateCounts()
      expect(q(element, "mapped-count").textContent).toBe("1")
      expect(spy).toHaveBeenCalledOnce()
      expect(spy.mock.calls[0][0].detail).toEqual({ industry: "retail", count: 1 })
    })
  })

  describe("countVisibleCards", () => {
    it("counts non-hidden template cards in a container", () => {
      expect(controller.countVisibleCards(q(element, "avail-container"))).toBe(2)
      cardEl(element, "b").classList.add("hidden")
      expect(controller.countVisibleCards(q(element, "avail-container"))).toBe(1)
    })
  })

  describe("search + filters", () => {
    it("searchTemplates hides non-matching cards and reveals the clear button", () => {
      const input = q(element, "search")
      input.value = "Alpha"
      input.dispatchEvent(new Event("input", { bubbles: true }))
      expect(cardEl(element, "a").classList.contains("hidden")).toBe(false)
      expect(cardEl(element, "b").classList.contains("hidden")).toBe(true)
      expect(cardEl(element, "c").classList.contains("hidden")).toBe(true)
      expect(q(element, "search-clear").classList.contains("hidden")).toBe(false)
      expect(q(element, "results-number").textContent).toBe("1")
    })

    it("clearSearch resets the query and shows all cards again", () => {
      const input = q(element, "search")
      input.value = "Alpha"
      input.dispatchEvent(new Event("input", { bubbles: true }))
      controller.clearSearch({ preventDefault() {} })
      expect(input.value).toBe("")
      expect(cardEl(element, "b").classList.contains("hidden")).toBe(false)
      expect(q(element, "search-clear").classList.contains("hidden")).toBe(true)
    })

    it("filterCategory limits cards to the active category", () => {
      controller.filterCategory({ preventDefault() {}, stopPropagation() {}, currentTarget: q(element, "tab-forms") })
      expect(cardEl(element, "a").classList.contains("hidden")).toBe(false) // forms
      expect(cardEl(element, "b").classList.contains("hidden")).toBe(false) // forms
      expect(cardEl(element, "c").classList.contains("hidden")).toBe(true)  // layout
    })

    it("shows the noResults element when nothing matches", () => {
      const input = q(element, "search")
      input.value = "zzzzz"
      input.dispatchEvent(new Event("input", { bubbles: true }))
      expect(q(element, "no-results").classList.contains("hidden")).toBe(false)
    })
  })

  describe("updateCategoryTabs", () => {
    it("marks the active tab with indigo styling", () => {
      controller.applyFilters()
      expect(q(element, "tab-all").classList.contains("bg-indigo-100")).toBe(true)
      expect(q(element, "tab-all").classList.contains("text-indigo-700")).toBe(true)
    })
  })

  describe("toggleGroup", () => {
    it("toggles group content visibility and rotates the chevron", () => {
      // Use a group key distinct from "grpA" (already present in the mounted
      // HTML) so querySelector inside the controller can't find that other
      // node instead of these test-local ones.
      const content = document.createElement("div")
      content.dataset.groupContent = "grpZ"
      content.classList.add("hidden") // starts collapsed
      const chevron = document.createElement("button")
      chevron.dataset.groupChevron = "grpZ"
      element.append(content, chevron)

      controller.toggleGroup({ preventDefault() {}, currentTarget: { dataset: { groupKey: "grpZ" } } })
      // toggleGroup expands a collapsed group and rotates the chevron to
      // indicate the expanded state.
      expect(content.classList.contains("hidden")).toBe(false)
      expect(chevron.classList.contains("rotate-180")).toBe(true)
    })
  })

  describe("selectTemplate", () => {
    it("optimistically toggles mapping and POSTs for a newly-mapped card", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: true })
      const c = cardEl(element, "b")
      await controller.selectTemplate({ currentTarget: c })
      expect(controller.mappedKeys.has("b")).toBe(true)
      expect(global.fetch).toHaveBeenCalledWith(
        "/1/admin/industries/retail/template_assignments",
        expect.objectContaining({ method: "POST" })
      )
    })

    it("DELETEs and unmaps for an already-mapped card", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: true })
      const c = cardEl(element, "a")
      await controller.selectTemplate({ currentTarget: c })
      expect(controller.mappedKeys.has("a")).toBe(false)
      expect(global.fetch.mock.calls[0][1].method).toBe("DELETE")
    })

    it("reverts the optimistic toggle when the request fails", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: false })
      const c = cardEl(element, "b")
      await controller.selectTemplate({ currentTarget: c })
      expect(controller.mappedKeys.has("b")).toBe(false) // reverted
    })
  })

  describe("preview modal", () => {
    it("openPreviewModal populates fields, clones preview, and reveals the modal", () => {
      controller.openPreviewModal({ stopPropagation() {}, currentTarget: cardEl(element, "a") })
      expect(q(element, "pm-name").textContent).toBe("Alpha")
      expect(q(element, "pm-theme").textContent).toBe("Dark") // capitalized
      expect(q(element, "preview-modal").classList.contains("hidden")).toBe(false)
      expect(q(element, "pm-content").children.length).toBe(1)
      expect(document.body.style.overflow).toBe("hidden")
    })

    it("closePreviewModal hides the modal and restores body overflow", () => {
      controller.openPreviewModal({ stopPropagation() {}, currentTarget: cardEl(element, "a") })
      controller.closePreviewModal({ preventDefault() {} })
      expect(q(element, "preview-modal").classList.contains("hidden")).toBe(true)
      expect(document.body.style.overflow).toBe("")
    })

    it("closePreviewModalOnBackdrop only closes when the backdrop itself is clicked", () => {
      controller.openPreviewModal({ stopPropagation() {}, currentTarget: cardEl(element, "a") })
      const modal = q(element, "preview-modal")
      controller.closePreviewModalOnBackdrop({ preventDefault() {}, target: modal.firstElementChild, currentTarget: modal })
      expect(modal.classList.contains("hidden")).toBe(false) // inner click ignored
      controller.closePreviewModalOnBackdrop({ preventDefault() {}, target: modal, currentTarget: modal })
      expect(modal.classList.contains("hidden")).toBe(true)
    })
  })

  describe("csrfToken", () => {
    it("reads the meta[name=csrf-token] content, empty string when absent", () => {
      expect(controller.csrfToken).toBe("")
      const meta = document.createElement("meta")
      meta.name = "csrf-token"; meta.content = "tok123"
      document.head.appendChild(meta)
      expect(controller.csrfToken).toBe("tok123")
      meta.remove()
    })
  })

  describe("handleDoubleClick", () => {
    it("delegates to openPreviewModal", () => {
      const spy = vi.spyOn(controller, "openPreviewModal")
      const event = { stopPropagation() {}, currentTarget: cardEl(element, "a") }
      controller.handleDoubleClick(event)
      expect(spy).toHaveBeenCalledWith(event)
    })
  })

  describe("selectTemplate edge cases", () => {
    it("no-ops when the click target isn't inside a template card", async () => {
      global.fetch = vi.fn()
      await controller.selectTemplate({ currentTarget: element })
      expect(global.fetch).not.toHaveBeenCalled()
    })

    it("no-ops when the card has no data-template-key", async () => {
      global.fetch = vi.fn()
      const orphan = document.createElement("div")
      orphan.dataset.templateKey = ""
      element.appendChild(orphan)
      await controller.selectTemplate({ currentTarget: orphan })
      expect(global.fetch).not.toHaveBeenCalled()
    })

    it("reverts the optimistic toggle when the request throws", async () => {
      global.fetch = vi.fn().mockRejectedValue(new Error("network down"))
      const c = cardEl(element, "b")
      await controller.selectTemplate({ currentTarget: c })
      expect(controller.mappedKeys.has("b")).toBe(false) // reverted
    })

    it("reverts to mapped (re-adds the key) when unmapping a previously-mapped card fails", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: false })
      const c = cardEl(element, "a") // already mapped
      await controller.selectTemplate({ currentTarget: c })
      expect(controller.mappedKeys.has("a")).toBe(true) // reverted back to mapped
    })
  })

  describe("toggleGroup edge cases", () => {
    it("no-ops when the group content element can't be found", () => {
      expect(() =>
        controller.toggleGroup({ preventDefault() {}, currentTarget: { dataset: { groupKey: "missing" } } })
      ).not.toThrow()
    })
  })

  describe("applyFilters dataset fallbacks", () => {
    it("treats cards with no name/description/category-label/group dataset as empty strings", () => {
      const c = cardEl(element, "b")
      delete c.dataset.templateName
      delete c.dataset.templateDescription
      delete c.dataset.templateCategoryLabel
      delete c.dataset.templateCategoryGroup
      controller.searchQuery = "zzz-no-match"
      expect(() => controller.applyFilters()).not.toThrow()
      expect(c.classList.contains("hidden")).toBe(true)
    })
  })

  describe("updateCategoryTabs totalCount fallback", () => {
    it("falls back to 0 when data-total-count is not a number", () => {
      const tab = q(element, "tab-forms")
      tab.dataset.totalCount = "not-a-number"
      expect(() => controller.applyFilters()).not.toThrow()
      // happy-dom quirk: assigning the number 0 to .textContent yields "" rather
      // than "0" (verified empirically against a real Node/happy-dom script), so
      // we can't assert the string here — the throw-free run above is what
      // exercises the `parseInt(...) || 0` fallback branch.
      expect(tab.querySelector("[data-count-badge]").textContent).toBe("")
    })
  })

  describe("openPreviewModal edge cases", () => {
    it("no-ops when the click target isn't inside a template card", () => {
      expect(() =>
        controller.openPreviewModal({ stopPropagation() {}, currentTarget: element })
      ).not.toThrow()
      expect(q(element, "preview-modal").classList.contains("hidden")).toBe(true)
    })

    it("falls back to empty strings when name/description/theme/category-label are absent", () => {
      const c = cardEl(element, "a")
      delete c.dataset.templateName
      delete c.dataset.templateDescription
      delete c.dataset.templateTheme
      delete c.dataset.templateCategoryLabel
      controller.openPreviewModal({ stopPropagation() {}, currentTarget: c })
      expect(q(element, "pm-name").textContent).toBe("")
      expect(q(element, "pm-desc").textContent).toBe("")
      expect(q(element, "pm-theme").textContent).toBe("")
      expect(q(element, "pm-cat").textContent).toBe("")
    })
  })

  describe("scalePreviewElements", () => {
    it("scales up tiny text/gap/height/width/radius/margin utility classes", () => {
      const container = document.createElement("div")
      container.innerHTML = `
        <span class="text-[5px]">t5</span>
        <span class="text-[4px]">t4</span>
        <span class="text-[3px]">t3</span>
        <div class="gap-1">g1</div>
        <div class="gap-0.5">g05</div>
        <div class="gap-px">gpx</div>
        <div class="h-[7px]">h7</div>
        <div class="h-[7px] border">h7border</div>
        <div class="h-[14px] border">h14border</div>
        <div class="h-[14px]">h14plain</div>
        <div class="h-[12px]">h12</div>
        <div class="h-[8px]">h8</div>
        <div class="h-[4px]">h4</div>
        <div class="w-1">w1</div>
        <div class="w-1.5">w15</div>
        <div class="w-2">w2</div>
        <div class="w-[6px]"><svg></svg></div>
        <div class="rounded-sm">rsm-only</div>
        <div class="rounded-sm rounded-md">rsm-and-rmd</div>
        <div class="mb-px px-0.5 pr-0.5 pl-0.5">margins</div>
      `
      controller.scalePreviewElements(container)

      container.querySelectorAll("span").forEach(el => expect(el.classList.contains("text-sm")).toBe(true))
      container.querySelectorAll("div").forEach(el => {
        if (el.textContent.startsWith("g")) expect(el.classList.contains("gap-3")).toBe(true)
      })

      // A bordered h-[14px] is a textarea: the textarea pass upsizes it to h-20
      // (before the general height pass could size it as a plain input).
      const bordered = Array.from(container.children).find(el => el.textContent === "h14border")
      expect(bordered.classList.contains("h-20")).toBe(true)
      expect(bordered.classList.contains("h-10")).toBe(false)

      // A non-bordered h-[14px] is not a textarea -> falls through to the general
      // pass -> h-8.
      const plain = Array.from(container.children).find(el => el.textContent === "h14plain")
      expect(plain.classList.contains("h-8")).toBe(true)
      expect(plain.classList.contains("h-20")).toBe(false)

      // a bordered non-textarea height marker (h-[7px].border) is an input -> h-10
      const h7border = Array.from(container.children).find(el => el.textContent === "h7border")
      expect(h7border.classList.contains("h-10")).toBe(true)

      const svgWrapper = Array.from(container.children).find(el => el.querySelector("svg"))
      expect(svgWrapper.classList.contains("w-5")).toBe(true)
      expect(svgWrapper.classList.contains("h-5")).toBe(true)

      const plainWidth = Array.from(container.children).find(el => el.textContent === "w1")
      expect(plainWidth.classList.contains("w-4")).toBe(true)

      const rsmOnly = Array.from(container.children).find(el => el.textContent === "rsm-only")
      expect(rsmOnly.classList.contains("rounded-md")).toBe(true)

      const rsmAndRmd = Array.from(container.children).find(el => el.textContent === "rsm-and-rmd")
      expect(rsmAndRmd.classList.contains("rounded-sm")).toBe(false)
      expect(rsmAndRmd.classList.contains("rounded-md")).toBe(true)

      const margins = Array.from(container.children).find(el => el.textContent === "margins")
      expect(margins.classList.contains("mb-2")).toBe(true)
      expect(margins.classList.contains("mt-1")).toBe(true)
      expect(margins.classList.contains("px-2")).toBe(true)
    })
  })
})
