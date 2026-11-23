import { describe, it, expect } from "vitest"
import {
  renderInputsSection,
  renderOutputsSection,
  renderReadOnlyInputRow,
  renderEditableInputRow,
  NO_PRODUCER_SENTINEL,
} from "controllers/property_editor/element_io/renderers"

// Pure HTML string builders — assert structure/markers, no DOM mounting needed.
// We parse into a fragment to make structural assertions robust.
const frag = (html) => {
  const t = document.createElement("template")
  t.innerHTML = html
  return t.content
}

describe("element_io renderers", () => {
  it("exposes the no-producer sentinel", () => {
    expect(NO_PRODUCER_SENTINEL).toBe("__none__")
  })

  describe("renderInputsSection", () => {
    it("renders an empty state when there are no input pins", () => {
      const html = renderInputsSection([], [], () => "ROW")
      expect(html).toContain("No inputs detected")
      expect(html).toContain("data-element-io-inputs")
      expect(html).not.toContain("ROW")
    })

    it("delegates each pin to the renderRow closure and shows the count", () => {
      const rows = []
      const renderRow = (p, overrideList) => {
        rows.push([p, overrideList])
        return `<div class="r">${p.pin}</div>`
      }
      const html = renderInputsSection([{ pin: "model" }, { pin: "user" }], [{ pin: "model" }], renderRow)
      expect(rows).toHaveLength(2)
      expect(rows[0][1]).toEqual([{ pin: "model" }]) // override list passed through
      const f = frag(html)
      expect(f.querySelectorAll(".r")).toHaveLength(2)
      // count chip shows 2
      expect(html).toContain(">2<")
    })

    it("honors translated label overrides for the section header and empty state", () => {
      const html = renderInputsSection([], [], () => "ROW", { inputsLabel: "输入", noInputsLabel: "未检测到输入" })
      expect(html).toContain("未检测到输入")
      expect(html).toContain(">输入<")
    })
  })

  describe("renderOutputsSection", () => {
    it("renders empty state with no outputs", () => {
      const html = renderOutputsSection([], [])
      expect(html).toContain("No outputs detected")
      expect(html).toContain("data-element-io-outputs")
    })

    it("honors translated label overrides for the section header and empty state", () => {
      const html = renderOutputsSection([], [], { outputsLabel: "输出", noOutputsLabel: "未检测到输出" })
      expect(html).toContain("未检测到输出")
      expect(html).toContain(">输出<")
    })

    it("renders a plain output row without a rename badge", () => {
      const html = renderOutputsSection([{ pin: "token" }], [])
      const f = frag(html)
      const row = f.querySelector("[data-element-io-output]")
      expect(row.getAttribute("data-pin")).toBe("token")
      expect(f.querySelector("[data-element-io-renamed]")).toBeNull()
    })

    it("renders a rename badge when the pin was renamed", () => {
      const html = renderOutputsSection([{ pin: "token" }], [{ pin: "token", renamed_to: "token_b7e1" }])
      const f = frag(html)
      expect(f.querySelector("[data-element-io-renamed]")).not.toBeNull()
      expect(html).toContain("token_b7e1")
    })

    it("honors translated label overrides for the rename badge", () => {
      const html = renderOutputsSection(
        [{ pin: "token" }],
        [{ pin: "token", renamed_to: "token_b7e1" }],
        { renamedTitle: "已自动重命名", renamedBadgeLabel: "已重命名" }
      )
      expect(html).toContain("已自动重命名")
      expect(html).toContain("已重命名")
    })

    it("escapes pin names", () => {
      const html = renderOutputsSection([{ pin: "<x>" }], [])
      expect(html).toContain("&lt;x&gt;")
      expect(html).not.toContain("<x>")
    })
  })

  describe("renderReadOnlyInputRow", () => {
    it("renders the pin and no select", () => {
      const html = renderReadOnlyInputRow({ pin: "model", source: "" })
      const f = frag(html)
      expect(f.querySelector("[data-element-io-input]").getAttribute("data-pin")).toBe("model")
      expect(f.querySelector("select")).toBeNull()
    })

    it("renders a config badge for config_expr source", () => {
      const html = renderReadOnlyInputRow({ pin: "x", source: "config_expr" })
      expect(html).toContain(">config<")
    })

    it("renders an auto badge for generator_literal source", () => {
      const html = renderReadOnlyInputRow({ pin: "x", source: "generator_literal" })
      expect(html).toContain(">auto<")
    })

    it("honors translated label overrides for source badges", () => {
      const configHtml = renderReadOnlyInputRow({ pin: "x", source: "config_expr" }, { configSourceLabel: "配置", configSourceTitle: "由配置表达式驱动" })
      expect(configHtml).toContain(">配置<")
      expect(configHtml).toContain("由配置表达式驱动")

      const autoHtml = renderReadOnlyInputRow({ pin: "x", source: "generator_literal" }, { autoSourceLabel: "自动", autoSourceTitle: "生成器提供的字面量" })
      expect(autoHtml).toContain(">自动<")
      expect(autoHtml).toContain("生成器提供的字面量")
    })
  })

  describe("renderEditableInputRow", () => {
    const externals = [{ effective: "model", label: "Fetch" }]
    const selfs = [{ effective: "model_ab12", label: "Self" }]

    it("builds a producer select with a no-producer option selected when unwired", () => {
      const html = renderEditableInputRow({ pin: "model", source: "" }, externals, selfs, null)
      const f = frag(html)
      const opts = [...f.querySelectorAll("option")]
      expect(opts[0].value).toBe(NO_PRODUCER_SENTINEL)
      expect(opts[0].hasAttribute("selected")).toBe(true)
      // external + self candidates rendered
      expect(opts.map((o) => o.value)).toContain("model")
      expect(opts.map((o) => o.value)).toContain("model_ab12")
      expect(html).toContain("(self)")
    })

    it("marks the wired candidate option as selected", () => {
      const html = renderEditableInputRow({ pin: "model", source: "" }, externals, selfs, "model")
      const f = frag(html)
      const sel = [...f.querySelectorAll("option")].find((o) => o.value === "model")
      expect(sel.hasAttribute("selected")).toBe(true)
      // no-producer option not selected when wired
      const none = [...f.querySelectorAll("option")].find((o) => o.value === NO_PRODUCER_SENTINEL)
      expect(none.hasAttribute("selected")).toBe(false)
    })

    it("marks a wired self candidate option as selected", () => {
      const html = renderEditableInputRow({ pin: "model", source: "" }, externals, selfs, "model_ab12")
      const f = frag(html)
      const sel = [...f.querySelectorAll("option")].find((o) => o.value === "model_ab12")
      expect(sel.hasAttribute("selected")).toBe(true)
      const external = [...f.querySelectorAll("option")].find((o) => o.value === "model")
      expect(external.hasAttribute("selected")).toBe(false)
    })

    it("honors translated label overrides for the no-producer option and aria-label", () => {
      const html = renderEditableInputRow({ pin: "model", source: "" }, externals, selfs, null, {
        noProducerLabel: "— 无生产者 —",
        producerAriaLabelFormat: "{pin} 的生产者"
      })
      expect(html).toContain("— 无生产者 —")
      expect(html).toContain('aria-label="model 的生产者"')
    })
  })
})
