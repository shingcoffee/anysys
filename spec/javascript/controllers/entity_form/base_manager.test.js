import { describe, it, expect } from "vitest"
import { BaseManager, CSS, escapeHtml } from "controllers/entity_form/base_manager"
import { escapeHtml as utilsEscapeHtml } from "utils"
import { buildController } from "./support.js"

describe("BaseManager — CSS + escapeHtml exports", () => {
  it("freezes the CSS token map", () => {
    expect(CSS.hidden).toBe("hidden")
    expect(CSS.errorRing).toEqual(["ring-2", "ring-red-500", "border-red-500"])
    expect(CSS.highlightRing).toEqual(["ring-2", "ring-amber-400"])
    expect(Object.isFrozen(CSS)).toBe(true)
  })

  it("re-exports escapeHtml from utils", () => {
    expect(escapeHtml).toBe(utilsEscapeHtml)
    expect(escapeHtml('<a href="x">&\'</a>')).toBe("&lt;a href=&quot;x&quot;&gt;&amp;&#39;&lt;/a&gt;")
  })
})

describe("BaseManager — generateSlug", () => {
  const mgr = () => new BaseManager({})

  it("lowercases and joins words with the default underscore separator", () => {
    expect(mgr().generateSlug("Hello World")).toBe("hello_world")
  })

  it("honors a custom separator", () => {
    expect(mgr().generateSlug("Hello World", "-")).toBe("hello-world")
  })

  it("strips diacritics via NFD normalization", () => {
    expect(mgr().generateSlug("Café Münü")).toBe("cafe_munu")
  })

  it("drops disallowed punctuation and collapses runs of separators", () => {
    expect(mgr().generateSlug("Price ($USD)!!")).toBe("price_usd")
    expect(mgr().generateSlug("  --Trim__me--  ")).toBe("trim_me")
  })

  it("returns empty string for blank/nullish input", () => {
    expect(mgr().generateSlug("")).toBe("")
    expect(mgr().generateSlug(null)).toBe("")
    expect(mgr().generateSlug(undefined)).toBe("")
  })
})

describe("BaseManager — capitalize", () => {
  it("uppercases only the first char", () => {
    expect(new BaseManager({}).capitalize("abc")).toBe("Abc")
    expect(new BaseManager({}).capitalize("A")).toBe("A")
  })

  it("returns empty string for falsy input", () => {
    expect(new BaseManager({}).capitalize("")).toBe("")
    expect(new BaseManager({}).capitalize(null)).toBe("")
  })
})

describe("BaseManager — target helpers + value getters", () => {
  it("reads value getters straight off the controller", () => {
    const { controller } = buildController("", { values: { customerIdValue: "42", currentEntityIdValue: "7" } })
    const mgr = new BaseManager(controller)
    expect(mgr.c).toBe(controller)
    expect(mgr.customerIdValue).toBe("42")
    expect(mgr.currentEntityIdValue).toBe("7")
  })

  it("target()/hasTarget() delegate to Stimulus-style accessors", () => {
    const { controller, element } = buildController(
      `<input data-entity-form-target="modalName" value="Foo">`
    )
    const mgr = new BaseManager(controller)
    expect(mgr.hasTarget("modalName")).toBe(true)
    expect(mgr.hasTarget("missing")).toBeFalsy()
    expect(mgr.target("modalName")).toBe(element.querySelector("input"))
  })

  it("getTargetValue returns the input value or '' when the target is absent", () => {
    const { controller } = buildController(`<input data-entity-form-target="modalName" value="  keep  ">`)
    const mgr = new BaseManager(controller)
    expect(mgr.getTargetValue("modalName")).toBe("  keep  ") // no trim here
    expect(mgr.getTargetValue("nope")).toBe("")
  })

  it("getTargetValue coerces an empty input value to ''", () => {
    const { controller } = buildController(`<input data-entity-form-target="modalName" value="">`)
    expect(new BaseManager(controller).getTargetValue("modalName")).toBe("")
  })
})
