import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/grants_editor_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

// One checkbox row. `originalChecked` seeds the "dirty vs saved" baseline.
const row = ({ label, groupKey, action, checked = false, original = false, subjKey }) => `
  <div data-grants-editor-target="row" data-group-key="${groupKey}"
       data-display-label="${label}" data-row-label="${label.toLowerCase()}" data-actions="${action}" data-row-granted="${checked}">
    <p class="text-sm">${label}</p>
    <label class="grants-checkbox-label">
      <input type="checkbox" class="grants-checkbox" ${checked ? "checked" : ""}
        data-grants-editor-target="checkbox"
        data-grants-editor-group-key-param="${groupKey}"
        data-grants-editor-original-checked-param="${original}"
        data-grants-editor-subject-type-param="Model"
        data-grants-editor-subject-key-param="${subjKey}"
        data-grants-editor-subject-id-param="1"
        data-action-name="${action}">
      <span>${action === "read" ? "Read records" : "Change records"}</span>
    </label>
  </div>`

const group = (key, rows) => `
  <div data-grants-editor-target="group" data-group-key="${key}">
    <span data-grants-editor-target="groupCount" data-group-key="${key}">0</span>
    <span data-grants-editor-target="groupDirty" data-group-key="${key}" class="hidden"></span>
    ${rows}
  </div>`

const html = `
  <div data-controller="grants-editor" data-grants-editor-update-url-value="/42/admin/grants">
    ${group("g1", row({ label: "View Users", groupKey: "g1", action: "read", subjKey: "users" }) +
                   row({ label: "Edit Users", groupKey: "g1", action: "write", checked: true, original: true, subjKey: "users" }))}
    ${group("g2", row({ label: "View Posts", groupKey: "g2", action: "read", subjKey: "posts" }))}
    <input data-grants-editor-target="search" data-action="input->grants-editor#filter">
    <div data-grants-editor-target="emptyState" class="hidden"></div>
    <div data-grants-editor-target="saveBar" class="translate-y-full">
      <span data-grants-editor-target="dirtyCount"></span>
      <button data-grants-editor-target="saveButton">Save grants</button>
    </div>
    <span data-grants-editor-target="counter"></span>
    <div data-grants-editor-target="diffDrawer" class="hidden">
      <div data-grants-editor-target="diffContent"></div>
    </div>
  </div>`

// Same markup with the controller locked (read-only): toggles/bulk ops/save must no-op.
const lockedHtml = html.replace(
  'data-grants-editor-update-url-value="/42/admin/grants"',
  'data-grants-editor-update-url-value="/x" data-grants-editor-locked-value="true"'
)

const cbAt = (el, i) => el.querySelectorAll("input.grants-checkbox")[i]
const t = (el, n) => el.querySelector(`[data-grants-editor-target='${n}']`)

describe("grants-editor controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    globalThis.alert = vi.fn()
    globalThis.confirm = vi.fn(() => true)
    document.head.innerHTML = `<meta name="csrf-token" content="tok">`
    ;({ application, element } = await mountController("grants-editor", Controller, html))
    ctrl = controllerFor(application, element, "grants-editor")
  })
  afterEach(() => {
    vi.restoreAllMocks()
    document.head.innerHTML = ""
  })

  // Flip checkbox `i` (default: check it) and run the controller's toggle for group g1.
  const toggleRow = (i, checked = true) => {
    const cb = cbAt(element, i)
    cb.checked = checked
    ctrl.toggle({ target: cb, params: { groupKey: "g1" } })
    return cb
  }

  // Mount a second, locked instance and flip+toggle its first checkbox.
  const mountLocked = async () => {
    const m = await mountController("grants-editor", Controller, lockedHtml)
    const lctrl = controllerFor(m.application, m.element, "grants-editor")
    const cb = m.element.querySelectorAll("input.grants-checkbox")[0]
    cb.checked = true
    lctrl.toggle({ target: cb, params: { groupKey: "g1" } })
    return { lctrl, lel: m.element, cb }
  }

  describe("initial state", () => {
    it("reports zero dirty changes and the granted counter", () => {
      expect(ctrl.dirtyCount()).toBe(0)
      expect(t(element, "counter").textContent).toBe("1 / 3 granted")
      expect(t(element, "saveBar").classList.contains("translate-y-full")).toBe(true)
    })
  })

  describe("toggle", () => {
    it("marks a checkbox dirty and surfaces the save bar", () => {
      const cb = toggleRow(0)
      expect(ctrl.dirtyCount()).toBe(1)
      expect(cb.closest(".grants-checkbox-label").classList.contains("grants-dirty")).toBe(true)
      expect(t(element, "saveBar").classList.contains("translate-y-full")).toBe(false)
      expect(t(element, "dirtyCount").textContent).toBe("1 change")
    })

    it("toggling back to the original state clears dirtiness", () => {
      const cb = toggleRow(1, false) // originally checked
      expect(ctrl.dirtyCount()).toBe(1)
      cb.checked = true
      ctrl.toggle({ target: cb, params: { groupKey: "g1" } })
      expect(ctrl.dirtyCount()).toBe(0)
    })

    it("does nothing when locked", async () => {
      const { lctrl, cb } = await mountLocked()
      expect(lctrl.dirtyCount()).toBe(1) // checkbox state changed, but no dirty class applied
      expect(cb.closest(".grants-checkbox-label").classList.contains("grants-dirty")).toBe(false)
    })
  })

  describe("group bulk operations", () => {
    it("grantAllInGroup checks every box in the group and updates the count", () => {
      ctrl.grantAllInGroup({ currentTarget: { dataset: { groupKey: "g1" } } })
      expect(ctrl.checkboxesInGroup("g1").every((cb) => cb.checked)).toBe(true)
      expect(t(element, "counter").textContent).toContain("granted")
      const counter = element.querySelector("[data-grants-editor-target='groupCount'][data-group-key='g1']")
      expect(counter.textContent).toBe("2")
    })

    it("revokeAllInGroup unchecks every box in the group", () => {
      ctrl.revokeAllInGroup({ currentTarget: { dataset: { groupKey: "g1" } } })
      expect(ctrl.checkboxesInGroup("g1").some((cb) => cb.checked)).toBe(false)
    })
  })

  describe("filtering", () => {
    it("combines subsystem search with the existing action and only-granted controls through native events", async () => {
      const labels = ["平台管理 — 邮件 — 凭据", "平台管理 — 短信 — 凭据", "平台管理 — 邮件 — 设置"]
      ctrl.rowTargets.forEach((resource, index) => {
        resource.dataset.displayLabel = labels[index]
        resource.dataset.rowLabel = labels[index].toLowerCase()
      })
      const toolbar = document.createElement("div")
      toolbar.innerHTML = `<button data-action="click->grants-editor#toggleOnlyGranted">已授权</button>
        <button data-action="click->grants-editor#toggleActionFilter" data-action-name="read">查看</button>`
      element.appendChild(toolbar)
      await new Promise(resolve => setTimeout(resolve, 0))
      const search = t(element, "search")
      const visible = () => ctrl.rowTargets.filter(resource => !resource.classList.contains("hidden"))
      search.value = "邮件"
      search.dispatchEvent(new Event("input", { bubbles: true }))
      expect(visible().map(resource => resource.dataset.displayLabel)).toEqual([labels[0], labels[2]])
      toolbar.children[0].click()
      expect(visible()).toHaveLength(0)
      expect(t(element, "emptyState").classList.contains("hidden")).toBe(false)
      search.value = "短信"
      search.dispatchEvent(new Event("input", { bubbles: true }))
      expect(visible().map(resource => resource.dataset.displayLabel)).toEqual([labels[1]])
      toolbar.children[1].click()
      expect(visible()).toHaveLength(0)
      toolbar.children[1].click()
      expect(visible()).toHaveLength(1)
      expect(ctrl.groupTargets[1].classList.contains("hidden")).toBe(true)
      toolbar.children[0].click()
      search.value = ""
      search.dispatchEvent(new Event("input", { bubbles: true }))
      expect(visible()).toHaveLength(3)
      expect(ctrl.dirtyCount()).toBe(0)
    })

    it("filters rows by search term and shows the empty state when nothing matches", () => {
      ctrl.filter({ target: { value: "users" } })
      const visible = ctrl.rowTargets.filter((r) => !r.classList.contains("hidden"))
      expect(visible.length).toBe(2)
      ctrl.filter({ target: { value: "nonexistent" } })
      expect(t(element, "emptyState").classList.contains("hidden")).toBe(false)
    })

    it("action filter narrows to rows carrying the action", () => {
      ctrl.toggleActionFilter({ currentTarget: { dataset: { actionName: "write" }, classList: { add() {}, remove() {} } } })
      const visible = ctrl.rowTargets.filter((r) => !r.classList.contains("hidden"))
      expect(visible.length).toBe(1)
      expect(visible[0].dataset.rowLabel).toBe("edit users")
    })

    it("only-granted filter hides rows with no granted action", () => {
      ctrl.toggleOnlyGranted({ currentTarget: { classList: { toggle() {} } } })
      const visible = ctrl.rowTargets.filter((r) => !r.classList.contains("hidden"))
      expect(visible.every((r) => r.dataset.rowGranted === "true")).toBe(true)
    })
  })

  describe("discard", () => {
    it("resets checkboxes to their saved state after confirmation", () => {
      const cb = toggleRow(0)
      expect(ctrl.dirtyCount()).toBe(1)
      ctrl.discard()
      expect(globalThis.confirm).toHaveBeenCalled()
      expect(cb.checked).toBe(false)
      expect(ctrl.dirtyCount()).toBe(0)
    })

    it("does nothing when there are no changes", () => {
      ctrl.discard()
      expect(globalThis.confirm).not.toHaveBeenCalled()
    })
  })

  describe("diff drawer", () => {
    it("openDiff lists added/removed changes; closeDiff hides it", () => {
      toggleRow(0)
      ctrl.openDiff()
      expect(t(element, "diffDrawer").classList.contains("hidden")).toBe(false)
      expect(t(element, "diffContent").textContent).toContain("Added")
      expect(t(element, "diffContent").textContent).toContain("View Users")
      ctrl.closeDiff()
      expect(t(element, "diffDrawer").classList.contains("hidden")).toBe(true)
    })

    it("openDiff no-ops with no dirty changes", () => {
      ctrl.openDiff()
      expect(t(element, "diffDrawer").classList.contains("hidden")).toBe(true)
    })
  })

  describe("save", () => {
    it("PATCHes the added/removed grants payload", async () => {
      toggleRow(0) // read/users -> newly added
      globalThis.fetch = vi.fn(() => Promise.resolve({ ok: false, json: () => Promise.resolve({ errors: "nope" }) }))
      await ctrl.save()
      expect(globalThis.fetch).toHaveBeenCalledWith(
        "/42/admin/grants",
        expect.objectContaining({ method: "PATCH", headers: expect.objectContaining({ "X-CSRF-Token": "tok" }) })
      )
      const body = JSON.parse(globalThis.fetch.mock.calls[0][1].body)
      expect(body.role_grants.added).toEqual([
        { subject_type: "Model", subject_key: "users", subject_id: 1, action: "read" },
      ])
      expect(body.role_grants.removed).toEqual([])
      expect(globalThis.alert).toHaveBeenCalled() // non-ok -> alert
    })

    it("no-ops when there are no dirty changes", async () => {
      globalThis.fetch = vi.fn()
      await ctrl.save()
      expect(globalThis.fetch).not.toHaveBeenCalled()
    })
  })

  describe("keyboard", () => {
    it("Escape closes an open diff drawer", () => {
      toggleRow(0)
      ctrl.openDiff()
      ctrl.handleKeydown({ key: "Escape", preventDefault() {} })
      expect(t(element, "diffDrawer").classList.contains("hidden")).toBe(true)
    })
  })

  it("esc() encodes html-significant characters", () => {
    expect(ctrl.esc(`<a>&"'`)).toBe("&lt;a&gt;&amp;&quot;&#39;")
    expect(ctrl.esc(null)).toBe("")
  })

  describe("disconnect", () => {
    it("removes the document keydown listener", () => {
      const spy = vi.spyOn(document, "removeEventListener")
      ctrl.disconnect()
      expect(spy).toHaveBeenCalledWith("keydown", ctrl._keyHandler)
    })
  })

  describe("keyboard shortcut", () => {
    it("Cmd/Ctrl+S saves when dirty and unlocked", () => {
      toggleRow(0)
      const saveSpy = vi.spyOn(ctrl, "save").mockImplementation(() => {})
      const preventDefault = vi.fn()
      ctrl.handleKeydown({ metaKey: true, key: "s", preventDefault })
      expect(preventDefault).toHaveBeenCalled()
      expect(saveSpy).toHaveBeenCalled()
    })

    it("ignores Cmd+S when there are no dirty changes", () => {
      const saveSpy = vi.spyOn(ctrl, "save").mockImplementation(() => {})
      ctrl.handleKeydown({ ctrlKey: true, key: "s", preventDefault() {} })
      expect(saveSpy).not.toHaveBeenCalled()
    })

    it("ignores Cmd+S when locked", async () => {
      const { lctrl } = await mountLocked()
      const saveSpy = vi.spyOn(lctrl, "save").mockImplementation(() => {})
      lctrl.handleKeydown({ metaKey: true, key: "s", preventDefault() {} })
      expect(saveSpy).not.toHaveBeenCalled()
    })

    it("ignores other keys", () => {
      const saveSpy = vi.spyOn(ctrl, "save").mockImplementation(() => {})
      ctrl.handleKeydown({ key: "a", preventDefault() {} })
      expect(saveSpy).not.toHaveBeenCalled()
    })

    it("Escape is a no-op when the diff drawer is already hidden", () => {
      expect(t(element, "diffDrawer").classList.contains("hidden")).toBe(true)
      ctrl.handleKeydown({ key: "Escape", preventDefault() {} })
      expect(t(element, "diffDrawer").classList.contains("hidden")).toBe(true)
    })
  })

  describe("locked group bulk operations", () => {
    it("grantAllInGroup no-ops when locked", async () => {
      const { lctrl } = await mountLocked()
      lctrl.grantAllInGroup({ currentTarget: { dataset: { groupKey: "g2" } } })
      expect(lctrl.checkboxesInGroup("g2").every((cb) => !cb.checked)).toBe(true)
    })

    it("revokeAllInGroup no-ops when locked", async () => {
      // Pristine locked instance (no toggle) so g1 keeps its single seeded check.
      const m = await mountController("grants-editor", Controller, lockedHtml)
      const lctrl = controllerFor(m.application, m.element, "grants-editor")
      lctrl.revokeAllInGroup({ currentTarget: { dataset: { groupKey: "g1" } } })
      expect(lctrl.checkboxesInGroup("g1").filter((cb) => cb.checked).length).toBe(1) // untouched
    })
  })

  describe("updateRowGrantedAttr edge cases", () => {
    it("no-ops when passed a falsy row", () => {
      expect(() => ctrl.updateRowGrantedAttr(null)).not.toThrow()
    })

    it("re-applies filters when onlyGranted is active", () => {
      ctrl.onlyGranted = true
      const applySpy = vi.spyOn(ctrl, "applyFilters")
      const row = element.querySelector("[data-grants-editor-target='row']")
      ctrl.updateRowGrantedAttr(row)
      expect(applySpy).toHaveBeenCalled()
    })
  })

  describe("updateGroupCount edge cases", () => {
    it("no-ops when no groupCount target matches the key", () => {
      expect(() => ctrl.updateGroupCount("nonexistent-group")).not.toThrow()
    })
  })

  describe("filter fallback", () => {
    it("treats a missing target value as an empty search term", () => {
      ctrl.filter({ target: { value: null } })
      expect(ctrl.searchTerm).toBe("")
      const visible = ctrl.rowTargets.filter((r) => !r.classList.contains("hidden"))
      expect(visible.length).toBe(3)
    })
  })

  describe("toggleActionFilter removal", () => {
    it("removing an already-active filter clears it and the pill class", () => {
      const classList = { add: vi.fn(), remove: vi.fn() }
      const btn = { dataset: { actionName: "write" }, classList }
      ctrl.toggleActionFilter({ currentTarget: btn })
      expect(classList.add).toHaveBeenCalledWith("grants-action-pill-active")
      ctrl.toggleActionFilter({ currentTarget: btn })
      expect(classList.remove).toHaveBeenCalledWith("grants-action-pill-active")
      expect(ctrl.activeActionFilters.has("write")).toBe(false)
    })
  })

  describe("applyFilters dataset fallbacks", () => {
    it("treats rows with no label/actions dataset as empty strings", () => {
      const rowEl = element.querySelector("[data-grants-editor-target='row']")
      delete rowEl.dataset.rowLabel
      delete rowEl.dataset.actions
      ctrl.searchTerm = ""
      expect(() => ctrl.applyFilters()).not.toThrow()
      expect(rowEl.classList.contains("hidden")).toBe(false)
    })
  })

  describe("discard cancellation", () => {
    it("keeps dirty state when the user declines the confirm prompt", () => {
      toggleRow(0)
      globalThis.confirm = vi.fn(() => false)
      ctrl.discard()
      expect(ctrl.dirtyCount()).toBe(1)
    })
  })

  describe("diff drawer content edge cases", () => {
    it("keeps subsystem context in review and preserves the distinct route payloads", async () => {
      const keys = ["admin/maintenance/platform/captcha/settings", "admin/maintenance/platform/billing/settings"]
      const labels = ["平台管理 — 验证码 — 设置", "平台管理 — 订阅与账单 — 设置"]
      ;[0, 2].forEach((index, n) => {
        const checkbox = toggleRow(index)
        checkbox.dataset.grantsEditorSubjectKeyParam = keys[n]
        const resource = checkbox.closest("[data-grants-editor-target='row']")
        resource.dataset.displayLabel = labels[n]
        resource.querySelector("p").textContent = "设置"
      })
      ctrl.openDiff()
      const content = t(element, "diffContent").textContent
      labels.forEach(label => expect(content).toContain(label))
      keys.forEach(key => expect(content).not.toContain(key))
      globalThis.fetch = vi.fn(() => Promise.resolve({ ok: false, json: () => Promise.resolve({}) }))
      await ctrl.save()
      expect(JSON.parse(globalThis.fetch.mock.calls[0][1].body).role_grants.added.map(grant => grant.subject_key)).toEqual(keys)
    })

    it("reviews translated actions and resource names without authorization identifiers", () => {
      const checkbox = toggleRow(0)
      checkbox.dataset.grantsEditorSubjectKeyParam = "admin/internal_people"
      checkbox.closest("label").querySelector("span").textContent = "查看记录"
      ctrl.openDiff()
      const content = t(element, "diffContent")
      expect(content.textContent).toContain("查看记录")
      expect(content.textContent).toContain("View Users")
      expect(content.textContent).not.toContain("admin/internal_people")
      expect(content.querySelector("[style]")).toBeNull()
      expect(checkbox.dataset.actionName).toBe("read")
    })

    it("falls back to 'No changes yet' when dirtyCount is stubbed truthy but nothing is actually dirty", () => {
      vi.spyOn(ctrl, "dirtyCount").mockReturnValue(1)
      ctrl.openDiff()
      expect(t(element, "diffContent").textContent).toContain("No changes yet")
    })

    it("renders both Added and Removed sections with subject-key and label fallbacks", () => {
      const added = toggleRow(0) // read/users, unchecked -> check it
      toggleRow(1, false) // write/users, originally checked -> uncheck it
      // A missing display label must never fall back to an authorization key.
      added.dataset.grantsEditorSubjectKeyParam = ""
      const row = added.closest("[data-grants-editor-target='row']")
      delete row.dataset.displayLabel
      ctrl.openDiff()
      const content = t(element, "diffContent").textContent
      expect(content).toContain("Added")
      expect(content).toContain("Removed")
    })

    it("closeDiffOnBackdrop closes only when the click target is the backdrop itself", () => {
      toggleRow(0)
      ctrl.openDiff()
      const drawer = t(element, "diffDrawer")
      ctrl.closeDiffOnBackdrop({ target: t(element, "diffContent") })
      expect(drawer.classList.contains("hidden")).toBe(false)
      ctrl.closeDiffOnBackdrop({ target: drawer })
      expect(drawer.classList.contains("hidden")).toBe(true)
    })
  })

  describe("save edge cases", () => {
    it("reloads the page on a successful save", async () => {
      toggleRow(0)
      const originalLocation = window.location
      window.location = { ...originalLocation, reload: vi.fn() }
      globalThis.fetch = vi.fn(() => Promise.resolve({ ok: true, json: () => Promise.resolve({}) }))
      await ctrl.save()
      expect(window.location.reload).toHaveBeenCalled()
      window.location = originalLocation
    })

    it("alerts 'unknown error' when the failure response carries no errors payload", async () => {
      toggleRow(0)
      globalThis.fetch = vi.fn(() => Promise.resolve({ ok: false, json: () => Promise.resolve({}) }))
      await ctrl.save()
      expect(globalThis.alert).toHaveBeenCalledWith("Save failed: unknown error")
    })

    it("alerts the exception message and re-enables the save button when fetch rejects", async () => {
      toggleRow(0)
      globalThis.fetch = vi.fn(() => Promise.reject(new Error("network down")))
      await ctrl.save()
      expect(globalThis.alert).toHaveBeenCalledWith("Save failed: network down")
      expect(t(element, "saveButton").disabled).toBe(false)
      expect(t(element, "saveButton").textContent).toBe("Save grants")
    })

    it("serializes null subject_key/subject_id when the dataset params are absent", async () => {
      const cb = cbAt(element, 0)
      delete cb.dataset.grantsEditorSubjectKeyParam
      delete cb.dataset.grantsEditorSubjectIdParam
      cb.checked = true
      ctrl.toggle({ target: cb, params: { groupKey: "g1" } })
      globalThis.fetch = vi.fn(() => Promise.resolve({ ok: false, json: () => Promise.resolve({}) }))
      await ctrl.save()
      const body = JSON.parse(globalThis.fetch.mock.calls[0][1].body)
      expect(body.role_grants.added[0].subject_key).toBeNull()
      expect(body.role_grants.added[0].subject_id).toBeNull()
    })
  })
})
