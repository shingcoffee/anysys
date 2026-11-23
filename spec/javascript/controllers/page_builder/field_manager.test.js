import { describe, it, expect, beforeEach } from "vitest"
import {
  FieldManager,
  FIELD_TYPE_MAPPING,
  FIELD_ICONS,
  LAYOUT_ICONS,
  LAYOUT_DEFAULTS,
  WIDTH_CLASSES,
} from "controllers/page_builder/field_manager"
import { makeCtrl, field } from "../../support/page_builder.js"

const data = (id, w, extra = {}) => field({ id, width: w, property_type: "string", ...extra })
const layout = (id, ft, extra = {}) =>
  field({ id, field_type: ft, property_type: "layout", ...extra })
const sec = (id, extra = {}) => layout(id, "section", extra)
const autoDiv = (id) => layout(id, "divider", { auto_section_divider: true })

describe("FieldManager exports", () => {
  it("maps html field types to property types with a string fallback", () => {
    expect(FIELD_TYPE_MAPPING.text).toBe("string")
    expect(FIELD_TYPE_MAPPING.checkbox).toBe("boolean")
    expect(FIELD_TYPE_MAPPING.currency).toBe("number")
    expect(FIELD_TYPE_MAPPING.section).toBe("layout")
  })

  it("exposes icon + default + width-class tables", () => {
    expect(FIELD_ICONS.string).toContain("<path")
    expect(LAYOUT_ICONS.columns).toContain("<path")
    expect(LAYOUT_DEFAULTS.button.button_variant).toBe("primary")
    expect(WIDTH_CLASSES.half).toBe("col-span-6")
    expect(WIDTH_CLASSES.full).toBe("col-span-12")
  })
})

describe("FieldManager._effectiveWidth", () => {
  let fm
  beforeEach(() => {
    fm = new FieldManager(makeCtrl())
  })

  it("returns the field width (defaulting to full) with no layout template", () => {
    expect(fm._effectiveWidth(data("a", "half"))).toBe("half")
    expect(fm._effectiveWidth(data("b", undefined))).toBe("full")
  })

  it("layout fields always use their own width", () => {
    expect(fm._effectiveWidth(layout("s", "section", { width: "half" }))).toBe("half")
  })

  it("applies a responsive override on a non-desktop viewport", () => {
    fm.c.viewportValue = "mobile"
    const f = data("a", "full", { responsive_widths: { mobile: "half" } })
    expect(fm._effectiveWidth(f)).toBe("half")
  })

  it("mobile falls back to the tablet override when no mobile override exists", () => {
    fm.c.viewportValue = "mobile"
    const f = data("a", "full", { responsive_widths: { tablet: "third" } })
    expect(fm._effectiveWidth(f)).toBe("third")
  })

  it("layout template default applies unless the width was set explicitly", () => {
    fm.c.layoutTemplateValue = { default_width: "half" }
    expect(fm._effectiveWidth(data("a", "full"))).toBe("half")
    expect(fm._effectiveWidth(data("b", "full", { width_explicit: true }))).toBe("full")
  })

  it("a layout field with no width defaults to full", () => {
    expect(fm._effectiveWidth({ id: "s", field_type: "section", property_type: "layout" })).toBe("full")
  })

  it("template width chain falls through to 'full' with no rule, default, or field width", () => {
    fm.c.layoutTemplateValue = { field_width_rules: {} } // hasLayout true, no rule for html_type, no default
    expect(fm._effectiveWidth({ id: "a", property_type: "string", html_type: "email" })).toBe("full")
  })

  it("defaults the viewport to desktop when none is set", () => {
    fm.c.viewportValue = ""
    expect(fm._effectiveWidth(data("a", "half"))).toBe("half")
  })

  it("prefers a per-html-type template rule, then the field width when the template has neither rule nor default", () => {
    fm.c.layoutTemplateValue = { field_width_rules: { tel: "third" } }
    expect(fm._effectiveWidth(data("a", "full", { html_type: "tel" }))).toBe("third")
    // no rule for this html_type and no default_width → field.width
    expect(fm._effectiveWidth(data("b", "half", { html_type: "email" }))).toBe("half")
  })
})

describe("FieldManager._getBreakpointBadge", () => {
  const fm = new FieldManager(makeCtrl())
  it("returns empty string when there are no responsive widths", () => {
    expect(fm._getBreakpointBadge(data("a"))).toBe("")
    expect(fm._getBreakpointBadge(data("b", "full", { responsive_widths: {} }))).toBe("")
  })
  it("emits T/M badges for tablet and mobile overrides", () => {
    const f = data("a", "full", { responsive_widths: { tablet: "half", mobile: "full" } })
    expect(fm._getBreakpointBadge(f)).toContain(">TM<")
  })
})

describe("FieldManager.groupFieldsIntoRows", () => {
  const fm = new FieldManager(makeCtrl())

  it("packs fields into 12-column rows", () => {
    const rows = fm.groupFieldsIntoRows([data("a", "half"), data("b", "half"), data("c", "half")])
    expect(rows).toHaveLength(2)
    expect(rows[0].fields.map((f) => f.id)).toEqual(["a", "b"]) // 6+6 = 12
    expect(rows[1].fields.map((f) => f.id)).toEqual(["c"])
  })

  it("full-width layout elements get their own row", () => {
    const rows = fm.groupFieldsIntoRows([data("a", "half"), sec("s"), data("b", "half")])
    expect(rows.map((r) => r.fields.map((f) => f.id))).toEqual([["a"], ["s"], ["b"]])
    expect(rows[1].isLayoutRow).toBe(true)
    expect(rows[1].layoutType).toBe("section")
  })

  it("field groups always occupy their own full-width row", () => {
    const g = field({ id: "g", type: "field_group", fields: [] })
    const rows = fm.groupFieldsIntoRows([data("a", "half"), g])
    expect(rows[1].isGroupRow).toBe(true)
    expect(rows[1].usedCols).toBe(12)
  })

  it("treats an unknown width as full (12 cols)", () => {
    const rows = fm.groupFieldsIntoRows([data("a", "weird")])
    expect(rows[0].usedCols).toBe(12)
  })

  it("flushes the current row before a field group and before a full-row layout element", () => {
    const g = field({ id: "g", type: "field_group", fields: [] })
    const rows = fm.groupFieldsIntoRows([data("a", "half"), g, data("b", "half"), sec("s")])
    // half, [group], half, [section] → the pending half rows are flushed each time
    expect(rows.map((r) => r.isGroupRow || r.isLayoutRow || false)).toEqual([false, true, false, true])
  })
})

describe("FieldManager section-divider helpers", () => {
  const fm = new FieldManager(makeCtrl())

  it("identifies section fields, dividers, and auto dividers", () => {
    expect(fm._isSectionField(sec("s"))).toBe(true)
    expect(fm._isDivider(layout("d", "divider"))).toBe(true)
    expect(fm._isAutoSectionDivider(autoDiv("d"))).toBe(true)
    expect(fm._isAutoSectionDivider(layout("d", "divider"))).toBe(false)
  })

  it("_sectionDividersValid: single section needs no dividers", () => {
    expect(fm._sectionDividersValid([sec("s1"), data("a")])).toBe(true)
  })

  it("_sectionDividersValid: an auto divider is required before every non-first section", () => {
    expect(fm._sectionDividersValid([sec("s1"), data("a"), sec("s2")])).toBe(false)
    expect(fm._sectionDividersValid([sec("s1"), data("a"), autoDiv("d"), sec("s2")])).toBe(true)
  })

  it("_sectionDividersValid: rejects a second divider stacked before an auto divider", () => {
    expect(fm._sectionDividersValid([sec("s1"), data("a"), layout("u", "divider"), autoDiv("d"), sec("s2")])).toBe(false)
  })

  it("_sectionDividersValid: rejects an auto divider not sitting before a section header", () => {
    expect(fm._sectionDividersValid([autoDiv("d"), data("a")])).toBe(false)
  })
})

describe("FieldManager.normalizeSectionDividers (self-healing)", () => {
  it("drops a stray user divider run sitting before a non-first section header", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [sec("s1"), data("a"), layout("u", "divider"), sec("s2")] } })
    const fm = new FieldManager(ctrl)
    fm.normalizeSectionDividers()
    const kinds = ctrl.currentPage.fields.map((f) => (fm._isAutoSectionDivider(f) ? "auto" : f.field_type))
    // the user divider is removed and replaced by a single auto separator
    expect(kinds).toEqual(["section", "text", "auto", "section"])
  })

  it("keeps a cleaned single-section list as-is (sectionCount <= 1 branch)", () => {
    // a stray auto divider not before a section is dropped, leaving <= 1 section
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [data("a"), autoDiv("d")] } })
    const fm = new FieldManager(ctrl)
    fm.normalizeSectionDividers()
    expect(ctrl.currentPage.fields.map((f) => f.id)).toEqual(["a"])
  })
})

describe("FieldManager.normalizeSectionDividers", () => {
  it("inserts an auto divider before each non-first section header", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [sec("s1"), data("a"), sec("s2"), data("b")] } })
    const fm = new FieldManager(ctrl)
    fm.normalizeSectionDividers()
    const kinds = ctrl.currentPage.fields.map((f) => (fm._isAutoSectionDivider(f) ? "auto" : f.field_type))
    expect(kinds).toEqual(["section", "text", "auto", "section", "text"])
  })

  it("is idempotent — a valid arrangement is left untouched (ids stable)", () => {
    const div = autoDiv("d")
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [sec("s1"), data("a"), div, sec("s2")] } })
    const fm = new FieldManager(ctrl)
    fm.normalizeSectionDividers()
    expect(ctrl.currentPage.fields.find((f) => fm._isAutoSectionDivider(f))).toBe(div)
  })

  it("does nothing for an empty or single-section list", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [] } })
    const fm = new FieldManager(ctrl)
    expect(() => fm.normalizeSectionDividers()).not.toThrow()
  })
})

describe("FieldManager.getFieldIcon", () => {
  const fm = new FieldManager(makeCtrl())
  it("prefers a layout icon for layout fields", () => {
    expect(fm.getFieldIcon("layout", "section")).toContain("text-violet-500")
  })
  it("prefers an html-type icon over the property-type fallback", () => {
    const svg = fm.getFieldIcon("string", null, null, "tel")
    expect(svg).toContain("<path")
  })
  it("falls back to the string icon for unknown types", () => {
    expect(fm.getFieldIcon("nonsense")).toContain(FIELD_ICONS.string)
  })
})

describe("FieldManager.getUsedPropertySlugs", () => {
  it("collects non-blank slugs across all fields", () => {
    const ctrl = makeCtrl({
      currentPage: { id: "p1", fields: [data("a", "full", { property_slug: "name" }), data("b", "full", { property_slug: "" })] },
    })
    const fm = new FieldManager(ctrl)
    const slugs = fm.getUsedPropertySlugs()
    expect(slugs.has("name")).toBe(true)
    expect(slugs.has("")).toBe(false)
  })
})

describe("FieldManager._groupRowsIntoSections", () => {
  const fm = new FieldManager(makeCtrl())
  it("wraps rows following a section header into a section group", () => {
    const rows = [
      { isLayoutRow: true, layoutType: "section", fields: [sec("s")] },
      { fields: [data("a")] },
    ]
    const groups = fm._groupRowsIntoSections(rows)
    expect(groups[0].type).toBe("section")
    expect(groups[0].sectionField.id).toBe("s")
    expect(groups[0].rows).toHaveLength(1)
  })

  it("a divider inside a section ends the section group", () => {
    const rows = [
      { isLayoutRow: true, layoutType: "section", fields: [sec("s")] },
      { fields: [data("a")] },
      { isLayoutRow: true, layoutType: "divider", fields: [layout("d", "divider")] },
      { fields: [data("b")] },
    ]
    const groups = fm._groupRowsIntoSections(rows)
    expect(groups.map((g) => g.type)).toEqual(["section", "standalone", "standalone"])
  })

  it("flushes a pending standalone group when a section header appears", () => {
    const rows = [
      { fields: [data("a")] }, // standalone content first
      { isLayoutRow: true, layoutType: "section", fields: [sec("s")] },
    ]
    const groups = fm._groupRowsIntoSections(rows)
    expect(groups.map((g) => g.type)).toEqual(["standalone", "section"])
  })

  it("ends a section group on a divider even with no child rows yet (sectionField-only flush)", () => {
    const rows = [
      { isLayoutRow: true, layoutType: "section", fields: [sec("s")] },
      { isLayoutRow: true, layoutType: "divider", fields: [layout("d", "divider")] },
    ]
    const groups = fm._groupRowsIntoSections(rows)
    expect(groups.map((g) => g.type)).toEqual(["section", "standalone"])
  })
})

describe("FieldManager.createFieldCard (DOM structure, no geometry)", () => {
  it("builds a data-field card with drag + action wiring", () => {
    const ctrl = makeCtrl()
    const fm = new FieldManager(ctrl)
    const card = fm.createFieldCard(data("a", "half", { label: "Name", html_type: "text" }))
    expect(card.dataset.fieldId).toBe("a")
    expect(card.dataset.dragKind).toBe("move")
    expect(card.className).toContain("col-span-6")
    expect(card.dataset.action).toContain("click->page-builder#selectField")
    expect(card.innerHTML).toContain("Name")
  })

  it("marks a selected data field with a resize handle", () => {
    const ctrl = makeCtrl({ selectedFieldId: "a" })
    const fm = new FieldManager(ctrl)
    const card = fm.createFieldCard(data("a", "full", { html_type: "text" }))
    expect(card.querySelector(".resize-handle")).not.toBeNull()
    expect(card.getAttribute("aria-selected")).toBe("true")
  })

  it("renders a layout card for layout fields", () => {
    const ctrl = makeCtrl()
    const fm = new FieldManager(ctrl)
    const card = fm.createFieldCard(sec("s", { label: "My Section" }))
    expect(card.className).toContain("layout-card")
    expect(card.innerHTML).toContain("My Section")
  })

  it("defaults width/label and falls back to full col-span for a widthless, labelless field", () => {
    const fm = new FieldManager(makeCtrl())
    const f = field({ id: "a", property_type: "string", html_type: "text", width: "weird" })
    delete f.label
    const card = fm.createFieldCard(f)
    expect(card.dataset.width).toBe("weird") // dataset.width keeps the raw value...
    expect(card.className).toContain("col-span-12") // ...but WIDTH_CLASSES[weird] → col-span-12 fallback
    expect(card.getAttribute("aria-label")).toContain("Untitled")
    expect(card.innerHTML).toContain("Untitled")
  })

  it("dataset.width defaults to full when the field has no width", () => {
    const fm = new FieldManager(makeCtrl())
    const f = field({ id: "a", property_type: "string", html_type: "text" })
    delete f.width
    expect(fm.createFieldCard(f).dataset.width).toBe("full")
  })

  it("marks a selected layout card as selected", () => {
    const ctrl = makeCtrl({ selectedFieldId: "s" })
    const fm = new FieldManager(ctrl)
    const card = fm.createFieldCard(sec("s"))
    expect(card.className).toContain("selected")
  })

  it("renders the required asterisk, breakpoint badge, help text, and tolerates a missing theme", () => {
    const ctrl = makeCtrl()
    ctrl.configuration.theme = undefined
    const fm = new FieldManager(ctrl)
    const f = data("a", "full", { label: "Q", html_type: "text", required: true, help_text: "Some help", responsive_widths: { mobile: "half" } })
    const card = fm.createFieldCard(f)
    expect(card.innerHTML).toContain("*")
    expect(card.innerHTML).toContain("Some help")
    expect(card.innerHTML).toContain(">M<")
  })
})

describe("FieldManager.renderFields (full DOM render)", () => {
  function renderCtrl(fields) {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields } })
    ctrl.fields = ctrl.currentPage.fields
    ctrl.hasFieldsContainerTarget = true
    ctrl.fieldsContainerTarget = document.createElement("div")
    ctrl.element = document.createElement("div")
    return ctrl
  }

  it("no-ops without a fields container", () => {
    const fm = new FieldManager(makeCtrl())
    expect(() => fm.renderFields()).not.toThrow()
  })

  it("toggles the empty-state target based on field count", () => {
    const ctrl = renderCtrl([])
    ctrl.hasEmptyStateTarget = true
    ctrl.emptyStateTarget = document.createElement("div")
    const fm = new FieldManager(ctrl)
    fm.renderFields()
    expect(ctrl.emptyStateTarget.classList.contains("hidden")).toBe(false) // no fields → shown
  })

  it("renders a section group with an inner row + drop zone and a final inserter", () => {
    const ctrl = renderCtrl([sec("s1", { label: "Sec", order: 0 }), data("a", "half", { order: 1 })])
    const fm = new FieldManager(ctrl)
    fm.renderFields()
    const c = ctrl.fieldsContainerTarget
    expect(c.querySelector(".section-group")).not.toBeNull()
    expect(c.querySelectorAll(".field-card").length).toBeGreaterThanOrEqual(2) // header + data card
    expect(c.querySelector(".row-drop-zone")).not.toBeNull() // half-width row leaves space
    expect(c.querySelectorAll(".inserter-row").length).toBeGreaterThan(0)
    expect(ctrl.pageManager.updateFormFooter).toHaveBeenCalled()
  })

  it("renders standalone rows, a field group (no order), and a col-span drop zone fallback", () => {
    const grp = field({ id: "g", type: "field_group", label: "Grp", fields: [data("gc", "full")] })
    delete grp.order
    const ctrl = renderCtrl([data("a", "quarter", { order: 0 }), grp]) // quarter row → remaining 9 (fallback col-span)
    const fm = new FieldManager(ctrl)
    fm.renderFields()
    const c = ctrl.fieldsContainerTarget
    expect(c.querySelector(".field-group")).not.toBeNull()
    expect(c.querySelector('[data-group-fields-container="g"]')).not.toBeNull()
    expect(c.querySelector(".row-drop-zone.col-span-9")).not.toBeNull()
  })

  it("marks a selected section header inside its section group", () => {
    const ctrl = renderCtrl([sec("s1", { label: "Sec", order: 0 }), data("a", "half", { order: 1 })])
    ctrl.selectedFieldId = "s1"
    const fm = new FieldManager(ctrl)
    fm.renderFields()
    const header = ctrl.fieldsContainerTarget.querySelector('.section-group .field-card[data-field-id="s1"]')
    expect(header.className).toContain("selected")
  })
})

describe("FieldManager._organizeFieldsBySource", () => {
  const fm = new FieldManager(makeCtrl())

  it("groups entity, associated (bridge) and standalone-layout fields, adding headers", () => {
    fm.c.metadata = { entity_name: "Contact" }
    const result = fm._organizeFieldsBySource([
      data("d1", "full", { source: "entity", property_slug: "d1" }),
      field({ id: "b1", source: "bridge", source_section: "Orders", property_slug: "b1" }),
      layout("div", "divider"), // standalone layout (no source)
    ])
    const ids = result.map((f) => f.id)
    // an auto entity header + d1, then a bridge header + b1, then the standalone divider
    expect(ids).toContain("d1")
    expect(ids).toContain("b1")
    expect(ids[ids.length - 1]).toBe("div")
    const headers = result.filter((f) => f.field_type === "section")
    expect(headers.length).toBeGreaterThanOrEqual(2)
  })

  it("treats a source-less section header as an entity field and defaults entity_name to null", () => {
    const fm2 = new FieldManager(makeCtrl())
    fm2.c.metadata = {} // no entity_name → `|| null`
    const result = fm2._organizeFieldsBySource([
      sec("hdr"), // section header with no source → third clause of the entity check
      data("d1", "full", { property_slug: "d1" }),
    ])
    expect(result.map((f) => f.id)).toContain("hdr")
    expect(result[0].id).toBe("hdr") // header moved to front of the entity group
  })
})

describe("FieldManager._ensureSectionHeader", () => {
  const fm = new FieldManager(makeCtrl())

  it("no-ops for an empty group", () => {
    const g = []
    fm._ensureSectionHeader(g, "entity", "X")
    expect(g).toEqual([])
  })

  it("moves an existing section header to the front", () => {
    const g = [data("a"), sec("s"), data("b")]
    fm._ensureSectionHeader(g, "entity", "X")
    expect(g[0].id).toBe("s")
  })

  it("leaves an already-leading header untouched", () => {
    const g = [sec("s"), data("a")]
    fm._ensureSectionHeader(g, "entity", "X")
    expect(g[0].id).toBe("s")
  })

  it("auto-generates a header, appending ' Fields' for entity groups and the raw name otherwise", () => {
    const entityGroup = [data("a")]
    fm._ensureSectionHeader(entityGroup, "entity", "Person")
    expect(entityGroup[0].label).toBe("Person Fields")

    const bridgeGroup = [data("b")]
    fm._ensureSectionHeader(bridgeGroup, "bridge", "Orders")
    expect(bridgeGroup[0].label).toBe("Orders")

    const noName = [data("c")]
    fm._ensureSectionHeader(noName, "bridge", null)
    expect(noName[0].label).toBe("Fields") // sectionName null → "Fields"
  })
})

describe("FieldManager.selectField / selectSection / selectFieldById / deselectField", () => {
  it("selectField forwards the field id and modifier keys, skipping handle/remove/duplicate clicks", () => {
    const ctrl = makeCtrl()
    const fm = new FieldManager(ctrl)
    const card = document.createElement("div")
    card.dataset.fieldId = "a"
    fm.selectField({ currentTarget: card, target: card, shiftKey: true, metaKey: false, ctrlKey: false })
    expect(ctrl.selectionManager.selectField).toHaveBeenCalledWith("a", { shift: true, meta: false })

    // a click landing on the drag handle is ignored
    const handle = document.createElement("div"); handle.className = "field-drag-handle"; card.appendChild(handle)
    ctrl.selectionManager.selectField.mockClear()
    fm.selectField({ currentTarget: card, target: handle, shiftKey: false, metaKey: false, ctrlKey: false })
    expect(ctrl.selectionManager.selectField).not.toHaveBeenCalled()
  })

  it("selectField ignores clicks on the remove and duplicate buttons", () => {
    const ctrl = makeCtrl()
    const fm = new FieldManager(ctrl)
    const card = document.createElement("div")
    card.dataset.fieldId = "a"
    const remove = document.createElement("div"); remove.className = "field-remove-btn"; card.appendChild(remove)
    const dup = document.createElement("div"); dup.className = "field-duplicate-btn"; card.appendChild(dup)
    fm.selectField({ currentTarget: card, target: remove, shiftKey: false, metaKey: false, ctrlKey: false })
    fm.selectField({ currentTarget: card, target: dup, shiftKey: false, metaKey: false, ctrlKey: false })
    expect(ctrl.selectionManager.selectField).not.toHaveBeenCalled()
  })

  it("selectSection selects every field card in the wrapper, deferring to inline edit", () => {
    const ctrl = makeCtrl()
    const fm = new FieldManager(ctrl)
    const wrapper = document.createElement("div")
    wrapper.className = "section-group"
    wrapper.innerHTML = '<div class="field-card" data-field-id="h"></div><div class="field-card" data-field-id="a"></div>'
    const trigger = document.createElement("div")
    wrapper.appendChild(trigger)
    fm.selectSection({ currentTarget: trigger, target: trigger })
    expect(ctrl.selectionManager.selectFields).toHaveBeenCalledWith(["h", "a"])

    // inline-edit target defers (no selection)
    ctrl.selectionManager.selectFields.mockClear()
    const editTarget = document.createElement("div"); editTarget.setAttribute("data-inline-edit-property", "label")
    fm.selectSection({ currentTarget: trigger, target: editTarget })
    expect(ctrl.selectionManager.selectFields).not.toHaveBeenCalled()
  })

  it("selectSection bails without a wrapper or with no cards", () => {
    const ctrl = makeCtrl()
    const fm = new FieldManager(ctrl)
    const lonely = document.createElement("div")
    expect(() => fm.selectSection({ currentTarget: lonely, target: lonely })).not.toThrow()
    const emptyWrapper = document.createElement("div"); emptyWrapper.className = "section-group"
    const t = document.createElement("div"); emptyWrapper.appendChild(t)
    fm.selectSection({ currentTarget: t, target: t })
    expect(ctrl.selectionManager.selectFields).not.toHaveBeenCalled()
  })

  it("selectFieldById and deselectField delegate to the selection manager", () => {
    const ctrl = makeCtrl()
    const fm = new FieldManager(ctrl)
    fm.selectFieldById("x")
    expect(ctrl.selectionManager.selectField).toHaveBeenCalledWith("x", { shift: false, meta: false })
    fm.deselectField()
    expect(ctrl.selectionManager.deselectAll).toHaveBeenCalled()
  })
})

describe("FieldManager.updateField", () => {
  function formOf(values) {
    const form = document.createElement("form")
    for (const [name, value] of Object.entries(values)) {
      const input = document.createElement("input")
      input.name = name
      input.value = value
      if (name === "required") { input.type = "checkbox"; input.checked = value === "on"; input.value = "on" }
      form.appendChild(input)
    }
    return form
  }
  function ctrlWith(field0) {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field0] }, selectedFieldId: field0.id })
    ctrl.fields = ctrl.currentPage.fields
    return ctrl
  }

  it("no-ops without a selection or when the field is missing", () => {
    const ctrl = makeCtrl({ selectedFieldId: null })
    const fm = new FieldManager(ctrl)
    fm.updateField({})
    ctrl.selectedFieldId = "ghost"
    ctrl.fields = []
    ctrl.propertyFormTarget = formOf({ label: "X" })
    fm.updateField({})
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("writes core attributes for a data field", () => {
    const ctrl = ctrlWith(data("a", "half", { label: "Old" }))
    ctrl.propertyFormTarget = formOf({ label: "New", placeholder: "ph", help_text: "help", required: "on", width: "full" })
    const fm = new FieldManager(ctrl)
    fm.updateField({})
    const f = ctrl.fields[0]
    expect(f).toMatchObject({ label: "New", placeholder: "ph", help_text: "help", required: true, width: "full" })
    expect(ctrl.undoRedoManager.saveState).toHaveBeenCalled()
  })

  it("keeps the existing label/width when the form omits them", () => {
    const ctrl = ctrlWith(data("a", "third", { label: "Keep" }))
    ctrl.propertyFormTarget = formOf({ label: "", width: "" })
    const fm = new FieldManager(ctrl)
    fm.updateField({})
    expect(ctrl.fields[0].label).toBe("Keep")
    expect(ctrl.fields[0].width).toBe("third")
  })

  it("writes every layout type-specific attribute", () => {
    const cases = [
      ["heading", { heading_level: "h1" }, "heading_level", "h1"],
      ["spacer", { spacer_height: "lg" }, "spacer_height", "lg"],
      ["alert", { alert_variant: "warning" }, "alert_variant", "warning"],
      ["image", { image_url: "u", alt_text: "alt" }, "image_url", "u"],
      ["quote", { attribution: "me" }, "attribution", "me"],
      ["button", { button_url: "b", button_variant: "ghost", button_size: "lg", alignment: "right" }, "button_variant", "ghost"],
      ["video", { video_url: "v", alignment: "left" }, "video_url", "v"],
      ["list", { list_style: "numbered" }, "list_style", "numbered"],
      ["code_block", { code_language: "ruby" }, "code_language", "ruby"],
      ["progress_bar", { progress_value: "42", progress_color: "rose" }, "progress_value", 42],
    ]
    for (const [ft, formValues, key, expected] of cases) {
      const ctrl = ctrlWith(layout("a", ft, { content: "" }))
      ctrl.propertyFormTarget = formOf({ label: "L", content: "body", ...formValues })
      const fm = new FieldManager(ctrl)
      fm.updateField({})
      expect(ctrl.fields[0][key]).toEqual(expected)
      expect(ctrl.fields[0].content).toBe("body")
    }
  })

  it("falls back to hard-coded defaults for every layout type when the form omits values", () => {
    const cases = [
      ["heading", "heading_level", "h3"],
      ["spacer", "spacer_height", "md"],
      ["alert", "alert_variant", "info"],
      ["image", "image_url", ""],
      ["quote", "attribution", ""],
      ["button", "button_url", "#"],
      ["button", "button_variant", "primary"],
      ["button", "button_size", "md"],
      ["button", "alignment", "left"],
      ["video", "video_url", ""],
      ["video", "alignment", "center"],
      ["list", "list_style", "bullet"],
      ["code_block", "code_language", ""],
      ["progress_bar", "progress_value", 0], // parseInt(null) || 0
      ["progress_bar", "progress_color", "indigo"],
    ]
    for (const [ft, key, expected] of cases) {
      const ctrl = ctrlWith(layout("a", ft))
      ctrl.propertyFormTarget = formOf({ label: "L" }) // no type-specific inputs, no content
      const fm = new FieldManager(ctrl)
      fm.updateField({})
      expect(ctrl.fields[0][key]).toEqual(expected)
      expect(ctrl.fields[0].content).toBe("") // formData.get("content") null → ""
    }
  })

  it("defaults width to full when neither the form nor the field carries one", () => {
    const f = data("a", undefined, { label: "X" })
    delete f.width
    const ctrl = ctrlWith(f)
    ctrl.propertyFormTarget = formOf({ label: "X" }) // no width input
    const fm = new FieldManager(ctrl)
    fm.updateField({})
    expect(ctrl.fields[0].width).toBe("full")
  })
})

describe("FieldManager._renderFieldGroup", () => {
  const fm = new FieldManager(makeCtrl())

  it("builds a field-group element with nested cards and default styling", () => {
    const grp = field({ id: "g", type: "field_group", label: "My Group", fields: [data("c1", "full")] })
    const el = fm._renderFieldGroup(grp)
    expect(el.className).toContain("field-group")
    expect(el.dataset.groupId).toBe("g")
    expect(el.querySelector('[data-group-fields-container="g"]').children.length).toBe(1)
    expect(el.innerHTML).toContain("My Group")
  })

  it("applies custom style tokens and marks a selected group", () => {
    const ctrl = makeCtrl()
    ctrl.selectionManager.isSelected = () => true
    const fm2 = new FieldManager(ctrl)
    const grp = field({ id: "g", type: "field_group", width: "half", style: { border: "solid", background: "light_blue" }, fields: [] })
    const el = fm2._renderFieldGroup(grp)
    expect(el.className).toContain("col-span-6")
    expect(el.className).toContain("border-solid")
    expect(el.className).toContain("bg-blue-50/30")
    expect(el.classList.contains("selected")).toBe(true)
  })

  it("defaults the group label and falls back to full width / default border for unknown tokens", () => {
    const grp = field({ id: "g", type: "field_group", width: "weird", style: { border: "unknown", background: "unknown" } })
    delete grp.label
    delete grp.fields
    const el = fm._renderFieldGroup(grp)
    expect(el.innerHTML).toContain("Field Group")
    expect(el.className).toContain("col-span-12") // WIDTH_CLASSES[weird] → fallback
  })

  it("defaults to full width when the group has no width and no style object", () => {
    const grp = field({ id: "g", type: "field_group", fields: [] })
    delete grp.width
    const el = fm._renderFieldGroup(grp) // group.style?.border → dashed default
    expect(el.className).toContain("col-span-12")
    expect(el.className).toContain("border-dashed")
  })
})

describe("FieldManager.updateSidebarFieldStates", () => {
  function sidebar(usedSlug) {
    const el = document.createElement("div")
    el.innerHTML = `
      <div data-searchable-section>
        <div class="entity-field-item" data-property-slug="used"></div>
        <div class="entity-field-item" data-property-slug="free"></div>
        <button data-add-all-section></button>
        <button data-remove-all-section></button>
      </div>`
    return el
  }

  it("disables used items, enables free ones, and toggles section add/remove buttons + count badge", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [data("x", "full", { property_slug: "used" })] } })
    ctrl.fields = ctrl.currentPage.fields
    ctrl.element = sidebar()
    ctrl.hasEntityFieldCountTarget = true
    ctrl.entityFieldCountTarget = document.createElement("span")
    const fm = new FieldManager(ctrl)
    fm.updateSidebarFieldStates()
    const used = ctrl.element.querySelector('[data-property-slug="used"]')
    const free = ctrl.element.querySelector('[data-property-slug="free"]')
    expect(used.classList.contains("opacity-40")).toBe(true)
    expect(used.draggable).toBe(false)
    expect(free.draggable).toBe(true)
    expect(ctrl.entityFieldCountTarget.textContent).toBe("1/2") // one of two available
    // add stays enabled (not all used), remove enabled (not none used)
    expect(ctrl.element.querySelector("[data-add-all-section]").disabled).toBe(false)
    expect(ctrl.element.querySelector("[data-remove-all-section]").disabled).toBe(false)
  })

  it("shows a plain total when every field is available, and disables remove-all", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [] } })
    ctrl.fields = []
    ctrl.element = sidebar()
    ctrl.hasEntityFieldCountTarget = true
    ctrl.entityFieldCountTarget = document.createElement("span")
    const fm = new FieldManager(ctrl)
    fm.updateSidebarFieldStates()
    expect(ctrl.entityFieldCountTarget.textContent).toBe("2") // all available → plain total
    expect(ctrl.element.querySelector("[data-remove-all-section]").disabled).toBe(true) // none used
  })
})

describe("FieldManager.renderFieldCard", () => {
  it("replaces an existing card and re-applies selection visuals", () => {
    const ctrl = makeCtrl()
    ctrl.element = document.createElement("div")
    ctrl.element.innerHTML = '<div data-field-id="a" class="old"></div>'
    const fm = new FieldManager(ctrl)
    fm.renderFieldCard(data("a", "half", { label: "Fresh", html_type: "text" }))
    const card = ctrl.element.querySelector('[data-field-id="a"]')
    expect(card.classList.contains("old")).toBe(false)
    expect(card.innerHTML).toContain("Fresh")
    expect(ctrl.selectionManager.updateVisuals).toHaveBeenCalled()
  })

  it("is a no-op when no matching card exists", () => {
    const ctrl = makeCtrl()
    ctrl.element = document.createElement("div")
    const fm = new FieldManager(ctrl)
    expect(() => fm.renderFieldCard(data("ghost"))).not.toThrow()
  })
})
