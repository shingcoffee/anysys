import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/versions_controller"
import { versionDiff } from "versions/version_diff"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

// Delegate to the real implementation by default so every existing test keeps
// exercising real jsdiff-backed behavior; individual tests can override the
// return value with mockReturnValueOnce to reach rows the real diff never
// produces (e.g. a row with a null side outside add/del/context).
vi.mock("versions/version_diff", async () => {
  const actual = await vi.importActual("versions/version_diff")
  return { versionDiff: vi.fn(actual.versionDiff) }
})

// Resource-agnostic version-history modal. All network I/O goes through fetch,
// which we stub per-test. versionDiff (jsdiff-backed) runs for real.
const html = `
  <div data-controller="versions"
       data-versions-customer-id-value="42"
       data-versions-resource-value="flowcharts">
    <div data-versions-target="modal" class="hidden">
      <h2 data-versions-target="title"></h2>
      <span data-versions-target="count"></span>
      <div data-versions-target="listView">
        <div data-versions-target="scroll">
          <table><tbody data-versions-target="list"></tbody></table>
        </div>
        <div data-versions-target="pagination" class="hidden">
          <span data-versions-target="pageInfo"></span>
          <button data-versions-target="prevButton"></button>
          <button data-versions-target="nextButton"></button>
        </div>
        <button data-versions-target="diffButton"></button>
        <button data-versions-target="clearButton" class="hidden"></button>
        <span data-versions-target="selectionInfo"></span>
        <span data-versions-target="hint"></span>
      </div>
      <div data-versions-target="content" class="hidden"></div>
      <div data-versions-target="error" class="hidden"><span data-versions-target="errorMessage"></span></div>
    </div>
  </div>`

function version(id, num, extra = {}) {
  return { id, version_number: num, created_at: "2026-01-0" + num + "T10:00:00Z", description: `desc ${num}`, ...extra }
}

async function mount() {
  const { application, element } = await mountController("versions", Controller, html)
  const ctrl = controllerFor(application, element, "versions")
  return { application, element, ctrl }
}

// Only the required `modal` target — every other target is optional (guarded
// by hasXTarget?) in the controller. Used to exercise the "target missing"
// branches without duplicating the full fixture.
const bareHtml = `
  <div data-controller="versions" data-versions-customer-id-value="42" data-versions-resource-value="flowcharts">
    <div data-versions-target="modal" class="hidden"></div>
  </div>`

// modal + error, but no errorMessage target, to hit _error's else branch.
const errorOnlyHtml = `
  <div data-controller="versions" data-versions-customer-id-value="42" data-versions-resource-value="flowcharts">
    <div data-versions-target="modal" class="hidden"></div>
    <div data-versions-target="error" class="hidden"></div>
  </div>`

async function mountBare(fixture = bareHtml) {
  const { application, element } = await mountController("versions", Controller, fixture)
  const ctrl = controllerFor(application, element, "versions")
  return { application, element, ctrl }
}

const noop = () => {}
const ev = (params = {}) => ({ params, preventDefault: noop, stopPropagation: noop })

// open() fires loadVersions() fire-and-forget, so every test that opens the modal
// kicks off an async fetch it doesn't await. Give each test a safe default fetch
// (ok + empty body) so that auto-load never hits the real network (ECONNREFUSED);
// individual tests override this with their own response as needed.
beforeEach(() => {
  vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, status: 200, json: async () => [] })))
})

afterEach(async () => {
  // Let any fire-and-forget load settle under the still-active stub before we
  // restore globals, otherwise it leaks past the test (unhandled rejection /
  // late real-network call).
  await new Promise((resolve) => setTimeout(resolve, 0))
  vi.unstubAllGlobals()
})

describe("versions — open / close / load", () => {
  let element, ctrl
  beforeEach(async () => { ({ element, ctrl } = await mount()) })

  it("open() shows the modal, sets the title and loads versions", async () => {
    const versions = [version(3, 3, { is_default: true }), version(2, 2), version(1, 1)]
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => versions })))
    ctrl.open(ev({ id: "99", name: "My Flow" }))
    expect(element.querySelector('[data-versions-target="modal"]').classList.contains("hidden")).toBe(false)
    expect(element.querySelector('[data-versions-target="title"]').textContent).toBe("My Flow")
    await tick(); await tick()
    expect(ctrl.versions.length).toBe(3)
    expect(element.querySelector('[data-versions-target="count"]').textContent).toContain("3 versions")
    // latest (id 3) is default -> Default pill; row for v2 latest? no, v3 is first
    expect(element.querySelector('[data-versions-target="list"]').innerHTML).toContain("Default")
  })

  it("_base builds the resource-scoped URL", () => {
    ctrl.parentId = "99"
    expect(ctrl._base()).toBe("/42/admin/maintenance/flowcharts/99/versions")
  })

  it("defaults pathPrefix to admin/maintenance", () => {
    ctrl.resourceValue = "flowcharts"
    ctrl.customerIdValue = "42"
    ctrl.parentId = "99"
    expect(ctrl._base()).toBe("/42/admin/maintenance/flowcharts/99/versions")
  })

  it("uses pathPrefix value when set", () => {
    ctrl.pathPrefixValue = "admin/modules/emails"
    ctrl.resourceValue = "templates"
    ctrl.customerIdValue = "42"
    ctrl.parentId = "7"
    expect(ctrl._base()).toBe("/42/admin/modules/emails/templates/7/versions")
  })

  it("close() hides the modal and clears diff content", () => {
    ctrl.open(ev({ id: "1", name: "X" }))
    ctrl.close(ev())
    expect(element.querySelector('[data-versions-target="modal"]').classList.contains("hidden")).toBe(true)
  })

  it("shows an error row when loadVersions gets a non-OK response", async () => {
    ctrl.parentId = "1"
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 500 })))
    await ctrl.loadVersions()
    expect(element.querySelector('[data-versions-target="error"]').classList.contains("hidden")).toBe(false)
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toContain("500")
  })

  it("surfaces network errors from _fetch", async () => {
    ctrl.parentId = "1"
    vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("down") }))
    await ctrl.loadVersions()
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toContain("Network error: down")
  })
})

describe("versions — selection & compare buttons", () => {
  let element, ctrl
  beforeEach(async () => {
    ({ element, ctrl } = await mount())
    ctrl.parentId = "1"
    ctrl.versions = [version(3, 3), version(2, 2), version(1, 1)]
    ctrl._renderList()
  })

  it("toggleSelect keeps at most two ids (drops the oldest)", () => {
    ctrl.toggleSelect(ev({ id: 3 }))
    ctrl.toggleSelect(ev({ id: 2 }))
    ctrl.toggleSelect(ev({ id: 1 }))
    expect(ctrl.selected).toEqual(["2", "1"])
  })

  it("toggleSelect deselects an already-selected id", () => {
    ctrl.toggleSelect(ev({ id: 3 }))
    ctrl.toggleSelect(ev({ id: 3 }))
    expect(ctrl.selected).toEqual([])
  })

  it("_updateButtons enables Compare only with two selections", () => {
    const diffBtn = element.querySelector('[data-versions-target="diffButton"]')
    ctrl.selected = ["3"]; ctrl._updateButtons()
    expect(diffBtn.disabled).toBe(true)
    expect(element.querySelector('[data-versions-target="selectionInfo"]').textContent).toContain("pick one more")
    ctrl.selected = ["3", "2"]; ctrl._updateButtons()
    expect(diffBtn.disabled).toBe(false)
    expect(element.querySelector('[data-versions-target="hint"]').textContent).toBe("Ready to compare")
  })

  it("clearSelection empties the selection and returns to list view", () => {
    ctrl.selected = ["3", "2"]
    ctrl.clearSelection(ev())
    expect(ctrl.selected).toEqual([])
    expect(element.querySelector('[data-versions-target="listView"]').classList.contains("hidden")).toBe(false)
  })
})

describe("versions — list rendering & pagination", () => {
  let element, ctrl
  beforeEach(async () => { ({ element, ctrl } = await mount()); ctrl.parentId = "1" })

  it("renders an empty state when there are no versions", () => {
    ctrl.versions = []
    ctrl._renderList()
    expect(element.querySelector('[data-versions-target="list"]').innerHTML).toContain("No versions yet.")
  })

  it("hides the default version's delete/set-default buttons", () => {
    ctrl.versions = [version(2, 2, { is_default: true }), version(1, 1)]
    ctrl._renderList()
    const rows = element.querySelectorAll('[data-versions-target="list"] tr')
    // default row (v2) has no Set default / Delete buttons
    expect(rows[0].innerHTML).not.toContain("versions#setDefault")
    expect(rows[0].innerHTML).not.toContain("versions#destroy")
    // non-default row (v1) has them
    expect(rows[1].innerHTML).toContain("versions#setDefault")
    expect(rows[1].innerHTML).toContain("versions#destroy")
  })

  it("paginates at PER_PAGE and moves between pages", () => {
    ctrl.versions = Array.from({ length: 23 }, (_, i) => version(23 - i, 23 - i))
    ctrl.page = 1
    ctrl._renderList()
    expect(element.querySelectorAll('[data-versions-target="list"] tr').length).toBe(10)
    expect(element.querySelector('[data-versions-target="pagination"]').classList.contains("hidden")).toBe(false)
    expect(element.querySelector('[data-versions-target="pageInfo"]').textContent).toBe("1–10 of 23")
    ctrl.nextPage(ev())
    expect(ctrl.page).toBe(2)
    expect(element.querySelector('[data-versions-target="pageInfo"]').textContent).toBe("11–20 of 23")
    ctrl.prevPage(ev())
    expect(ctrl.page).toBe(1)
  })

  it("_totalPages is at least 1", () => {
    ctrl.versions = []
    expect(ctrl._totalPages()).toBe(1)
  })
})

describe("versions — setDefault / destroy", () => {
  let element, ctrl
  beforeEach(async () => { ({ element, ctrl } = await mount()); ctrl.parentId = "1" })

  it("setDefault closes the modal and refreshes on success", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, status: 200, json: async () => [] })))
    const refresh = vi.spyOn(ctrl, "_refreshList").mockImplementation(noop)
    ctrl.open(ev({ id: "1", name: "X" }))
    await ctrl.setDefault(ev({ id: 5 }))
    expect(element.querySelector('[data-versions-target="modal"]').classList.contains("hidden")).toBe(true)
    expect(refresh).toHaveBeenCalled()
  })

  it("setDefault surfaces the 422 message from the body", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 422, json: async () => ({ message: "still active" }) })))
    await ctrl.setDefault(ev({ id: 5 }))
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toBe("still active")
  })

  it("setDefault shows the Shared Resources path-lock message on 403", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 403 })))
    await ctrl.setDefault(ev({ id: 5 }))
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toContain("Shared Resources")
  })

  it("destroy asks for confirmation and reloads on success", async () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, status: 200, json: async () => [] })))
    ctrl.selected = ["5"]
    const reload = vi.spyOn(ctrl, "loadVersions").mockResolvedValue()
    await ctrl.destroy(ev({ id: 5, version: 5 }))
    expect(reload).toHaveBeenCalledWith(true)
    expect(ctrl.selected).toEqual([]) // dropped from selection
  })

  it("destroy is a no-op when the confirm is declined", async () => {
    vi.stubGlobal("confirm", vi.fn(() => false))
    const fetchSpy = vi.fn()
    vi.stubGlobal("fetch", fetchSpy)
    await ctrl.destroy(ev({ id: 5, version: 5 }))
    expect(fetchSpy).not.toHaveBeenCalled()
  })
})

describe("versions — diff & view", () => {
  let element, ctrl
  beforeEach(async () => { ({ element, ctrl } = await mount()); ctrl.parentId = "1" })

  it("view() opens the version editor in a new tab", () => {
    const openSpy = vi.fn()
    vi.stubGlobal("open", openSpy)
    ctrl.view(ev({ id: 7 }))
    expect(openSpy).toHaveBeenCalledWith("/42/admin/maintenance/flowcharts/1/versions/7/edit", "_blank")
  })

  it("diff() fetches both versions and renders an add/remove side-by-side table", async () => {
    ctrl.selected = ["1", "2"]
    const va = { version_number: 1, configuration: { a: 1, list: [1, 2] } }
    const vb = { version_number: 2, configuration: { a: 1, list: [1, 2, 3] } }
    vi.stubGlobal("fetch", vi.fn(async (url) => ({
      ok: true,
      json: async () => (url.endsWith("/1.json") ? va : vb),
    })))
    await ctrl.diff(ev())
    const content = element.querySelector('[data-versions-target="content"]')
    expect(content.classList.contains("hidden")).toBe(false)
    expect(content.innerHTML).toContain("added")
    expect(content.innerHTML).toContain("removed")
    expect(content.innerHTML).toContain("v1")
    expect(content.innerHTML).toContain("v2")
  })

  it("diff() bails without exactly two selections", async () => {
    const fetchSpy = vi.fn()
    vi.stubGlobal("fetch", fetchSpy)
    ctrl.selected = ["1"]
    await ctrl.diff(ev())
    expect(fetchSpy).not.toHaveBeenCalled()
  })
})

describe("versions — _formatDate", () => {
  it("returns '' for empty and echoes an unparseable string", async () => {
    const { ctrl } = await mount()
    expect(ctrl._formatDate("")).toBe("")
    expect(ctrl._formatDate("not-a-date")).toBe("not-a-date")
    expect(ctrl._formatDate("2026-01-02T10:00:00Z")).toMatch(/2026/)
  })
})

describe("versions — open() argument fallbacks", () => {
  let ctrl
  beforeEach(async () => { ({ ctrl } = await mount()) })

  it("tolerates a missing event and defaults the parent name to 'Item'", () => {
    expect(() => ctrl.open()).not.toThrow()
    expect(ctrl.parentName).toBe("Item")
  })

  it("close() tolerates a missing event", async () => {
    ctrl.open(ev({ id: "1", name: "X" }))
    expect(() => ctrl.close()).not.toThrow()
  })
})

describe("versions — count pluralization", () => {
  it("shows the singular 'version' for exactly one", async () => {
    const { element, ctrl } = await mount()
    ctrl.parentId = "1"
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => [version(1, 1)] })))
    await ctrl.loadVersions()
    expect(element.querySelector('[data-versions-target="count"]').textContent).toBe(" · 1 version")
  })
})

describe("versions — setDefault / destroy edge cases", () => {
  let element, ctrl
  beforeEach(async () => { ({ element, ctrl } = await mount()); ctrl.parentId = "1" })

  it("setDefault no-ops when _fetch returns null (network error)", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("down") }))
    await ctrl.setDefault(ev({ id: 5 }))
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toContain("Network error")
  })

  it("setDefault falls back to a generic message when the 422 body has none", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 422, json: async () => ({}) })))
    await ctrl.setDefault(ev({ id: 5 }))
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toContain("Deactivate it first")
  })

  it("setDefault surfaces a generic failure message for other non-OK statuses", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 500 })))
    await ctrl.setDefault(ev({ id: 5 }))
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toContain("Failed to set default (500)")
  })

  it("destroy no-ops when _fetch returns null (network error)", async () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("down") }))
    await ctrl.destroy(ev({ id: 5, version: 5 }))
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toContain("Network error")
  })

  it("destroy surfaces the 422 message from the body, falling back when absent", async () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 422, json: async () => ({ message: "in use" }) })))
    await ctrl.destroy(ev({ id: 5, version: 5 }))
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toBe("in use")
  })

  it("destroy falls back to a generic 422 message when the body has none", async () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 422, json: async () => ({}) })))
    await ctrl.destroy(ev({ id: 5, version: 5 }))
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toBe("This version can't be deleted.")
  })

  it("destroy shows the Shared Resources path-lock message on 403", async () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 403 })))
    await ctrl.destroy(ev({ id: 5, version: 5 }))
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toContain("Shared Resources")
  })

  it("destroy surfaces a generic failure message for other non-OK statuses", async () => {
    vi.stubGlobal("confirm", vi.fn(() => true))
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 500 })))
    await ctrl.destroy(ev({ id: 5, version: 5 }))
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toContain("Failed to delete version (500)")
  })
})

describe("versions — diff() early return + backToList", () => {
  let ctrl
  beforeEach(async () => { ({ ctrl } = await mount()); ctrl.parentId = "1" })

  it("diff() bails when either version fails to load", async () => {
    ctrl.selected = ["1", "2"]
    vi.stubGlobal("fetch", vi.fn(async (url) =>
      url.endsWith("/1.json") ? { ok: false, status: 404 } : { ok: true, json: async () => ({ version_number: 2 }) }
    ))
    vi.mocked(versionDiff).mockClear()
    await ctrl.diff(ev())
    // no diff content rendered because _showVersion("1") resolved to null
    expect(vi.mocked(versionDiff)).not.toHaveBeenCalled()
  })

  it("_showVersion returns null (without erroring) when _fetch itself returns null", async () => {
    ctrl.selected = ["1", "2"]
    vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("down") }))
    await ctrl.diff(ev())
    expect(vi.mocked(versionDiff)).not.toHaveBeenCalled()
  })

  it("backToList() returns to the list view", async () => {
    const { element, ctrl: c2 } = await mount()
    c2.parentId = "1"
    c2.selected = ["1", "2"]
    vi.stubGlobal("fetch", vi.fn(async (url) => ({
      ok: true,
      json: async () => ({ version_number: url.endsWith("/1.json") ? 1 : 2, configuration: {} }),
    })))
    await c2.diff(ev())
    expect(element.querySelector('[data-versions-target="content"]').classList.contains("hidden")).toBe(false)
    c2.backToList(ev())
    expect(element.querySelector('[data-versions-target="listView"]').classList.contains("hidden")).toBe(false)
    expect(element.querySelector('[data-versions-target="content"]').classList.contains("hidden")).toBe(true)
  })
})

describe("versions — pagination boundaries", () => {
  let ctrl
  beforeEach(async () => { ({ ctrl } = await mount()); ctrl.parentId = "1" })

  it("prevPage no-ops on the first page", () => {
    ctrl.versions = Array.from({ length: 3 }, (_, i) => version(i + 1, i + 1))
    ctrl.page = 1
    ctrl.prevPage(ev())
    expect(ctrl.page).toBe(1)
  })

  it("nextPage no-ops on the last page", () => {
    ctrl.versions = Array.from({ length: 3 }, (_, i) => version(i + 1, i + 1))
    ctrl.page = ctrl._totalPages()
    ctrl.nextPage(ev())
    expect(ctrl.page).toBe(1)
  })

  it("_renderList clamps an out-of-range page down to the last page", () => {
    ctrl.versions = Array.from({ length: 3 }, (_, i) => version(i + 1, i + 1))
    ctrl.page = 999
    ctrl._renderList()
    expect(ctrl.page).toBe(1) // only one page for 3 versions
  })

  it("_renderList clamps a sub-1 page up to 1", () => {
    ctrl.versions = Array.from({ length: 3 }, (_, i) => version(i + 1, i + 1))
    ctrl.page = 0
    ctrl._renderList()
    expect(ctrl.page).toBe(1)
  })
})

describe("versions — row rendering detail", () => {
  let element, ctrl
  beforeEach(async () => { ({ element, ctrl } = await mount()); ctrl.parentId = "1" })

  it("marks the first- and second-selected rows A and B respectively", () => {
    ctrl.versions = [version(3, 3), version(2, 2), version(1, 1)]
    ctrl.selected = ["3", "2"]
    ctrl._renderList()
    const rows = element.querySelectorAll('[data-versions-target="list"] tr')
    expect(rows[0].textContent).toContain("A")
    expect(rows[1].textContent).toContain("B")
  })

  it("renders the based-on-version badge when based_on_version_number is present", () => {
    ctrl.versions = [version(2, 2, { based_on_version_number: 1 }), version(1, 1)]
    ctrl._renderList()
    const rows = element.querySelectorAll('[data-versions-target="list"] tr')
    expect(rows[0].innerHTML).toContain("v1")
  })

  it("falls back to italic 'No description' when a version has no description", () => {
    ctrl.versions = [version(1, 1, { description: "" })]
    ctrl._renderList()
    const rows = element.querySelectorAll('[data-versions-target="list"] tr')
    expect(rows[0].textContent).toContain("No description")
    expect(rows[0].innerHTML).toContain("italic text-text-muted")
  })
})

describe("versions — _refreshList", () => {
  afterEach(() => { document.querySelector("turbo-frame#admin-table")?.remove() })

  it("no-ops when the admin-table turbo-frame isn't on the page", async () => {
    const { ctrl } = await mount()
    expect(() => ctrl._refreshList()).not.toThrow()
  })

  it("forces a reload when the frame already has a src", async () => {
    const { ctrl } = await mount()
    const frame = document.createElement("turbo-frame")
    frame.id = "admin-table"
    frame.src = "/1/admin/x" // property assignment, as a real turbo-frame custom element reflects
    frame.reload = vi.fn()
    document.body.appendChild(frame)
    ctrl._refreshList()
    expect(frame.reload).toHaveBeenCalled()
  })

  it("assigns src to trigger the first load when the frame is eager (no src yet)", async () => {
    const { ctrl } = await mount()
    const frame = document.createElement("turbo-frame")
    frame.id = "admin-table"
    document.body.appendChild(frame)
    ctrl._refreshList()
    expect(frame.src).toBe(window.location.href)
  })
})

describe("versions — optional-target guards (minimal fixture)", () => {
  it("open/close/_renderList/_renderPagination/_error/_clearError no-op gracefully without their optional targets", async () => {
    const { ctrl } = await mountBare()
    ctrl.parentId = "1"
    expect(() => ctrl.open(ev({ id: "1", name: "X" }))).not.toThrow()
    expect(() => ctrl.close(ev())).not.toThrow()
    ctrl.versions = [version(1, 1)]
    expect(() => ctrl._renderList()).not.toThrow()
    expect(() => ctrl._renderPagination()).not.toThrow()
    expect(() => ctrl._error("boom")).not.toThrow()
    expect(() => ctrl._clearError()).not.toThrow()
  })

  it("_error writes to the error target directly when there's no separate errorMessage target", async () => {
    const { element, ctrl } = await mountBare(errorOnlyHtml)
    ctrl._error("plain message")
    const err = element.querySelector('[data-versions-target="error"]')
    expect(err.textContent).toBe("plain message")
    expect(err.classList.contains("hidden")).toBe(false)
  })
})

describe("versions — create page from entity version", () => {
  const entitiesHtml = html.replace('data-versions-resource-value="flowcharts"', 'data-versions-resource-value="entities"')

  async function mountEntities() {
    const { application, element } = await mountController("versions", Controller, entitiesHtml)
    const ctrl = controllerFor(application, element, "versions")
    ctrl.parentId = "1"
    return { application, element, ctrl }
  }

  it("hides Set default and Delete on a read-only shared fallback line", async () => {
    const { element, ctrl } = await mountEntities()
    ctrl.versions = [
      version(3, 3, { is_default: true, writable: false }),
      version(2, 2, { writable: false })
    ]
    ctrl._renderList()
    expect(element.querySelector('[data-action="click->versions#createPage"]')).not.toBeNull()
    expect(element.querySelector('[data-action="click->versions#setDefault"]')).toBeNull()
    expect(element.querySelector('[data-action="click->versions#destroy"]')).toBeNull()
    expect(element.querySelector('[data-action="click->versions#view"]')).not.toBeNull()
  })

  it("shows Create page on entity versions when none have generated_page_id", async () => {
    const { element, ctrl } = await mountEntities()
    ctrl.versions = [version(3, 3, { is_default: true }), version(2, 2)]
    ctrl._renderList()
    expect(element.querySelector('[data-action="click->versions#createPage"]')).not.toBeNull()
    expect(element.querySelectorAll('[data-action="click->versions#createPage"]').length).toBe(2)
  })

  it("hides Create page only on the version that already has a generated page", async () => {
    const { element, ctrl } = await mountEntities()
    ctrl.versions = [
      version(3, 3, { is_default: true, generated_page_id: 99 }),
      version(2, 2)
    ]
    ctrl._renderList()
    const buttons = element.querySelectorAll('[data-action="click->versions#createPage"]')
    expect(buttons.length).toBe(1)
    expect(buttons[0].getAttribute("data-versions-id-param")).toBe("2")
  })

  it("does not show Create page for non-entity resources", async () => {
    const { element, ctrl } = await mount()
    ctrl.parentId = "1"
    ctrl.versions = [version(3, 3, { is_default: true })]
    ctrl._renderList()
    expect(element.querySelector('[data-action="click->versions#createPage"]')).toBeNull()
  })

  it("navigates to the created page detail on success", async () => {
    const { ctrl } = await mountEntities()
    const assign = vi.spyOn(window.location, "assign").mockImplementation(() => {})
    const reload = vi.spyOn(ctrl, "loadVersions")
    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: true, status: 200, json: async () => ({ success: true, url: "/42/admin/maintenance/pages/9" })
    })))
    await ctrl.createPage(ev({ id: 3 }))
    expect(assign).toHaveBeenCalledWith("/42/admin/maintenance/pages/9")
    expect(reload).not.toHaveBeenCalled()
  })

  it("reloads versions when the success body has no url", async () => {
    const { ctrl } = await mountEntities()
    const assign = vi.spyOn(window.location, "assign").mockImplementation(() => {})
    const reload = vi.spyOn(ctrl, "loadVersions").mockResolvedValue()
    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: true, status: 200, json: async () => { throw new Error("bad json") }
    })))
    await ctrl.createPage(ev({ id: 3 }))
    expect(assign).not.toHaveBeenCalled()
    expect(reload).toHaveBeenCalledWith(true)
  })

  it("no-ops when fetch returns null", async () => {
    const { element, ctrl } = await mountEntities()
    vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("down") }))
    await ctrl.createPage(ev({ id: 3 }))
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toContain("Network error")
  })

  it("surfaces the 422 message, falling back when the body has none", async () => {
    const { element, ctrl } = await mountEntities()
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 422, json: async () => ({ message: "already exists" }) })))
    await ctrl.createPage(ev({ id: 3 }))
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toBe("already exists")

    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 422, json: async () => { throw new Error("nope") } })))
    await ctrl.createPage(ev({ id: 3 }))
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toContain("Failed to create page (422)")
  })

  it("shows the Shared Resources path-lock message on 403", async () => {
    const { element, ctrl } = await mountEntities()
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 403 })))
    await ctrl.createPage(ev({ id: 3 }))
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toContain("Shared Resources")
  })

  it("surfaces a generic failure message for other non-OK statuses", async () => {
    const { element, ctrl } = await mountEntities()
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 500 })))
    await ctrl.createPage(ev({ id: 3 }))
    expect(element.querySelector('[data-versions-target="errorMessage"]').textContent).toContain("Failed to create page (500)")
  })
})

describe("versions — _renderDiff with a synthetic null-side row", () => {
  it("renders an empty cell when a row side is null (defensive branch, not produced by real versionDiff)", async () => {
    const { element, ctrl } = await mount()
    ctrl.parentId = "1"
    vi.mocked(versionDiff).mockReturnValueOnce([{ type: "context", left: null, right: null }])
    ctrl._renderDiff({ version_number: 1, configuration: {} }, { version_number: 2, configuration: {} })
    const content = element.querySelector('[data-versions-target="content"]')
    expect(content.querySelectorAll("td")[0].textContent).toBe("")
    expect(content.querySelectorAll("td")[1].textContent).toBe("")
  })
})

