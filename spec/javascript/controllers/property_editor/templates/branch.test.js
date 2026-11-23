import { describe, it, expect } from "vitest"
import { buildBranchItemTemplate } from "controllers/property_editor/templates/branch"

describe("buildBranchItemTemplate", () => {
  it("renders name, Yes/No match select, and Otherwise in condition mode", () => {
    const html = buildBranchItemTemplate({
      index: 0,
      branchValue: "Yes",
      matchValue: "true",
      branchElementId: "e1",
      connectionId: "c1",
      routeBy: "condition"
    })
    expect(html).toContain("data-branch-item")
    expect(html).toContain('data-branch-element-id="e1"')
    expect(html).toContain('data-connection-id="c1"')
    expect(html).toContain('name="branches[0][name]"')
    expect(html).toContain("value=\"Yes\"")
    expect(html).toContain("<select data-branch-match-value")
    expect(html).toContain('value="true" selected')
    expect(html).toContain("Yes")
    expect(html).toContain("No")
    expect(html).toContain("Otherwise")
    expect(html).toContain("click->property-editor#removeBranch")
  })

  it("renders a text match input in value mode", () => {
    const html = buildBranchItemTemplate({
      index: 1,
      branchValue: "Active",
      matchValue: "active",
      routeBy: "value"
    })
    expect(html).toContain('type="text" data-branch-match-value')
    expect(html).toContain('value="active"')
    expect(html).not.toContain("<select data-branch-match-value")
  })

  it("hides and disables the match control when Otherwise is selected", () => {
    const html = buildBranchItemTemplate({
      index: 2,
      branchValue: "Other",
      matchValue: "",
      routeBy: "value"
    })
    expect(html).toContain("checked")
    expect(html).toContain("disabled")
    expect(html).toContain("hidden")
  })

  it("omits element and connection hidden inputs when ids are blank", () => {
    const html = buildBranchItemTemplate({ index: 0, branchValue: "A", matchValue: "true" })
    expect(html).not.toContain("[elementId]")
    expect(html).not.toContain("data-branch-element-id")
    expect(html).not.toContain("[connectionId]")
  })

  it("escapes labels and uses translated overrides", () => {
    const html = buildBranchItemTemplate({
      index: 0,
      branchValue: "<x>",
      matchValue: "true",
      labels: {
        branchNameLabel: "Name",
        yesMatchLabel: "是",
        noMatchLabel: "否",
        otherwiseLabel: "其他",
        removeBranchItemTitle: "删除"
      }
    })
    expect(html).toContain("&lt;x&gt;")
    expect(html).toContain("是")
    expect(html).toContain("否")
    expect(html).toContain("其他")
    expect(html).toContain('title="删除"')
  })

  it("marks the No option selected in condition mode", () => {
    const html = buildBranchItemTemplate({
      index: 0,
      matchValue: "false",
      routeBy: "condition"
    })
    expect(html).toContain('value="false" selected')
  })
})
