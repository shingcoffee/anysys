import { describe, it, expect } from "vitest"
import {
  buildDisclosureSection,
  buildSetCountBadge,
  buildVarPickButton,
  getColorClasses,
  buildStepPickerTemplate,
  buildEntityColumnSelect,
  buildStepConfigFieldsHTML,
  configFieldKey,
  configFieldType,
  matchesWhen,
} from "controllers/property_editor/templates/fields"

describe("buildDisclosureSection", () => {
  it("renders collapsed by default (body hidden, chevron not rotated)", () => {
    const html = buildDisclosureSection({ id: "sec1", label: "More" })
    expect(html).toContain('data-disclosure-id="sec1"')
    expect(html).toContain('data-disclosure-body class="hidden')
    expect(html).not.toContain("rotate-180")
  })

  it("renders open when startOpen is true", () => {
    const html = buildDisclosureSection({ id: "sec1", label: "More", startOpen: true })
    expect(html).toContain("rotate-180")
    // body class starts with empty (not hidden) when open
    expect(html).toContain('data-disclosure-body class=" px-2.5')
  })

  it("injects badgeHTML and bodyHTML raw, escapes label + id", () => {
    const html = buildDisclosureSection({
      id: "<id>",
      label: "<lbl>",
      badgeHTML: "<span data-b></span>",
      bodyHTML: "<div data-body></div>",
    })
    expect(html).toContain("&lt;id&gt;")
    expect(html).toContain("&lt;lbl&gt;")
    expect(html).toContain("<span data-b></span>")
    expect(html).toContain("<div data-body></div>")
  })
})

describe("buildSetCountBadge", () => {
  it("hidden at 0, visible when > 0", () => {
    expect(buildSetCountBadge(0)).toContain("hidden")
    expect(buildSetCountBadge(2)).not.toContain(" hidden")
    expect(buildSetCountBadge(2)).toContain(">2 set<")
  })

  it("honors a translated format override", () => {
    expect(buildSetCountBadge(2, "已设置 {count} 项")).toContain(">已设置 2 项<")
  })
})

describe("buildVarPickButton", () => {
  it("uses the default position and wires autocomplete actions", () => {
    const html = buildVarPickButton()
    expect(html).toContain("right-0.5 top-1/2 -translate-y-1/2")
    expect(html).toContain("mousedown->context-autocomplete#keepFocus")
    expect(html).toContain("click->context-autocomplete#picker")
    expect(html).toContain(">{x}</button>")
    expect(html).toContain('title="Insert variable"')
  })

  it("escapes a custom positionClasses", () => {
    const html = buildVarPickButton({ positionClasses: 'right-9"x' })
    expect(html).toContain("right-9&quot;x")
  })

  it("honors a translated title override", () => {
    const html = buildVarPickButton({ title: "插入变量" })
    expect(html).toContain('title="插入变量"')
  })
})

describe("getColorClasses", () => {
  it("returns the mapping for a known color", () => {
    expect(getColorClasses("amber").icon).toBe("text-amber-600")
  })

  it("falls back to blue for unknown colors", () => {
    expect(getColorClasses("chartreuse")).toEqual(getColorClasses("blue"))
    expect(getColorClasses(undefined).icon).toBe("text-blue-600")
  })
})

describe("buildStepPickerTemplate", () => {
  it("embeds the escaped options JSON and searchable-select wiring", () => {
    const json = '[{"label":"a & b"}]'
    const html = buildStepPickerTemplate(json)
    expect(html).toContain("data-step-picker")
    expect(html).toContain('data-controller="searchable-select"')
    expect(html).toContain("a &amp; b")
    expect(html).toContain("change->property-editor#stepPickerCommit")
    expect(html).toContain('placeholder="Search actions…"')
  })

  it("honors a translated search placeholder override", () => {
    const html = buildStepPickerTemplate("[]", "搜索操作…")
    expect(html).toContain('placeholder="搜索操作…"')
  })
})

describe("buildEntityColumnSelect", () => {
  const attrs = [
    { name_slug: "email", html_type: "email" },
    { name_slug: "age", html_type: "number" },
  ]

  it("returns null when no columns are available", () => {
    expect(buildEntityColumnSelect({ key: "f" }, "", [])).toBeNull()
    expect(buildEntityColumnSelect({ key: "f" }, "", null)).toBeNull()
  })

  it("renders a select with a bare-slug value + label type suffix", () => {
    const html = buildEntityColumnSelect({ key: "col" }, "email", attrs)
    expect(html).toContain('<option value="email" selected data-col-type="email">email — email</option>')
    expect(html).toContain('data-config-input="col"')
    expect(html).toContain("__manual__")
  })

  it("shows the manual input (select hidden) when value is not a known column", () => {
    const html = buildEntityColumnSelect({ key: "col" }, "custom", attrs)
    // select gets the "hidden " prefix class; manual wrap has no hidden prefix
    expect(html).toContain('class="hidden w-full px-2')
    expect(html).toContain('data-entity-manual-wrap class="relative')
    expect(html).toContain('value="custom"') // hidden input mirrors the value
    expect(html).toContain("data-entity-column-manual")
  })

  it("empty value keeps the dropdown visible (valueInColumns true)", () => {
    const html = buildEntityColumnSelect({ key: "col" }, "", attrs)
    expect(html).toContain('data-entity-manual-wrap class="hidden ')
  })

  it("coerces a nullish value to an empty string", () => {
    const html = buildEntityColumnSelect({ key: "col" }, undefined, attrs)
    expect(html).toContain('data-entity-manual-wrap class="hidden ')
  })

  it("adds autocomplete wiring + a var-pick button to the manual input when elementId is present", () => {
    const html = buildEntityColumnSelect({ key: "col" }, "custom", attrs, { elementId: "el1", stepIndex: 1 })
    expect(html).toContain('data-controller="context-autocomplete"')
    expect(html).toContain('data-context-autocomplete-target="input"')
    expect(html).toContain("{x}</button>")
  })

  it("defaults the step index to -1 when elementId is present but stepIndex is not", () => {
    const html = buildEntityColumnSelect({ key: "col" }, "custom", attrs, { elementId: "el1" })
    expect(html).toContain('data-context-autocomplete-step-index-value="-1"')
  })

  it("falls back to name, then String(attr), for the slug — and empty htmlType when absent", () => {
    const html = buildEntityColumnSelect({ key: "col" }, "", [{ name: "legacy_col" }, "plain_string_col"])
    expect(html).toContain('value="legacy_col">legacy_col<')
    expect(html).toContain('value="plain_string_col">plain_string_col<')
    expect(html).not.toContain("data-col-type")
  })

  it("honors translated label overrides for placeholder/optgroup/manual-entry chrome", () => {
    const html = buildEntityColumnSelect({ key: "col" }, "custom", attrs, {
      elementId: "el1",
      labels: {
        selectColumnPlaceholder: "<选择列…>",
        otherOptgroupLabel: "其他\"",
        enterManuallyOptionLabel: "<手动输入…>",
        columnNamePlaceholder: "列名",
        switchToDropdownTitle: "切换到下拉框",
        insertVariableTitle: "插入变量",
        noVariablesAvailable: "暂无可用变量",
        usedInThisElement: "在此元素中使用",
        noMatchingVariables: "没有匹配的变量",
      },
    })
    expect(html).toContain('data-context-autocomplete-no-variables-available-value="暂无可用变量"')
    expect(html).toContain('data-context-autocomplete-used-in-this-element-label-value="在此元素中使用"')
    expect(html).toContain('data-context-autocomplete-no-matching-variables-label-value="没有匹配的变量"')
    expect(html).toContain("&lt;选择列…&gt;")
    expect(html).toContain('label="其他&quot;"')
    expect(html).toContain("&lt;手动输入…&gt;")
    expect(html).toContain('placeholder="列名"')
    expect(html).toContain('title="切换到下拉框"')
    expect(html).toContain('title="插入变量"')
  })

  it("omits autocomplete copy attributes when a label is an empty string", () => {
    const html = buildEntityColumnSelect({ key: "col" }, "custom", attrs, {
      elementId: "el1",
      labels: { noVariablesAvailable: "", usedInThisElement: "Used in this element", noMatchingVariables: "No matching variables" },
    })
    expect(html).not.toContain("data-context-autocomplete-no-variables-available-value")
    expect(html).toContain('data-context-autocomplete-used-in-this-element-label-value="Used in this element"')
  })
})

describe("buildStepConfigFieldsHTML", () => {
  it("returns empty string for empty/missing schema", () => {
    expect(buildStepConfigFieldsHTML(null)).toBe("")
    expect(buildStepConfigFieldsHTML([])).toBe("")
  })

  it("renders a flat list when <= 6 visible fields", () => {
    const schema = [
      { key: "a", label: "A", type: "text" },
      { key: "b", label: "B", type: "number" },
    ]
    const html = buildStepConfigFieldsHTML(schema, { a: "x" })
    expect(html).toContain("data-step-config-fields")
    expect(html).not.toContain("More options")
    expect(html).toContain('data-config-field="a"')
    expect(html).toContain('data-config-field="b"')
  })

  it("hides fields whose visibleWhen does not match current config", () => {
    const schema = [
      { key: "mode", label: "Mode", type: "select", options: ["x", "y"] },
      { key: "extra", label: "Extra", type: "text", visibleWhen: { field: "mode", value: "y" } },
    ]
    const html = buildStepConfigFieldsHTML(schema, { mode: "x" })
    // extra field wrapper carries the hidden class
    expect(html).toMatch(/step-config-field hidden"[\s\S]*data-config-field="extra"/)
  })

  it("partitions into core + 'More options' disclosure when > 6 visible fields", () => {
    const schema = [
      { key: "r1", label: "R1", type: "text", required: true },
      { key: "r2", label: "R2", type: "text", required: true },
      { key: "r3", label: "R3", type: "text", required: true },
      { key: "o1", label: "O1", type: "text" },
      { key: "o2", label: "O2", type: "text" },
      { key: "o3", label: "O3", type: "text" },
      { key: "o4", label: "O4", type: "text" },
    ]
    const html = buildStepConfigFieldsHTML(schema, {})
    expect(html).toContain("More options")
    expect(html).toContain("data-set-count-badge")
  })

  it("honors translated 'More options' label / set-count format overrides", () => {
    const schema = [
      { key: "r1", label: "R1", type: "text", required: true },
      { key: "r2", label: "R2", type: "text", required: true },
      { key: "r3", label: "R3", type: "text", required: true },
      { key: "o1", label: "O1", type: "text" },
      { key: "o2", label: "O2", type: "text" },
      { key: "o3", label: "O3", type: "text" },
      { key: "o4", label: "O4", type: "text" },
    ]
    const html = buildStepConfigFieldsHTML(schema, {}, {
      labels: { moreOptionsLabel: "更多选项", setCountFormat: "已设置 {count} 项" },
    })
    expect(html).toContain("更多选项")
    expect(html).toContain("已设置 0 项")
  })

  it("renders flat (no disclosure) when the partition is degenerate", () => {
    // 7 optional fields → core is empty → degenerate → flat
    const schema = Array.from({ length: 7 }, (_, i) => ({
      key: `o${i}`,
      label: `O${i}`,
      type: "text",
    }))
    const html = buildStepConfigFieldsHTML(schema, {})
    expect(html).not.toContain("More options")
  })

  it("routes group:'core' and group:'advanced' fields explicitly, bypassing the required/visibleWhen heuristic", () => {
    const schema = [
      { key: "c1", label: "C1", type: "text", group: "core" },
      { key: "c2", label: "C2", type: "text", group: "core" },
      // required but forced into "more" via an explicit group hint
      { key: "a1", label: "A1", type: "text", group: "advanced", required: true },
      { key: "o1", label: "O1", type: "text" },
      { key: "o2", label: "O2", type: "text" },
      { key: "o3", label: "O3", type: "text" },
      { key: "o4", label: "O4", type: "text" },
      { key: "o5", label: "O5", type: "text" },
    ]
    const html = buildStepConfigFieldsHTML(schema, {})
    expect(html).toContain("More options")
    const discloseStart = html.indexOf("More options")
    const a1Index = html.indexOf('data-config-field="a1"')
    expect(a1Index).toBeGreaterThan(discloseStart)
  })

  it("computes the 'N set' badge via isFieldValueNonDefault (default / non-default / key_value_list)", () => {
    const schema = [
      { key: "r1", label: "R1", type: "text", required: true },
      { key: "r2", label: "R2", type: "text", required: true },
      { key: "r3", label: "R3", type: "text", required: true },
      { key: "notset", label: "Not set", type: "text" }, // absent from currentConfig entirely
      { key: "explicitUndef", label: "EU", type: "text" }, // present, but value undefined
      { key: "atdefault", label: "At default", type: "text", default: "x" },
      { key: "changed", label: "Changed", type: "text", default: "x" },
      { key: "kvEmpty", label: "KV empty", type: "key_value_list" },
      { key: "kvSet", label: "KV set", type: "key_value_list" },
    ]
    const currentConfig = {
      explicitUndef: undefined,
      atdefault: "x",
      changed: "y",
      kvEmpty: [{ key: "", value: "" }],
      kvSet: [{ key: "Authorization", value: "Bearer" }],
    }
    const html = buildStepConfigFieldsHTML(schema, currentConfig)
    // only "changed" and "kvSet" are non-default among the 5 "more" fields.
    expect(html).toContain(">2 set<")
  })
})

describe("textarea config field", () => {
  it("renders a plain textarea without an elementId", () => {
    const schema = [{ key: "notes", label: "Notes", type: "textarea", placeholder: "Add notes" }]
    const html = buildStepConfigFieldsHTML(schema, { notes: "hi <b>" })
    expect(html).toContain("<textarea")
    expect(html).toContain('data-config-input="notes"')
    expect(html).toContain("hi &lt;b&gt;")
    expect(html).not.toContain("context-autocomplete")
  })

  it("wraps a var-ref textarea key with the autocomplete picker when elementId is present", () => {
    const schema = [{ key: "bodyExpression", label: "Body", type: "textarea", required: true }]
    const html = buildStepConfigFieldsHTML(schema, {}, { elementId: "el1", stepIndex: 2 })
    expect(html).toContain('data-controller="context-autocomplete"')
    expect(html).toContain('data-context-autocomplete-step-index-value="2"')
    expect(html).toContain("{x}</button>")
    expect(html).toContain("required")
  })

  it("omits the required attribute on a var-ref textarea that isn't required", () => {
    const schema = [{ key: "bodyExpression", label: "Body", type: "textarea" }]
    const html = buildStepConfigFieldsHTML(schema, {}, { elementId: "el1" })
    expect(html).not.toContain("required")
  })

  it("adds context-autocomplete controller attrs (no picker button) for a non-var-ref key with elementId", () => {
    const schema = [{ key: "notes", label: "Notes", type: "textarea", required: true }]
    const html = buildStepConfigFieldsHTML(schema, {}, { elementId: "el1" })
    expect(html).toContain('data-controller="context-autocomplete"')
    expect(html).not.toContain("{x}</button>")
    expect(html).toContain("required")
  })
})

describe("json_or_expression config field", () => {
  const schema = [{ key: "smsVars", label: "Variables", type: "json_or_expression" }]

  it("renders escaped JSON for typed objects in a marked textarea", () => {
    const vars = { code: "ctx.code", minutes: 5, note: "</textarea><script>bad()</script>" }
    document.body.innerHTML = buildStepConfigFieldsHTML(schema, { smsVars: vars })
    const textarea = document.querySelector("[data-json-or-expression] textarea")
    expect(JSON.parse(textarea.value)).toEqual(vars)
    expect(document.querySelectorAll("textarea")).toHaveLength(1)
    expect(document.querySelector("script")).toBeNull()
  })

  it("leaves context expressions unquoted and keeps autocomplete available", () => {
    document.body.innerHTML = buildStepConfigFieldsHTML(schema, { smsVars: "ctx.payload.vars" }, { elementId: "sms-node" })
    const textarea = document.querySelector("[data-json-or-expression] textarea")
    expect(textarea.value).toBe("ctx.payload.vars")
    expect(textarea.dataset.controller).toBe("context-autocomplete")
  })

  it("keeps omitted values blank and explicit empty objects editable as JSON", () => {
    document.body.innerHTML = buildStepConfigFieldsHTML(schema)
    expect(document.querySelector("textarea").value).toBe("")
    document.body.innerHTML = buildStepConfigFieldsHTML(schema, { smsVars: {} })
    expect(document.querySelector("textarea").value).toBe("{}")
  })

  it("does not opt ordinary text or textarea fields into JSON parsing", () => {
    document.body.innerHTML = buildStepConfigFieldsHTML([
      { key: "text", label: "Text", type: "text" },
      { key: "body", label: "Body", type: "textarea" }
    ], { text: '{"code":"literal"}', body: '{"code":"literal"}' })
    expect(document.querySelector("[data-json-or-expression]")).toBeNull()
    expect(document.querySelector("input").value).toBe('{"code":"literal"}')
    expect(document.querySelector("textarea").value).toBe('{"code":"literal"}')
  })
})

describe("number config field", () => {
  it("renders min/max attributes when provided", () => {
    const schema = [{ key: "n", label: "N", type: "number", min: 0, max: 10 }]
    const html = buildStepConfigFieldsHTML(schema, { n: 5 })
    expect(html).toContain('min="0"')
    expect(html).toContain('max="10"')
  })

  it("omits min/max attributes when absent", () => {
    const schema = [{ key: "n", label: "N", type: "number" }]
    const html = buildStepConfigFieldsHTML(schema, {})
    expect(html).not.toContain("min=")
    expect(html).not.toContain("max=")
  })
})

describe("select config field", () => {
  it("renders string options and marks the matching one selected", () => {
    const schema = [{ key: "mode", label: "Mode", type: "select", options: ["a", "b"] }]
    const html = buildStepConfigFieldsHTML(schema, { mode: "b" })
    expect(html).toContain('<option value="b" selected>b</option>')
    expect(html).toContain('<option value="a">a</option>')
  })

  it("renders object options ({value, label})", () => {
    const schema = [{ key: "mode", label: "Mode", type: "select", options: [{ value: "x", label: "X label" }] }]
    const html = buildStepConfigFieldsHTML(schema, {})
    expect(html).toContain('<option value="x">X label</option>')
  })

  it("adds a None option when the optional enum has no options (F3)", () => {
    const schema = [{ key: "mode", label: "Mode", type: "select" }]
    const html = buildStepConfigFieldsHTML(schema, {})
    expect(html).toContain("<select")
    expect(html).toContain('<option value="" selected>None</option>')
  })
})

describe("key_value_list config field", () => {
  it("renders one row per existing entry, falling back to '' for a missing key/value", () => {
    const schema = [{ key: "headers", label: "Headers", type: "key_value_list" }]
    const html = buildStepConfigFieldsHTML(schema, {
      headers: [{ key: "Authorization" }, { value: "v2" }],
    })
    expect((html.match(/data-kv-row /g) || []).length).toBe(3)
    expect(html).toContain('value="Authorization"')
    expect(html).toContain('value="v2"')
  })

  it("renders a single empty row when the value is not a non-empty array", () => {
    const schema = [{ key: "headers", label: "Headers", type: "key_value_list" }]
    const html = buildStepConfigFieldsHTML(schema, {})
    expect((html.match(/data-kv-row /g) || []).length).toBe(2)
  })

  it("honors custom key/value placeholders", () => {
    const schema = [
      { key: "headers", label: "Headers", type: "key_value_list", keyPlaceholder: "Header", valuePlaceholder: "Val" },
    ]
    const html = buildStepConfigFieldsHTML(schema, {})
    expect(html).toContain('placeholder="Header"')
    expect(html).toContain('placeholder="Val"')
  })

  it("honors translated key/value/remove-row/add label overrides via context.labels", () => {
    const schema = [{ key: "headers", label: "Headers", type: "key_value_list" }]
    const html = buildStepConfigFieldsHTML(schema, {}, {
      labels: { kvKeyPlaceholder: "键", kvValuePlaceholder: "值", kvRemoveRowTitle: "删除行", addRowLabel: "添加" },
    })
    expect(html).toContain('placeholder="键"')
    expect(html).toContain('placeholder="值"')
    expect(html).toContain('title="删除行"')
    expect(html).toContain("添加")
  })
})

describe("text config field with elementId", () => {
  it("wraps a var-ref key with the autocomplete picker when elementId is present", () => {
    const schema = [{ key: "resultVar", label: "Result", type: "text", required: true, maxLength: 12 }]
    const html = buildStepConfigFieldsHTML(schema, {}, { elementId: "el1", stepIndex: 3 })
    expect(html).toContain('data-controller="context-autocomplete"')
    expect(html).toContain('data-context-autocomplete-step-index-value="3"')
    expect(html).toContain("{x}</button>")
    expect(html).toContain("required")
    expect(html).toContain('maxlength="12"')
  })

  it("omits the required attribute on a var-ref field that isn't required", () => {
    const schema = [{ key: "resultVar", label: "Result", type: "text" }]
    const html = buildStepConfigFieldsHTML(schema, {}, { elementId: "el1" })
    expect(html).not.toContain("required")
  })

  it("marks a required var-pick textarea and applies maxlength", () => {
    const html = buildStepConfigFieldsHTML([
      { name: "bodyExpression", label: "Body", control: "textarea", required: true, maxLength: 20, variablePicker: true },
    ], {}, { elementId: "el1" })
    expect(html).toContain("{x}</button>")
    expect(html).toContain("required")
    expect(html).toContain('maxlength="20"')
  })

  it("renders a number input with an empty value when the saved value is missing", () => {
    const html = buildStepConfigFieldsHTML([{ name: "limit", label: "Limit", control: "number" }], {})
    expect(html).toContain('type="number"')
    expect(html).toContain('value=""')
  })

  it("adds context-autocomplete controller attrs (no picker button) for a non-var-ref key with elementId", () => {
    const schema = [{ key: "label", label: "Label", type: "text" }]
    const html = buildStepConfigFieldsHTML(schema, {}, { elementId: "el1" })
    expect(html).toContain('data-controller="context-autocomplete"')
    expect(html).not.toContain("{x}</button>")
  })

  it("omits the controller attrs entirely without an elementId", () => {
    const schema = [{ key: "label", label: "Label", type: "text" }]
    const html = buildStepConfigFieldsHTML(schema, {})
    expect(html).not.toContain("context-autocomplete")
  })
})

describe("shouldFieldBeVisible edge cases", () => {
  it("treats a missing currentConfig key as an empty string when matching visibleWhen", () => {
    const schema = [{ key: "extra", label: "Extra", type: "text", visibleWhen: { field: "mode", value: "" } }]
    const html = buildStepConfigFieldsHTML(schema, {}) // no "mode" key at all
    expect(html).not.toMatch(/step-config-field hidden"/)
  })

  it("supports the plural visibleWhen.values array", () => {
    const schema = [{ key: "extra", label: "Extra", type: "text", visibleWhen: { field: "mode", values: ["a", "b"] } }]
    expect(buildStepConfigFieldsHTML(schema, { mode: "b" })).not.toMatch(/step-config-field hidden"/)
    expect(buildStepConfigFieldsHTML(schema, { mode: "c" })).toMatch(/step-config-field hidden"/)
  })
})

describe("entityField rendering inside buildStepConfigFieldsHTML", () => {
  it("renders the entity column select when entityField is true and columns exist", () => {
    const schema = [{ key: "col", label: "Column", type: "text", entityField: true }]
    const html = buildStepConfigFieldsHTML(schema, {}, { entityAttributes: [{ name_slug: "email" }] })
    expect(html).toContain("data-entity-field-wrapper")
  })

  it("falls back to a plain text field when entityField is true but entityAttributes is empty", () => {
    const schema = [{ key: "col", label: "Column", type: "text", entityField: true }]
    const html = buildStepConfigFieldsHTML(schema, {}, { entityAttributes: [] })
    expect(html).not.toContain("data-entity-field-wrapper")
    expect(html).toContain('data-config-input="col"')
  })

  it("falls back to a plain text field when entityField is true and no entityAttributes context is given at all", () => {
    const schema = [{ key: "col", label: "Column", type: "text", entityField: true }]
    const html = buildStepConfigFieldsHTML(schema, {})
    expect(html).not.toContain("data-entity-field-wrapper")
  })

  it("falls back to a text field when entityAttributes has entries but none yield a usable slug", () => {
    const schema = [{ key: "col", label: "Column", type: "text", entityField: true }]
    const html = buildStepConfigFieldsHTML(schema, {}, { entityAttributes: [""] })
    expect(html).not.toContain("data-entity-field-wrapper")
    expect(html).toContain('data-config-input="col"')
  })

  it("falls back to buildConfigTextField for an unrecognized field type", () => {
    const schema = [{ key: "weird", label: "Weird", type: "totally_unknown" }]
    const html = buildStepConfigFieldsHTML(schema, {})
    expect(html).toContain('data-config-input="weird"')
    expect(html).toContain('type="text"')
  })
})

describe("export field shape (name/control)", () => {
  it("configFieldKey prefers name then key", () => {
    expect(configFieldKey({ name: "a", key: "b" })).toBe("a")
    expect(configFieldKey({ key: "b" })).toBe("b")
  })

  it("configFieldType maps export controls onto renderer types", () => {
    expect(configFieldType({ type: "textarea" })).toBe("textarea")
    expect(configFieldType({ control: "textarea" })).toBe("textarea")
    expect(configFieldType({ control: "select" })).toBe("select")
    expect(configFieldType({ control: "number" })).toBe("number")
    expect(configFieldType({ control: "mapping" })).toBe("key_value_list")
    expect(configFieldType({ control: "code" })).toBe("json_or_expression")
    expect(configFieldType({ control: "toggle" })).toBe("toggle")
    expect(configFieldType({ control: "list" })).toBe("list")
    expect(configFieldType({ control: "conditions" })).toBe("conditions")
    expect(configFieldType({ control: "attribute_picker" })).toBe("attribute_picker")
    expect(configFieldType({ control: "reference_picker" })).toBe("reference_picker")
    expect(configFieldType({ control: "localized_text" })).toBe("localized_text")
    expect(configFieldType({ control: "text" })).toBe("text")
    expect(configFieldType({})).toBe("text")
  })

  it("matchesWhen accepts the export { fieldName: values } shape and the legacy { field, value }", () => {
    expect(matchesWhen(null, {})).toBe(true)
    expect(matchesWhen({ findStrategy: ["find_by", "where_first"] }, { findStrategy: "find_by" })).toBe(true)
    expect(matchesWhen({ findStrategy: "find_by" }, { findStrategy: "where_first" })).toBe(false)
    expect(matchesWhen({ field: "mode", value: "y" }, { mode: "y" })).toBe(true)
    expect(matchesWhen({ field: "mode", values: ["a", "b"] }, { mode: "b" })).toBe(true)
  })

  it("renders an empty label when the catalog omits one", () => {
    const html = buildStepConfigFieldsHTML([{ name: "anon", control: "text" }], {})
    expect(html).toContain("data-config-field=\"anon\"")
    expect(html).toContain("<label")
  })

  it("renders help text under the control (F2)", () => {
    const html = buildStepConfigFieldsHTML([
      { name: "sourceVariable", label: "Source", control: "text", help: "Context path this step reads." },
    ], {})
    expect(html).toContain("Context path this step reads.")
  })

  it("renders the export empty option on optional selects (F3)", () => {
    const html = buildStepConfigFieldsHTML([{
      name: "operation",
      label: "Operation",
      control: "select",
      options: [{ value: "", label: "None" }, { value: "sum", label: "Sum" }],
    }], {})
    expect(html).toContain('<option value="" selected>None</option>')
  })

  it("omits the variable picker when variablePicker is false even for a Var-suffixed name (F9)", () => {
    const html = buildStepConfigFieldsHTML([
      { name: "resultVar", label: "Save result as", control: "text", variablePicker: false },
    ], {}, { elementId: "el1" })
    expect(html).not.toContain("{x}</button>")
  })

  it("shows the variable picker when variablePicker is true even if the name is not a var-ref", () => {
    const html = buildStepConfigFieldsHTML([
      { name: "source", label: "Source", control: "text", variablePicker: true },
    ], {}, { elementId: "el1" })
    expect(html).toContain("{x}</button>")
  })

  it("stringifies an object saved in a text field", () => {
    const html = buildStepConfigFieldsHTML(
      [{ name: "meta", label: "Meta", control: "text" }],
      { meta: { a: 1 } },
    )
    expect(html).toContain("{")
    expect(html).toContain("&quot;a&quot;")
  })

  it("renders list rows and a structured conditions editor", () => {
    const html = buildStepConfigFieldsHTML([
      { name: "tags", label: "Tags", control: "list" },
      { name: "filter", label: "Filter", control: "conditions" },
    ], { tags: ["a", "b"], filter: { type: "group", joins: [], conditions: [{ kind: "field", leftOperand: "ctx.a", operator: "==", rightOperand: "1" }] } })
    expect(html).toContain("data-list-editor")
    expect(html).toContain('value="a"')
    expect(html).toContain('value="b"')
    expect(html).toContain("data-conditions-editor")
    expect(html).toContain('value="ctx.a"')
  })

  it("marks a field required when requiredWhen matches", () => {
    const html = buildStepConfigFieldsHTML([
      { name: "rateSource", label: "Source", control: "select", options: ["fixed", "live"], default: "fixed" },
      { name: "fixedRate", label: "Fixed rate", control: "text", requiredWhen: { rateSource: "fixed" } },
    ], { rateSource: "fixed" })
    expect(html).toContain("data-required-when")
    expect(html).toContain("text-red-500")
  })

  it("renders dedicated controls for toggle, list, conditions, localized_text, and reference", () => {
    const html = buildStepConfigFieldsHTML([
      { name: "skipNil", label: "Skip nil", control: "toggle", default: true },
      { name: "tags", label: "Tags", control: "list", default: [] },
      { name: "filter", label: "Filter", control: "conditions", default: { type: "group" } },
      { name: "title", label: "Title", control: "localized_text", default: { en: "Title" } },
      { name: "templateId", label: "Email template", control: "reference_picker", source: "email_templates" },
    ], {})
    expect(html).toContain('type="checkbox"')
    expect(html).toContain("sr-only peer")
    expect(html).toContain('data-config-input="skipNil"')
    expect(html).toContain("data-list-editor")
    expect(html).toContain("data-conditions-editor")
    expect(html).toContain("data-localized-text")
    expect(html).toContain('data-locale-tab="en"')
    expect(html).toContain('data-locale-tab="zh-CN"')
    expect(html).toContain("data-reference-picker")
    expect(html).toContain('data-config-input="templateId"')
    expect(html).toContain("email_templates")
  })

  it("renders attribute_picker as the entity column select when columns exist", () => {
    const html = buildStepConfigFieldsHTML(
      [{ name: "amountField", label: "Amount field", control: "attribute_picker" }],
      {},
      { entityAttributes: [{ name_slug: "amount", name: "Amount" }] },
    )
    expect(html).toContain("data-entity-field-wrapper")
    expect(html).toContain('data-config-input="amountField"')
  })

  it("hides export-shape visibleWhen dependents and honors group:main as core", () => {
    const schema = [
      { name: "c1", label: "C1", control: "text", group: "main" },
      { name: "c2", label: "C2", control: "text", group: "main" },
      { name: "mode", label: "Mode", control: "select", group: "main", options: ["x", "y"], default: "x" },
      { name: "extra", label: "Extra", control: "text", visibleWhen: { mode: ["y"] } },
      { name: "o1", label: "O1", control: "text" },
      { name: "o2", label: "O2", control: "text" },
      { name: "o3", label: "O3", control: "text" },
      { name: "o4", label: "O4", control: "text" },
    ]
    const html = buildStepConfigFieldsHTML(schema, {})
    expect(html).toContain("More options")
    expect(html).toMatch(/step-config-field hidden"[\s\S]*data-config-field="extra"/)
  })

  it("counts a toggle as set when it differs from the boolean default", () => {
    const schema = [
      { key: "r1", label: "R1", type: "text", required: true },
      { key: "r2", label: "R2", type: "text", required: true },
      { key: "r3", label: "R3", type: "text", required: true },
      { key: "flag", label: "Flag", type: "toggle", default: false },
      { key: "o1", type: "text", label: "O1" },
      { key: "o2", type: "text", label: "O2" },
      { key: "o3", type: "text", label: "O3" },
    ]
    const html = buildStepConfigFieldsHTML(schema, { flag: true })
    expect(html).toContain(">1 set<")
  })

  it("applies maxlength on text/textarea when the export sets maxLength", () => {
    const html = buildStepConfigFieldsHTML([
      { name: "label", label: "Label", control: "text", maxLength: 40 },
      { name: "message", label: "Message", control: "textarea", maxLength: 80 },
    ], {})
    expect(html).toContain('maxlength="40"')
    expect(html).toContain('maxlength="80"')
  })

  it("renders mixed string/object select options and a required entity picker in both modes", () => {
    const mixed = buildStepConfigFieldsHTML([{
      name: "mode",
      label: "Mode",
      control: "select",
      options: ["plain", { value: "obj" }],
    }], { mode: "obj" })
    expect(mixed).toContain('<option value="plain">plain</option>')
    expect(mixed).toContain('<option value="obj" selected>obj</option>')

    const inColumns = buildEntityColumnSelect(
      { name: "col", required: true },
      "email",
      [{ name_slug: "email", name: "Email" }],
    )
    expect(inColumns).toContain("required")
    const manual = buildEntityColumnSelect(
      { name: "col", required: true },
      "custom",
      [{ name_slug: "email", name: "Email" }],
    )
    expect(manual).toContain("required")
  })

  it("prepends a None option on optional enums and does not silently select the first required option (F3)", () => {
    const optional = buildStepConfigFieldsHTML([{
      name: "operation",
      label: "Operation",
      control: "select",
      options: [{ value: "sum", label: "Sum" }],
    }], {})
    expect(optional).toContain('<option value="" selected>None</option>')
    expect(optional).toContain('<option value="sum">Sum</option>')

    const required = buildStepConfigFieldsHTML([{
      name: "mode",
      label: "Mode",
      control: "select",
      required: true,
      options: [{ value: "live", label: "Live" }],
    }], {})
    expect(required).toContain("selected disabled hidden")
    expect(required).toContain('<option value="live">Live</option>')
    expect(required).not.toContain(">None<")

    const blankOpt = buildStepConfigFieldsHTML([{
      name: "blank",
      label: "Blank",
      control: "select",
      required: true,
      options: [{}],
    }], { blank: "" })
    expect(blankOpt).toContain("<option value=\"\" selected></option>")

    const nullValue = buildStepConfigFieldsHTML([{
      name: "mode",
      label: "Mode",
      control: "select",
      options: [{ value: null, label: "Unset" }, { value: "live", label: "Live" }],
    }], { mode: "" })
    expect(nullValue).toContain(">Unset<")
  })

  it("renders mapping with entity_attribute keys and localized text locales", () => {
    const html = buildStepConfigFieldsHTML([
      { name: "aliases", label: "Aliases", control: "mapping", keyRole: "entity_attribute", valueRole: "input" },
      { name: "title", label: "Title", control: "localized_text", required: true, default: { en: "Hello" } },
    ], {}, { entityAttributes: [{ name_slug: "email", name: "Email" }] })
    expect(html).toContain("sm:grid-cols-[1fr_1fr_auto]")
    expect(html).toContain('data-kv-key')
    expect(html).toContain('value="email"')
    expect(html).toContain('data-locale-input')
    expect(html).toContain("required")
    expect(html).toContain('value="Hello"')
  })

  it("counts list, conditions, and localized_text as set when they differ from defaults", () => {
    const schema = [
      { key: "r1", label: "R1", type: "text", required: true },
      { key: "r2", label: "R2", type: "text", required: true },
      { key: "r3", label: "R3", type: "text", required: true },
      { name: "tags", label: "Tags", control: "list" },
      { name: "filter", label: "Filter", control: "conditions" },
      { name: "title", label: "Title", control: "localized_text", default: { en: "Title" } },
      { name: "o1", control: "text", label: "O1" },
    ]
    const html = buildStepConfigFieldsHTML(schema, {
      tags: ["a"],
      filter: { type: "group", conditions: [{ leftOperand: "ctx.a" }] },
      title: { en: "Other" },
    })
    expect(html).toContain(">3 set<")
  })

  it("counts a record-count condition row as set when it has an entity", () => {
    const schema = [
      { key: "r1", label: "R1", type: "text", required: true },
      { key: "r2", label: "R2", type: "text", required: true },
      { key: "r3", label: "R3", type: "text", required: true },
      { name: "filter", label: "Filter", control: "conditions" },
      { name: "o1", control: "text", label: "O1" },
      { name: "o2", control: "text", label: "O2" },
      { name: "o3", control: "text", label: "O3" },
    ]
    const setHtml = buildStepConfigFieldsHTML(schema, {
      filter: { type: "group", conditions: [{ kind: "query_count", queryConfig: { entityId: 3 } }] },
    })
    expect(setHtml).toContain(">1 set<")

    const emptyHtml = buildStepConfigFieldsHTML(schema, {
      filter: { type: "group", conditions: [{ kind: "query_count", queryConfig: {} }] },
    })
    expect(emptyHtml).toContain(">0 set<")
  })

  it("does not count empty list/conditions/localized values as set", () => {
    const schema = [
      { key: "r1", label: "R1", type: "text", required: true },
      { key: "r2", label: "R2", type: "text", required: true },
      { key: "r3", label: "R3", type: "text", required: true },
      { name: "tags", label: "Tags", control: "list" },
      { name: "filter", label: "Filter", control: "conditions" },
      { name: "title", label: "Title", control: "localized_text" },
      { name: "o1", control: "text", label: "O1" },
    ]
    const html = buildStepConfigFieldsHTML(schema, {
      tags: [null, ""],
      filter: { type: "group", conditions: [null, { kind: "field" }] },
      title: null,
    })
    expect(html).toContain(">0 set<")
  })
})
