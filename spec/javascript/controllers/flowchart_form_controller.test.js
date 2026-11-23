import { describe, it, expect } from "vitest"
import Controller from "controllers/flowchart_form_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const card = (tpl, { checkmark = true } = {}) => `
  <div class="template-card border-gray-300" data-flowchart-form-target="templateCard"
       data-template="${tpl}" data-action="click->flowchart-form#selectTemplate">
    ${checkmark ? '<span class="template-checkmark hidden"></span>' : ""}
  </div>`

const html = ({ template = "blank" } = {}) => `
  <div data-controller="flowchart-form">
    ${card("blank")}${card("page_record")}
    <input type="hidden" data-flowchart-form-target="templateInput" value="${template}">
  </div>`

const cardEl = (el, tpl) => el.querySelector(`[data-template='${tpl}']`)
const templateInput = (el) => el.querySelector("[data-flowchart-form-target='templateInput']")
const checkmark = (el, tpl) => cardEl(el, tpl).querySelector(".template-checkmark")

describe("flowchart-form controller", () => {
  it("on connect selects the default (blank) template card", async () => {
    const { element } = await mountController("flowchart-form", Controller, html())
    expect(cardEl(element, "blank").classList.contains("border-indigo-600")).toBe(true)
    expect(checkmark(element, "blank").classList.contains("hidden")).toBe(false)
    expect(templateInput(element).value).toBe("blank")
  })

  it("on connect selects the template already in the hidden field", async () => {
    const { element } = await mountController("flowchart-form", Controller, html({ template: "page_record" }))
    expect(cardEl(element, "page_record").classList.contains("border-indigo-600")).toBe(true)
    expect(cardEl(element, "blank").classList.contains("border-indigo-600")).toBe(false)
  })

  it("defaults to the blank template when templateInput starts out empty", async () => {
    const { element } = await mountController("flowchart-form", Controller, html({ template: "" }))
    expect(cardEl(element, "blank").classList.contains("border-indigo-600")).toBe(true)
    expect(templateInput(element).value).toBe("blank")
  })

  it("selecting a card moves the selection and writes its template key", async () => {
    const { element } = await mountController("flowchart-form", Controller, html())
    cardEl(element, "page_record").dispatchEvent(new Event("click", { bubbles: true }))

    expect(templateInput(element).value).toBe("page_record")
    expect(cardEl(element, "page_record").classList.contains("border-indigo-600")).toBe(true)
    expect(checkmark(element, "page_record").classList.contains("hidden")).toBe(false)
    expect(cardEl(element, "blank").classList.contains("border-indigo-600")).toBe(false)
    expect(cardEl(element, "blank").classList.contains("border-gray-300")).toBe(true)
    expect(checkmark(element, "blank").classList.contains("hidden")).toBe(true)
  })

  it("ignores an unknown template key", async () => {
    const { element } = await mountController("flowchart-form", Controller, html({ template: "unknown" }))
    expect(element.querySelectorAll(".border-indigo-600")).toHaveLength(0)
    expect(templateInput(element).value).toBe("unknown")
  })

  it("tolerates cards without a checkmark", async () => {
    const { element } = await mountController("flowchart-form", Controller, `
      <div data-controller="flowchart-form">
        ${card("blank", { checkmark: false })}${card("page_record", { checkmark: false })}
        <input type="hidden" data-flowchart-form-target="templateInput" value="blank">
      </div>`)
    cardEl(element, "page_record").dispatchEvent(new Event("click", { bubbles: true }))

    expect(cardEl(element, "page_record").classList.contains("border-indigo-600")).toBe(true)
    expect(templateInput(element).value).toBe("page_record")
  })

  it("selects cards without a hidden template field", async () => {
    const { application, element } = await mountController("flowchart-form", Controller, `
      <div data-controller="flowchart-form">${card("blank")}${card("page_record")}</div>`)
    const ctrl = controllerFor(application, element, "flowchart-form")

    expect(element.querySelectorAll(".border-indigo-600")).toHaveLength(0)
    ctrl.selectTemplateByValue("page_record")
    expect(cardEl(element, "page_record").classList.contains("border-indigo-600")).toBe(true)
  })
})
