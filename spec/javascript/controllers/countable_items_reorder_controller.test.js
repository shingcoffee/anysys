import { describe, it, expect, vi, beforeEach } from "vitest"

// SortableJS attaches native drag listeners we don't exercise in happy-dom;
// mock it so connect() wires cleanly and we can assert the controller drives
// its own renumbering (the drag itself is Tier C / Playwright).
vi.mock("sortablejs", () => ({
  default: { create: vi.fn(() => ({ destroy: vi.fn() })) },
}))

import Sortable from "sortablejs"
import Controller from "controllers/countable_items_reorder_controller"
import { mountController, click } from "../support/stimulus.js"

// Rows are emitted on a single line each: inter-element whitespace text nodes
// interact badly with insertAdjacentElement in happy-dom, so keep markup tight.
const row = (i) =>
  `<li data-countable-items-reorder-target="row" data-row="${i}">` +
  `<span data-countable-items-reorder-target="handle">⠿</span>` +
  `<span data-countable-items-reorder-target="positionLabel"></span>` +
  `<input type="hidden" data-countable-items-reorder-target="positionInput">` +
  `<button data-countable-items-reorder-target="upButton" data-action="click->countable-items-reorder#moveUp">↑</button>` +
  `<button data-countable-items-reorder-target="downButton" data-action="click->countable-items-reorder#moveDown">↓</button>` +
  `</li>`
const listHtml = (n) =>
  `<ol data-controller="countable-items-reorder">${Array.from({ length: n }, (_, i) => row(i)).join("")}</ol>`

const order = (el) => [...el.querySelectorAll("[data-row]")].map((r) => r.dataset.row)
const labels = (el) => [...el.querySelectorAll("[data-countable-items-reorder-target='positionLabel']")].map((s) => s.textContent)
const posInputs = (el) => [...el.querySelectorAll("[data-countable-items-reorder-target='positionInput']")].map((i) => i.value)
const downBtn = (el, i) => el.querySelector(`[data-row='${i}'] [data-countable-items-reorder-target='downButton']`)
const upBtn = (el, i) => el.querySelector(`[data-row='${i}'] [data-countable-items-reorder-target='upButton']`)

describe("countable-items-reorder controller", () => {
  let application, element
  beforeEach(async () => {
    Sortable.create.mockClear()
    ;({ application, element } = await mountController("countable-items-reorder", Controller, listHtml(3)))
  })

  it("initializes SortableJS on connect and numbers rows 1-based", () => {
    expect(Sortable.create).toHaveBeenCalledOnce()
    expect(labels(element)).toEqual(["1", "2", "3"])
    expect(posInputs(element)).toEqual(["0", "1", "2"])
  })

  it("disables Up on the first row and Down on the last", () => {
    expect(upBtn(element, 0).disabled).toBe(true)
    expect(downBtn(element, 2).disabled).toBe(true)
    expect(upBtn(element, 1).disabled).toBe(false)
  })

  it("moveDown on the first row swaps it below its neighbour and renumbers positions", () => {
    click(downBtn(element, 0))
    expect(order(element)).toEqual(["1", "0", "2"])
    expect(posInputs(element)).toEqual(["0", "1", "2"]) // position tracks slot, not data-row
    expect(labels(element)).toEqual(["1", "2", "3"])
  })

  it("moveUp on the last row swaps it above its neighbour", () => {
    click(upBtn(element, 2))
    expect(order(element)).toEqual(["0", "2", "1"])
  })

  it("moveUp on the first row is a no-op", () => {
    click(upBtn(element, 0))
    expect(order(element)).toEqual(["0", "1", "2"])
  })

  it("moveDown on the last row is a no-op", () => {
    click(downBtn(element, 2))
    expect(order(element)).toEqual(["0", "1", "2"])
  })

  it("onEnd (drag finished) triggers the same renumbering as the buttons", () => {
    const options = Sortable.create.mock.calls[0][1]
    // Simulate SortableJS having physically moved row 0 below row 1 during the drag.
    element.insertBefore(element.querySelector("[data-row='1']"), element.querySelector("[data-row='0']"))
    options.onEnd()
    expect(order(element)).toEqual(["1", "0", "2"])
    expect(posInputs(element)).toEqual(["0", "1", "2"])
    expect(labels(element)).toEqual(["1", "2", "3"])
  })

  it("destroys the sortable instance on disconnect (element removed from DOM)", async () => {
    const instance = Sortable.create.mock.results[0].value
    element.remove()
    await new Promise((r) => setTimeout(r, 0)) // let Stimulus MutationObserver fire
    expect(instance.destroy).toHaveBeenCalled()
    application.stop()
  })
})
