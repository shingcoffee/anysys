import { describe, it, expect } from "vitest"
import { buildStepItemTemplate } from "controllers/property_editor/templates/step"

const base = { index: 0, action: "send_email", suboption: "" }

describe("buildStepItemTemplate", () => {
  it("uses the actionOptionData color as accent, else blue", () => {
    const colored = buildStepItemTemplate({ ...base, actionOptionData: { color: "emerald" } })
    expect(colored).toContain("border-emerald-400")
    const plain = buildStepItemTemplate({ ...base })
    expect(plain).toContain("border-blue-400")
  })

  it("builds the breadcrumb title from selectionLabels joined by ›", () => {
    const html = buildStepItemTemplate({ ...base, selectionLabels: ["New", "Model"] })
    expect(html).toContain("New › Model")
  })

  it("falls back to actionOptionData label then action for the title", () => {
    expect(buildStepItemTemplate({ ...base, actionOptionData: { label: "Send" } })).toContain(">Send<")
    expect(buildStepItemTemplate({ ...base })).toContain(">send_email<")
  })

  it("does not emit step-level guard, retry, or timeout inputs", () => {
    const html = buildStepItemTemplate({ ...base })
    expect(html).not.toContain("retryCount")
    expect(html).not.toContain("retryBackoff")
    expect(html).not.toContain("[timeout]")
    expect(html).not.toContain("guardCondition")
    expect(html).not.toContain("data-override-badge")
  })

  it("renders expanded (details visible, chevron rotated) when expanded=true", () => {
    const expanded = buildStepItemTemplate({ ...base, expanded: true })
    expect(expanded).toContain("step-expanded")
    expect(expanded).toContain("rotate-90")
    expect(expanded).toContain('data-step-details class=" pl-6')

    const collapsed = buildStepItemTemplate({ ...base, expanded: false })
    expect(collapsed).toContain('data-step-details class="hidden pl-6')
  })

  it("emits the hidden step inputs with escaped JSON payloads", () => {
    const html = buildStepItemTemplate({
      ...base,
      id: "s1",
      keywordParams: ["to", "subject"],
      currentConfig: { to: "a@b.com" },
      selectionLabels: ["X"],
    })
    expect(html).toContain('name="steps[0][action]" value="send_email"')
    expect(html).toContain("data-step-config")
    expect(html).toContain("data-step-description")
    // JSON is html-escaped (quotes → &quot;)
    expect(html).toContain("&quot;to&quot;")
    expect(html).toContain('data-step-item draggable="true" data-step-index="0" data-step-id="s1"')
  })

  it("renders the keyword-params hint only when params present", () => {
    expect(buildStepItemTemplate({ ...base, keywordParams: ["x"], expanded: true })).toContain(
      "Params: x"
    )
    expect(buildStepItemTemplate({ ...base, keywordParams: [], expanded: true })).not.toContain(
      "Params:"
    )
  })

  it("renders the description line when present and defaults a falsy currentConfig to {}", () => {
    // `currentConfig = {}` is a destructuring default that only fires for
    // `undefined` — pass `null` so the function body's own `|| {}` (not the
    // destructuring default) is what's exercised.
    const html = buildStepItemTemplate({ ...base, description: "Sends a welcome email", currentConfig: null })
    expect(html).toContain("Sends a welcome email")
    expect(html).toContain('name="steps[0][config]" value="{}"')
  })

  it("wires drag + toggle + remove + change actions", () => {
    const html = buildStepItemTemplate({ ...base })
    expect(html).toContain("dragstart->property-editor#handleStepDragStart")
    expect(html).toContain("click->property-editor#toggleStep")
    expect(html).toContain("click->property-editor#removeStep")
    expect(html).toContain("click->property-editor#changeStep")
  })

  it("keeps Change/Remove always visible with 40px touch targets and an error badge slot", () => {
    const html = buildStepItemTemplate({ ...base })
    expect(html).not.toContain("opacity-0")
    expect(html).not.toContain("group-hover:opacity-100")
    expect(html).toContain("min-h-10")
    expect(html).toContain("min-w-10")
    expect(html).toContain("data-step-error-badge")
    expect(html).toContain(">Change<")
    expect(html).toContain(">Remove<")
  })

  it("honors a full translated labels override", () => {
    const html = buildStepItemTemplate({
      ...base,
      keywordParams: ["x"],
      expanded: true,
      labels: {
        dragToReorderTitle: "拖动排序",
        changeButtonLabel: "更改",
        changeActionTitle: "更改操作",
        removeButtonLabel: "删除",
        removeButtonTitle: "移除步骤",
        errorBadgeLabel: "错误",
        paramsPrefixLabel: "参数：",
      },
    })
    expect(html).toContain('title="拖动排序"')
    expect(html).toContain('title="更改操作">更改<')
    expect(html).toContain('title="移除步骤"')
    expect(html).toContain(">删除<")
    expect(html).toContain(">错误<")
    expect(html).toContain("参数： x")
  })
})
