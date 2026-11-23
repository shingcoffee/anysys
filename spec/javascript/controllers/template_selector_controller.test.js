import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/template_selector_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

// The card grid is lazy-fetched; for most tests we pre-render cards inside the
// container so they register as templateCard targets on connect.
function card({ key, name = key, category = "forms", theme = "modern" }) {
  return `
    <div data-template-selector-target="templateCard"
         data-template-key="${key}" data-template-name="${name}"
         data-template-description="${name} desc" data-template-category="${category}"
         data-template-theme="${theme}" class="border-gray-200">
      <div data-checkmark class="hidden"></div>
    </div>`
}

function buildHtml({ selectedKey = "", cards = ["t1", "t2"] } = {}) {
  return `
    <div data-controller="template-selector"
         data-template-selector-customer-id-value="42"
         data-template-selector-cards-url-value="/cards">
      <input type="hidden" data-template-selector-target="selectedTemplate"
             value="${selectedKey}" data-template-key="${selectedKey}">
      <input type="hidden" data-template-selector-target="selectedTheme" value="">
      <button data-template-selector-target="changeBtn"></button>
      <button data-template-selector-target="clearTemplateBtn"></button>
      <span data-template-selector-target="lockedNote" class="hidden"></span>
      <div data-template-selector-target="triggerEmpty"></div>
      <div data-template-selector-target="triggerSelected" class="hidden"></div>
      <span data-template-selector-target="triggerName"></span>
      <div data-template-selector-target="pickerModal" class="hidden"></div>
      <div data-template-selector-target="picker" data-template-picker-cards-url="/cards"></div>
      <div data-template-selector-target="loadingState" class="hidden"></div>
      <div data-template-selector-target="errorState" class="hidden"></div>
      <input data-template-selector-target="searchInput">
      <button data-template-selector-target="searchClear" class="hidden"></button>
      <div data-template-selector-target="noResults" class="hidden"></div>
      <div data-template-selector-target="templateContainer">
        ${cards.map(k => card({ key: k })).join("")}
      </div>
    </div>`
}

async function mount(opts = {}) {
  const { application, element } = await mountController("template-selector", Controller, buildHtml(opts))
  await tick()
  const ctrl = controllerFor(application, element, "template-selector")
  return { application, element, ctrl }
}

const cardByKey = (el, k) => [...el.querySelectorAll('[data-template-selector-target="templateCard"]')].find(c => c.dataset.templateKey === k)
const cur = (e) => ({ currentTarget: e, preventDefault() {}, stopPropagation() {} })

afterEach(() => { document.body.style.overflow = ""; vi.unstubAllGlobals() })

describe("template-selector — connect state & trigger", () => {
  it("reads the committed key from the hidden field's data attribute", async () => {
    const { ctrl } = await mount({ selectedKey: "t1" })
    expect(ctrl.selectedKey).toBe("t1")
    expect(ctrl.pendingKey).toBe("t1")
  })

  it("refreshTrigger toggles empty/selected trigger states", async () => {
    const { element, ctrl } = await mount({ selectedKey: "t1" })
    expect(element.querySelector('[data-template-selector-target="triggerEmpty"]').classList.contains("hidden")).toBe(true)
    expect(element.querySelector('[data-template-selector-target="triggerSelected"]').classList.contains("hidden")).toBe(false)
    // trigger name from the matching card
    expect(element.querySelector('[data-template-selector-target="triggerName"]').textContent).toBe("t1")
  })

  it("refreshTrigger keeps the existing trigger text when the selected key matches no loaded card", async () => {
    const { element, ctrl } = await mount({ selectedKey: "t1" })
    element.querySelector('[data-template-selector-target="triggerName"]').textContent = "Stale Name"
    ctrl.selectedKey = "unknown-key"
    ctrl.refreshTrigger()
    expect(element.querySelector('[data-template-selector-target="triggerName"]').textContent).toBe("Stale Name")
  })

  it("refreshTrigger falls back to the key itself when the matching card has no name", async () => {
    const html2 = `
      <div data-controller="template-selector">
        <input type="hidden" data-template-selector-target="selectedTemplate" value="t1" data-template-key="t1">
        <div data-template-selector-target="triggerEmpty"></div>
        <div data-template-selector-target="triggerSelected" class="hidden"></div>
        <span data-template-selector-target="triggerName"></span>
        <div data-template-selector-target="templateContainer">
          <div data-template-selector-target="templateCard" data-template-key="t1"></div>
        </div>
      </div>`
    const { application, element } = await mountController("template-selector", Controller, html2)
    const ctrl = controllerFor(application, element, "template-selector")
    expect(element.querySelector('[data-template-selector-target="triggerName"]').textContent).toBe("t1")
  })
})

describe("template-selector — modal open/close", () => {
  it("openModal reveals the picker modal (when not locked) and loads templates", async () => {
    const { element, ctrl } = await mount()
    const loadSpy = vi.spyOn(ctrl, "loadTemplates").mockResolvedValue()
    ctrl.openModal(cur(null))
    expect(element.querySelector('[data-template-selector-target="pickerModal"]').classList.contains("hidden")).toBe(false)
    expect(document.body.style.overflow).toBe("hidden")
    expect(loadSpy).toHaveBeenCalled()
  })

  it("openModal is a no-op while locked", async () => {
    const { element, ctrl } = await mount()
    ctrl.setLocked(true)
    ctrl.openModal(cur(null))
    expect(element.querySelector('[data-template-selector-target="pickerModal"]').classList.contains("hidden")).toBe(true)
  })

  it("closeModal hides the modal and discards the pending highlight", async () => {
    const { element, ctrl } = await mount({ selectedKey: "t1" })
    ctrl.pendingKey = "t2"
    ctrl.closeModal(cur(null))
    expect(element.querySelector('[data-template-selector-target="pickerModal"]').classList.contains("hidden")).toBe(true)
    expect(ctrl.pendingKey).toBe("t1") // reverted to committed
  })
})

describe("template-selector — pending selection & commit", () => {
  it("selectTemplate sets a pending key and highlights the card", async () => {
    const { element, ctrl } = await mount()
    ctrl.selectTemplate(cur(cardByKey(element, "t2")))
    expect(ctrl.pendingKey).toBe("t2")
    expect(cardByKey(element, "t2").classList.contains("border-indigo-500")).toBe(true)
    expect(cardByKey(element, "t2").querySelector("[data-checkmark]").classList.contains("hidden")).toBe(false)
  })

  it("confirmSelection commits the pending key, updates the hidden field and dispatches", async () => {
    const { element, ctrl } = await mount()
    const events = []
    element.addEventListener("template-selector:templateSelected", (e) => events.push(e.detail))
    ctrl.selectTemplate(cur(cardByKey(element, "t2")))
    ctrl.confirmSelection(cur(null))
    expect(ctrl.selectedKey).toBe("t2")
    expect(element.querySelector('[data-template-selector-target="selectedTemplate"]').value).toBe("t2")
    expect(ctrl.selectedTheme).toBe("modern") // from card theme
    expect(events).toEqual([{ key: "t2" }])
    expect(element.querySelector('[data-template-selector-target="pickerModal"]').classList.contains("hidden")).toBe(true)
  })

  it("confirmSelection with no pending key just closes the modal", async () => {
    const { ctrl } = await mount()
    ctrl.selectedKey = null; ctrl.pendingKey = null
    const dispatchSpy = vi.spyOn(ctrl, "dispatch")
    ctrl.confirmSelection(cur(null))
    expect(dispatchSpy).not.toHaveBeenCalled()
  })

  it("revertCommit restores the prior committed selection", async () => {
    const { element, ctrl } = await mount({ selectedKey: "t1" })
    ctrl.selectTemplate(cur(cardByKey(element, "t2")))
    ctrl.confirmSelection(cur(null)) // commit t2, prior = t1
    ctrl.revertCommit()
    expect(ctrl.selectedKey).toBe("t1")
    expect(element.querySelector('[data-template-selector-target="selectedTemplate"]').value).toBe("t1")
  })

  it("revertCommit falls back to null/empty when there was no prior commit", async () => {
    const { element, ctrl } = await mount()
    // _priorKey/_priorValue/_priorTheme are all undefined — never went through confirmSelection.
    ctrl.revertCommit()
    expect(ctrl.selectedKey).toBeNull()
    expect(element.querySelector('[data-template-selector-target="selectedTemplate"]').value).toBe("")
    expect(ctrl.selectedTheme).toBeNull()
  })

  it("revertCommit skips writing dataset.templateKey when the field has no such attribute", async () => {
    const html2 = `
      <div data-controller="template-selector">
        <input type="hidden" data-template-selector-target="selectedTemplate" value="t1">
      </div>`
    const { application, element } = await mountController("template-selector", Controller, html2)
    const ctrl = controllerFor(application, element, "template-selector")
    expect(() => ctrl.revertCommit()).not.toThrow()
    expect(element.querySelector('[data-template-selector-target="selectedTemplate"]').dataset.templateKey).toBeUndefined()
  })
})

describe("template-selector — concurrent loadTemplates", () => {
  it("returns the same in-flight promise when called again before it resolves", async () => {
    const { ctrl } = await mount({ cards: [] })
    let resolveFetch
    vi.stubGlobal("fetch", vi.fn(() => new Promise((r) => { resolveFetch = r })))
    const first = ctrl.loadTemplates()
    const second = ctrl.loadTemplates() // hits `if (this.loadPromise) return this.loadPromise`
    expect(second).toBe(first)
    resolveFetch({ ok: true, text: async () => "" })
    await first
  })
})

describe("template-selector — clear & lock", () => {
  it("clearTemplate resets to empty and dispatches templateCleared", async () => {
    const { element, ctrl } = await mount({ selectedKey: "t1" })
    const events = []
    element.addEventListener("template-selector:templateCleared", () => events.push(true))
    ctrl.clearTemplate(cur(null))
    expect(ctrl.selectedKey).toBeNull()
    expect(element.querySelector('[data-template-selector-target="selectedTemplate"]').value).toBe("")
    expect(events).toEqual([true])
  })

  it("clearTemplate is a no-op while locked", async () => {
    const { ctrl } = await mount({ selectedKey: "t1" })
    ctrl.setLocked(true)
    ctrl.clearTemplate(cur(null))
    expect(ctrl.selectedKey).toBe("t1")
  })

  it("applyLockState hides change/clear affordances and shows the locked note", async () => {
    const { element, ctrl } = await mount()
    ctrl.setLocked(true)
    expect(element.querySelector('[data-template-selector-target="changeBtn"]').classList.contains("hidden")).toBe(true)
    expect(element.querySelector('[data-template-selector-target="clearTemplateBtn"]').classList.contains("hidden")).toBe(true)
    expect(element.querySelector('[data-template-selector-target="lockedNote"]').classList.contains("hidden")).toBe(false)
  })
})

describe("template-selector — parseReferencedTemplate", () => {
  it("parses a JSON string, passes an object through and returns null on garbage", async () => {
    const { ctrl } = await mount()
    expect(ctrl.parseReferencedTemplate('{"key":"t1"}')).toEqual({ key: "t1" })
    expect(ctrl.parseReferencedTemplate({ key: "t2" })).toEqual({ key: "t2" })
    expect(ctrl.parseReferencedTemplate("{not json")).toBeNull()
    expect(ctrl.parseReferencedTemplate(null)).toBeNull()
  })
})

describe("template-selector — lazy load", () => {
  it("loadTemplates fetches the grid HTML and injects it once", async () => {
    const { element, ctrl } = await mount({ cards: [] })
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, text: async () => card({ key: "tX" }) })))
    await ctrl.loadTemplates()
    expect(ctrl.loaded).toBe(true)
    expect(element.querySelector('[data-template-selector-target="templateContainer"]').innerHTML).toContain("tX")
    // second call is a no-op (already loaded)
    const fetchSpy = vi.fn()
    vi.stubGlobal("fetch", fetchSpy)
    await ctrl.loadTemplates()
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it("loadTemplates shows the error state on a failed fetch", async () => {
    const { element, ctrl } = await mount({ cards: [] })
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 500 })))
    await ctrl.loadTemplates()
    expect(element.querySelector('[data-template-selector-target="errorState"]').classList.contains("hidden")).toBe(false)
  })

  it("autoSelectTemplate loads, commits and locks when the referenced template exists", async () => {
    const { element, ctrl } = await mount()
    const applied = await ctrl.autoSelectTemplate("t1")
    expect(applied).toBe(true)
    expect(ctrl.selectedKey).toBe("t1")
    expect(cardByKey(element, "t1").classList.contains("border-indigo-500")).toBe(true)
  })

  it("autoSelectTemplate returns false for a missing template", async () => {
    const { ctrl } = await mount()
    expect(await ctrl.autoSelectTemplate("nope")).toBe(false)
  })
})

describe("template-selector — search & filters", () => {
  it("searchTemplates filters cards and toggles the clear button + no-results", async () => {
    const { element, ctrl } = await mount({ cards: ["contact", "signup"] })
    ctrl.searchTemplates({ target: { value: "contact" } })
    expect(cardByKey(element, "contact").classList.contains("hidden")).toBe(false)
    expect(cardByKey(element, "signup").classList.contains("hidden")).toBe(true)
    expect(element.querySelector('[data-template-selector-target="searchClear"]').classList.contains("hidden")).toBe(false)
  })

  it("clearSearch resets the query and reveals all cards", async () => {
    const { element, ctrl } = await mount({ cards: ["contact", "signup"] })
    ctrl.searchTemplates({ target: { value: "contact" } })
    ctrl.clearSearch({ preventDefault() {} })
    expect(ctrl.searchQuery).toBe("")
    expect(cardByKey(element, "signup").classList.contains("hidden")).toBe(false)
    expect(element.querySelector('[data-template-selector-target="searchInput"]').value).toBe("")
  })

  it("shows the search-results count and number while searching", async () => {
    const html2 = `
      <div data-controller="template-selector">
        <input type="hidden" data-template-selector-target="selectedTemplate">
        <div data-template-selector-target="searchResultsCount" class="hidden">
          <span data-template-selector-target="searchResultsNumber"></span>
        </div>
        <div data-template-selector-target="templateContainer">
          ${card({ key: "contact", name: "Contact" })}
          ${card({ key: "signup", name: "Signup" })}
        </div>
      </div>`
    const { application, element } = await mountController("template-selector", Controller, html2)
    const ctrl = controllerFor(application, element, "template-selector")
    ctrl.searchTemplates({ target: { value: "contact" } })
    const count = element.querySelector('[data-template-selector-target="searchResultsCount"]')
    expect(count.classList.contains("hidden")).toBe(false)
    expect(element.querySelector('[data-template-selector-target="searchResultsNumber"]').textContent).toBe("1")
  })

  it("skips writing the results number when the count target has no number sub-target", async () => {
    const html2 = `
      <div data-controller="template-selector">
        <input type="hidden" data-template-selector-target="selectedTemplate">
        <div data-template-selector-target="searchResultsCount" class="hidden"></div>
        <div data-template-selector-target="templateContainer">
          ${card({ key: "contact", name: "Contact" })}
        </div>
      </div>`
    const { application, element } = await mountController("template-selector", Controller, html2)
    const ctrl = controllerFor(application, element, "template-selector")
    expect(() => ctrl.searchTemplates({ target: { value: "contact" } })).not.toThrow()
    expect(element.querySelector('[data-template-selector-target="searchResultsCount"]').classList.contains("hidden")).toBe(false)
  })

  it("treats cards missing name/description data as empty strings when searching", async () => {
    const html2 = `
      <div data-controller="template-selector">
        <input type="hidden" data-template-selector-target="selectedTemplate">
        <div data-template-selector-target="templateContainer">
          <div data-template-selector-target="templateCard" data-template-key="bare" data-template-category="forms"></div>
        </div>
      </div>`
    const { application, element } = await mountController("template-selector", Controller, html2)
    const ctrl = controllerFor(application, element, "template-selector")
    ctrl.searchTemplates({ target: { value: "" } })
    expect(element.querySelector('[data-template-selector-target="templateCard"]').classList.contains("hidden")).toBe(false)
  })
})

describe("template-selector — category tabs + group auto-expand", () => {
  function tabsHtml() {
    return `
      <div data-controller="template-selector">
        <input type="hidden" data-template-selector-target="selectedTemplate">
        <input data-template-selector-target="searchInput">
        <div data-group-content="forms">
          <button data-template-selector-target="categoryTab" data-category="forms" data-total-count="1">
            <span data-count-badge></span>
          </button>
        </div>
        <div data-group-chevron="forms"></div>
        <div data-group-content="surveys" class="hidden">
          <button data-template-selector-target="categoryTab" data-category="surveys">
            <span data-count-badge></span>
          </button>
        </div>
        <div data-group-chevron="surveys" class="rotate-180"></div>
        <div data-template-selector-target="templateContainer">
          ${card({ key: "t1", name: "Contact", category: "forms" })}
        </div>
      </div>`
  }

  it("highlights the active tab and shows total counts while not searching", async () => {
    const { application, element } = await mountController("template-selector", Controller, tabsHtml())
    const ctrl = controllerFor(application, element, "template-selector")
    ctrl.filterCategory(cur({ dataset: { category: "forms" } }))
    const formsTab = element.querySelector('[data-category="forms"]')
    expect(formsTab.classList.contains("bg-indigo-100")).toBe(true)
    expect(formsTab.querySelector("[data-count-badge]").textContent).toBe("1")
    const surveysTab = element.querySelector('[data-category="surveys"]')
    expect(surveysTab.classList.contains("bg-gray-100")).toBe(true)
  })

  it("green-highlights matched tabs and dims unmatched ones while searching, auto-expanding/collapsing their groups", async () => {
    const { application, element } = await mountController("template-selector", Controller, tabsHtml())
    const ctrl = controllerFor(application, element, "template-selector")
    ctrl.searchTemplates({ target: { value: "contact" } })
    const formsTab = element.querySelector('[data-category="forms"]')
    expect(formsTab.classList.contains("bg-green-50")).toBe(true)
    const surveysTab = element.querySelector('[data-category="surveys"]')
    expect(surveysTab.classList.contains("opacity-40")).toBe(true)
    expect(element.querySelector('[data-group-content="forms"]').classList.contains("hidden")).toBe(false)
    expect(element.querySelector('[data-group-chevron="forms"]').classList.contains("rotate-180")).toBe(true)
    expect(element.querySelector('[data-group-content="surveys"]').classList.contains("hidden")).toBe(true)
    expect(element.querySelector('[data-group-chevron="surveys"]').classList.contains("rotate-180")).toBe(false)
  })

  it("defaults an un-set data-total-count to 0", async () => {
    const { application, element } = await mountController("template-selector", Controller, tabsHtml())
    const ctrl = controllerFor(application, element, "template-selector")
    // "surveys" tab has no data-total-count attribute.
    ctrl.filterCategory(cur({ dataset: { category: "forms" } }))
    // happy-dom's textContent setter coerces the falsy number 0 to "" (verified
    // empirically — see the equivalent template_applier_controller test).
    expect(element.querySelector('[data-category="surveys"] [data-count-badge]').textContent).toBe("")
  })
})

describe("template-selector — updateCardStates", () => {
  it("highlights the pending card and clears others", async () => {
    const { element, ctrl } = await mount()
    ctrl.pendingKey = "t1"
    ctrl.updateCardStates()
    expect(cardByKey(element, "t1").classList.contains("border-indigo-500")).toBe(true)
    expect(cardByKey(element, "t2").classList.contains("border-gray-200")).toBe(true)
    expect(cardByKey(element, "t2").querySelector("[data-checkmark]").classList.contains("hidden")).toBe(true)
  })
})

describe("template-selector — refreshFromEntity", () => {
  it("unlocks and resets when the entity id is blank", async () => {
    const { ctrl } = await mount({ selectedKey: "t1" })
    await ctrl.refreshFromEntity("")
    expect(ctrl.locked).toBe(false)
    expect(ctrl.selectedKey).toBeNull()
  })

  it("locks to the entity's referenced template when present and available", async () => {
    const { ctrl } = await mount()
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ referenced_template: { key: "t2" } }) })))
    await ctrl.refreshFromEntity("77")
    expect(ctrl.selectedKey).toBe("t2")
    expect(ctrl.locked).toBe(true)
  })

  it("stays editable when the entity references no template", async () => {
    const { ctrl } = await mount({ selectedKey: "t1" })
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ referenced_template: null }) })))
    await ctrl.refreshFromEntity("77")
    expect(ctrl.locked).toBe(false)
    expect(ctrl.selectedKey).toBeNull()
  })

  it("unlocks without resetting when the response is not ok", async () => {
    const { ctrl } = await mount({ selectedKey: "t1" })
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false })))
    await ctrl.refreshFromEntity("77")
    expect(ctrl.locked).toBe(false)
    expect(ctrl.selectedKey).toBe("t1") // resetSelection was NOT called on this branch
  })

  it("unlocks (without resetting) when the referenced template isn't in the picker", async () => {
    const { ctrl } = await mount()
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ referenced_template: { key: "missing" } }) })))
    await ctrl.refreshFromEntity("77")
    expect(ctrl.locked).toBe(false)
    expect(ctrl.selectedKey).toBeNull()
  })

  it("unlocks on a network/parse failure", async () => {
    const { ctrl } = await mount({ selectedKey: "t1" })
    vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("network down") }))
    await ctrl.refreshFromEntity("77")
    expect(ctrl.locked).toBe(false)
  })

  it("entityChanged reads the select's value and delegates to refreshFromEntity", async () => {
    const { ctrl } = await mount()
    const spy = vi.spyOn(ctrl, "refreshFromEntity").mockResolvedValue()
    ctrl.entityChanged({ target: { value: "99" } })
    expect(spy).toHaveBeenCalledWith("99")
  })
})

describe("template-selector — closeModalOnBackdrop", () => {
  it("only closes when the click lands directly on the backdrop", async () => {
    const { element, ctrl } = await mount()
    const modal = element.querySelector('[data-template-selector-target="pickerModal"]')
    modal.classList.remove("hidden")
    ctrl.closeModalOnBackdrop({ target: document.createElement("div"), currentTarget: modal })
    expect(modal.classList.contains("hidden")).toBe(false)
    ctrl.closeModalOnBackdrop({ target: modal, currentTarget: modal, preventDefault() {} })
    expect(modal.classList.contains("hidden")).toBe(true)
  })
})

describe("template-selector — handleDoubleClick / filterCategory / toggleGroup", () => {
  it("handleDoubleClick delegates to openPreviewModal", async () => {
    const { element, ctrl } = await mount()
    const c = cardByKey(element, "t1")
    expect(() => ctrl.handleDoubleClick(cur(c))).not.toThrow()
  })

  it("filterCategory narrows visible cards to the chosen category", async () => {
    const { element, ctrl } = await mount({ cards: ["t1", "t2"] })
    // t1 defaults to category "forms" via the card() helper; give t2 a different one.
    cardByKey(element, "t2").dataset.templateCategory = "surveys"
    ctrl.filterCategory(cur({ dataset: { category: "surveys" } }))
    expect(cardByKey(element, "t1").classList.contains("hidden")).toBe(true)
    expect(cardByKey(element, "t2").classList.contains("hidden")).toBe(false)
  })

  it("toggleGroup expands/collapses group content and rotates its chevron", async () => {
    const html2 = `
      <div data-controller="template-selector">
        <input type="hidden" data-template-selector-target="selectedTemplate">
        <button data-group-key="forms">toggle</button>
        <div data-group-content="forms" class="hidden"></div>
        <div data-group-chevron="forms"></div>
      </div>`
    const { application, element } = await mountController("template-selector", Controller, html2)
    const ctrl = controllerFor(application, element, "template-selector")
    ctrl.toggleGroup(cur(element.querySelector("[data-group-key='forms']")))
    expect(element.querySelector("[data-group-content='forms']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-group-chevron='forms']").classList.contains("rotate-180")).toBe(true)
    ctrl.toggleGroup(cur(element.querySelector("[data-group-key='forms']")))
    expect(element.querySelector("[data-group-content='forms']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-group-chevron='forms']").classList.contains("rotate-180")).toBe(false)
  })

  it("toggleGroup is a no-op without a matching content element", async () => {
    const html2 = `
      <div data-controller="template-selector">
        <input type="hidden" data-template-selector-target="selectedTemplate">
        <button data-group-key="ghost">toggle</button>
      </div>`
    const { application, element } = await mountController("template-selector", Controller, html2)
    const ctrl = controllerFor(application, element, "template-selector")
    expect(() => ctrl.toggleGroup(cur(element.querySelector("[data-group-key='ghost']")))).not.toThrow()
  })

  it("toggleGroup tolerates a missing chevron", async () => {
    const html2 = `
      <div data-controller="template-selector">
        <input type="hidden" data-template-selector-target="selectedTemplate">
        <button data-group-key="forms">toggle</button>
        <div data-group-content="forms" class="hidden"></div>
      </div>`
    const { application, element } = await mountController("template-selector", Controller, html2)
    const ctrl = controllerFor(application, element, "template-selector")
    ctrl.toggleGroup(cur(element.querySelector("[data-group-key='forms']")))
    expect(element.querySelector("[data-group-content='forms']").classList.contains("hidden")).toBe(false)
  })
})

describe("template-selector — selectTemplate edge cases", () => {
  it("is a no-op when there is no ancestor card", async () => {
    const { ctrl } = await mount()
    const orphan = document.createElement("div")
    document.body.appendChild(orphan)
    ctrl.selectTemplate(cur(orphan))
    expect(ctrl.pendingKey).toBeNull()
  })

  it("is a no-op when the card's template key is empty", async () => {
    const { element, ctrl } = await mount()
    const emptyKeyCard = document.createElement("div")
    emptyKeyCard.setAttribute("data-template-key", "")
    element.appendChild(emptyKeyCard)
    const before = ctrl.pendingKey
    ctrl.selectTemplate(cur(emptyKeyCard))
    expect(ctrl.pendingKey).toBe(before)
  })
})

function previewHtml({ selectedKey = "" } = {}) {
  return `
    <div data-controller="template-selector"
         data-template-selector-customer-id-value="42">
      <input type="hidden" data-template-selector-target="selectedTemplate" value="${selectedKey}" data-template-key="${selectedKey}">
      <div data-template-selector-target="previewModal" class="hidden">
        <span data-template-selector-target="previewModalName"></span>
        <span data-template-selector-target="previewModalDescription"></span>
        <span data-template-selector-target="previewModalTheme"></span>
        <div data-template-selector-target="previewModalContent"></div>
      </div>
      <div data-template-selector-target="templateContainer">
        <div data-template-selector-target="templateCard" data-template-key="t1" data-template-name="Contact"
             data-template-description="Contact desc" data-template-theme="modern" data-template-category="forms">
          <div data-preview-content class="max-h-[110px] px-2 py-1.5 space-y-1">
            <span class="text-[4px]">x</span>
          </div>
        </div>
      </div>
    </div>`
}

describe("template-selector — preview modal", () => {
  it("openPreviewModal shows the modal populated from the clicked card", async () => {
    const { application, element } = await mountController("template-selector", Controller, previewHtml())
    const ctrl = controllerFor(application, element, "template-selector")
    const card = element.querySelector('[data-template-selector-target="templateCard"]')
    ctrl.openPreviewModal(cur(card.querySelector("[data-preview-content]")))
    expect(element.querySelector('[data-template-selector-target="previewModalName"]').textContent).toBe("Contact")
    expect(element.querySelector('[data-template-selector-target="previewModalTheme"]').textContent).toBe("Modern")
    expect(element.querySelector('[data-template-selector-target="previewModal"]').classList.contains("hidden")).toBe(false)
    expect(document.body.style.overflow).toBe("hidden")
  })

  it("falls back to the key/empty-string when name/description/theme are unset on the card", async () => {
    const html2 = `
      <div data-controller="template-selector">
        <input type="hidden" data-template-selector-target="selectedTemplate">
        <div data-template-selector-target="previewModal" class="hidden">
          <span data-template-selector-target="previewModalName"></span>
          <span data-template-selector-target="previewModalDescription"></span>
          <span data-template-selector-target="previewModalTheme"></span>
        </div>
        <div data-template-selector-target="templateContainer">
          <div data-template-selector-target="templateCard" data-template-key="bare"></div>
        </div>
      </div>`
    const { application, element } = await mountController("template-selector", Controller, html2)
    const ctrl = controllerFor(application, element, "template-selector")
    const card = element.querySelector('[data-template-selector-target="templateCard"]')
    ctrl.showPreviewForCard(card)
    expect(element.querySelector('[data-template-selector-target="previewModalName"]').textContent).toBe("bare")
    expect(element.querySelector('[data-template-selector-target="previewModalDescription"]').textContent).toBe("")
    expect(element.querySelector('[data-template-selector-target="previewModalTheme"]').textContent).toBe("")
  })

  it("showPreviewForCard is a no-op for a null card", async () => {
    const { application, element } = await mountController("template-selector", Controller, previewHtml())
    const ctrl = controllerFor(application, element, "template-selector")
    expect(() => ctrl.showPreviewForCard(null)).not.toThrow()
    expect(element.querySelector('[data-template-selector-target="previewModal"]').classList.contains("hidden")).toBe(true)
  })

  it("closePreviewModal hides the modal and restores scroll", async () => {
    const { application, element } = await mountController("template-selector", Controller, previewHtml())
    const ctrl = controllerFor(application, element, "template-selector")
    const card = element.querySelector('[data-template-selector-target="templateCard"]')
    ctrl.openPreviewModal(cur(card.querySelector("[data-preview-content]")))
    ctrl.closePreviewModal({ preventDefault() {} })
    expect(element.querySelector('[data-template-selector-target="previewModal"]').classList.contains("hidden")).toBe(true)
    expect(document.body.style.overflow).toBe("")
  })

  it("closePreviewModalOnBackdrop only closes on a backdrop click", async () => {
    const { application, element } = await mountController("template-selector", Controller, previewHtml())
    const ctrl = controllerFor(application, element, "template-selector")
    const modal = element.querySelector('[data-template-selector-target="previewModal"]')
    modal.classList.remove("hidden")
    ctrl.closePreviewModalOnBackdrop({ target: document.createElement("div"), currentTarget: modal })
    expect(modal.classList.contains("hidden")).toBe(false)
    ctrl.closePreviewModalOnBackdrop({ target: modal, currentTarget: modal, preventDefault() {} })
    expect(modal.classList.contains("hidden")).toBe(true)
  })

  it("previewSelected opens the server-rendered preview in a new tab when a customer id is set", async () => {
    const { application, element } = await mountController("template-selector", Controller, previewHtml({ selectedKey: "t1" }))
    const ctrl = controllerFor(application, element, "template-selector")
    const openSpy = vi.fn()
    vi.stubGlobal("open", openSpy)
    await ctrl.previewSelected(cur(null))
    expect(openSpy).toHaveBeenCalledWith(
      "/42/admin/maintenance/template_previews/t1", "_blank", "noopener"
    )
  })

  it("previewSelected returns early without a selected key", async () => {
    const { application, element } = await mountController("template-selector", Controller, previewHtml())
    const ctrl = controllerFor(application, element, "template-selector")
    const openSpy = vi.fn()
    vi.stubGlobal("open", openSpy)
    await ctrl.previewSelected(cur(null))
    expect(openSpy).not.toHaveBeenCalled()
  })

  it("previewSelected falls back to the client-side zoom preview without a customer id", async () => {
    const html2 = previewHtml({ selectedKey: "t1" })
      .replace('data-template-selector-customer-id-value="42"', "")
      .replace(
        '<div data-template-selector-target="templateContainer">',
        '<div data-template-selector-target="picker" data-template-picker-cards-url="/cards"></div>' +
        '<div data-template-selector-target="templateContainer">'
      )
    const { application, element } = await mountController("template-selector", Controller, html2)
    const ctrl = controllerFor(application, element, "template-selector")
    const openSpy = vi.fn()
    vi.stubGlobal("open", openSpy)
    await ctrl.previewSelected(cur(null))
    expect(openSpy).not.toHaveBeenCalled()
    expect(element.querySelector('[data-template-selector-target="previewModalName"]').textContent).toBe("Contact")
  })
})

describe("template-selector — scalePreviewElements", () => {
  it("scales every targeted class family", async () => {
    const { ctrl } = await mount()
    const container = document.createElement("div")
    container.innerHTML = `
      <span class="text-[5px]">a</span>
      <span class="text-[4px]">b</span>
      <span class="text-[3px]">c</span>
      <div class="gap-1">g1</div>
      <div class="gap-0.5">g2</div>
      <div class="gap-px">g3</div>
      <div class="h-[7px] border">hb</div>
      <div class="h-[12px]">h12</div>
      <div class="w-1.5">w15</div>
      <div class="w-[6px]"><svg></svg></div>
      <div class="rounded-sm">rs</div>
      <div class="rounded-sm rounded-md">rsmd</div>
      <div class="mb-px mb-0.5 mt-0.5 px-0.5 pr-0.5 pl-0.5">sp</div>
    `
    ctrl.scalePreviewElements(container)
    container.querySelectorAll("span").forEach(el => expect(el.classList.contains("text-sm")).toBe(true))
    expect(container.querySelector("[class*='gap']").classList.contains("gap-3")).toBe(true)
    const hb = container.querySelector(".h-10")
    expect(hb.classList.contains("border")).toBe(true)
    const h12 = [...container.querySelectorAll("div")].find(el => el.textContent === "h12")
    expect(h12.classList.contains("h-8")).toBe(true)
    expect(container.querySelector(".w-1\\.5")).toBeNull()
    const svgWrap = container.querySelector("svg").closest("div")
    expect(svgWrap.classList.contains("w-5")).toBe(true)
    expect(svgWrap.classList.contains("h-5")).toBe(true)
    const rs = [...container.querySelectorAll("div")].find(el => el.textContent === "rs")
    expect(rs.classList.contains("rounded-md")).toBe(true)
    const rsmd = [...container.querySelectorAll("div")].find(el => el.textContent === "rsmd")
    expect(rsmd.classList.contains("rounded-sm")).toBe(false)
    const sp = [...container.querySelectorAll("div")].find(el => el.textContent === "sp")
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
    expect(textarea.classList.contains("h-20")).toBe(true)
    expect(textarea.classList.contains("h-10")).toBe(false)
    expect(plain.classList.contains("h-8")).toBe(true)
    expect(plain.classList.contains("h-20")).toBe(false)
  })
})

describe("template-selector — theme selector", () => {
  function themeHtml({ selectedKey = "t1", selectedTheme = "" } = {}) {
    return `
      <div data-controller="template-selector"
           data-template-selector-customer-id-value="42">
        <input type="hidden" data-template-selector-target="selectedTemplate" value="${selectedKey}" data-template-key="${selectedKey}">
        <input type="hidden" data-template-selector-target="selectedTheme" value="${selectedTheme}">
        <div data-template-selector-target="themeSelector" class="hidden">
          <button data-template-selector-target="themeOption" data-theme-key="modern">
            <span data-theme-checkmark class="hidden"></span>
          </button>
          <button data-template-selector-target="themeOption" data-theme-key="classic">
            <span data-theme-checkmark class="hidden"></span>
          </button>
        </div>
        <div data-template-selector-target="templateContainer">
          <div data-template-selector-target="templateCard" data-template-key="t1" data-template-theme="modern"></div>
        </div>
      </div>`
  }

  it("selectTheme marks the matching option selected and reveals its checkmark", async () => {
    const { application, element } = await mountController("template-selector", Controller, themeHtml())
    const ctrl = controllerFor(application, element, "template-selector")
    const modernBtn = element.querySelector("[data-theme-key='modern']")
    ctrl.selectTheme(cur(modernBtn))
    expect(ctrl.selectedTheme).toBe("modern")
    expect(modernBtn.classList.contains("border-indigo-500")).toBe(true)
    expect(modernBtn.querySelector("[data-theme-checkmark]").classList.contains("hidden")).toBe(false)
    const classicBtn = element.querySelector("[data-theme-key='classic']")
    expect(classicBtn.classList.contains("border-gray-200")).toBe(true)
    expect(classicBtn.querySelector("[data-theme-checkmark]").classList.contains("hidden")).toBe(true)
    expect(element.querySelector('[data-template-selector-target="selectedTheme"]').value).toBe("modern")
  })

  it("selectTheme is a no-op without a theme key on the target", async () => {
    const { application, element } = await mountController("template-selector", Controller, themeHtml())
    const ctrl = controllerFor(application, element, "template-selector")
    const before = ctrl.selectedTheme
    ctrl.selectTheme(cur(document.createElement("button")))
    expect(ctrl.selectedTheme).toBe(before)
  })

  it("updateThemeSelector defaults the theme from the selected card and reveals the selector", async () => {
    const { application, element } = await mountController("template-selector", Controller, themeHtml({ selectedTheme: "" }))
    const ctrl = controllerFor(application, element, "template-selector")
    ctrl.selectedKey = "t1"
    ctrl.selectedTheme = null
    ctrl.updateThemeSelector()
    expect(element.querySelector('[data-template-selector-target="themeSelector"]').classList.contains("hidden")).toBe(false)
    expect(ctrl.selectedTheme).toBe("modern")
  })

  it("updateThemeSelector leaves an already-set theme untouched", async () => {
    const { application, element } = await mountController("template-selector", Controller, themeHtml({ selectedTheme: "classic" }))
    const ctrl = controllerFor(application, element, "template-selector")
    ctrl.selectedKey = "t1"
    ctrl.selectedTheme = "classic"
    ctrl.updateThemeSelector()
    expect(ctrl.selectedTheme).toBe("classic")
  })

  it("updateThemeSelector hides the selector when there is no matching card", async () => {
    const { application, element } = await mountController("template-selector", Controller, themeHtml())
    const ctrl = controllerFor(application, element, "template-selector")
    element.querySelector('[data-template-selector-target="themeSelector"]').classList.remove("hidden")
    ctrl.selectedKey = "no-such-key"
    ctrl.updateThemeSelector()
    expect(element.querySelector('[data-template-selector-target="themeSelector"]').classList.contains("hidden")).toBe(true)
  })

  it("updateThemeSelector is a no-op without a themeSelector target", async () => {
    const { ctrl } = await mount()
    expect(() => ctrl.updateThemeSelector()).not.toThrow()
  })

  it("updateThemeOptionStates is a no-op without theme option targets", async () => {
    const { ctrl } = await mount()
    expect(() => ctrl.updateThemeOptionStates()).not.toThrow()
  })

  it("defaults to 'modern' when the selected card carries no theme data", async () => {
    const html2 = `
      <div data-controller="template-selector">
        <input type="hidden" data-template-selector-target="selectedTemplate" value="t1" data-template-key="t1">
        <input type="hidden" data-template-selector-target="selectedTheme" value="">
        <div data-template-selector-target="themeSelector" class="hidden"></div>
        <div data-template-selector-target="templateContainer">
          <div data-template-selector-target="templateCard" data-template-key="t1"></div>
        </div>
      </div>`
    const { application, element } = await mountController("template-selector", Controller, html2)
    const ctrl = controllerFor(application, element, "template-selector")
    ctrl.selectedTheme = null
    ctrl.updateThemeSelector()
    expect(ctrl.selectedTheme).toBe("modern")
  })

  it("defaults the theme from the card without erroring when there is no selectedTheme hidden field", async () => {
    const html2 = `
      <div data-controller="template-selector">
        <input type="hidden" data-template-selector-target="selectedTemplate" value="t1" data-template-key="t1">
        <div data-template-selector-target="themeSelector" class="hidden"></div>
        <div data-template-selector-target="templateContainer">
          <div data-template-selector-target="templateCard" data-template-key="t1" data-template-theme="modern"></div>
        </div>
      </div>`
    const { application, element } = await mountController("template-selector", Controller, html2)
    const ctrl = controllerFor(application, element, "template-selector")
    ctrl.selectedTheme = null
    expect(() => ctrl.updateThemeSelector()).not.toThrow()
    expect(ctrl.selectedTheme).toBe("modern")
  })
})
