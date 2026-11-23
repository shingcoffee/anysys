import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/email_template_token_bulk_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = `<form data-controller="email-template-token-bulk" data-email-template-token-bulk-count-label-value="已选：{count}">
  <select data-email-template-token-bulk-target="entity" data-action="change->email-template-token-bulk#refresh">
    <option value=""></option><option value="1">Contact</option><option value="2">Order</option>
  </select>
  <p data-email-template-token-bulk-target="prompt">Choose a record</p>
  <div data-email-template-token-bulk-target="group" data-entity-id="1" hidden>
    <span data-email-template-token-bulk-target="count"></span>
    <div class="flex flex-col"><input type="hidden" name="fields[0][selected]" value="0"><input type="checkbox" checked data-email-template-token-bulk-target="checkbox" data-action="change->email-template-token-bulk#updateCount"><input type="text" value="Name"></div>
    <div class="flex flex-col"><input type="checkbox" checked data-email-template-token-bulk-target="checkbox" data-action="change->email-template-token-bulk#updateCount"><input type="text" value="Status"></div>
  </div>
  <div data-email-template-token-bulk-target="group" data-entity-id="2" hidden>
    <span data-email-template-token-bulk-target="count"></span>
    <div class="flex flex-col"><input type="checkbox" checked data-email-template-token-bulk-target="checkbox"><input type="text" value="Amount"></div>
  </div>
  <input type="submit" data-email-template-token-bulk-target="submit">
</form>`

describe("email-template-token-bulk controller", () => {
  let element, ctrl, groups, entity

  beforeEach(async () => {
    const mounted = await mountController("email-template-token-bulk", Controller, html)
    element = mounted.element
    ctrl = controllerFor(mounted.application, element, "email-template-token-bulk")
    groups = [...element.querySelectorAll('[data-email-template-token-bulk-target="group"]')]
    entity = element.querySelector("select")
  })

  it("starts with a prompt and no enabled field inputs", () => {
    expect(element.querySelector('[data-email-template-token-bulk-target="prompt"]').hidden).toBe(false)
    expect(groups.every((group) => group.hidden && [...group.querySelectorAll("input")].every((input) => input.disabled))).toBe(true)
    expect(element.querySelector('input[type="submit"]').disabled).toBe(true)
  })

  it("shows all fields selected with translated count and required names for the selected record type", () => {
    entity.value = "1"
    ctrl.refresh()
    expect(groups[0].hidden).toBe(false)
    expect(groups[1].hidden).toBe(true)
    expect(element.querySelector('[data-email-template-token-bulk-target="prompt"]').hidden).toBe(true)
    expect(groups[0].querySelector("span").textContent).toBe("已选：2")
    expect(element.querySelector('input[type="submit"]').disabled).toBe(false)
    expect([...groups[0].querySelectorAll('input[type="text"]')].every((input) => input.required)).toBe(true)
    expect([...groups[1].querySelectorAll("input")].every((input) => input.disabled)).toBe(true)
  })

  it("clears, selects all, and recalculates required names when checkboxes change", () => {
    entity.value = "1"
    ctrl.refresh()
    ctrl.clearAll()
    expect(groups[0].querySelector("span").textContent).toBe("已选：0")
    expect(element.querySelector('input[type="submit"]').disabled).toBe(true)
    expect([...groups[0].querySelectorAll('input[type="text"]')].every((input) => !input.required)).toBe(true)
    ctrl.selectAll()
    expect(groups[0].querySelector("span").textContent).toBe("已选：2")
    expect(element.querySelector('input[type="submit"]').disabled).toBe(false)
    const checkbox = groups[0].querySelector('input[type="checkbox"]')
    checkbox.checked = false
    ctrl.updateCount()
    expect(groups[0].querySelector("span").textContent).toBe("已选：1")
    expect(groups[0].querySelector('input[type="text"]').required).toBe(false)
  })

  it("retains selections when switching record types and disables the previous type", () => {
    entity.value = "1"
    ctrl.refresh()
    ctrl.clearAll()
    entity.value = "2"
    ctrl.refresh()
    expect(groups[1].querySelector("span").textContent).toBe("已选：1")
    expect(groups[0].querySelector('input[type="checkbox"]').disabled).toBe(true)
    entity.value = "1"
    ctrl.refresh()
    expect(groups[0].querySelector("span").textContent).toBe("已选：0")
  })

  it("uses an English template when no server translation is provided", async () => {
    const mounted = await mountController("email-template-token-bulk", Controller, html.replace(' data-email-template-token-bulk-count-label-value="已选：{count}"', ""))
    const fallback = controllerFor(mounted.application, mounted.element, "email-template-token-bulk")
    mounted.element.querySelector("select").value = "2"
    fallback.refresh()
    expect(mounted.element.querySelectorAll('[data-email-template-token-bulk-target="count"]')[1].textContent).toBe("Selected: 1")
  })
})
