import { describe, it, expect } from "vitest"
import { buildListField, collectList } from "controllers/property_editor/controls/list"

describe("buildListField", () => {
  it("renders one empty row when the value is not a populated array", () => {
    const html = buildListField({ name: "tags", control: "list" }, [])
    expect(html).toContain("data-list-editor")
    expect((html.match(/data-list-row /g) || []).length).toBe(2) // visible row + template row
    expect(html).toContain("Add row")
  })

  it("renders a row per item and an attribute select when itemRole is entity_attribute", () => {
    const html = buildListField(
      { name: "cols", itemRole: "entity_attribute" },
      ["email"],
      { entityAttributes: [{ name_slug: "email", name: "Email" }, { name_slug: "age", name: "Age" }] },
    )
    expect(html).toContain("<select")
    expect(html).toContain('value="email" selected')
    expect(html).toContain("Age")
    expect(html).toContain("Select column")
  })

  it("uses a custom column placeholder on entity_attribute items", () => {
    const html = buildListField(
      { name: "cols", itemRole: "entity_attribute" },
      [""],
      {
        entityAttributes: [{ name_slug: "email", name: "Email" }],
        labels: { selectColumnPlaceholder: "选列" },
      },
    )
    expect(html).toContain("选列")
  })

  it("falls back to a text input when no entity columns are available", () => {
    const html = buildListField({ name: "cols", itemRole: "entity_attribute" }, ["x"], { entityAttributes: [] })
    expect(html).toContain('type="text"')
    expect(html).toContain('value="x"')
  })

  it("renders an empty input for a null list item", () => {
    const html = buildListField({ name: "tags" }, [null])
    expect(html).toContain('data-list-value value=""')
  })
})

describe("collectList", () => {
  it("returns trimmed non-empty item values", () => {
    document.body.innerHTML = `
      <div data-list-editor>
        <div data-list-row><input data-list-value value="  a "></div>
        <div data-list-row><input data-list-value value="  "></div>
        <div data-list-row><select data-list-value><option value="b" selected>b</option></select></div>
      </div>`
    expect(collectList(document.querySelector("[data-list-editor]"))).toEqual(["a", "b"])
  })
})
