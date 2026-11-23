import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/segment_builder_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

// happy-dom 15.x's query-selector engine does not implement the `:scope`
// pseudo-class at all (`el.querySelector(":scope > x")` always returns null,
// `querySelectorAll` always returns empty) — see
// node_modules/happy-dom/src/query-selector/QuerySelector.ts, which has no
// handling for it. `:scope` is fully supported in every real browser and is
// exactly what this controller uses (`:scope > [data-sb-rows]`,
// `:scope > [data-sb-row], :scope > [data-sb-group]`) to scan a group's own
// direct-child members without reaching into nested groups. Without a patch,
// EVERY method that touches `:scope` (_rowsContainer, _readGroup,
// _memberCount, _lastMember) silently no-ops in this environment, which
// would make addRow/addGroup/serialize untestable — not because the
// controller is broken, but because the DOM shim is incomplete. Patch
// querySelector/querySelectorAll for this file only to implement the one
// pattern the controller relies on (`:scope > selector[, :scope > selector]`
// = direct children matching selector, in document order), restoring real
// browser semantics so the controller's actual logic gets exercised.
function scopeChildMatches(el, selector) {
  const childSelectors = []
  let includeSelf = false
  selector.split(",").forEach((clause) => {
    clause = clause.trim()
    const m = clause.match(/^:scope\s*>\s*(.+)$/)
    if (m) childSelectors.push(m[1])
    else if (clause === ":scope") includeSelf = true
  })
  const results = includeSelf ? [el] : []
  Array.from(el.children).forEach((child) => {
    if (childSelectors.some((sel) => child.matches(sel))) results.push(child)
  })
  return results
}
const nativeQuerySelector = Element.prototype.querySelector
const nativeQuerySelectorAll = Element.prototype.querySelectorAll
Element.prototype.querySelector = function (selector) {
  if (typeof selector === "string" && selector.includes(":scope")) {
    return scopeChildMatches(this, selector)[0] || null
  }
  return nativeQuerySelector.call(this, selector)
}
Element.prototype.querySelectorAll = function (selector) {
  if (typeof selector === "string" && selector.includes(":scope")) {
    return scopeChildMatches(this, selector)
  }
  return nativeQuerySelectorAll.call(this, selector)
}

// Mirrors the SegmentBuilderComponent DOM contract. Rows/groups/joins are
// cloned from <template> elements. No geometry — the controller only walks the
// DOM and serializes JSON into the hidden output.
const fieldSelect = `<select data-sb-field><option value="amount" selected>Amount</option><option value="name">Name</option></select>`
const rowInner = `${fieldSelect}<select data-sb-operator></select><input data-sb-value>`

const html = `
  <div data-controller="segment-builder"
       data-segment-builder-fields-value='{"amount":{"operators":["gt","lt"]},"name":{"operators":["eq","contains"]}}'>
    <div data-segment-builder-target="groupRoot" data-sb-group>
      <div data-sb-rows></div>
    </div>
    <input type="hidden" data-segment-builder-target="output">
    <template data-segment-builder-target="rowTemplate"><div data-sb-row>${rowInner}</div></template>
    <template data-segment-builder-target="groupTemplate"><div data-sb-group><div data-sb-rows><div data-sb-row>${rowInner}</div></div></div></template>
    <template data-segment-builder-target="joinTemplate"><div data-sb-join-wrap><button data-sb-join="AND" data-action="click->segment-builder#toggleJoin">AND</button></div></template>
  </div>`

const output = (el) => JSON.parse(el.querySelector("[data-segment-builder-target='output']").value)
const rowsContainer = (el) => el.querySelector("[data-segment-builder-target='groupRoot'] > [data-sb-rows]")

describe("segment-builder controller", () => {
  let application, element, ctrl
  beforeEach(async () => {
    ;({ application, element } = await mountController("segment-builder", Controller, html))
    ctrl = controllerFor(application, element, "segment-builder")
  })

  it("serializes an empty root group on connect", () => {
    expect(output(element)).toEqual({ type: "group", joins: [], conditions: [] })
  })

  it("addRow appends a condition and populates its operators from the field catalog", () => {
    ctrl.addRow({ target: rowsContainer(element) })
    const out = output(element)
    expect(out.conditions.length).toBe(1)
    expect(out.conditions[0]).toEqual({ field: "amount", operator: "gt", value: "" })
    // operator select got populated
    const opEl = element.querySelector("[data-sb-row] [data-sb-operator]")
    expect([...opEl.options].map((o) => o.value)).toEqual(["gt", "lt"])
  })

  it("adding a second row inserts an AND join between them", () => {
    ctrl.addRow({ target: rowsContainer(element) })
    ctrl.addRow({ target: rowsContainer(element) })
    const out = output(element)
    expect(out.conditions.length).toBe(2)
    expect(out.joins).toEqual(["AND"])
  })

  it("toggleJoin flips a single join AND↔OR and reserializes", () => {
    ctrl.addRow({ target: rowsContainer(element) })
    ctrl.addRow({ target: rowsContainer(element) })
    const joinBtn = element.querySelector("[data-sb-join]")
    ctrl.toggleJoin({ preventDefault() {}, currentTarget: joinBtn })
    expect(joinBtn.getAttribute("data-sb-join")).toBe("OR")
    expect(joinBtn.textContent).toBe("OR")
    expect(output(element).joins).toEqual(["OR"])
  })

  it("fieldChanged repopulates operators for the row's new field", () => {
    ctrl.addRow({ target: rowsContainer(element) })
    const fieldEl = element.querySelector("[data-sb-row] [data-sb-field]")
    fieldEl.value = "name"
    ctrl.fieldChanged({ target: fieldEl })
    const opEl = element.querySelector("[data-sb-row] [data-sb-operator]")
    expect([...opEl.options].map((o) => o.value)).toEqual(["eq", "contains"])
    expect(output(element).conditions[0].field).toBe("name")
  })

  it("addGroup nests a group (with its seeded row) into the root", () => {
    ctrl.addGroup({ target: rowsContainer(element) })
    const out = output(element)
    expect(out.conditions.length).toBe(1)
    expect(out.conditions[0].type).toBe("group")
    expect(out.conditions[0].conditions.length).toBe(1)
  })

  it("removeRow drops the row and its adjacent join, keeping joins aligned", () => {
    ctrl.addRow({ target: rowsContainer(element) })
    ctrl.addRow({ target: rowsContainer(element) })
    const secondRow = element.querySelectorAll("[data-sb-row]")[1]
    ctrl.removeRow({ target: secondRow })
    const out = output(element)
    expect(out.conditions.length).toBe(1)
    expect(out.joins).toEqual([])
  })

  it("removeGroup never removes the root group", () => {
    const root = element.querySelector("[data-segment-builder-target='groupRoot']")
    ctrl.removeGroup({ target: root })
    expect(element.querySelector("[data-segment-builder-target='groupRoot']")).not.toBeNull()
  })

  it("removeGroup removes a nested (non-root) group", () => {
    ctrl.addGroup({ target: rowsContainer(element) })
    const nested = element.querySelector("[data-sb-rows] [data-sb-group]")
    expect(nested).not.toBeNull()
    ctrl.removeGroup({ target: nested })
    expect(element.querySelector("[data-sb-rows] [data-sb-group]")).toBeNull()
    expect(output(element).conditions.length).toBe(0)
  })

  it("addGroup prepends an AND join when the group already has a member", () => {
    ctrl.addRow({ target: rowsContainer(element) })
    ctrl.addGroup({ target: rowsContainer(element) })
    const out = output(element)
    expect(out.conditions.length).toBe(2)
    expect(out.joins).toEqual(["AND"])
  })

  it("removeRow of the FIRST row removes the following join toggle", () => {
    ctrl.addRow({ target: rowsContainer(element) })
    ctrl.addRow({ target: rowsContainer(element) })
    const firstRow = element.querySelectorAll("[data-sb-row]")[0]
    ctrl.removeRow({ target: firstRow })
    const out = output(element)
    expect(out.conditions.length).toBe(1)
    expect(out.joins).toEqual([])
  })

  it("removeRow is a no-op when the target is not inside a row", () => {
    const outputEl = element.querySelector("[data-segment-builder-target='output']")
    expect(() => ctrl.removeRow({ target: outputEl })).not.toThrow()
  })

  it("toggleJoin flips OR back to AND (and repaints AND pill classes)", () => {
    ctrl.addRow({ target: rowsContainer(element) })
    ctrl.addRow({ target: rowsContainer(element) })
    const joinBtn = element.querySelector("[data-sb-join]")
    ctrl.toggleJoin({ preventDefault() {}, currentTarget: joinBtn }) // AND -> OR
    ctrl.toggleJoin({ preventDefault() {}, currentTarget: joinBtn }) // OR -> AND
    expect(joinBtn.getAttribute("data-sb-join")).toBe("AND")
    expect(joinBtn.className).toContain("bg-amber-200")
    expect(output(element).joins).toEqual(["AND"])
  })

  it("addRow falls back to the root group when the target sits outside any group", () => {
    const outputEl = element.querySelector("[data-segment-builder-target='output']")
    ctrl.addRow({ target: outputEl })
    expect(output(element).conditions.length).toBe(1)
  })

  it("_populateOperators clears options for an unknown field and no-ops without field/op elements", () => {
    ctrl.addRow({ target: rowsContainer(element) })
    const row = element.querySelector("[data-sb-row]")
    const fieldEl = row.querySelector("[data-sb-field]")
    fieldEl.insertAdjacentHTML("beforeend", '<option value="zzz">zzz</option>')
    fieldEl.value = "zzz"
    ctrl._populateOperators(row)
    expect(row.querySelector("[data-sb-operator]").options.length).toBe(0)

    const bare = document.createElement("div")
    bare.setAttribute("data-sb-row", "")
    expect(() => ctrl._populateOperators(bare)).not.toThrow()
  })

  it("_readRow returns blanks for a row missing its inputs", () => {
    const bare = document.createElement("div")
    bare.setAttribute("data-sb-row", "")
    expect(ctrl._readRow(bare)).toEqual({ field: "", operator: "", value: "" })
  })

  it("_readGroup skips a leading join and defaults to AND when a join wrapper has no button", () => {
    const g = document.createElement("div")
    g.setAttribute("data-sb-group", "")
    g.innerHTML =
      `<div data-sb-rows>` +
      `<div data-sb-join-wrap><button data-sb-join="AND">AND</button></div>` + // leading, before any condition
      `<div data-sb-row><select data-sb-field></select><select data-sb-operator></select><input data-sb-value></div>` +
      `<div data-sb-join-wrap></div>` + // no button -> defaults to AND
      `<div data-sb-row><select data-sb-field></select><select data-sb-operator></select><input data-sb-value></div>` +
      `</div>`
    const res = ctrl._readGroup(g)
    expect(res.conditions.length).toBe(2)
    expect(res.joins).toEqual(["AND"])
  })

  it("connect populates operator selects for pre-rendered rows, preserving the server operator", async () => {
    const preRow =
      `<div data-sb-row>` +
      `<select data-sb-field><option value="amount" selected>Amount</option></select>` +
      `<select data-sb-operator><option value="lt" selected>lt</option><option value="gt">gt</option></select>` +
      `<input data-sb-value></div>`
    // A second pre-rendered row missing its operator select exercises the null path.
    const preRowNoOp = `<div data-sb-row><select data-sb-field><option value="amount" selected>Amount</option></select></div>`
    const preHtml = html.replace('<div data-sb-rows></div>', `<div data-sb-rows>${preRow}${preRowNoOp}</div>`)
    const m = await mountController("segment-builder", Controller, preHtml)
    const opEl = m.element.querySelector("[data-sb-row] [data-sb-operator]")
    expect([...opEl.options].map((o) => o.value)).toEqual(["gt", "lt"])
    expect(opEl.value).toBe("lt")
  })

  it("addRow is a no-op without a row template", async () => {
    const stripped = html.replace(/<template data-segment-builder-target="rowTemplate">.*?<\/template>/s, "")
    const m = await mountController("segment-builder", Controller, stripped)
    const c = controllerFor(m.application, m.element, "segment-builder")
    const rows = m.element.querySelector("[data-sb-group] > [data-sb-rows]")
    c.addRow({ target: rows })
    expect(m.element.querySelectorAll("[data-sb-row]").length).toBe(0)
  })

  it("addGroup is a no-op without a group template", async () => {
    const stripped = html.replace(/<template data-segment-builder-target="groupTemplate">.*?<\/template>/s, "")
    const m = await mountController("segment-builder", Controller, stripped)
    const c = controllerFor(m.application, m.element, "segment-builder")
    const rows = m.element.querySelector("[data-sb-group] > [data-sb-rows]")
    c.addGroup({ target: rows })
    expect(m.element.querySelectorAll("[data-sb-group]").length).toBe(1) // only the root
  })

  it("_lastMember returns null for an empty rows container", () => {
    const emptyRows = document.createElement("div")
    emptyRows.setAttribute("data-sb-rows", "")
    expect(ctrl._lastMember(emptyRows)).toBeNull()
  })

  it("_rowsContainer returns null when there is no enclosing group and no root", () => {
    // Defensive `group ? … : null` branch: no ancestor group AND no root target.
    const detached = document.createElement("div")
    Object.defineProperty(ctrl, "groupRootTarget", { configurable: true, get: () => null })
    expect(ctrl._rowsContainer(detached)).toBeNull()
  })

  it("serialize and _allRows are safe no-ops without the groupRoot/output targets", async () => {
    const stripped = html
      .replace('data-segment-builder-target="groupRoot" ', "")
      .replace('data-segment-builder-target="output"', "")
    const m = await mountController("segment-builder", Controller, stripped)
    const c = controllerFor(m.application, m.element, "segment-builder")
    expect(c.hasGroupRootTarget).toBe(false)
    expect(c._allRows()).toEqual([])
    expect(() => c.serialize()).not.toThrow()
  })
})
