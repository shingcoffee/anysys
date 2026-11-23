import { describe, it, expect, beforeEach } from "vitest"
import Controller from "controllers/list_module_controller"
import { mountController, controllerFor, click } from "../support/stimulus.js"

const html = `
  <table data-controller="list-module" data-list-module-module-id-value="mod9" data-list-module-page-value="2">
    <tbody>
      <tr data-record-id="r1" data-action="click->list-module#selectRow" data-role="row1">
        <td><button data-row-action="edit" data-record-id="r1" data-action="click->list-module#rowAction" data-role="act1">edit</button></td>
      </tr>
      <tr data-record-id="r2" data-action="click->list-module#selectRow" data-role="row2"><td>b</td></tr>
      <tr data-record-id="r3" data-action="click->list-module#selectRow" data-role="row3">
        <td><a href="/actions/enroll" data-role="link1">Open</a></td>
      </tr>
    </tbody>
  </table>`

const q = (el, role) => el.querySelector(`[data-role='${role}']`)

describe("list-module controller", () => {
  let element, controller
  beforeEach(async () => {
    const m = await mountController("list-module", Controller, html)
    element = m.element
    controller = controllerFor(m.application, element, "list-module")
  })

  it("selectRow highlights the clicked row and dispatches row-selected", () => {
    const events = []
    element.addEventListener("list-module:row-selected", (e) => events.push(e.detail))
    click(q(element, "row1"))
    expect(q(element, "row1").classList.contains("bg-indigo-50")).toBe(true)
    click(q(element, "row2"))
    expect(q(element, "row1").classList.contains("bg-indigo-50")).toBe(false)
    expect(q(element, "row2").classList.contains("bg-indigo-50")).toBe(true)
    expect(events).toEqual([
      { recordId: "r1", moduleId: "mod9" },
      { recordId: "r2", moduleId: "mod9" },
    ])
  })

  it("selectRow ignores clicks on an inner link so the browser can follow href", () => {
    const events = []
    element.addEventListener("list-module:row-selected", (e) => events.push(e.detail))
    click(q(element, "link1"))
    expect(q(element, "row3").classList.contains("bg-indigo-50")).toBe(false)
    expect(events).toEqual([])
  })

  it("rowAction dispatches row-action with action + recordId", () => {
    const events = []
    element.addEventListener("list-module:row-action", (e) => events.push(e.detail))
    click(q(element, "act1"))
    expect(events).toEqual([{ action: "edit", recordId: "r1", moduleId: "mod9" }])
  })

  it("nextPage/prevPage adjust page value (clamped at 1) and dispatch page-changed", () => {
    const events = []
    element.addEventListener("list-module:page-changed", (e) => events.push(e.detail))
    controller.nextPage()
    expect(controller.pageValue).toBe(3)
    controller.prevPage()
    controller.prevPage()
    controller.prevPage() // would go below 1
    expect(controller.pageValue).toBe(1)
    expect(events.map(e => e.page)).toEqual([3, 2, 1, 1])
    expect(events[0].moduleId).toBe("mod9")
  })
})
