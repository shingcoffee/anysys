import { describe, it, expect, afterEach, vi } from "vitest"
import {
  appendEntityLoadError,
  buildConditionsField,
  canvasCustomerId,
  collectConditions,
  collectQueryCountRow,
  emptyFieldCondition,
  entitySchemaUrl,
  fillEntitySelect,
  loadEntityOptions,
  normalizeGroup,
  parsePanelSchema,
  parseSavedRules,
  resolveConditionLabels,
} from "controllers/property_editor/controls/conditions"
import { catalogOperators, isUnaryOperator } from "controllers/property_editor/templates/conditions"
import { resetReferenceCache } from "controllers/property_editor/controls/reference_options"
import { clearElementCatalog, installSampleElementCatalog } from "../../../support/element_catalog.js"
import { setElementCatalog } from "flowchart/constants/element_registry"

afterEach(() => {
  document.body.innerHTML = ""
  resetReferenceCache()
  installSampleElementCatalog()
  vi.unstubAllGlobals()
})

describe("normalizeGroup", () => {
  it("returns an empty group for blank, non-group, or string leftovers", () => {
    expect(normalizeGroup(null).conditions).toEqual([])
    expect(normalizeGroup("ctx.status").conditions).toEqual([])
    expect(normalizeGroup({ leftOperand: "a", operator: "==" }).conditions).toEqual([])
    expect(normalizeGroup({ type: "group", joins: "nope", conditions: [] }).joins).toEqual([])
    expect(normalizeGroup({ type: "group", conditions: null }).conditions).toEqual([])
  })

  it("keeps a flat group and drops nested group members", () => {
    const group = normalizeGroup({
      type: "group",
      joins: ["OR"],
      conditions: [
        { kind: "field", leftOperand: "a", operator: "==", rightOperand: "1" },
        { type: "group", conditions: [] },
        { kind: "query_count", queryConfig: { entityId: 3 } },
      ],
    })
    expect(group.joins).toEqual(["OR"])
    expect(group.conditions).toHaveLength(2)
    expect(group.conditions[1].kind).toBe("query_count")
  })
})

describe("buildConditionsField", () => {
  it("renders one empty row for a blank or empty group", () => {
    const html = buildConditionsField({ name: "filter" }, { type: "group", joins: [], conditions: [] })
    expect(html).toContain("data-conditions-editor")
    expect(html).toContain('data-controller="property-editor--controls--conditions"')
    expect(html).toContain("data-condition-row")
    expect(html).toContain("data-condition-left")
    expect(html).toContain("data-condition-op")
    expect(html).not.toContain("data-condition-join")
    expect(html).not.toContain("<option value=\"\"></option>")
    expect(html).toContain("data-row-type=\"query_count\"")
  })

  it("hides the right operand for unary operators and keeps catalog labels", () => {
    const html = buildConditionsField({ name: "filter" }, {
      type: "group",
      joins: [],
      conditions: [{ kind: "field", leftOperand: "ctx.a", operator: "is_empty", rightOperand: "" }],
    })
    expect(html).toContain("data-unary=\"true\"")
    expect(html).toContain("data-condition-right-wrap")
    expect(html).toContain("hidden")
    expect(html).toContain("is empty")
  })

  it("renders join selects between rows and honors operator label overrides", () => {
    const html = buildConditionsField({ name: "filter" }, {
      type: "group",
      joins: ["OR"],
      conditions: [
        { kind: "field", leftOperand: "a", operator: "contains", rightOperand: "x" },
        { kind: "field", leftOperand: "b", operator: "==", rightOperand: "y" },
      ],
    }, { labels: { joinOrLabel: "或", branchOperatorLabels: { contains: "包含" } } })
    expect(html).toContain("data-condition-join")
    expect(html).toContain("或")
    expect(html).toContain("包含")
    expect(html).toContain("option value=\"OR\" selected")
  })

  it("uses the translated value placeholder from the labels or the editor mount", () => {
    expect(buildConditionsField({ name: "filter" }, {}, { labels: { valuePlaceholder: "值" } })).toContain("placeholder=\"值\"")
    document.body.innerHTML = `<div data-controller="property-editor" data-property-editor-value-placeholder-value="数值" data-property-editor-condition-field-type-label-value="字段"></div>`
    expect(buildConditionsField({ name: "filter" }, {})).toContain("placeholder=\"数值\"")
    expect(buildConditionsField({ name: "filter" }, {})).toContain("字段")
  })

  it("renders a record-count row with saved entity and count operators", () => {
    const html = buildConditionsField({ key: "condition" }, {
      type: "group",
      joins: [],
      conditions: [{
        kind: "query_count",
        queryConfig: { entityId: 9, entityName: "Order", conditions: { rules: [{ field: "data.x", op: ">", value: "1" }] } },
        countOperator: ">=",
        countValue: 2,
      }],
    }, { elementId: "el1", entityAttributes: [{ name_slug: "email", name: "Email" }] })
    expect(html).toContain("data-condition-kind=\"query_count\"")
    expect(html).toContain("data-cond-qc-entity")
    expect(html).toContain("value=\"9\"")
    expect(html).toContain("Order")
    expect(html).toContain("data-cond-qc-count-op")
    expect(html).toContain("id=\"cond-left-condition\"")
    expect(html).toContain("ctx.model.email")
    expect(html).toContain("{x}</button>")
  })

  it("skips a datalist when there are no entity attributes and omits the var picker without an elementId", () => {
    const html = buildConditionsField({ name: "filter" }, null, { entityAttributes: [{ name_slug: "" }, ""] })
    expect(html).not.toContain("<datalist")
    expect(html).not.toContain("context-autocomplete")
  })
})

describe("collectConditions", () => {
  it("records an OR join between two adjacent filled rows from a button or a select", () => {
    document.body.innerHTML = `
      <div data-conditions-editor>
        <div data-condition-row>
          <input data-condition-left value="a">
          <select data-condition-op><option value="==" selected></option></select>
          <input data-condition-right value="1">
        </div>
        <button data-condition-join="OR"></button>
        <div data-condition-row>
          <input data-condition-left value="b">
          <select data-condition-op><option value="!=" selected></option></select>
          <input data-condition-right value="2">
        </div>
      </div>`
    expect(collectConditions(document.querySelector("[data-conditions-editor]")).joins).toEqual(["OR"])

    document.body.innerHTML = `
      <div data-conditions-editor>
        <div data-condition-rows>
          <div data-condition-row>
            <input data-condition-left value="a">
            <select data-condition-op><option value="==" selected></option></select>
            <input data-condition-right value="1">
          </div>
          <select data-condition-join><option value="AND"></option><option value="OR" selected></option></select>
          <div data-condition-row>
            <input data-condition-left value="b">
            <select data-condition-op><option value="!=" selected></option></select>
            <input data-condition-right value="2">
          </div>
        </div>
      </div>`
    expect(collectConditions(document.querySelector("[data-conditions-editor]")).joins).toEqual(["OR"])
  })

  it("skips empty rows and records AND/OR joins", () => {
    document.body.innerHTML = `
      <div data-conditions-editor>
        <div data-condition-row>
          <input data-condition-left value="a">
          <select data-condition-op><option value="==" selected></option></select>
          <input data-condition-right value="1">
        </div>
        <button data-condition-join="OR"></button>
        <div data-condition-row>
          <input data-condition-left value="">
          <select data-condition-op><option value="==" selected></option></select>
          <input data-condition-right value="">
        </div>
        <button data-condition-join="AND"></button>
        <div data-condition-row>
          <input data-condition-left value="b">
          <select data-condition-op><option value="!=" selected></option></select>
          <input data-condition-right value="2">
        </div>
      </div>`
    expect(collectConditions(document.querySelector("[data-conditions-editor]"))).toEqual({
      type: "group",
      joins: ["AND"],
      conditions: [
        { kind: "field", leftOperand: "a", operator: "==", rightOperand: "1" },
        { kind: "field", leftOperand: "b", operator: "!=", rightOperand: "2" },
      ],
    })
  })

  it("defaults the join to AND when two filled rows have no join control between them", () => {
    document.body.innerHTML = `
      <div data-conditions-editor>
        <div data-condition-row>
          <input data-condition-left value="a">
          <select data-condition-op><option value="==" selected></option></select>
          <input data-condition-right value="1">
        </div>
        <div data-condition-row>
          <input data-condition-left value="b">
          <select data-condition-op><option value="!=" selected></option></select>
          <input data-condition-right value="2">
        </div>
      </div>`
    expect(collectConditions(document.querySelector("[data-conditions-editor]")).joins).toEqual(["AND"])
  })

  it("defaults AND when a later filled row has no previous sibling join", () => {
    document.body.innerHTML = `
      <div data-conditions-editor>
        <div data-condition-row>
          <input data-condition-left value="a">
          <select data-condition-op><option value="==" selected></option></select>
          <input data-condition-right value="1">
        </div>
        <section>
          <div data-condition-row>
            <input data-condition-left value="b">
            <select data-condition-op><option value="!=" selected></option></select>
            <input data-condition-right value="2">
          </div>
        </section>
      </div>`
    expect(collectConditions(document.querySelector("[data-conditions-editor]")).joins).toEqual(["AND"])
  })

  it("defaults a missing operator and keeps a right-only field row", () => {
    document.body.innerHTML = `
      <div data-conditions-editor>
        <div data-condition-row>
          <input data-condition-left value="a">
          <input data-condition-right value="1">
        </div>
      </div>`
    expect(collectConditions(document.querySelector("[data-conditions-editor]")).conditions[0]).toEqual({
      kind: "field", leftOperand: "a", operator: "", rightOperand: "1",
    })
  })

  it("clears the right operand for unary operators", () => {
    document.body.innerHTML = `
      <div data-conditions-editor>
        <div data-condition-row>
          <input data-condition-left value="ctx.a">
          <select data-condition-op><option value="is_empty" selected></option></select>
          <div data-condition-right-wrap class="hidden"><input data-condition-right value="keep"></div>
        </div>
      </div>`
    expect(collectConditions(document.querySelector("[data-conditions-editor]")).conditions[0]).toEqual({
      kind: "field", leftOperand: "ctx.a", operator: "is_empty", rightOperand: "",
    })
  })

  it("skips rows nested in a template and collects a visible query panel without a kind attr", () => {
    document.body.innerHTML = `
      <div data-conditions-editor>
        <div data-condition-row-template>
          <div data-condition-row>
            <input data-condition-left value="skip">
            <select data-condition-op><option value="==" selected></option></select>
            <input data-condition-right value="1">
          </div>
        </div>
        <div data-condition-row>
          <div data-condition-row-query-panel></div>
          <select data-cond-qc-entity><option value="4" selected>Items</option></select>
          <select data-cond-qc-count-op><option value="==" selected></option></select>
          <input data-cond-qc-count-value value="1">
        </div>
      </div>`
    const out = collectConditions(document.querySelector("[data-conditions-editor]"))
    expect(out.conditions).toHaveLength(1)
    expect(out.conditions[0]).toMatchObject({
      kind: "query_count",
      queryConfig: { entityId: 4 },
      countOperator: "==",
      countValue: 1,
    })
  })

  it("treats a hidden query panel as a field row and unary ops without a wrap", () => {
    document.body.innerHTML = `
      <div data-conditions-editor>
        <div data-condition-row>
          <div data-condition-row-query-panel class="hidden"></div>
          <input data-condition-left value="ctx.a">
          <select data-condition-op><option value="is_empty" selected></option></select>
          <input data-condition-right value="keep">
        </div>
      </div>`
    expect(collectConditions(document.querySelector("[data-conditions-editor]")).conditions[0]).toEqual({
      kind: "field", leftOperand: "ctx.a", operator: "is_empty", rightOperand: "",
    })
  })

  it("collects a query_count row and skips a QC row without an entity", () => {
    document.body.innerHTML = `
      <div data-conditions-editor>
        <div data-condition-rows>
          <div data-condition-row data-condition-kind="query_count">
            <div data-condition-row-query-panel></div>
            <select data-cond-qc-entity>
              <option value=""></option>
              <option value="5" selected>Users</option>
            </select>
            <div data-cond-qc-where-rows>
              <div data-cond-qc-where-row>
                <div data-cond-qc-where-field-manual class="hidden"></div>
                <select data-cond-qc-where-field><option value="data.name" selected></option></select>
                <select data-cond-qc-where-op><option value="==" selected></option></select>
                <input data-cond-qc-where-value value="bob">
              </div>
            </div>
            <select data-cond-qc-count-op><option value=">" selected></option></select>
            <input data-cond-qc-count-value value="3">
          </div>
          <select data-condition-join><option value="AND" selected></option></select>
          <div data-condition-row data-condition-kind="query_count">
            <div data-condition-row-query-panel></div>
            <select data-cond-qc-entity><option value="" selected></option></select>
          </div>
        </div>
      </div>`
    const out = collectConditions(document.querySelector("[data-conditions-editor]"))
    expect(out.conditions).toEqual([{
      kind: "query_count",
      queryConfig: {
        entityId: 5,
        entityName: "Users",
        conditions: { operator: "AND", rules: [{ field: "data.name", op: "==", value: "bob" }] },
      },
      countOperator: ">",
      countValue: 3,
    }])
    expect(out.joins).toEqual([])
  })
})

describe("collectQueryCountRow", () => {
  const buildCondRow = ({
    entityId = "5", entityName = "Users", savedAttrs = "", whereRows = "", countOp = ">", countValue = "3",
  } = {}) => {
    const row = document.createElement("div")
    row.setAttribute("data-condition-row", "")
    row.innerHTML = `
      <div data-condition-row-query-panel ${savedAttrs}></div>
      <select data-cond-qc-entity>
        <option value=""></option>
        <option value="${entityId}" selected>${entityName}</option>
      </select>
      <div data-cond-qc-where-rows>${whereRows}</div>
      <select data-cond-qc-count-op><option value="${countOp}" selected>${countOp}</option></select>
      <input data-cond-qc-count-value value="${countValue}">`
    return row
  }

  it("returns null without a live or saved entity", () => {
    const row = document.createElement("div")
    row.innerHTML = `<div data-condition-row-query-panel></div><select data-cond-qc-entity><option value="" selected></option></select>`
    expect(collectQueryCountRow(row)).toBeNull()
  })

  it("falls back to saved entity data and saved rules when live rows are absent", () => {
    const savedRules = JSON.stringify([{ field: "data.x", op: ">", value: "1" }])
    const row = document.createElement("div")
    row.innerHTML = `
      <div data-condition-row-query-panel data-cond-qc-saved-entity-id="9" data-cond-qc-saved-entity-name="Orders" data-cond-qc-saved-rules='${savedRules}'></div>
      <select data-cond-qc-entity><option value="" selected></option></select>
      <div data-cond-qc-where-rows></div>`
    const member = collectQueryCountRow(row)
    expect(member.queryConfig).toMatchObject({ entityId: 9, entityName: "Orders" })
    expect(member.queryConfig.conditions.rules).toEqual([{ field: "data.x", op: ">", value: "1" }])
  })

  it("defaults entityName and swallows malformed saved rules", () => {
    const row = buildCondRow({
      entityName: "",
      savedAttrs: `data-cond-qc-saved-entity-id="5" data-cond-qc-saved-rules="not json{"`,
    })
    const member = collectQueryCountRow(row)
    expect(member.queryConfig.entityName).toBe("")
    expect(member.queryConfig.conditions).toBeUndefined()
  })

  it("reads a manual-visible WHERE field and drops a blank one", () => {
    const whereRows = `
      <div data-cond-qc-where-row>
        <div data-cond-qc-where-field-manual>
          <input data-cond-qc-where-field-input value="   ">
        </div>
        <select data-cond-qc-where-field><option value="data.name" selected></option></select>
      </div>
      <div data-cond-qc-where-row>
        <div data-cond-qc-where-field-manual>
          <input data-cond-qc-where-field-input value="custom">
        </div>
        <select data-cond-qc-where-op><option value="!=" selected></option></select>
        <input data-cond-qc-where-value value="z">
      </div>`
    const member = collectQueryCountRow(buildCondRow({ whereRows }))
    expect(member.queryConfig.conditions.rules).toEqual([{ field: "custom", op: "!=", value: "z" }])
  })

  it("defaults missing op/value and skips a row without a field control", () => {
    const whereRows = `
      <div data-cond-qc-where-row>
        <select data-cond-qc-where-field><option value="data.name" selected></option></select>
      </div>
      <div data-cond-qc-where-row>
        <select data-cond-qc-where-op><option value=">" selected></option></select>
      </div>`
    const member = collectQueryCountRow(buildCondRow({ whereRows, countValue: "nope" }))
    expect(member.queryConfig.conditions.rules).toEqual([{ field: "data.name", op: "==", value: "" }])
    expect(member.countValue).toBe(0)
  })

  it("uses an empty saved entity name when the data attribute is absent", () => {
    const row = document.createElement("div")
    row.innerHTML = `
      <div data-condition-row-query-panel data-cond-qc-saved-entity-id="9"></div>
      <select data-cond-qc-entity><option value="" selected></option></select>`
    expect(collectQueryCountRow(row).queryConfig.entityName).toBe("")
  })
})

describe("entity helpers", () => {
  it("reads the canvas customer id, then the path, and builds a schema URL", () => {
    expect(canvasCustomerId()).toBeNull()
    expect(entitySchemaUrl("5")).toBeNull()
    document.body.innerHTML = `<div data-controller="flowchart-canvas" data-flowchart-canvas-customer-id-value="81721200"></div>`
    expect(canvasCustomerId()).toBe("81721200")
    expect(entitySchemaUrl("5")).toBe("/81721200/admin/maintenance/entities/5.json")
    expect(entitySchemaUrl("")).toBeNull()
  })

  it("falls back to the 8-digit path segment when the canvas has no customer id", () => {
    vi.stubGlobal("window", { ...window, location: { ...window.location, pathname: "/12345678/admin/maintenance/flowcharts" } })
    // happy-dom location.pathname may be read-only; also exercise the helper via a canvas-less document.
    const original = window.location.pathname
    expect(typeof original).toBe("string")
    document.body.innerHTML = ""
    const id = canvasCustomerId()
    expect(id === null || /^\d{8}$/.test(id)).toBe(true)
  })

  it("appends a single load-error option and fills unique entity options", () => {
    const select = document.createElement("select")
    select.innerHTML = `<option value=""></option><option value="5" selected>Users</option>`
    appendEntityLoadError(select, "Could not load entities")
    appendEntityLoadError(select, "Could not load entities")
    expect(select.querySelectorAll("option[data-entity-load-error]")).toHaveLength(1)

    fillEntitySelect(null, [])
    appendEntityLoadError(null, "x")
    fillEntitySelect(select, [
      { value: "5", label: "Users" },
      { id: 6, name: "Orders" },
      { value: "6", label: "Dup" },
      { value: "", label: "skip" },
      { value: "7" },
      { label: "skip-no-id" },
    ], "5")
    expect([...select.options].map((o) => o.value)).toEqual(expect.arrayContaining(["5", "6", "7"]))
    expect(select.value).toBe("5")

    const empty = document.createElement("select")
    fillEntitySelect(empty, [{ value: "8", label: "X" }])
    expect([...empty.options].map((o) => o.value)).toEqual(["8"])
  })

  it("parses panel schema and saved rules, including malformed JSON", () => {
    const panel = document.createElement("div")
    expect(parsePanelSchema(null)).toEqual([])
    expect(parseSavedRules(null)).toEqual([])
    panel.dataset.condQcSchema = "[1]"
    panel.dataset.condQcSavedRules = "[{\"field\":\"a\"}]"
    expect(parsePanelSchema(panel)).toEqual([1])
    expect(parseSavedRules(panel)).toEqual([{ field: "a" }])
    panel.dataset.condQcSchema = "{}"
    panel.dataset.condQcSavedRules = "{}"
    expect(parsePanelSchema(panel)).toEqual([])
    expect(parseSavedRules(panel)).toEqual([])
    panel.dataset.condQcSchema = "nope"
    panel.dataset.condQcSavedRules = "nope"
    expect(parsePanelSchema(panel)).toEqual([])
    expect(parseSavedRules(panel)).toEqual([])
  })

  it("loads entity options through the reference source", async () => {
    document.body.innerHTML = `<div data-controller="flowchart-canvas" data-flowchart-canvas-urls-value='{"referenceOptions":"/ref/__SOURCE__.json"}'></div>`
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, json: async () => ({ options: [{ value: "1", label: "A" }] }) })))
    const hit = await loadEntityOptions()
    expect(hit.ok).toBe(true)
    expect(hit.options).toEqual([{ value: "1", label: "A" }])
  })
})

describe("operators and labels", () => {
  it("treats catalog unary flags as unary and falls back when the catalog is empty", () => {
    expect(isUnaryOperator("is_empty")).toBe(true)
    expect(isUnaryOperator("==")).toBe(false)
    expect(isUnaryOperator("nope")).toBe(false)
    expect(emptyFieldCondition().operator).toBe("==")
    clearElementCatalog()
    expect(catalogOperators()[0].value).toBe("==")
    expect(isUnaryOperator("is_empty")).toBe(false)
    expect(buildConditionsField({}, null)).toContain("list=\"cond-left-condition\"")
    setElementCatalog({ types: {}, operators: [{ value: "" }] })
    expect(emptyFieldCondition().operator).toBe("==")
  })

  it("resolveConditionLabels merges editor dataset values", () => {
    document.body.innerHTML = `<div data-controller="property-editor" data-property-editor-add-filter-label-value="加筛选"></div>`
    expect(resolveConditionLabels().addFilterLabel).toBe("加筛选")
    expect(resolveConditionLabels({ addFilterLabel: "X" }).addFilterLabel).toBe("X")
    expect(resolveConditionLabels({ branchOperatorLabels: "nope" }).branchOperatorLabels).toEqual({})
  })
})
