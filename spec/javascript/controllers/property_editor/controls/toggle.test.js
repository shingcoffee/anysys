import { describe, it, expect } from "vitest"
import { buildToggleField } from "controllers/property_editor/controls/toggle"

describe("buildToggleField", () => {
  it("renders an unchecked switch for a falsey value", () => {
    const html = buildToggleField({ name: "skipNil" }, false)
    expect(html).toContain('data-config-input="skipNil"')
    expect(html).toContain('type="checkbox"')
    expect(html).not.toContain('checked="checked"')
  })

  it("checks the switch for true or the string true", () => {
    expect(buildToggleField({ key: "flag" }, true)).toContain('checked="checked"')
    expect(buildToggleField({ key: "flag" }, "true")).toContain('checked="checked"')
  })
})
