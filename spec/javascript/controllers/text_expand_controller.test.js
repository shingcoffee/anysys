import { describe, it, expect, beforeEach, vi } from "vitest"
import Controller from "controllers/text_expand_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const LONG_BODY = "A".repeat(40)
const LONG_TITLE = "T".repeat(24)

function itemHtml({ body = LONG_BODY, title = LONG_TITLE, bodyLimit = 20, titleLimit = 12 } = {}) {
  return `
  <div data-controller="text-expand"
       data-action="click->text-expand#toggle keydown.enter->text-expand#toggle keydown.space->text-expand#toggle"
       data-role="item">
    <p data-text-expand-target="clamped" data-limit="${titleLimit}" data-role="title">${title}</p>
    <p data-text-expand-target="clamped" data-limit="${bodyLimit}" data-role="body">${body}</p>
    <a href="/learn" data-role="link">Learn more</a>
    <form data-text-expand-target="markRead" data-role="mark-read"></form>
  </div>`
}

function clickCancelable(el) {
  const event = new Event("click", { bubbles: true, cancelable: true })
  el.dispatchEvent(event)
  return event
}

function key(el, keyName) {
  const event = new KeyboardEvent("keydown", { key: keyName, bubbles: true, cancelable: true })
  el.dispatchEvent(event)
  return event
}

describe("text-expand controller", () => {
  let element
  let application
  let controller
  let body
  let title

  async function mount(html = itemHtml()) {
    ;({ element, application } = await mountController("text-expand", Controller, html))
    controller = controllerFor(application, element, "text-expand")
    body = element.querySelector("[data-role='body']")
    title = element.querySelector("[data-role='title']")
  }

  beforeEach(async () => {
    await mount()
  })

  it("leaves a short notice as static copy", async () => {
    await mount(itemHtml({ title: "Short title", body: "Short body" }))
    expect(element.classList.contains("cursor-pointer")).toBe(false)
    expect(element.hasAttribute("aria-expanded")).toBe(false)
    expect(title.textContent).toBe("Short title")
    expect(body.textContent).toBe("Short body")
    const event = clickCancelable(body)
    expect(event.defaultPrevented).toBe(false)
  })

  it("truncates title and body that exceed their length limits", () => {
    expect(title.textContent).toBe(`${"T".repeat(11)}…`)
    expect(body.textContent).toBe(`${"A".repeat(19)}…`)
    expect(element.classList.contains("cursor-pointer")).toBe(true)
    expect(element.getAttribute("aria-expanded")).toBe("false")
    expect(element.getAttribute("tabindex")).toBe("0")
  })

  it("expands to the full text when the notice item is clicked", () => {
    const event = clickCancelable(body)
    expect(event.defaultPrevented).toBe(true)
    expect(title.textContent).toBe(LONG_TITLE)
    expect(body.textContent).toBe(LONG_BODY)
    expect(element.getAttribute("aria-expanded")).toBe("true")
  })

  it("folds the full text on a second item click", () => {
    clickCancelable(body)
    const event = clickCancelable(body)
    expect(event.defaultPrevented).toBe(true)
    expect(title.textContent).toBe(`${"T".repeat(11)}…`)
    expect(body.textContent).toBe(`${"A".repeat(19)}…`)
    expect(element.getAttribute("aria-expanded")).toBe("false")
  })

  it("expands from the keyboard", () => {
    const event = key(element, "Enter")
    expect(event.defaultPrevented).toBe(true)
    expect(body.textContent).toBe(LONG_BODY)
  })

  it("prevents page scroll when Space expands the notice", () => {
    const event = key(element, " ")
    expect(event.defaultPrevented).toBe(true)
    expect(body.textContent).toBe(LONG_BODY)
  })

  it("ignores clicks on links and buttons inside the notice", () => {
    const event = clickCancelable(element.querySelector("[data-role='link']"))
    expect(event.defaultPrevented).toBe(false)
    expect(body.textContent).toContain("…")
  })

  it("submits the mark-read form once when the notice is opened", () => {
    const form = element.querySelector("[data-role='mark-read']")
    const submit = vi.fn()
    form.requestSubmit = submit
    clickCancelable(body)
    clickCancelable(body)
    expect(submit).toHaveBeenCalledTimes(1)
  })

  it("uses the controller default limit when a target omits data-limit", async () => {
    const html = `
      <div data-controller="text-expand" data-text-expand-limit-value="10"
           data-action="click->text-expand#toggle">
        <p data-text-expand-target="clamped" data-role="body">${"B".repeat(16)}</p>
      </div>`
    await mount(html)
    expect(body.textContent).toBe(`${"B".repeat(9)}…`)
  })

  it("falls back to the default limit when data-limit is not a positive number", async () => {
    const html = `
      <div data-controller="text-expand" data-text-expand-limit-value="8"
           data-action="click->text-expand#toggle">
        <p data-text-expand-target="clamped" data-limit="0" data-role="body">${"C".repeat(16)}</p>
      </div>`
    await mount(html)
    expect(body.textContent).toBe(`${"C".repeat(7)}…`)
  })

  it("does not submit mark-read when the form is absent", async () => {
    const html = `
      <div data-controller="text-expand" data-action="click->text-expand#toggle">
        <p data-text-expand-target="clamped" data-limit="8" data-role="body">${"D".repeat(16)}</p>
      </div>`
    await mount(html)
    expect(() => clickCancelable(body)).not.toThrow()
    expect(body.textContent).toBe("D".repeat(16))
  })

  it("keeps at least one character plus an ellipsis when the limit is 1", async () => {
    const html = `
      <div data-controller="text-expand" data-action="click->text-expand#toggle">
        <p data-text-expand-target="clamped" data-limit="1" data-role="body">Hello</p>
      </div>`
    await mount(html)
    expect(body.textContent).toBe("H…")
  })
})
