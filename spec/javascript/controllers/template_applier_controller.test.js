import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { Controller as StimulusController } from "@hotwired/stimulus"
import Controller from "controllers/template_applier_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

// A template card with the data-* attributes the controller reads.
function card({ key, name, category, categoryLabel = "", group = "", theme = "modern" }) {
  return `
    <div data-template-applier-target="templateCard"
         data-template-key="${key}" data-template-name="${name}"
         data-template-description="${name} desc" data-template-theme="${theme}"
         data-template-category="${category}" data-template-category-label="${categoryLabel}"
         data-template-category-group="${group}" class="border-gray-200">
      <div data-preview-content class="max-h-[110px] px-2 py-1.5 space-y-1">
        <span class="text-[5px]">x</span>
      </div>
      <div data-checkmark class="hidden"></div>
      <div data-template-applier-target="applySection" class="hidden">
        <button data-template-applier-target="applyButton">Apply</button>
      </div>
    </div>`
}

function tab(cat, total) {
  return `<button data-template-applier-target="categoryTab" data-category="${cat}" data-total-count="${total}">
            <span data-count-badge>${total}</span></button>`
}

const html = `
  <div data-controller="template-applier"
       data-template-applier-page-id-value="5"
       data-template-applier-customer-id-value="42">
    <input data-template-applier-target="searchInput">
    <div>${tab("all", 3)}${tab("forms", 2)}${tab("surveys", 1)}</div>
    <div data-template-applier-target="templatesGrid">
      ${card({ key: "t1", name: "Contact", category: "forms", categoryLabel: "Forms" })}
      ${card({ key: "t2", name: "Signup", category: "forms", categoryLabel: "Forms" })}
      ${card({ key: "t3", name: "Poll", category: "surveys", categoryLabel: "Surveys" })}
    </div>
    <div data-template-applier-target="noResults" class="hidden"></div>
    <div data-template-applier-target="searchResultsCount" class="hidden">
      <span data-template-applier-target="searchResultsNumber"></span>
    </div>
    <div data-template-applier-target="previewModal" class="hidden">
      <span data-template-applier-target="previewModalName"></span>
      <span data-template-applier-target="previewModalDescription"></span>
      <span data-template-applier-target="previewModalTheme"></span>
      <div data-template-applier-target="previewModalContent"></div>
    </div>
  </div>`

async function mount() {
  const { application, element } = await mountController("template-applier", Controller, html)
  await tick()
  const ctrl = controllerFor(application, element, "template-applier")
  return { application, element, ctrl }
}

const cards = (el) => [...el.querySelectorAll('[data-template-applier-target="templateCard"]')]
const cardByKey = (el, k) => cards(el).find(c => c.dataset.templateKey === k)
const cur = (e) => ({ currentTarget: e, preventDefault() {}, stopPropagation() {} })

afterEach(() => { document.body.style.overflow = ""; vi.unstubAllGlobals() })

describe("template-applier — search & category filters", () => {
  let element, ctrl
  beforeEach(async () => { ({ element, ctrl } = await mount()) })

  it("searchTemplates hides non-matching cards and shows the results count", () => {
    ctrl.searchTemplates({ target: { value: "Poll" } })
    expect(cardByKey(element, "t3").classList.contains("hidden")).toBe(false)
    expect(cardByKey(element, "t1").classList.contains("hidden")).toBe(true)
    const count = element.querySelector('[data-template-applier-target="searchResultsCount"]')
    expect(count.classList.contains("hidden")).toBe(false)
    expect(element.querySelector('[data-template-applier-target="searchResultsNumber"]').textContent).toBe("1")
  })

  it("filterCategory restricts to a single category", () => {
    ctrl.filterCategory(cur({ dataset: { category: "surveys" } }))
    expect(cardByKey(element, "t3").classList.contains("hidden")).toBe(false)
    expect(cardByKey(element, "t1").classList.contains("hidden")).toBe(true)
  })

  it("shows the no-results message when nothing matches", () => {
    ctrl.searchTemplates({ target: { value: "zzz" } })
    expect(element.querySelector('[data-template-applier-target="noResults"]').classList.contains("hidden")).toBe(false)
    expect(element.querySelector('[data-template-applier-target="templatesGrid"]').classList.contains("hidden")).toBe(true)
  })

  it("updateCategoryTabs highlights the active tab and shows total counts when not searching", () => {
    ctrl.filterCategory(cur({ dataset: { category: "forms" } }))
    const formsTab = element.querySelector('[data-category="forms"]')
    expect(formsTab.classList.contains("bg-indigo-100")).toBe(true)
    expect(formsTab.querySelector("[data-count-badge]").textContent).toBe("2")
  })
})

describe("template-applier — selection", () => {
  it("selectTemplate marks the card, reveals apply section + checkmark and records the key", async () => {
    const { element, ctrl } = await mount()
    const c = cardByKey(element, "t2")
    ctrl.selectTemplate(cur(c))
    expect(c.classList.contains("border-indigo-500")).toBe(true)
    expect(c.querySelector('[data-template-applier-target="applySection"]').classList.contains("hidden")).toBe(false)
    expect(c.querySelector("[data-checkmark]").classList.contains("hidden")).toBe(false)
    expect(ctrl.selectedTemplate).toBe("t2")
  })

  it("selecting a different card deselects the previous one", async () => {
    const { element, ctrl } = await mount()
    ctrl.selectTemplate(cur(cardByKey(element, "t1")))
    ctrl.selectTemplate(cur(cardByKey(element, "t2")))
    expect(cardByKey(element, "t1").classList.contains("border-indigo-500")).toBe(false)
    expect(cardByKey(element, "t1").querySelector("[data-checkmark]").classList.contains("hidden")).toBe(true)
  })
})

describe("template-applier — preview modal", () => {
  it("openPreviewModal clones the preview, scales it and fills the modal header", async () => {
    const { element, ctrl } = await mount()
    const c = cardByKey(element, "t1")
    ctrl.openPreviewModal(cur(c.querySelector("[data-preview-content]")))
    expect(element.querySelector('[data-template-applier-target="previewModalName"]').textContent).toBe("Contact")
    expect(element.querySelector('[data-template-applier-target="previewModalTheme"]').textContent).toBe("Modern")
    const clone = element.querySelector('[data-template-applier-target="previewModalContent"] [data-preview-content]')
    expect(clone).toBeTruthy()
    expect(clone.classList.contains("px-8")).toBe(true)
    expect(clone.classList.contains("max-h-[110px]")).toBe(false)
    // scaled inner text element
    expect(clone.querySelector(".text-sm")).toBeTruthy()
    expect(element.querySelector('[data-template-applier-target="previewModal"]').classList.contains("hidden")).toBe(false)
    expect(document.body.style.overflow).toBe("hidden")
  })

  it("closePreviewModal hides the modal and restores scroll", async () => {
    const { element, ctrl } = await mount()
    ctrl.openPreviewModal(cur(cardByKey(element, "t1").querySelector("[data-preview-content]")))
    ctrl.closePreviewModal({ preventDefault() {} })
    expect(element.querySelector('[data-template-applier-target="previewModal"]').classList.contains("hidden")).toBe(true)
    expect(document.body.style.overflow).toBe("")
  })

  it("closePreviewModalOnBackdrop only closes on a backdrop click", async () => {
    const { element, ctrl } = await mount()
    const modal = element.querySelector('[data-template-applier-target="previewModal"]')
    modal.classList.remove("hidden")
    ctrl.closePreviewModalOnBackdrop({ target: document.createElement("div"), currentTarget: modal })
    expect(modal.classList.contains("hidden")).toBe(false) // inner click ignored
    ctrl.closePreviewModalOnBackdrop({ target: modal, currentTarget: modal, preventDefault() {} })
    expect(modal.classList.contains("hidden")).toBe(true)
  })
})

describe("template-applier — applyTemplate guards", () => {
  it("returns without a selected template", async () => {
    const { ctrl } = await mount()
    const fetchSpy = vi.fn()
    vi.stubGlobal("fetch", fetchSpy)
    await ctrl.applyTemplate(cur(document.createElement("button")))
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it("alerts when the page-builder controller is missing", async () => {
    const { element, ctrl } = await mount()
    ctrl.selectTemplate(cur(cardByKey(element, "t1")))
    const alertSpy = vi.fn()
    vi.stubGlobal("alert", alertSpy)
    await ctrl.applyTemplate(cur(document.createElement("button")))
    expect(alertSpy).toHaveBeenCalledWith("Page builder not found.")
  })
})

describe("template-applier — handleDoubleClick", () => {
  it("delegates to openPreviewModal", async () => {
    const { element, ctrl } = await mount()
    const c = cardByKey(element, "t1")
    ctrl.handleDoubleClick(cur(c.querySelector("[data-preview-content]")))
    expect(element.querySelector('[data-template-applier-target="previewModalName"]').textContent).toBe("Contact")
  })
})

describe("template-applier — openPreviewModal edge cases", () => {
  it("returns early when the event target has no ancestor card", async () => {
    const { ctrl } = await mount()
    const orphan = document.createElement("div")
    document.body.appendChild(orphan)
    // Should not throw despite closest() finding nothing.
    expect(() => ctrl.openPreviewModal(cur(orphan))).not.toThrow()
  })

  it("falls back to templateKey/empty-string/empty-string when name/description/theme are unset but the modal targets exist", async () => {
    const bareCardHtml = `
      <div data-controller="template-applier">
        <div data-template-applier-target="templateCard" data-template-key="k9" class="border-gray-200">
          <div data-preview-content></div>
        </div>
        <div data-template-applier-target="previewModal" class="hidden">
          <span data-template-applier-target="previewModalName"></span>
          <span data-template-applier-target="previewModalDescription"></span>
          <span data-template-applier-target="previewModalTheme"></span>
          <div data-template-applier-target="previewModalContent"></div>
        </div>
      </div>`
    const { application, element } = await mountController("template-applier", Controller, bareCardHtml)
    const ctrl = controllerFor(application, element, "template-applier")
    const c = element.querySelector('[data-template-applier-target="templateCard"]')
    ctrl.openPreviewModal(cur(c.querySelector("[data-preview-content]")))
    expect(element.querySelector('[data-template-applier-target="previewModalName"]').textContent).toBe("k9")
    expect(element.querySelector('[data-template-applier-target="previewModalDescription"]').textContent).toBe("")
    expect(element.querySelector('[data-template-applier-target="previewModalTheme"]').textContent).toBe("")
  })

  it("falls back to the template key and skips missing modal header targets gracefully", async () => {
    const bareHtml = `
      <div data-controller="template-applier">
        <div data-template-applier-target="templateCard" data-template-key="bare"
             class="border-gray-200">
          <div data-preview-content class="max-h-[110px] px-2 py-1.5 space-y-1"></div>
        </div>
      </div>`
    const { application, element } = await mountController("template-applier", Controller, bareHtml)
    const ctrl = controllerFor(application, element, "template-applier")
    const card = element.querySelector('[data-template-applier-target="templateCard"]')
    // No previewModalName/Description/Theme/Content/previewModal targets present at all —
    // every hasXTarget guard should take its false branch without throwing.
    expect(() => ctrl.openPreviewModal(cur(card.querySelector("[data-preview-content]")))).not.toThrow()
  })

  it("skips cloning the preview when the card has no [data-preview-content]", async () => {
    const { element, ctrl } = await mount()
    const c = cardByKey(element, "t1")
    c.querySelector("[data-preview-content]").remove()
    expect(() => ctrl.openPreviewModal(cur(c))).not.toThrow()
    expect(element.querySelector('[data-template-applier-target="previewModalContent"]').innerHTML).toBe("")
  })
})

describe("template-applier — scalePreviewElements", () => {
  it("scales every targeted class family in the cloned preview", async () => {
    const { ctrl } = await mount()
    const container = document.createElement("div")
    container.innerHTML = `
      <span class="text-[6px]">a</span>
      <span class="text-[5px]">b</span>
      <span class="text-[4px]">c</span>
      <span class="text-[3px]">d</span>
      <div class="gap-1">g1</div>
      <div class="gap-0.5">g2</div>
      <div class="gap-px">g3</div>
      <div class="space-y-1.5">sy</div>
      <div class="h-[7px] border">hb</div>
      <div class="h-[12px]">h12</div>
      <div class="w-1 h-1">dot</div>
      <div class="w-1.5">w15</div>
      <div class="w-[6px]"><svg></svg></div>
      <div class="rounded-sm">rs</div>
      <div class="rounded-sm rounded-md">rsmd</div>
      <div class="mb-px mb-0.5 mt-0.5 px-0.5 pr-0.5 pl-0.5 my-0.5">sp</div>
    `
    ctrl.scalePreviewElements(container)

    // text sizes -> text-sm
    container.querySelectorAll("span").forEach(el => expect(el.classList.contains("text-sm")).toBe(true))
    // gaps -> gap-3
    container.querySelectorAll("[class*='gap']").forEach(el => expect(el.classList.contains("gap-3")).toBe(true))
    // space-y-1.5 -> space-y-4
    expect(container.querySelector(".space-y-4")).toBeTruthy()
    // height WITH border -> h-10 (input field sizing)
    const hb = container.querySelector(".h-10")
    expect(hb).toBeTruthy()
    expect(hb.classList.contains("border")).toBe(true)
    // height WITHOUT border -> h-8 (spacer/button sizing)
    const h12 = [...container.querySelectorAll("div")].find(el => el.textContent === "h12")
    expect(h12.classList.contains("h-8")).toBe(true)
    // dots (w-1.h-1 compound) get re-scaled to w-2/h-2 by the dots pass, then picked
    // up again by the width pass since they now match .w-2 — final state is width-pass output.
    const dot = [...container.querySelectorAll("div")].find(el => el.textContent === "dot")
    expect(dot.classList.contains("w-1")).toBe(false)
    expect(dot.classList.contains("h-1")).toBe(false)
    // width WITHOUT svg -> w-4
    expect(container.querySelector(".w-1\\.5")).toBeNull()
    // width WITH svg -> w-5 h-5
    const svgWrap = container.querySelector("svg").closest("div")
    expect(svgWrap.classList.contains("w-5")).toBe(true)
    expect(svgWrap.classList.contains("h-5")).toBe(true)
    // rounded-sm alone -> gets rounded-md added
    const rs = [...container.querySelectorAll("div")].find(el => el.textContent === "rs")
    expect(rs.classList.contains("rounded-md")).toBe(true)
    // rounded-sm + already-rounded-md -> rounded-sm stripped, rounded-md not duplicated
    const rsmd = [...container.querySelectorAll("div")].find(el => el.textContent === "rsmd")
    expect(rsmd.classList.contains("rounded-sm")).toBe(false)
    expect(rsmd.classList.contains("rounded-md")).toBe(true)
    // margins/paddings rewritten
    const sp = [...container.querySelectorAll("div")].find(el => el.textContent === "sp")
    expect(sp.classList.contains("mb-px")).toBe(false)
    expect(sp.classList.contains("mb-2")).toBe(true)
  })

  it("scales a bordered h-[14px] textarea up to h-20 (not h-10)", async () => {
    const { ctrl } = await mount()
    const container = document.createElement("div")
    container.innerHTML = `
      <div class="h-[14px] border">textarea</div>
      <div class="h-[14px]">plain</div>`
    ctrl.scalePreviewElements(container)
    const [textarea, plain] = container.children
    // bordered h-[14px] is a textarea -> h-20 (the textarea pass runs first)
    expect(textarea.classList.contains("h-20")).toBe(true)
    expect(textarea.classList.contains("h-10")).toBe(false)
    // non-bordered h-[14px] -> general pass -> h-8
    expect(plain.classList.contains("h-8")).toBe(true)
    expect(plain.classList.contains("h-20")).toBe(false)
  })
})

describe("template-applier — toggleGroup", () => {
  it("expands a hidden group and rotates its chevron", async () => {
    const html2 = `
      <div data-controller="template-applier">
        <button data-group-key="forms">toggle</button>
        <div data-group-content="forms" class="hidden"></div>
        <div data-group-chevron="forms"></div>
      </div>`
    const { application, element } = await mountController("template-applier", Controller, html2)
    const ctrl = controllerFor(application, element, "template-applier")
    ctrl.toggleGroup(cur(element.querySelector("[data-group-key='forms']")))
    expect(element.querySelector("[data-group-content='forms']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-group-chevron='forms']").classList.contains("rotate-180")).toBe(true)
  })

  it("collapses a visible group and un-rotates its chevron", async () => {
    const html2 = `
      <div data-controller="template-applier">
        <button data-group-key="forms">toggle</button>
        <div data-group-content="forms"></div>
        <div data-group-chevron="forms" class="rotate-180"></div>
      </div>`
    const { application, element } = await mountController("template-applier", Controller, html2)
    const ctrl = controllerFor(application, element, "template-applier")
    ctrl.toggleGroup(cur(element.querySelector("[data-group-key='forms']")))
    expect(element.querySelector("[data-group-content='forms']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-group-chevron='forms']").classList.contains("rotate-180")).toBe(false)
  })

  it("is a no-op when the group content element is missing", async () => {
    const html2 = `<div data-controller="template-applier"><button data-group-key="ghost">toggle</button></div>`
    const { application, element } = await mountController("template-applier", Controller, html2)
    const ctrl = controllerFor(application, element, "template-applier")
    expect(() => ctrl.toggleGroup(cur(element.querySelector("[data-group-key='ghost']")))).not.toThrow()
  })

  it("toggles the group content without erroring when no chevron element exists", async () => {
    const html2 = `
      <div data-controller="template-applier">
        <button data-group-key="forms">toggle</button>
        <div data-group-content="forms" class="hidden"></div>
      </div>`
    const { application, element } = await mountController("template-applier", Controller, html2)
    const ctrl = controllerFor(application, element, "template-applier")
    ctrl.toggleGroup(cur(element.querySelector("[data-group-key='forms']")))
    expect(element.querySelector("[data-group-content='forms']").classList.contains("hidden")).toBe(false)
  })
})

describe("template-applier — applyFilters / updateCategoryTabs fallbacks", () => {
  it("treats cards missing name/category-label/category-group data as empty strings", async () => {
    const html2 = `
      <div data-controller="template-applier">
        <div>${tab("all", 1)}</div>
        <div data-template-applier-target="templatesGrid">
          <div data-template-applier-target="templateCard" data-template-key="bare"
               data-template-category="misc" class="border-gray-200"></div>
        </div>
        <div data-template-applier-target="noResults" class="hidden"></div>
      </div>`
    const { application, element } = await mountController("template-applier", Controller, html2)
    const ctrl = controllerFor(application, element, "template-applier")
    // searchTemplates with empty query -> searchMatch true regardless of the fallback strings
    ctrl.searchTemplates({ target: { value: "" } })
    const card = element.querySelector('[data-template-applier-target="templateCard"]')
    expect(card.classList.contains("hidden")).toBe(false)
  })

  it("auto-expands a matched group and collapses an unmatched one while searching", async () => {
    const html2 = `
      <div data-controller="template-applier">
        <input data-template-applier-target="searchInput">
        <div data-group-content="forms">
          <button data-template-applier-target="categoryTab" data-category="forms" data-total-count="1">
            <span data-count-badge></span>
          </button>
        </div>
        <div data-group-chevron="forms"></div>
        <div data-group-content="surveys" class="hidden">
          <button data-template-applier-target="categoryTab" data-category="surveys" data-total-count="1">
            <span data-count-badge></span>
          </button>
        </div>
        <div data-group-chevron="surveys" class="rotate-180"></div>
        <div data-template-applier-target="templatesGrid">
          ${card({ key: "t1", name: "Contact", category: "forms" })}
        </div>
      </div>`
    const { application, element } = await mountController("template-applier", Controller, html2)
    const ctrl = controllerFor(application, element, "template-applier")
    ctrl.searchTemplates({ target: { value: "Contact" } })
    // "forms" group has a search match -> expanded + chevron rotated
    expect(element.querySelector('[data-group-content="forms"]').classList.contains("hidden")).toBe(false)
    expect(element.querySelector('[data-group-chevron="forms"]').classList.contains("rotate-180")).toBe(true)
    // "surveys" group has no match -> collapsed + chevron un-rotated
    expect(element.querySelector('[data-group-content="surveys"]').classList.contains("hidden")).toBe(true)
    expect(element.querySelector('[data-group-chevron="surveys"]').classList.contains("rotate-180")).toBe(false)
  })

  it("defaults an un-set data-total-count to 0 on a category tab", async () => {
    const html2 = `
      <div data-controller="template-applier">
        <button data-template-applier-target="categoryTab" data-category="all">
          <span data-count-badge></span>
        </button>
        <div data-template-applier-target="templatesGrid"></div>
      </div>`
    const { application, element } = await mountController("template-applier", Controller, html2)
    const ctrl = controllerFor(application, element, "template-applier")
    ctrl.updateCategoryTabs({})
    // The `parseInt(...) || 0` fallback is exercised here (no data-total-count attr).
    // happy-dom's textContent setter coerces ANY falsy assigned value (including the
    // number 0) to "" instead of the real-browser "0" — verified empirically — so the
    // badge reads "" rather than "0" in this environment.
    expect(element.querySelector("[data-count-badge]").textContent).toBe("")
  })
})

describe("template-applier — selectTemplate without a closest ancestor", () => {
  it("falls back to currentTarget itself when neither it nor any ancestor carries data-template-key", async () => {
    const { ctrl } = await mount()
    // No data-template-key anywhere on this element or its ancestors, so
    // closest("[data-template-key]") returns null and the `|| event.currentTarget`
    // fallback is exercised.
    const orphan = document.createElement("div")
    document.body.appendChild(orphan)
    ctrl.selectTemplate(cur(orphan))
    expect(ctrl.selectedTemplate).toBeUndefined()
  })
})

describe("template-applier — applyTemplate happy path", () => {
  class FakePageBuilder extends StimulusController {
    connect() {
      this.configuration = { pages: [], theme: null, metadata: {} }
      this.currentPage = { fields: [] }
      this.currentPageFields = []
      this.pageManager = { renderPageTabs: vi.fn() }
      this.fieldManager = { renderFields: vi.fn(), deselectField: vi.fn() }
      this.saveManager = { markDirty: vi.fn() }
      this.saveState = vi.fn()
      this.closeAllTabPanels = vi.fn()
    }
  }

  async function mountWithPageBuilder() {
    const { application, element, ctrl } = await mount()
    application.register("page-builder", FakePageBuilder)
    const pbEl = document.createElement("div")
    pbEl.setAttribute("data-controller", "page-builder")
    document.body.appendChild(pbEl)
    await tick()
    ctrl.selectTemplate(cur(cardByKey(element, "t1")))
    return { application, element, ctrl, pbEl }
  }

  function csrfMeta() {
    const meta = document.createElement("meta")
    meta.setAttribute("name", "csrf-token")
    meta.content = "tok"
    document.head.appendChild(meta)
    return meta
  }

  let meta
  beforeEach(() => { meta = csrfMeta() })
  afterEach(() => { meta.remove() })

  it("applies a multi-page configuration, theme, layout metadata and template_layout from the response", async () => {
    const { application, ctrl, pbEl } = await mountWithPageBuilder()
    const pageBuilder = application.getControllerForElementAndIdentifier(pbEl, "page-builder")
    const responseBody = {
      configuration: {
        pages: [{ fields: [{ id: "f1" }] }],
        theme: "dark",
        metadata: { layout_template_key: "grid" }
      },
      template_layout: { key: "grid" }
    }
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true, json: () => Promise.resolve(responseBody)
    }))
    const button = document.createElement("button")
    button.textContent = "Apply"
    await ctrl.applyTemplate(cur(button))

    expect(pageBuilder.saveState).toHaveBeenCalled()
    expect(pageBuilder.configuration.pages).toEqual(responseBody.configuration.pages)
    expect(pageBuilder.configuration.theme).toBe("dark")
    expect(pageBuilder.configuration.metadata.layout_template_key).toBe("grid")
    expect(pageBuilder.layoutTemplateValue).toEqual({ key: "grid" })
    expect(pageBuilder.pageManager.renderPageTabs).toHaveBeenCalled()
    expect(pageBuilder.fieldManager.renderFields).toHaveBeenCalled()
    expect(pageBuilder.fieldManager.deselectField).toHaveBeenCalled()
    expect(pageBuilder.saveManager.markDirty).toHaveBeenCalled()
    expect(pageBuilder.closeAllTabPanels).toHaveBeenCalled()
    expect(button.disabled).toBe(false)
    expect(button.textContent).toBe("Apply")
    expect(button.classList.contains("opacity-75")).toBe(false)
  })

  it("updates the current page's fields when the response is a single-page fields config", async () => {
    const { application, ctrl, pbEl } = await mountWithPageBuilder()
    const pageBuilder = application.getControllerForElementAndIdentifier(pbEl, "page-builder")
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true, json: () => Promise.resolve({ configuration: { fields: [{ id: "f2" }] } })
    }))
    await ctrl.applyTemplate(cur(document.createElement("button")))
    expect(pageBuilder.currentPage.fields).toEqual([{ id: "f2" }])
    // No `metadata` key at all on this response -> `newConfig.metadata?.layout_template_key`
    // takes its falsy branch and configuration.metadata is left untouched.
    expect(pageBuilder.configuration.metadata).toEqual({})
  })

  it("builds configuration.metadata from scratch when the page-builder had none yet", async () => {
    const { ctrl, application, pbEl } = await mountWithPageBuilder()
    const pageBuilder = application.getControllerForElementAndIdentifier(pbEl, "page-builder")
    pageBuilder.configuration.metadata = undefined // exercise the `|| {}` fallback
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true, json: () => Promise.resolve({ configuration: { fields: [], metadata: { layout_template_key: "grid" } } })
    }))
    await ctrl.applyTemplate(cur(document.createElement("button")))
    expect(pageBuilder.configuration.metadata).toEqual({ layout_template_key: "grid" })
  })

  it("leaves configuration.metadata untouched when metadata is present but has no layout_template_key", async () => {
    const { ctrl, application, pbEl } = await mountWithPageBuilder()
    const pageBuilder = application.getControllerForElementAndIdentifier(pbEl, "page-builder")
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: true, json: () => Promise.resolve({ configuration: { fields: [], metadata: {} } })
    }))
    await ctrl.applyTemplate(cur(document.createElement("button")))
    expect(pageBuilder.configuration.metadata).toEqual({})
  })

  it("alerts with the server error message when the response is not ok", async () => {
    const { ctrl } = await mountWithPageBuilder()
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: false, json: () => Promise.resolve({ message: "boom" })
    }))
    const alertSpy = vi.fn()
    vi.stubGlobal("alert", alertSpy)
    await ctrl.applyTemplate(cur(document.createElement("button")))
    expect(alertSpy).toHaveBeenCalledWith("Failed to apply template: boom")
  })

  it("falls back to 'Unknown error' when the error response has no message", async () => {
    const { ctrl } = await mountWithPageBuilder()
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({
      ok: false, json: () => Promise.resolve({})
    }))
    const alertSpy = vi.fn()
    vi.stubGlobal("alert", alertSpy)
    await ctrl.applyTemplate(cur(document.createElement("button")))
    expect(alertSpy).toHaveBeenCalledWith("Failed to apply template: Unknown error")
  })

  it("alerts and re-enables the button when fetch throws", async () => {
    const { ctrl } = await mountWithPageBuilder()
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("network down")))
    const alertSpy = vi.fn()
    vi.stubGlobal("alert", alertSpy)
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {})
    const button = document.createElement("button")
    button.textContent = "Apply"
    await ctrl.applyTemplate(cur(button))
    expect(alertSpy).toHaveBeenCalledWith("Failed to apply template. Please try again.")
    expect(button.disabled).toBe(false)
    errorSpy.mockRestore()
  })
})
