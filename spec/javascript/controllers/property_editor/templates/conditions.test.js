import { describe, it, expect, afterEach } from "vitest"
import {
  buildConditionRow,
  buildFieldPanel,
  buildJoinSelect,
  buildWhereRow,
  catalogOperators,
  countOperators,
  entityAttributeDatalist,
  isUnaryOperator,
} from "controllers/property_editor/templates/conditions"
import { clearElementCatalog, installSampleElementCatalog } from "../../../support/element_catalog.js"
import { setElementCatalog } from "flowchart/constants/element_registry"

afterEach(() => installSampleElementCatalog())

const labels = {
  fieldTypeLabel: "Field",
  countTypeLabel: "Count",
  removeRowTitle: "Remove",
  joinAndLabel: "AND",
  joinOrLabel: "OR",
  valuePlaceholder: "value",
  insertVariableTitle: "Insert variable",
  entityLabel: "Entity",
  selectEntityPlaceholder: "Select entity...",
  whereOptionalLabel: "Where (optional)",
  addFilterLabel: "Add Filter",
  countOperatorLabel: "Count Operator",
  countValueLabel: "Count Value",
  selectFieldPlaceholder: "Select field...",
  enterManuallyLabel: "enter manually…",
  removeFilterTitle: "Remove filter",
  switchToDropdownTitle: "Switch to dropdown",
  columnNamePlaceholder: "column name",
  otherGroupLabel: "Other",
}

describe("row builders", () => {
  it("builds a field row with a datalist id and a query-count row", () => {
    const field = buildConditionRow(
      { kind: "field", leftOperand: "ctx.a", operator: "==", rightOperand: "1" },
      labels,
      { elementId: "el1", leftListId: "cond-left-filter" },
    )
    expect(field).toContain("data-condition-kind=\"field\"")
    expect(field).toContain("list=\"cond-left-filter\"")
    expect(field).toContain("context-autocomplete")

    const qc = buildConditionRow({
      kind: "query_count",
      queryConfig: { entityId: 2, entityName: "Item" },
      countOperator: "==",
      countValue: 0,
    }, labels)
    expect(qc).toContain("data-condition-kind=\"query_count\"")
    expect(qc).toContain("data-condition-row-field-panel class=\"hidden\"")
    expect(qc).toContain("value=\"2\"")
  })

  it("builds a join select, a where row with schema/manual/removable variants, and a datalist", () => {
    expect(buildJoinSelect("OR", labels)).toContain("option value=\"OR\" selected")
    expect(buildJoinSelect("AND", labels)).toContain("option value=\"AND\" selected")

    const schema = [{ name_slug: "email", name: "Email", html_type: "text" }, { name_slug: "age" }]
    const matched = buildWhereRow({ schema, rule: { field: "data.email", op: "is_empty", value: "" }, labels, removable: true })
    expect(matched).toContain("data-cond-qc-where-row")
    expect(matched).toContain("removeWhere")
    expect(matched).toContain("data-col-type=\"text\"")
    expect(matched).toContain("data-cond-qc-where-value-wrap class=\"hidden\"")
    const escaped = buildWhereRow({ schema, rule: { field: "data.email", op: "==", value: "" }, labels: { ...labels, enterManuallyLabel: "<b>手动</b>" } })
    expect(escaped).toContain("&lt;b&gt;手动&lt;/b&gt;")
    expect(escaped).not.toContain("<b>")

    const created = buildWhereRow({ schema, rule: { field: "created_at", op: "==", value: "1" }, labels })
    expect(created).toContain("value=\"created_at\" selected")

    const manual = buildWhereRow({ schema, rule: { field: "custom_col", op: "!=", value: "z" }, labels, context: { elementId: "el1" } })
    expect(manual).toContain("data-cond-qc-where-field-manual class=\"flex")
    expect(manual).toContain("value=\"custom_col\"")
    expect(manual).toContain("{x}</button>")

    expect(entityAttributeDatalist("", [{ name_slug: "x" }])).toBe("")
    expect(entityAttributeDatalist("d1", [])).toBe("")
    expect(entityAttributeDatalist("d1", null)).toBe("")
    expect(entityAttributeDatalist("d1", [{ name_slug: "email" }, "plain", { name: "" }])).toContain("ctx.model.email")
    expect(entityAttributeDatalist("d1", ["plain"])).toContain("ctx.model.plain")
  })

  it("falls back to built-in operators when the catalog is empty", () => {
    clearElementCatalog()
    expect(catalogOperators()).toHaveLength(6)
    expect(countOperators()).toHaveLength(6)
    expect(isUnaryOperator("is_empty")).toBe(false)
    expect(buildFieldPanel({ operator: "==" }, labels)).toContain("value=\"==\"")
  })

  it("selects the first operator when the saved one is unknown, including count-only", () => {
    expect(buildFieldPanel({ operator: "nope" }, labels)).toContain("<option value=\"==\" selected>")
    const qc = buildConditionRow({
      kind: "query_count",
      queryConfig: { entityId: 1, entityName: "A" },
      countOperator: "is_empty",
      countValue: 4,
    }, labels)
    expect(qc).toContain("<option value=\"&gt;\" selected>")
    expect(qc).toContain("value=\"4\"")
  })

  it("renders schema options from name-only fields and skips blank slugs", () => {
    const html = buildWhereRow({
      schema: [{ name: "Title" }, { html_type: "text" }, { name_slug: "age" }],
      rule: { field: "data.Title", op: "==", value: "x" },
      labels,
    })
    expect(html).toContain("value=\"data.Title\" selected")
    expect(html).toContain("value=\"data.age\"")
    expect(html).not.toContain("data-col-type")
    expect(buildWhereRow({ labels })).toContain("data-cond-qc-where-row")
    expect(buildWhereRow({ schema: null, rule: { field: "updated_at" }, labels })).toContain("value=\"updated_at\" selected")
    expect(buildFieldPanel(null, labels)).toContain("data-condition-row-field-panel")
    expect(buildFieldPanel({ leftOperand: "a" }, { ...labels, insertVariableTitle: undefined }, { elementId: "e1", stepIndex: 2 })).toContain("data-context-autocomplete-step-index-value=\"2\"")
    expect(buildFieldPanel({ leftOperand: "a" }, { ...labels, valuePlaceholder: "" })).toContain("data-condition-left")
    expect(buildFieldPanel({ leftOperand: "a" }, {
      ...labels,
      valuePlaceholder: "",
      noVariablesAvailable: "None",
      usedInThisElement: "",
      noMatchingVariables: "No match",
    }, { elementId: "e1" })).toContain("data-context-autocomplete-no-variables-available-value=\"None\"")
  })

  it("uses the first count operator when the catalog has none matching >", () => {
    setElementCatalog({
      types: {},
      operators: [
        { value: "eq", unary: false, count: true },
        { value: "blank", label: "blank", unary: true, count: false },
      ],
    })
    expect(countOperators().map((op) => op.value)).toEqual(["eq"])
    const qc = buildConditionRow({
      kind: "query_count",
      queryConfig: {},
      countOperator: "nope",
    }, labels)
    expect(qc).toContain("<option value=\"eq\" selected>")
    expect(isUnaryOperator("blank")).toBe(true)

    setElementCatalog({
      types: {},
      operators: [{ value: "blank", label: "blank", unary: true, count: false }],
    })
    expect(countOperators()).toEqual([])
    expect(buildConditionRow({ kind: "query_count", queryConfig: {} }, labels)).toContain("data-cond-qc-count-op")
  })
})
