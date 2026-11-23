import { describe, it, expect } from "vitest"
import { buildMappingField, collectMapping } from "controllers/property_editor/controls/mapping"

describe("buildMappingField", () => {
  it("renders an empty key/value row and F11 pair grid", () => {
    const html = buildMappingField({ name: "aliases", keyRole: "literal", valueRole: "input" }, [])
    expect(html).toContain("data-key-value-list")
    expect(html).toContain("sm:grid-cols-[1fr_1fr_auto]")
    expect(html).toContain("data-kv-row-template")
    expect(html).toContain("Add row")
  })

  it("uses an attribute select when keyRole is entity_attribute", () => {
    const html = buildMappingField(
      { name: "map", keyRole: "entity_attribute", valueRole: "literal" },
      [{ key: "email", value: "ctx.email" }],
      { entityAttributes: [{ name_slug: "email", name: "Email" }] },
    )
    expect(html).toContain("<select")
    expect(html).toContain('data-kv-key')
    expect(html).toContain('value="email" selected')
    expect(html).toContain('value="ctx.email"')
    expect(html).toContain("Select column")
  })

  it("uses a custom column placeholder on entity_attribute keys", () => {
    const html = buildMappingField(
      { name: "map", keyRole: "entity_attribute" },
      [{ key: "", value: "" }],
      {
        entityAttributes: [{ name_slug: "email", name: "Email" }],
        labels: { selectColumnPlaceholder: "选列" },
      },
    )
    expect(html).toContain("选列")
  })

  it("honors custom placeholders and a translated add label", () => {
    const html = buildMappingField(
      { name: "headers", keyPlaceholder: "Header", valuePlaceholder: "Val" },
      [{ key: "", value: "" }],
      { labels: { addRowLabel: "添加", kvRemoveRowTitle: "删除行" } },
    )
    expect(html).toContain('placeholder="Header"')
    expect(html).toContain('placeholder="Val"')
    expect(html).toContain("添加")
    expect(html).toContain('title="删除行"')
  })

  it("falls back to text keys when no entity columns exist", () => {
    const html = buildMappingField(
      { name: "map", keyRole: "entity_attribute" },
      [{ key: "custom" }],
      { entityAttributes: [] },
    )
    expect(html).toContain('type="text"')
    expect(html).toContain('value="custom"')
    expect(html).toContain('data-kv-value value=""')
  })

  it("stringifies a non-null mapping value", () => {
    const html = buildMappingField({ name: "map" }, [{ key: "n", value: 0 }])
    expect(html).toContain('value="0"')
  })
})

describe("collectMapping", () => {
  function listOf(html) {
    const list = document.createElement("div")
    list.innerHTML = html
    return list
  }

  it("keeps keyed rows in order, trimming and defaulting a blank value", () => {
    const list = listOf(`
      <div data-kv-row><input data-kv-key value=" order "><input data-kv-value value=" ctx[:model] "></div>
      <div data-kv-row><input data-kv-key value="total"><input data-kv-value value=""></div>
      <div data-kv-row><input data-kv-key value="  "><input data-kv-value value="dropped"></div>`)

    expect(collectMapping(list)).toEqual([
      { key: "order", value: "ctx[:model]" },
      { key: "total", value: "" }
    ])
  })

  it("skips rows missing their inputs", () => {
    const list = listOf(`<div data-kv-row></div><div data-kv-row><input data-kv-key value="only"></div>`)

    expect(collectMapping(list)).toEqual([{ key: "only", value: "" }])
  })
})
