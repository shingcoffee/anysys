import { describe, it, expect, vi } from "vitest"
import { PropertyManager } from "controllers/page_builder/property_manager"
import { makeCtrl, field } from "../../../support/page_builder.js"

// BreadcrumbMixin is mixed into PropertyManager; exercise it through a real
// PropertyManager instance so `this` carries BaseManager helpers too.
function bcCtrl(fields = [], pageName = "Page 1") {
  const ctrl = makeCtrl({ currentPage: { id: "p1", name: pageName, fields } })
  return ctrl
}
const newPM = (fields, pageName) => new PropertyManager(bcCtrl(fields, pageName))

describe("BreadcrumbMixin._buildBreadcrumbTrail", () => {
  it("is [page, field] for a top-level field", () => {
    const f = field({ id: "f1", label: "Email" })
    const pm = newPM([f], "Signup")
    expect(pm._buildBreadcrumbTrail(f)).toEqual([
      { label: "Signup", id: null },
      { label: "Email", id: "f1" },
    ])
  })

  it("adds the field-group step when the field is nested in a group", () => {
    const child = field({ id: "c1", label: "Street" })
    const group = { id: "grp", type: "field_group", label: "Address", fields: [child] }
    const pm = newPM([group])
    const trail = pm._buildBreadcrumbTrail(child)
    expect(trail.map((t) => t.label)).toEqual(["Page 1", "Address", "Street"])
  })

  it("adds columns + specific column step when nested in a columns layout", () => {
    const child = field({ id: "c1", label: "First" })
    const cols = {
      id: "cols", field_type: "columns", label: "Row",
      columns: [{ fields: [] }, { fields: [child] }],
    }
    const pm = newPM([cols])
    const trail = pm._buildBreadcrumbTrail(child)
    expect(trail.map((t) => t.label)).toEqual(["Page 1", "Row", "Column 2", "First"])
    expect(trail[2].id).toBe("cols_col_1")
  })

  it("adds the enclosing section step for a field under a section marker", () => {
    const sec = { id: "s1", field_type: "section", label: "Details" }
    const f = field({ id: "f1", label: "Notes" })
    const pm = newPM([sec, f])
    const trail = pm._buildBreadcrumbTrail(f)
    expect(trail.map((t) => t.label)).toEqual(["Page 1", "Details", "Notes"])
  })

  it("falls back to field_type when the field has no label", () => {
    const f = { id: "f1", field_type: "divider" }
    const pm = newPM([f])
    const trail = pm._buildBreadcrumbTrail(f)
    expect(trail[trail.length - 1].label).toBe("divider")
  })

  it("falls back to 'Page 1' when the current page has no name", () => {
    const f = field({ id: "f1", label: "Email" })
    const pm = newPM([f], "")
    expect(pm._buildBreadcrumbTrail(f)[0]).toEqual({ label: "Page 1", id: null })
  })

  it("falls back to 'Field Group' / 'Columns' / 'Section' labels when the ancestor has none", () => {
    const groupChild = field({ id: "c1" })
    const group = { id: "grp", type: "field_group", fields: [groupChild] }
    expect(newPM([group])._buildBreadcrumbTrail(groupChild).map((t) => t.label)).toEqual(["Page 1", "Field Group", "Field"])

    const colChild = field({ id: "c2" })
    const cols = { id: "cols", field_type: "columns", columns: [{ fields: [colChild] }] }
    expect(newPM([cols])._buildBreadcrumbTrail(colChild).map((t) => t.label)).toEqual(["Page 1", "Columns", "Column 1", "Field"])

    const sec = { id: "s1", field_type: "section" }
    const f = field({ id: "f1" })
    expect(newPM([sec, f])._buildBreadcrumbTrail(f).map((t) => t.label)).toEqual(["Page 1", "Section", "Field"])
  })

  it("stops the section trail at the next section marker when the field precedes it", () => {
    const sec1 = { id: "s1", field_type: "section", label: "First" }
    const sec2 = { id: "s2", field_type: "section", label: "Second" }
    const f1 = field({ id: "f1", label: "Notes" })
    const f2 = field({ id: "f2", label: "Other" })
    const pm = newPM([sec1, f1, sec2, f2])
    // f1 is between sec1 and sec2 → picks up sec1's label (nextSection found)
    expect(pm._buildBreadcrumbTrail(f1).map((t) => t.label)).toEqual(["Page 1", "First", "Notes"])
  })
})

describe("BreadcrumbMixin._renderBreadcrumb", () => {
  function withBar(pm) {
    pm.c.hasBreadcrumbBarTarget = true
    pm.c.breadcrumbBarTarget = document.createElement("div")
    pm.c.breadcrumbBarTarget.classList.add("hidden")
    pm.c.breadcrumbContentTarget = document.createElement("div")
  }

  it("renders buttons for ancestors and a plain label for the current field", () => {
    const child = field({ id: "c1", label: "Street" })
    const group = { id: "grp", type: "field_group", label: "Address", fields: [child] }
    const pm = newPM([group])
    withBar(pm)
    pm._renderBreadcrumb(child)
    expect(pm.c.breadcrumbBarTarget.classList.contains("hidden")).toBe(false)
    const html = pm.c.breadcrumbContentTarget.innerHTML
    expect(html).toContain("data-field-id=\"grp\"")
    expect(html).toContain("Street") // last crumb, no button
    expect(html.match(/<button/g)).toHaveLength(2) // page + group crumbs
  })

  it("does nothing without a breadcrumb bar target", () => {
    const pm = newPM([field({ id: "f1" })])
    expect(() => pm._renderBreadcrumb(field({ id: "f1" }))).not.toThrow()
  })

  it("hides the bar when the trail has a single step", () => {
    const pm = newPM([field({ id: "f1" })])
    withBar(pm)
    pm.c.breadcrumbBarTarget.classList.remove("hidden")
    pm._buildBreadcrumbTrail = () => [{ label: "Only", id: null }]
    pm._renderBreadcrumb(field({ id: "f1" }))
    expect(pm.c.breadcrumbBarTarget.classList.contains("hidden")).toBe(true)
  })
})

describe("BreadcrumbMixin — navigate / highlight", () => {
  it("breadcrumbNavigate selects the target field", () => {
    const pm = newPM([field({ id: "f1" })])
    pm.c.fieldManager.selectFieldById = vi.fn()
    pm.breadcrumbNavigate({ currentTarget: { dataset: { fieldId: "grp" } } })
    expect(pm.c.fieldManager.selectFieldById).toHaveBeenCalledWith("grp")
  })

  it("breadcrumbNavigate ignores a crumb with no field id (the page crumb)", () => {
    const pm = newPM([field({ id: "f1" })])
    pm.c.fieldManager.selectFieldById = vi.fn()
    pm.breadcrumbNavigate({ currentTarget: { dataset: {} } })
    expect(pm.c.fieldManager.selectFieldById).not.toHaveBeenCalled()
  })

  it("highlight/unhighlight are no-ops when the crumb has no field id", () => {
    const pm = newPM([field({ id: "f1" })])
    const evt = { currentTarget: { dataset: {} } }
    expect(() => { pm.breadcrumbHighlight(evt); pm.breadcrumbUnhighlight(evt) }).not.toThrow()
  })

  it("highlight/unhighlight toggle ring classes on the matching card", () => {
    const pm = newPM([field({ id: "f1" })])
    const container = document.createElement("div")
    const card = document.createElement("div")
    card.dataset.fieldId = "f1"
    container.appendChild(card)
    pm.c.fieldsContainerTarget = container
    const evt = { currentTarget: { dataset: { fieldId: "f1" } } }
    pm.breadcrumbHighlight(evt)
    expect(card.classList.contains("ring-indigo-300")).toBe(true)
    pm.breadcrumbUnhighlight(evt)
    expect(card.classList.contains("ring-indigo-300")).toBe(false)
  })
})
