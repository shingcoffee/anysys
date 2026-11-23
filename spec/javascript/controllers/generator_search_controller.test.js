import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/generator_search_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const index = [
  { name: "step_action", category: "flowchart_steps", description: "generates a step action class", path: "/g/step_action" },
  { name: "payment_gateway", category: "payments", description: "scaffolds a payment gateway", path: "/g/payment_gateway" },
  { name: "captcha_provider", category: "captcha", description: "scaffolds a captcha provider", path: "/g/captcha_provider" },
]

const html = `
  <div data-controller="generator-search" data-generator-search-index-value='${JSON.stringify(index)}'>
    <input data-generator-search-target="input" data-action="input->generator-search#filter">
    <div data-generator-search-target="categoryList">categories</div>
    <div data-generator-search-target="searchResults" class="hidden">
      <span data-generator-search-target="resultCount"></span>
      <div data-generator-search-target="resultList"></div>
      <div data-generator-search-target="noResults" class="hidden">none</div>
    </div>
  </div>`

const input = (el) => el.querySelector("[data-generator-search-target='input']")
const categoryList = (el) => el.querySelector("[data-generator-search-target='categoryList']")
const searchResults = (el) => el.querySelector("[data-generator-search-target='searchResults']")
const resultList = (el) => el.querySelector("[data-generator-search-target='resultList']")
const resultCount = (el) => el.querySelector("[data-generator-search-target='resultCount']")
const noResults = (el) => el.querySelector("[data-generator-search-target='noResults']")

const filter = (el, term) => {
  const i = input(el)
  i.value = term
  i.dispatchEvent(new Event("input", { bubbles: true }))
}

describe("generator-search controller", () => {
  let element
  beforeEach(async () => {
    ;({ element } = await mountController("generator-search", Controller, html))
  })

  it("empty query shows categories and hides results", () => {
    filter(element, "   ")
    expect(categoryList(element).classList.contains("hidden")).toBe(false)
    expect(searchResults(element).classList.contains("hidden")).toBe(true)
  })

  it("a query hides categories, shows results, and reports the match count", () => {
    filter(element, "payment")
    expect(categoryList(element).classList.contains("hidden")).toBe(true)
    expect(searchResults(element).classList.contains("hidden")).toBe(false)
    expect(resultCount(element).textContent).toBe("1 found")
    expect(resultList(element).innerHTML).toContain("/g/payment_gateway")
    expect(noResults(element).classList.contains("hidden")).toBe(true)
  })

  it("requires ALL tokens to match (AND semantics)", () => {
    filter(element, "scaffolds provider")
    expect(resultCount(element).textContent).toBe("1 found")
    expect(resultList(element).innerHTML).toContain("captcha_provider")
  })

  it("shows the no-results state when nothing matches", () => {
    filter(element, "nonexistent_xyz")
    expect(resultCount(element).textContent).toBe("0 found")
    expect(noResults(element).classList.contains("hidden")).toBe(false)
  })

  it("truncates descriptions longer than 60 characters with an ellipsis", async () => {
    const longDescIndex = [{
      name: "long_gen", category: "misc",
      description: "a".repeat(75),
      path: "/g/long_gen",
    }]
    const { element: el } = await mountController(
      "generator-search", Controller,
      `<div data-controller="generator-search" data-generator-search-index-value='${JSON.stringify(longDescIndex)}'>
        <input data-generator-search-target="input" data-action="input->generator-search#filter">
        <div data-generator-search-target="categoryList"></div>
        <div data-generator-search-target="searchResults" class="hidden">
          <div data-generator-search-target="resultList"></div>
        </div>
      </div>`
    )
    filter(el, "long_gen")
    const list = resultList(el)
    expect(list.textContent).toContain("a".repeat(60) + "...")
    expect(list.textContent).not.toContain("a".repeat(61))
  })

  it("highlightMatches wraps matched tokens (>=2 chars) in <mark> and escapes html", async () => {
    const { application, element: el } = await mountController("generator-search", Controller, html)
    const ctrl = controllerFor(application, el, "generator-search")
    const out = ctrl.highlightMatches("step_action", ["step"])
    expect(out).toContain("<mark")
    expect(out.toLowerCase()).toContain("step")
    // Single-char tokens are not highlighted.
    expect(ctrl.highlightMatches("abc", ["a"])).toBe("abc")
    // escapeHtml neutralizes angle brackets.
    expect(ctrl.escapeHtml("<b>x</b>")).toBe("&lt;b&gt;x&lt;/b&gt;")
  })
})
