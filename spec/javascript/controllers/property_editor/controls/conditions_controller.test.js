import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/property_editor/controls/conditions_controller"
import { buildConditionsField } from "controllers/property_editor/controls/conditions"
import { resetReferenceCache } from "controllers/property_editor/controls/reference_options"
import { mountController, controllerFor, tick } from "../../../support/stimulus.js"

const IDENTIFIER = "property-editor--controls--conditions"

function canvasChrome() {
  return `<div data-controller="flowchart-canvas"
              data-flowchart-canvas-customer-id-value="77"
              data-flowchart-canvas-urls-value='{"referenceOptions":"/ref/__SOURCE__.json"}'></div>`
}

async function mount(html, fetchImpl) {
  if (fetchImpl) vi.stubGlobal("fetch", fetchImpl)
  const { application, element } = await mountController(
    IDENTIFIER,
    Controller,
    `${canvasChrome()}${html}`,
  )
  return { application, element, ctrl: controllerFor(application, element, IDENTIFIER) }
}

afterEach(() => {
  resetReferenceCache()
  vi.unstubAllGlobals()
})

describe("conditions controller", () => {
  beforeEach(() => resetReferenceCache())

  it("adds, joins, and removes rows, reseeding when the last row is gone", async () => {
    const html = buildConditionsField({ name: "filter" }, {
      type: "group",
      joins: [],
      conditions: [{ kind: "field", leftOperand: "a", operator: "==", rightOperand: "1" }],
    })
    const { element, ctrl } = await mount(html)
    expect(ctrl.serialized().conditions).toHaveLength(1)

    await ctrl.addRow({ preventDefault() {} })
    expect(element.querySelectorAll("[data-condition-rows] > [data-condition-row]")).toHaveLength(2)
    expect(element.querySelector("[data-condition-join]").value).toBe("AND")

    const second = element.querySelectorAll("[data-condition-row]")[1]
    await ctrl.removeRow({ preventDefault() {}, target: second.querySelector("[data-action*='removeRow']") })
    expect(element.querySelectorAll("[data-condition-rows] > [data-condition-row]")).toHaveLength(1)

    const first = element.querySelector("[data-condition-rows] > [data-condition-row]")
    await ctrl.removeRow({ preventDefault() {}, target: first.querySelector("[data-action*='removeRow']") })
    expect(element.querySelectorAll("[data-condition-rows] > [data-condition-row]")).toHaveLength(1)

    await ctrl.addRow({ preventDefault() {} })
    const leading = element.querySelector("[data-condition-rows] > [data-condition-row]")
    await ctrl.removeRow({ preventDefault() {}, target: leading.querySelector("[data-action*='removeRow']") })
    expect(element.querySelectorAll("[data-condition-rows] > [data-condition-row]")).toHaveLength(1)
  })

  it("no-ops add/remove/switch/operator/where/entity when the chrome is missing", async () => {
    const { element, ctrl } = await mount(`<div data-controller="${IDENTIFIER}"></div>`)
    const loose = document.createElement("button")
    element.appendChild(loose)
    expect(() => ctrl.addRow({ preventDefault() {} })).not.toThrow()
    expect(() => ctrl.removeRow({ preventDefault() {}, target: loose })).not.toThrow()
    expect(() => ctrl.switchKind({ preventDefault() {}, target: loose })).not.toThrow()
    expect(() => ctrl.operatorChanged({ target: loose })).not.toThrow()
    expect(() => ctrl.whereOperatorChanged({ target: loose })).not.toThrow()
    expect(() => ctrl.addWhere({ preventDefault() {}, target: loose })).not.toThrow()
    expect(() => ctrl.removeWhere({ preventDefault() {}, target: loose })).not.toThrow()
    expect(() => ctrl.whereFieldChanged({ target: loose })).not.toThrow()
    expect(() => ctrl.whereFieldToSelect({ preventDefault() {}, target: loose })).not.toThrow()
    expect(() => ctrl.entityChanged({ target: loose })).not.toThrow()
  })

  it("toggles field vs record-count panels and hides unary right operands", async () => {
    const html = buildConditionsField({ name: "filter" }, {
      type: "group",
      conditions: [{ kind: "field", leftOperand: "ctx.a", operator: "==", rightOperand: "1" }],
    })
    const { element, ctrl } = await mount(html, vi.fn(async (url) => {
      if (String(url).includes("reference_options") || String(url).includes("/ref/")) {
        return { ok: true, json: async () => ({ options: [{ value: "5", label: "Users" }] }) }
      }
      return { ok: false }
    }))
    const row = element.querySelector("[data-condition-row]")
    const countBtn = row.querySelector("[data-row-type='query_count']")
    await ctrl.switchKind({ preventDefault() {}, target: countBtn })
    expect(row.dataset.conditionKind).toBe("query_count")
    expect(row.querySelector("[data-condition-row-query-panel]").classList.contains("hidden")).toBe(false)
    expect(row.querySelector("[data-condition-row-field-panel]").classList.contains("hidden")).toBe(true)

    const fieldBtn = row.querySelector("[data-row-type='field']")
    await ctrl.switchKind({ preventDefault() {}, target: fieldBtn })
    expect(row.dataset.conditionKind).toBe("field")

    const op = row.querySelector("[data-condition-op]")
    op.value = "is_empty"
    await ctrl.operatorChanged({ target: op })
    expect(row.querySelector("[data-condition-right-wrap]").classList.contains("hidden")).toBe(true)
    op.value = "=="
    await ctrl.operatorChanged({ target: op })
    expect(row.querySelector("[data-condition-right-wrap]").classList.contains("hidden")).toBe(false)
  })

  it("loads entities from cache on a second row and records a fetch error", async () => {
    const html = buildConditionsField({ name: "filter" }, {
      type: "group",
      conditions: [
        { kind: "query_count", queryConfig: { entityId: 5, entityName: "Users" } },
        { kind: "field", leftOperand: "a", operator: "==", rightOperand: "1" },
      ],
      joins: ["AND"],
    })
    const fetchMock = vi.fn(async (url) => {
      if (String(url).includes("/ref/")) return { ok: true, json: async () => ({ options: [{ value: "5", label: "Users" }, { value: "6", label: "Orders" }] }) }
      return { ok: false }
    })
    const { element, ctrl } = await mount(html, fetchMock)
    const fieldRow = element.querySelector("[data-condition-kind='field']")
    await ctrl.switchKind({ preventDefault() {}, target: fieldRow.querySelector("[data-row-type='query_count']") })
    expect(fetchMock).toHaveBeenCalled()

    const alreadyLoaded = element.querySelector("[data-condition-kind='query_count']")
    await ctrl.loadEntities(alreadyLoaded)
    const select = alreadyLoaded.querySelector("[data-cond-qc-entity]")
    expect([...select.options].some((o) => o.value === "6")).toBe(true)
    select.value = ""
    await ctrl.loadEntities(alreadyLoaded)

    resetReferenceCache()
    ctrl._entityCache = null
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false })))
    const emptyRow = document.createElement("div")
    emptyRow.innerHTML = `<select data-cond-qc-entity><option value=""></option></select>`
    element.appendChild(emptyRow)
    await ctrl.loadEntities(emptyRow)
    expect(emptyRow.querySelector("option[data-entity-load-error]")).not.toBeNull()
    await ctrl.loadEntities(document.createElement("div"))
  })

  it("fetches a schema, adds a where row, and shows errors", async () => {
    const html = buildConditionsField({ name: "filter" }, {
      type: "group",
      conditions: [{ kind: "query_count", queryConfig: { entityId: 5, entityName: "Users" } }],
    })
    const fetchMock = vi.fn(async (url) => {
      if (String(url).includes("/ref/")) return { ok: true, json: async () => ({ options: [{ value: "5", label: "Users" }] }) }
      if (String(url).includes("/entities/5.json")) {
        return { ok: true, json: async () => ({ property_schema: [{ name_slug: "email", name: "Email", html_type: "text" }], name: "Users" }) }
      }
      return { ok: false }
    })
    const { element, ctrl } = await mount(html, fetchMock)
    const row = element.querySelector("[data-condition-row]")
    const select = row.querySelector("[data-cond-qc-entity]")
    select.value = "5"
    await ctrl.entityChanged({ target: select })
    expect(row.querySelectorAll("[data-cond-qc-where-row]")).toHaveLength(1)

    select.value = ""
    await ctrl.entityChanged({ target: select })
    expect(row.querySelector("[data-cond-qc-where-row]")).toBeNull()

    const noWhere = document.createElement("div")
    noWhere.setAttribute("data-condition-row", "")
    noWhere.innerHTML = `<select></select>`
    await ctrl.entityChanged({ target: noWhere.querySelector("select") })

    vi.stubGlobal("fetch", vi.fn(async (url) => {
      if (String(url).includes("/entities/")) return { ok: false }
      return { ok: true, json: async () => ({ options: [] }) }
    }))
    select.value = "5"
    await ctrl.entityChanged({ target: select })
    expect(row.querySelector("[data-cond-qc-schema-error]")).not.toBeNull()
    await ctrl.entityChanged({ target: select })
    expect(row.querySelectorAll("[data-cond-qc-schema-error]")).toHaveLength(1)

    vi.stubGlobal("fetch", vi.fn(async () => { throw new Error("down") }))
    ctrl._clearSchemaError(row)
    await ctrl.entityChanged({ target: select })
    expect(row.querySelector("[data-cond-qc-schema-error]")).not.toBeNull()

    ctrl._clearSchemaError(row)
    element.setAttribute(`data-${IDENTIFIER}-schema-unavailable-label-value`, "<i>架构</i>")
    await ctrl.entityChanged({ target: select })
    const error = row.querySelector("[data-cond-qc-schema-error]")
    expect(error.textContent).toContain("<i>架构</i>")
    expect(error.querySelector("i")).toBeNull()
  })

  it("ignores a stale schema response and a stale rejection", async () => {
    const html = buildConditionsField({ name: "filter" }, {
      type: "group",
      conditions: [{ kind: "query_count", queryConfig: { entityId: 5, entityName: "Users" } }],
    })
    const { element, ctrl } = await mount(html, vi.fn(async (url) => {
      if (String(url).includes("/ref/")) return { ok: true, json: async () => ({ options: [] }) }
      return { ok: true, json: async () => ({}) }
    }))
    const row = element.querySelector("[data-condition-row]")
    const select = row.querySelector("[data-cond-qc-entity]")
    vi.stubGlobal("fetch", vi.fn(async () => {
      ctrl._fetchSeq += 1
      return { ok: true, json: async () => ({ property_schema: [{ name: "X" }], name: "Stale" }) }
    }))
    select.value = "5"
    await ctrl.entityChanged({ target: select })
    expect(row.querySelector("[data-cond-qc-where-row]")).toBeNull()

    vi.stubGlobal("fetch", vi.fn(async () => {
      ctrl._fetchSeq += 1
      throw new Error("boom")
    }))
    ctrl._clearSchemaError(row)
    await ctrl.entityChanged({ target: select })
    expect(row.querySelector("[data-cond-qc-schema-error]")).toBeNull()
  })

  it("adds, swaps, and removes WHERE rows including unary value hiding", async () => {
    const html = buildConditionsField({ name: "filter" }, {
      type: "group",
      conditions: [{ kind: "query_count", queryConfig: { entityId: 5, entityName: "Users" } }],
    })
    const { element, ctrl } = await mount(html, vi.fn(async (url) => {
      if (String(url).includes("/ref/")) return { ok: true, json: async () => ({ options: [{ value: "5", label: "Users" }] }) }
      return { ok: true, json: async () => ({ property_schema: [{ name_slug: "age", html_type: "number" }], name: "Users" }) }
    }))
    const row = element.querySelector("[data-condition-row]")
    const add = row.querySelector("[data-action*='addWhere']")
    await ctrl.addWhere({ preventDefault() {}, target: add })
    await ctrl.addWhere({ preventDefault() {}, target: add })
    expect(row.querySelectorAll("[data-cond-qc-where-row]")).toHaveLength(2)

    const whereRow = row.querySelector("[data-cond-qc-where-row]")
    const fieldSelect = whereRow.querySelector("[data-cond-qc-where-field]")
    fieldSelect.value = "__manual__"
    await ctrl.whereFieldChanged({ target: fieldSelect })
    expect(whereRow.querySelector("[data-cond-qc-where-field-manual]").classList.contains("hidden")).toBe(false)

    await ctrl.whereFieldToSelect({ preventDefault() {}, target: whereRow.querySelector("[data-action*='whereFieldToSelect']") })
    expect(whereRow.querySelector("[data-cond-qc-where-field-manual]").classList.contains("hidden")).toBe(true)

    fieldSelect.innerHTML = `<option value="data.age" data-col-type="number" selected>age</option>`
    fieldSelect.value = "data.age"
    await ctrl.whereFieldChanged({ target: fieldSelect })
    expect(whereRow.dataset.condQcColType).toBe("number")

    fieldSelect.innerHTML = `<option value="created_at" selected>created_at</option>`
    fieldSelect.value = "created_at"
    await ctrl.whereFieldChanged({ target: fieldSelect })
    expect(whereRow.dataset.condQcColType).toBeUndefined()

    const op = whereRow.querySelector("[data-cond-qc-where-op]")
    op.value = "is_empty"
    await ctrl.whereOperatorChanged({ target: op })
    expect(whereRow.querySelector("[data-cond-qc-where-value-wrap]").classList.contains("hidden")).toBe(true)

    const removable = row.querySelector("[data-action*='removeWhere']")
    await ctrl.removeWhere({ preventDefault() {}, target: removable })
    expect(row.querySelectorAll("[data-cond-qc-where-row]")).toHaveLength(1)

    const noValue = document.createElement("div")
    noValue.setAttribute("data-cond-qc-where-row", "")
    noValue.innerHTML = `<select data-cond-qc-where-field><option value="data.age" data-col-type="number" selected></option></select>`
    row.appendChild(noValue)
    await ctrl.whereFieldChanged({ target: noValue.querySelector("select") })
  })

  it("prefills saved query-count rows from schema, including manual unknown fields", async () => {
    const html = buildConditionsField({ name: "filter" }, {
      type: "group",
      conditions: [{
        kind: "query_count",
        queryConfig: {
          entityId: 9,
          entityName: "Orders",
          conditions: { rules: [
            { field: "data.name", op: "==", value: "bob" },
            { field: "custom_col" },
            { op: ">" },
          ] },
        },
        countOperator: ">=",
        countValue: 2,
      }],
    })
    const fetchMock = vi.fn(async (url) => {
      if (String(url).includes("/ref/")) return { ok: true, json: async () => ({ options: [{ value: "9", label: "Orders" }] }) }
      if (String(url).includes("/entities/9.json")) {
        return {
          ok: true,
          json: async () => ({ property_schema: [{ name_slug: "name", name: "Name", html_type: "text" }], name: "Orders" }),
        }
      }
      return { ok: false }
    })
    const { element, ctrl } = await mount(html, fetchMock)
    await tick()
    await ctrl.prefillSavedQueryCounts()
    const rows = element.querySelectorAll("[data-cond-qc-where-row]")
    expect(rows.length).toBeGreaterThanOrEqual(2)
    expect(rows[0].querySelector("[data-cond-qc-where-field]").value).toBe("data.name")
    expect(rows[1].querySelector("[data-cond-qc-where-field-input]").value).toBe("custom_col")
  })

  it("prefills with empty rules, omitted schema name, and no-html_type columns", async () => {
    const html = buildConditionsField({ name: "filter" }, {
      type: "group",
      conditions: [{
        kind: "query_count",
        queryConfig: { entityId: 9, entityName: "Orders", conditions: { rules: [{ field: "data.name", op: "==", value: "x" }] } },
        countOperator: ">",
        countValue: 0,
      }],
    })
    const { element, ctrl } = await mount(html, vi.fn(async (url) => {
      if (String(url).includes("/ref/")) return { ok: true, json: async () => ({ options: [{ value: "9", label: "Orders" }] }) }
      return { ok: true, json: async () => ({ property_schema: [{ name_slug: "name", name: "Name" }] }) }
    }))
    await ctrl.prefillSavedQueryCounts()
    const row = element.querySelector("[data-cond-qc-where-row]")
    expect(row.dataset.condQcColType).toBeUndefined()
    expect(row.querySelector("[data-cond-qc-where-field]").value).toBe("data.name")

    const panel = element.querySelector("[data-condition-row-query-panel]")
    panel.dataset.condQcSavedRules = "[]"
    await ctrl.prefillSavedQueryCounts()

    panel.removeAttribute("data-cond-qc-saved-entity-id")
    panel.dataset.condQcSavedEntityId = ""
    const orphan = document.createElement("div")
    orphan.setAttribute("data-condition-row-query-panel", "")
    orphan.dataset.condQcSavedEntityId = "8"
    element.appendChild(orphan)
    await ctrl.prefillSavedQueryCounts()
  })

  it("skips schema fetch without a customer id and reads the soft-type hint from the editor", async () => {
    document.body.innerHTML = ""
    const html = `<div data-controller="property-editor" data-property-editor-soft-type-hint-title-value="Hint">
      <div data-controller="${IDENTIFIER}">
        <div data-condition-row>
          <div data-condition-row-query-panel></div>
          <select data-cond-qc-entity><option value="5" selected></option></select>
          <div data-cond-qc-where-rows></div>
        </div>
      </div>
    </div>`
    const { application } = await mountController(IDENTIFIER, Controller, html)
    const el = document.querySelector(`[data-controller~="${IDENTIFIER}"]`)
    const ctrl = controllerFor(application, el, IDENTIFIER)
    expect(ctrl._softTypeHint).toBe("Hint")
    const select = el.querySelector("[data-cond-qc-entity]")
    await ctrl.entityChanged({ target: select })
    expect(el.querySelector("[data-cond-qc-where-row]")).toBeNull()
  })

  it("_applyWhereRule no-ops without a row and _showSchemaError no-ops without whereRows", async () => {
    const { ctrl } = await mount(`<div data-controller="${IDENTIFIER}"></div>`)
    ctrl._applyWhereRule(null, { field: "x" })
    ctrl._showSchemaError(null)
    ctrl._clearSchemaError(null)
    ctrl._toggleUnary(null, null)
    ctrl._resetRow(document.createElement("div"))
    ctrl._swapWhereToManual({ target: document.createElement("button") })
    await ctrl._loadSchema(document.createElement("div"), "5")
  })

  it("covers schema load without a panel, unmatched unary options, and incomplete WHERE chrome", async () => {
    const html = buildConditionsField({ name: "filter" }, {
      type: "group",
      conditions: [{ kind: "query_count", queryConfig: { entityId: 5, entityName: "Users" } }],
    })
    const { element, ctrl } = await mount(html, vi.fn(async (url) => {
      if (String(url).includes("/ref/")) return { ok: true, json: async () => ({ options: [{ value: "5", label: "Users" }, { value: "6", label: "Orders" }] }) }
      return { ok: true, json: async () => ({ property_schema: [{ name_slug: "age", html_type: "number" }] }) }
    }))
    const row = document.createElement("div")
    row.setAttribute("data-condition-row", "")
    row.innerHTML = `<div data-cond-qc-where-rows></div>`
    element.appendChild(row)
    await ctrl._loadSchema(row, "5", { addEmptyWhere: true })
    expect(row.querySelector("[data-cond-qc-where-row]")).not.toBeNull()
    await ctrl._loadSchema(row, "5", {})

    const wrap = document.createElement("div")
    wrap.innerHTML = `<input type="text"><input type="checkbox"><input type="hidden">`
    const field = document.createElement("div")
    field.setAttribute("data-conditionally-required", "")
    field.appendChild(wrap)
    element.appendChild(field)
    const select = document.createElement("select")
    select.innerHTML = `<option value="==">==</option><option value="is_empty" data-unary="true">empty</option>`
    select.value = "is_empty"
    wrap.querySelector("input[type='text']").required = true
    ctrl._toggleUnary(wrap, select)
    expect(wrap.classList.contains("hidden")).toBe(true)
    expect(wrap.querySelector("input[type='text']").required).toBe(false)
    ctrl._toggleUnary(wrap, document.createElement("select"))
    select.value = "=="
    ctrl._toggleUnary(wrap, select)
    expect(wrap.classList.contains("hidden")).toBe(false)
    expect(wrap.querySelector("input[type='text']").required).toBe(true)
    field.classList.add("hidden")
    ctrl._toggleUnary(wrap, select)
    expect(wrap.querySelector("input[type='text']").required).toBe(false)
    const orphan = document.createElement("div")
    orphan.innerHTML = `<input type="text">`
    orphan.querySelector("input").required = true
    ctrl._toggleUnary(orphan, select)
    expect(orphan.querySelector("input").required).toBe(false)

    const incomplete = document.createElement("div")
    incomplete.setAttribute("data-cond-qc-where-row", "")
    incomplete.innerHTML = `<div data-cond-qc-where-field-manual class="flex"></div>`
    row.appendChild(incomplete)
    await ctrl.whereFieldToSelect({ preventDefault() {}, target: incomplete })
    ctrl._applyWhereRule(incomplete, { field: "data.age", op: "==", value: "1" })
    ctrl._swapWhereToManual({ target: incomplete })

    const typed = document.createElement("div")
    typed.setAttribute("data-cond-qc-where-row", "")
    typed.innerHTML = `<select data-cond-qc-where-field><option value="data.age" data-col-type="number" selected></option></select>`
    row.appendChild(typed)
    ctrl._applyWhereRule(typed, { field: "data.age", op: "is_empty", value: "" })
  })
})
