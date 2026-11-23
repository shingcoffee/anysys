import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/row_link_controller"
import { mountController } from "../support/stimulus.js"

const html = `
  <table>
    <tbody data-controller="row-link" data-action="click->row-link#open">
      <tr data-row-link-row>
        <td><input type="checkbox" class="box"></td>
        <td class="name"><a href="#entry-1" data-row-link-primary>Alice</a></td>
        <td class="plain"><span class="text">Grade A</span></td>
        <td><button type="button" class="action">Delete</button></td>
        <td data-row-link-ignore><span class="ignored">menu</span></td>
      </tr>
      <tr data-row-link-row>
        <td class="no-link">No primary link</td>
      </tr>
    </tbody>
    <tfoot><tr><td class="outside">outside rows</td></tr></tfoot>
  </table>`

describe("row-link controller", () => {
  let element, link, clicks

  beforeEach(async () => {
    ({ element } = await mountController("row-link", Controller, html))
    link = element.querySelector("[data-row-link-primary]")
    clicks = vi.fn((event) => event.preventDefault())
    link.addEventListener("click", clicks)
  })

  afterEach(() => vi.restoreAllMocks())

  const click = (selector, init = {}) =>
    element.querySelector(selector).dispatchEvent(
      new MouseEvent("click", { bubbles: true, cancelable: true, button: 0, ...init })
    )

  it("opens the row's primary link when a plain cell is clicked", () => {
    click(".plain .text")
    expect(clicks).toHaveBeenCalledOnce()
  })

  it("leaves clicks on the link itself to the browser", () => {
    click(".name a")
    expect(clicks).toHaveBeenCalledOnce()
  })

  it.each([
    [".box"],
    [".action"],
    [".ignored"]
  ])("ignores clicks on interactive descendant %s", (selector) => {
    click(selector)
    expect(clicks).not.toHaveBeenCalled()
  })

  it.each([
    [{ metaKey: true }],
    [{ ctrlKey: true }],
    [{ shiftKey: true }],
    [{ altKey: true }],
    [{ button: 1 }]
  ])("ignores modified or non-primary clicks %o", (init) => {
    click(".plain", init)
    expect(clicks).not.toHaveBeenCalled()
  })

  it("ignores clicks that finish a text selection", () => {
    vi.spyOn(window, "getSelection").mockReturnValue({ toString: () => "Grade" })
    click(".plain")
    expect(clicks).not.toHaveBeenCalled()
  })

  it("does nothing for a row without a primary link", () => {
    expect(() => click(".no-link")).not.toThrow()
    expect(clicks).not.toHaveBeenCalled()
  })

  it("does nothing for clicks outside any row", () => {
    const outside = document.querySelector(".outside")
    const controller = { open: Controller.prototype.open }
    expect(() => controller.open({ button: 0, target: outside })).not.toThrow()
    expect(clicks).not.toHaveBeenCalled()
  })
})
