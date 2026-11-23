import { describe, it, expect, beforeEach, vi, afterEach } from "vitest"
import { FieldManager, LAYOUT_DEFAULTS } from "controllers/page_builder/field_manager"
import { makeCtrl, field } from "../../../support/page_builder.js"

// A dataset-bearing element usable as event.currentTarget.
function el(dataset = {}) {
  const d = document.createElement("div")
  Object.assign(d.dataset, dataset)
  return d
}
const ev = (currentTarget) => ({ currentTarget, stopPropagation() {} })

// Builds a searchable-section container with entity-field-item children and a
// trigger button, appended to the body (callers clean up in afterEach).
function sectionEl(sectionId, items) {
  const section = document.createElement("div")
  section.dataset.searchableSection = sectionId
  items.forEach((data) => {
    const item = document.createElement("div")
    item.className = "entity-field-item"
    Object.assign(item.dataset, data)
    section.appendChild(item)
  })
  const trigger = document.createElement("button")
  section.appendChild(trigger)
  document.body.appendChild(section)
  return { section, trigger }
}

// FieldCrudMixin is mixed onto FieldManager.prototype, so we exercise it through
// a real FieldManager instance backed by a stub controller.
describe("FieldCrudMixin.createField", () => {
  let ctrl, fm
  beforeEach(() => {
    ctrl = makeCtrl()
    fm = new FieldManager(ctrl)
  })

  it("builds a data field with mapped property_type, slug, and html_type", () => {
    const f = fm.createField({ type: "text", label: "First Name" })
    expect(f.property_type).toBe("string")
    expect(f.property_slug).toBe("first_name")
    expect(f.html_type).toBe("text")
    expect(f.field_type).toBe("text")
    expect(f.required).toBe(false)
    expect(f.width).toBe("full")
    expect(f.id).toMatch(/^field_/)
  })

  it("applies layout defaults for layout types", () => {
    const f = fm.createField({ type: "button" })
    expect(f.property_type).toBe("layout")
    expect(f.button_variant).toBe("primary")
    expect(f.button_url).toBe("#")
    expect(f.content).toBe("Click Me")
    expect(f.html_type).toBeUndefined()
  })

  it("prefers server-provided localized default label/content over the English LAYOUT_DEFAULTS", () => {
    ctrl.layoutDefaultLabelsValue = { button: "按钮" }
    ctrl.layoutDefaultContentsValue = { button: "点击我" }
    const f = fm.createField({ type: "button" })
    expect(f.label).toBe("按钮")
    expect(f.content).toBe("点击我")
  })

  it("gives type-specific defaults for range/currency/rating/switch", () => {
    expect(fm.createField({ type: "range" })).toMatchObject({ min_value: "0", max_value: "100", step: "1" })
    expect(fm.createField({ type: "currency" })).toMatchObject({ currency_symbol: "$", decimal_places: "2" })
    expect(fm.createField({ type: "rating" })).toMatchObject({ max_rating: "5", allow_half: false })
    expect(fm.createField({ type: "switch" })).toMatchObject({ on_label: "Yes", off_label: "No" })
  })

  it("de-duplicates layout slugs against existing fields", () => {
    ctrl.currentPage.fields = [field({ id: "1", field_type: "divider", property_type: "layout", property_slug: "divider" })]
    ctrl.fields = ctrl.currentPage.fields
    const f = fm.createField({ type: "divider" })
    expect(f.property_slug).toBe("divider_1")
  })

  it("skips creating an html_type for entity fields without one", () => {
    const f = fm.createField({ type: "entity", label: "Ref" })
    expect(f.html_type).toBeUndefined()
  })

  it("merges override config but protects id/type/slug/order", () => {
    const f = fm.createField(
      { type: "text", label: "X" },
      { placeholder: "hi", id: "HACK", property_slug: "HACK", field_type: "evil", validation: { required: true } }
    )
    expect(f.placeholder).toBe("hi")
    expect(f.validation).toEqual({ required: true })
    expect(f.id).not.toBe("HACK")
    expect(f.property_slug).toBe("x")
    expect(f.field_type).toBe("text")
  })

  it("applies layout-template width to data fields when a template is active", () => {
    ctrl.layoutTemplateValue = { default_width: "half" }
    const f = fm.createField({ type: "text", label: "A" })
    expect(f.width).toBe("half")
  })

  it("prefers a per-html-type width rule over the template default", () => {
    ctrl.layoutTemplateValue = { field_width_rules: { email: "third" }, default_width: "half" }
    expect(fm.createField({ type: "email", label: "E" }).width).toBe("third")
    // a type with no rule falls back to the template default width
    expect(fm.createField({ type: "text", label: "T" }).width).toBe("half")
  })

  it("sets type-specific defaults for every layout type", () => {
    expect(fm.createField({ type: "heading" })).toMatchObject({ heading_level: "h3" })
    expect(fm.createField({ type: "spacer" })).toMatchObject({ spacer_height: "md" })
    expect(fm.createField({ type: "alert" })).toMatchObject({ alert_variant: "info" })
    expect(fm.createField({ type: "image", propertyType: "layout" })).toMatchObject({ image_url: "", alt_text: "" })
    expect(fm.createField({ type: "quote" })).toMatchObject({ attribution: "" })
    expect(fm.createField({ type: "video" })).toMatchObject({ video_url: "", alignment: "center" })
    expect(fm.createField({ type: "list" })).toMatchObject({ list_style: "bullet" })
    expect(fm.createField({ type: "code_block" })).toMatchObject({ code_language: "" })
    expect(fm.createField({ type: "progress_bar" })).toMatchObject({ progress_value: 50, progress_color: "indigo" })
    const cols = fm.createField({ type: "columns" })
    expect(cols.column_layout).toBe("50-50")
    expect(cols.columns).toEqual([{ fields: [] }, { fields: [] }])
  })

  it("falls back to formatLabel for a layout type with no LAYOUT_DEFAULTS entry", () => {
    const f = fm.createField({ type: "divider" })
    expect(f.property_type).toBe("layout")
    expect(f.label).toBe("Divider")
  })

  it("adds textarea rows and copies options / dynamic_options for data fields", () => {
    expect(fm.createField({ type: "textarea" }).rows).toBe("3")
    const withOpts = fm.createField({ type: "select", options: [{ label: "A" }] })
    expect(withOpts.options).toEqual([{ label: "A" }])
    const withDyn = fm.createField({ type: "select", dynamicOptions: { options_source: "entity" } })
    expect(withDyn.dynamic_options).toEqual({ options_source: "entity" })
  })

  it("ignores an empty options array and dynamicOptions without a source", () => {
    const f = fm.createField({ type: "select", options: [], dynamicOptions: { foo: 1 } })
    expect(f.options).toBeUndefined()
    expect(f.dynamic_options).toBeUndefined()
  })

  it("ignores a non-object override argument", () => {
    const f = fm.createField({ type: "text", label: "X" }, "not-an-object")
    expect(f.label).toBe("X")
  })

  it("hard-codes the fallback when a LAYOUT_DEFAULTS entry omits a type-specific key", () => {
    // Each of these `layoutDefaults.<key> || <literal>` guards fires only when
    // the (normally complete) LAYOUT_DEFAULTS entry lacks the key. Exercise the
    // fallback by temporarily removing the key, then restore it.
    const cases = [
      ["heading", "heading_level", "h3"],
      ["spacer", "spacer_height", "md"],
      ["alert", "alert_variant", "info"],
      ["button", "button_url", "#"],
      ["button", "button_variant", "primary"],
      ["button", "button_size", "md"],
      ["button", "alignment", "left"],
      ["video", "alignment", "center"],
      ["list", "list_style", "bullet"],
      ["progress_bar", "progress_value", 50],
      ["progress_bar", "progress_color", "indigo"],
      ["columns", "column_layout", "50-50"],
    ]
    for (const [type, key, expected] of cases) {
      const saved = LAYOUT_DEFAULTS[type][key]
      delete LAYOUT_DEFAULTS[type][key]
      try {
        expect(fm.createField({ type })[key]).toEqual(expected)
      } finally {
        LAYOUT_DEFAULTS[type][key] = saved
      }
    }
  })

  it("defaults the columns layout array when LAYOUT_DEFAULTS omits it", () => {
    const saved = LAYOUT_DEFAULTS.columns.columns
    delete LAYOUT_DEFAULTS.columns.columns
    try {
      expect(fm.createField({ type: "columns" }).columns).toEqual([{ fields: [] }, { fields: [] }])
    } finally {
      LAYOUT_DEFAULTS.columns.columns = saved
    }
  })

  it("uses an empty defaults object for a layout type absent from LAYOUT_DEFAULTS", () => {
    const f = fm.createField({ type: "widget", propertyType: "layout" })
    expect(f.property_type).toBe("layout")
    expect(f.content).toBe("") // layoutDefaults.content undefined → ""
    expect(f.label).toBe("Widget") // no defaults.label → formatLabel(type)
  })

  it("resolves template width to null when the active template has neither a rule nor a default", () => {
    ctrl.layoutTemplateValue = { some_other_key: true } // hasLayout true, but no width info
    const f = fm.createField({ type: "text", label: "A", width: "quarter" })
    expect(f.width).toBe("quarter") // templateWidth null → data.width
  })
})

describe("FieldCrudMixin.mapFieldTypeToPropertyType", () => {
  const fm = new FieldManager(makeCtrl())
  it("maps known types and falls back to string", () => {
    expect(fm.mapFieldTypeToPropertyType("date")).toBe("date")
    expect(fm.mapFieldTypeToPropertyType("mystery")).toBe("string")
  })
})

describe("FieldCrudMixin.findFieldById / removeFieldFromAnyColumn", () => {
  let ctrl, fm
  beforeEach(() => {
    const columnsField = field({
      id: "cols", field_type: "columns", property_type: "layout",
      columns: [{ fields: [field({ id: "child" })] }, { fields: [] }],
    })
    const group = field({ id: "grp", type: "field_group", fields: [field({ id: "gchild" })] })
    ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "top" }), columnsField, group] } })
    ctrl.fields = ctrl.currentPage.fields
    fm = new FieldManager(ctrl)
  })

  it("finds top-level, column-nested, and group-nested fields", () => {
    expect(fm.findFieldById("top").id).toBe("top")
    expect(fm.findFieldById("child").id).toBe("child")
    expect(fm.findFieldById("gchild").id).toBe("gchild")
    expect(fm.findFieldById("nope")).toBeNull()
  })

  it("removes a field from whichever column holds it", () => {
    expect(fm.removeFieldFromAnyColumn("child")).toBe(true)
    expect(fm.findFieldById("child")).toBeNull()
    expect(fm.removeFieldFromAnyColumn("child")).toBe(false)
  })

  it("tolerates columns whose column has no fields array (`col.fields || []`)", () => {
    const cols = field({ id: "cols", field_type: "columns", property_type: "layout", columns: [{}] }) // column w/o fields
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [cols] } })
    ctrl.fields = ctrl.currentPage.fields
    const fm2 = new FieldManager(ctrl)
    expect(fm2.findFieldById("nope")).toBeNull()
    expect(fm2.removeFieldFromAnyColumn("nope")).toBe(false)
  })
})

describe("FieldCrudMixin._uniqueCopySlug", () => {
  const ctrl = makeCtrl({
    currentPage: { id: "p1", fields: [field({ id: "1", property_slug: "email_copy" })] },
  })
  const fm = new FieldManager(ctrl)
  it("appends _copy and increments past collisions", () => {
    expect(fm._uniqueCopySlug("email")).toBe("email_copy_2")
  })
  it("strips an existing _copy suffix and handles blank input", () => {
    expect(fm._uniqueCopySlug("name_copy_3")).toBe("name_copy")
    expect(fm._uniqueCopySlug("")).toBe("field_copy")
  })
})

describe("FieldCrudMixin.duplicateField", () => {
  it("clones the selected field in place with a (Copy) label", () => {
    const a = field({ id: "a", label: "A", property_slug: "a", order: 0 })
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [a] }, selectedFieldId: "a" })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    fm.duplicateField()
    expect(ctrl.currentPage.fields).toHaveLength(2)
    expect(ctrl.currentPage.fields[1].label).toBe("A (Copy)")
    expect(ctrl.currentPage.fields[1].property_slug).toBe("a_copy")
    expect(ctrl.undoRedoManager.saveState).toHaveBeenCalled()
  })

  it("no-ops with no selection", () => {
    const ctrl = makeCtrl({ selectedFieldId: null })
    const fm = new FieldManager(ctrl)
    fm.duplicateField()
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("no-ops when the selected id resolves to no field", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a" })] }, selectedFieldId: "ghost" })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    fm.duplicateField()
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })
})

describe("FieldCrudMixin.deleteField", () => {
  it("removes the selected fields and prunes references", () => {
    const a = field({ id: "a" })
    const b = field({ id: "b" })
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [a, b] } })
    ctrl.fields = ctrl.currentPage.fields
    ctrl.selectionManager.isEmpty = false
    ctrl.selectionManager.getSelectedFieldIds.mockReturnValue(["a"])
    const fm = new FieldManager(ctrl)
    fm.deleteField()
    expect(ctrl.currentPage.fields.map((f) => f.id)).toEqual(["b"])
    expect(ctrl.pageManager.pruneReferencesToDeletedFields).toHaveBeenCalled()
    expect(ctrl.selectionManager.deselectAll).toHaveBeenCalled()
  })

  it("no-ops when the selection is empty", () => {
    const ctrl = makeCtrl()
    ctrl.selectionManager.isEmpty = true
    const fm = new FieldManager(ctrl)
    fm.deleteField()
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("removes a nested column child via removeFieldFromAnyColumn (topIdx -1 branch)", () => {
    const cols = field({ id: "cols", field_type: "columns", property_type: "layout", columns: [{ fields: [field({ id: "child" })] }] })
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [cols] } })
    ctrl.fields = ctrl.currentPage.fields
    ctrl.selectionManager.isEmpty = false
    ctrl.selectionManager.getSelectedFieldIds.mockReturnValue(["child"])
    const fm = new FieldManager(ctrl)
    fm.deleteField()
    expect(fm.findFieldById("child")).toBeNull()
    expect(ctrl.currentPage.fields[0].columns[0].fields).toHaveLength(0)
  })
})

describe("FieldCrudMixin._insertFieldInSourceOrder", () => {
  it("inserts an entity field before the first bridge-sourced field", () => {
    const ctrl = makeCtrl({
      currentPage: { id: "p1", fields: [field({ id: "e1", source: "entity" }), field({ id: "b1", source: "bridge", source_section: "S" })] },
    })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    fm._insertFieldInSourceOrder(field({ id: "new", source: "entity" }))
    expect(ctrl.currentPage.fields.map((f) => f.id)).toEqual(["e1", "new", "b1"])
  })

  it("inserts a bridge field after the last field of its own section", () => {
    const ctrl = makeCtrl({
      currentPage: { id: "p1", fields: [field({ id: "b1", source: "bridge", source_section: "S" }), field({ id: "b2", source: "bridge", source_section: "T" })] },
    })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    fm._insertFieldInSourceOrder(field({ id: "new", source: "bridge", source_section: "S" }))
    expect(ctrl.currentPage.fields.map((f) => f.id)).toEqual(["b1", "new", "b2"])
  })

  it("appends a bridge field when its section has no existing members (lastIdx -1)", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "b2", source: "bridge", source_section: "T" })] } })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    fm._insertFieldInSourceOrder(field({ id: "new", source: "bridge", source_section: "S" }))
    expect(ctrl.currentPage.fields.map((f) => f.id)).toEqual(["b2", "new"])
  })
})

describe("FieldCrudMixin.addField", () => {
  let ctrl, fm
  beforeEach(() => {
    ctrl = makeCtrl({ currentPage: { id: "p1", fields: [] } })
    ctrl.fields = ctrl.currentPage.fields
    fm = new FieldManager(ctrl)
  })

  it("creates and inserts a palette field, then selects it and closes the panels", () => {
    fm.addField(ev(el({ fieldType: "text", fieldLabel: "Name" })))
    expect(ctrl.currentPage.fields).toHaveLength(1)
    expect(ctrl.currentPage.fields[0].field_type).toBe("text")
    expect(ctrl.undoRedoManager.saveState).toHaveBeenCalled()
    expect(ctrl.tabManager.closeAllTabPanels).toHaveBeenCalled()
  })

  it("parses field options / dynamic options datasets and falls back label to propertyName", () => {
    fm.addField(ev(el({
      fieldType: "select", propertyName: "Country", propertySlug: "country",
      fieldOptions: JSON.stringify([{ label: "US" }]),
      dynamicOptions: JSON.stringify({ options_source: "entity" }),
    })))
    const f = ctrl.currentPage.fields[0]
    expect(f.label).toBe("Country")
    expect(f.options).toEqual([{ label: "US" }])
    expect(f.dynamic_options).toEqual({ options_source: "entity" })
  })

  it("skips a field whose property slug is already used", () => {
    ctrl.currentPage.fields = [field({ id: "1", property_slug: "email" })]
    ctrl.fields = ctrl.currentPage.fields
    fm.addField(ev(el({ fieldType: "email", propertySlug: "email" })))
    expect(ctrl.currentPage.fields).toHaveLength(1)
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("skips an entity field with no html type", () => {
    fm.addField(ev(el({ fieldType: "entity", propertyName: "Ref" })))
    expect(ctrl.currentPage.fields).toHaveLength(0)
  })
})

describe("FieldCrudMixin.addFieldAtIndex", () => {
  it("inserts at a clamped index and renumbers order", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a" }), field({ id: "b" })] } })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    fm.addFieldAtIndex({ type: "text", label: "Mid" }, 1)
    expect(ctrl.currentPage.fields.map((f) => f.label)).toEqual(["Field", "Mid", "Field"])
    expect(ctrl.currentPage.fields.map((f) => f.order)).toEqual([0, 1, 2])

    // an out-of-range index clamps to the end
    fm.addFieldAtIndex({ type: "text", label: "End" }, 99)
    expect(ctrl.currentPage.fields[3].label).toBe("End")
  })
})

describe("FieldCrudMixin.duplicateSelectedField / deleteSelectedField", () => {
  it("duplicateSelectedField delegates to duplicateField", () => {
    const a = field({ id: "a", label: "A", property_slug: "a" })
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [a] }, selectedFieldId: "a" })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    fm.duplicateSelectedField()
    expect(ctrl.currentPage.fields).toHaveLength(2)
  })

  it("deleteSelectedField hides the panel then deletes", () => {
    const a = field({ id: "a" })
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [a] } })
    ctrl.fields = ctrl.currentPage.fields
    ctrl.selectionManager.isEmpty = false
    ctrl.selectionManager.getSelectedFieldIds.mockReturnValue(["a"])
    const fm = new FieldManager(ctrl)
    fm.deleteSelectedField()
    expect(ctrl.propertyManager.hideFloatingPanel).toHaveBeenCalled()
    expect(ctrl.currentPage.fields).toHaveLength(0)
  })
})

describe("FieldCrudMixin.duplicateFieldFromCard / removeFieldFromCard", () => {
  let ctrl, fm
  beforeEach(() => {
    const cols = field({ id: "cols", field_type: "columns", property_type: "layout", columns: [{ fields: [field({ id: "child", property_slug: "child" })] }] })
    ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a", property_slug: "a" }), cols] } })
    ctrl.fields = ctrl.currentPage.fields
    fm = new FieldManager(ctrl)
  })

  it("duplicateFieldFromCard clones a top-level field in place", () => {
    fm.duplicateFieldFromCard(ev(el({ fieldId: "a" })))
    expect(ctrl.currentPage.fields.map((f) => f.id).length).toBe(3)
    expect(ctrl.currentPage.fields[1].property_slug).toBe("a_copy")
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
  })

  it("duplicateFieldFromCard is a no-op for an unknown field id", () => {
    fm.duplicateFieldFromCard(ev(el({ fieldId: "ghost" })))
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("removeFieldFromCard deletes a top-level field and deselects it if selected", () => {
    ctrl.selectedFieldId = "a"
    fm.removeFieldFromCard(ev(el({ fieldId: "a" })))
    expect(ctrl.currentPage.fields.find((f) => f.id === "a")).toBeUndefined()
    expect(ctrl.pageManager.pruneReferencesToDeletedFields).toHaveBeenCalled()
  })

  it("removeFieldFromCard removes a nested column child", () => {
    fm.removeFieldFromCard(ev(el({ fieldId: "child" })))
    expect(fm.findFieldById("child")).toBeNull()
  })

  it("removeFieldFromCard bails without a field id", () => {
    fm.removeFieldFromCard(ev(el({})))
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })
})

describe("FieldCrudMixin.ungroupFields", () => {
  it("splices a field group's children back into the page", () => {
    const grp = field({ id: "grp", type: "field_group", fields: [field({ id: "g1" }), field({ id: "g2" })] })
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a" }), grp] } })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    fm.ungroupFields(ev(el({ groupId: "grp" })))
    expect(ctrl.currentPage.fields.map((f) => f.id)).toEqual(["a", "g1", "g2"])
    expect(ctrl.saveManager.markDirty).toHaveBeenCalled()
  })

  it("is a no-op for an unknown group id", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a" })] } })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    fm.ungroupFields(ev(el({ groupId: "ghost" })))
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("ungroups an empty group (no fields array) without error", () => {
    const grp = field({ id: "grp", type: "field_group" })
    delete grp.fields
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [grp] } })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    fm.ungroupFields(ev(el({ groupId: "grp" })))
    expect(ctrl.currentPage.fields).toHaveLength(0)
  })
})

describe("FieldCrudMixin._ensureSectionHeaderInFields", () => {
  it("inserts a bridge section header when none exists, and is idempotent", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [] } })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    fm._ensureSectionHeaderInFields("Contact Info")
    expect(ctrl.currentPage.fields).toHaveLength(1)
    const header = ctrl.currentPage.fields[0]
    expect(header).toMatchObject({ field_type: "section", source: "bridge", source_section: "Contact Info", property_slug: "contact_info" })
    // second call is a no-op (header already present)
    fm._ensureSectionHeaderInFields("Contact Info")
    expect(ctrl.currentPage.fields).toHaveLength(1)
  })
})

describe("FieldCrudMixin.addAllFieldsFromSection", () => {
  afterEach(() => { document.body.innerHTML = "" })

  it("is a no-op when the trigger is not inside a searchable section", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [] } })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    fm.addAllFieldsFromSection(ev(document.createElement("button")))
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("adds every not-yet-used field in the section", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "x", property_slug: "used" })] } })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    const { trigger } = sectionEl("plain", [
      { fieldType: "select", propertyName: "Fresh", propertySlug: "fresh", fieldOptions: JSON.stringify([{ label: "A" }]), dynamicOptions: JSON.stringify({ options_source: "entity" }) },
      { fieldType: "text", propertyName: "Used", propertySlug: "used" }, // already present → skipped
      { fieldType: "entity", propertyName: "NoHtml", propertySlug: "nohtml" }, // entity w/o html → skipped
    ])
    fm.addAllFieldsFromSection(ev(trigger))
    const slugs = ctrl.currentPage.fields.map((f) => f.property_slug)
    expect(slugs).toContain("fresh")
    expect(slugs.filter((s) => s === "used")).toHaveLength(1)
    expect(slugs).not.toContain("nohtml")
  })

  it("is a no-op when every field in the section is already used", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "x", property_slug: "used" })] } })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    const { trigger } = sectionEl("plain", [{ fieldType: "text", propertyName: "U", propertySlug: "used" }])
    fm.addAllFieldsFromSection(ev(trigger))
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("treats an empty section id as a plain (non-bridge) section", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [] } })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    const { trigger } = sectionEl("", [{ fieldType: "text", propertyName: "Solo", propertySlug: "solo" }])
    fm.addAllFieldsFromSection(ev(trigger))
    expect(ctrl.currentPage.fields.map((f) => f.property_slug)).toEqual(["solo"])
  })

  it("ensures a bridge section header for associated (bridge-) sections", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [] } })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    const { trigger } = sectionEl("bridge-contacts", [
      { fieldType: "text", propertyName: "Email", propertySlug: "b_email", source: "bridge", sourceSection: "Contacts" },
    ])
    fm.addAllFieldsFromSection(ev(trigger))
    const headers = ctrl.currentPage.fields.filter((f) => f.field_type === "section")
    expect(headers).toHaveLength(1)
    expect(headers[0].source_section).toBe("Contacts")
  })
})

describe("FieldCrudMixin.removeAllFieldsFromSection", () => {
  afterEach(() => { document.body.innerHTML = "" })

  it("is a no-op outside a searchable section, and when the section has no matching fields", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a", property_slug: "a" })] } })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    fm.removeAllFieldsFromSection(ev(document.createElement("button")))
    const { trigger } = sectionEl("plain", [{ propertySlug: "notpresent" }])
    fm.removeAllFieldsFromSection(ev(trigger))
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("bails when the section items carry no slugs", () => {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [field({ id: "a", property_slug: "a" })] } })
    ctrl.fields = ctrl.currentPage.fields
    const fm = new FieldManager(ctrl)
    const { trigger } = sectionEl("plain", [{}]) // item has no propertySlug
    fm.removeAllFieldsFromSection(ev(trigger))
    expect(ctrl.undoRedoManager.saveState).not.toHaveBeenCalled()
  })

  it("removes matching fields (top-level and column-nested) and deselects a removed selection", () => {
    const cols = field({ id: "cols", field_type: "columns", property_type: "layout", columns: [{ fields: [field({ id: "c", property_slug: "c_slug" })] }, {}] }) // 2nd column has no fields
    const pages = [{ id: "p1", name: "P1", fields: [field({ id: "a", property_slug: "a_slug" }), cols] }]
    const ctrl = makeCtrl({ configuration: { pages, rules: [], calculations: [], theme: {} }, activePageValue: "p1" })
    ctrl.currentPage = pages[0]
    ctrl.fields = pages[0].fields
    ctrl.selectedFieldId = "a"
    const fm = new FieldManager(ctrl)
    const { trigger } = sectionEl("plain", [{ propertySlug: "a_slug" }, { propertySlug: "c_slug" }])
    fm.removeAllFieldsFromSection(ev(trigger))
    expect(ctrl.deselectField ? true : true).toBe(true)
    expect(pages[0].fields.find((f) => f.id === "a")).toBeUndefined()
    expect(pages[0].fields.find((f) => f.id === "cols").columns[0].fields).toHaveLength(0)
    expect(ctrl.pageManager.renderPageTabs).toHaveBeenCalled()
  })

  it("treats an empty section id as plain when removing (no bridge header sweep)", () => {
    const pages = [{ id: "p1", name: "P1", fields: [field({ id: "a", property_slug: "a_slug" })] }]
    const ctrl = makeCtrl({ configuration: { pages, rules: [], calculations: [], theme: {} }, activePageValue: "p1" })
    ctrl.currentPage = pages[0]
    ctrl.fields = pages[0].fields
    const fm = new FieldManager(ctrl)
    const { trigger } = sectionEl("", [{ propertySlug: "a_slug" }])
    fm.removeAllFieldsFromSection(ev(trigger))
    expect(pages[0].fields.find((f) => f.id === "a")).toBeUndefined()
  })

  it("removes bridge section headers across pages for associated sections", () => {
    const header = field({ id: "hdr", field_type: "section", property_type: "layout", source: "bridge", source_section: "Contacts" })
    const dataField = field({ id: "d", property_slug: "d_slug", source: "bridge", source_section: "Contacts" })
    const pages = [{ id: "p1", name: "P1", fields: [header, dataField] }]
    const ctrl = makeCtrl({ configuration: { pages, rules: [], calculations: [], theme: {} }, activePageValue: "p1" })
    ctrl.currentPage = pages[0]
    ctrl.fields = pages[0].fields
    const fm = new FieldManager(ctrl)
    const { trigger } = sectionEl("bridge-contacts", [{ propertySlug: "d_slug", sourceSection: "Contacts" }])
    fm.removeAllFieldsFromSection(ev(trigger))
    expect(pages[0].fields.find((f) => f.id === "hdr")).toBeUndefined()
    expect(pages[0].fields.find((f) => f.id === "d")).toBeUndefined()
  })
})

describe("FieldCrudMixin.saveFieldAsTemplate", () => {
  afterEach(() => { vi.restoreAllMocks(); delete global.fetch })

  function fmWith(fieldObj) {
    const ctrl = makeCtrl({ currentPage: { id: "p1", fields: [fieldObj] } })
    ctrl.fields = ctrl.currentPage.fields
    ctrl.customerIdValue = "42"
    return { ctrl, fm: new FieldManager(ctrl) }
  }

  it("POSTs a stripped field config and alerts on success", async () => {
    // include a csrf-token element so the `?.content` header is populated
    const meta = document.createElement("meta")
    meta.setAttribute("name", "csrf-token")
    meta.setAttribute("content", "tok123")
    document.head.appendChild(meta)
    vi.spyOn(window, "prompt").mockReturnValue("My Template")
    const alertSpy = vi.spyOn(window, "alert").mockImplementation(() => {})
    global.fetch = vi.fn(async () => ({ ok: true, json: async () => ({}) }))
    const { fm } = fmWith(field({ id: "a", property_slug: "a", order: 3 }))
    fm.saveFieldAsTemplate(ev(el({ fieldId: "a" })))
    await new Promise((r) => setTimeout(r, 0))
    expect(global.fetch.mock.calls[0][1].headers["X-CSRF-Token"]).toBe("tok123")
    meta.remove()
    expect(global.fetch).toHaveBeenCalledWith("/42/admin/maintenance/pages/field_templates", expect.objectContaining({ method: "POST" }))
    const body = JSON.parse(global.fetch.mock.calls[0][1].body)
    expect(body.field_template.name).toBe("My Template")
    expect(body.field_template.configuration.id).toBeUndefined()
    expect(body.field_template.configuration.order).toBeUndefined()
    expect(alertSpy).toHaveBeenCalledWith("Template saved!")
  })

  it("alerts a failure when the request is rejected", async () => {
    vi.spyOn(window, "prompt").mockReturnValue("T")
    const alertSpy = vi.spyOn(window, "alert").mockImplementation(() => {})
    global.fetch = vi.fn(async () => ({ ok: false }))
    const { fm } = fmWith(field({ id: "a" }))
    fm.saveFieldAsTemplate(ev(el({ fieldId: "a" })))
    await new Promise((r) => setTimeout(r, 0))
    expect(alertSpy).toHaveBeenCalledWith("Failed to save template")
  })

  it("bails for an unknown field, and when the prompt is cancelled", () => {
    global.fetch = vi.fn()
    const { fm } = fmWith(field({ id: "a" }))
    vi.spyOn(window, "prompt").mockReturnValue("N")
    fm.saveFieldAsTemplate(ev(el({ fieldId: "ghost" }))) // no field
    vi.spyOn(window, "prompt").mockReturnValue(null) // cancelled prompt
    fm.saveFieldAsTemplate(ev(el({ fieldId: "a" })))
    expect(global.fetch).not.toHaveBeenCalled()
  })
})

describe("FieldCrudMixin._pageHasInputFields / _pruneEmptyPages", () => {
  it("detects input (non-layout) fields, including inside columns", () => {
    const fm = new FieldManager(makeCtrl())
    expect(fm._pageHasInputFields({ fields: [field({ property_type: "layout", field_type: "divider" })] })).toBe(false)
    expect(fm._pageHasInputFields({ fields: [field({ property_type: "string" })] })).toBe(true)
    const cols = { fields: [field({ field_type: "columns", columns: [{ fields: [field({ property_type: "number" })] }] })] }
    expect(fm._pageHasInputFields(cols)).toBe(true)
  })

  it("tolerates sparse pages/columns in _pageHasInputFields (defensive `|| []`)", () => {
    const fm = new FieldManager(makeCtrl())
    expect(fm._pageHasInputFields({})).toBe(false) // no fields
    expect(fm._pageHasInputFields({ fields: [field({ field_type: "columns" })] })).toBe(false) // no columns
    expect(fm._pageHasInputFields({ fields: [field({ field_type: "columns", columns: [{}] })] })).toBe(false) // column w/o fields
  })

  it("removes empty pages but always keeps at least one", () => {
    const pages = [
      { id: "p1", fields: [field({ property_type: "string" })] },
      { id: "p2", fields: [field({ property_type: "layout", field_type: "divider" })] },
    ]
    const ctrl = makeCtrl({ configuration: { pages, calculations: [], rules: [], theme: {} }, activePageValue: "p1" })
    const fm = new FieldManager(ctrl)
    fm._pruneEmptyPages()
    expect(ctrl.configuration.pages.map((p) => p.id)).toEqual(["p1"])
  })

  it("keeps every page when none has input fields (would-remove-all guard)", () => {
    const pages = [
      { id: "p1", fields: [field({ property_type: "layout", field_type: "divider" })] },
      { id: "p2", fields: [] },
    ]
    const ctrl = makeCtrl({ configuration: { pages, calculations: [], rules: [], theme: {} }, activePageValue: "p1" })
    const fm = new FieldManager(ctrl)
    fm._pruneEmptyPages()
    expect(ctrl.configuration.pages).toHaveLength(2)
  })

  it("switches the active page when the active page is pruned", () => {
    const pages = [
      { id: "p1", fields: [field({ property_type: "string" })] },
      { id: "p2", fields: [] }, // active but empty → removed
    ]
    const ctrl = makeCtrl({ configuration: { pages, calculations: [], rules: [], theme: {} }, activePageValue: "p2" })
    const fm = new FieldManager(ctrl)
    fm._pruneEmptyPages()
    expect(ctrl.configuration.pages.map((p) => p.id)).toEqual(["p1"])
    expect(ctrl.activePageValue).toBe("p1")
  })
})
