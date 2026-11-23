import { describe, it, expect } from "vitest"
import { buildReferencePickerField } from "controllers/property_editor/controls/reference_picker"

describe("buildReferencePickerField", () => {
  it("mounts the searchable combobox with a hidden stored id", () => {
    const html = buildReferencePickerField(
      { name: "templateId", source: "email_templates" },
      "tpl-1",
    )
    expect(html).toContain('data-controller="property-editor--controls--reference-picker"')
    expect(html).toContain('data-config-input="templateId"')
    expect(html).toContain('value="tpl-1"')
    expect(html).toContain("email_templates")
    expect(html).toContain('role="combobox"')
    expect(html).toContain(">tpl-1<")
  })

  it("shows the placeholder when no value is stored", () => {
    const html = buildReferencePickerField({ key: "ref", source: "" }, null, {
      labels: { referencePlaceholder: "请选择…", searchPlaceholder: "搜索…" },
    })
    expect(html).toContain("请选择…")
    expect(html).toContain("搜索…")
    expect(html).toContain("text-slate-400")
  })
})
