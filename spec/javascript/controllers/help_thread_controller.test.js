import { describe, it, expect, vi, afterEach } from "vitest"
import Controller from "controllers/help_thread_controller"
import { mountController, controllerFor, tick } from "../support/stimulus.js"

function threadHtml(overrides = {}) {
  const thread = overrides.omitThread
    ? ""
    : `<div data-help-thread-target="thread" style="height:40px;overflow:auto"></div>`
  const form = overrides.omitForm
    ? ""
    : `<form data-help-thread-target="form"><textarea></textarea><button type="submit">Send</button></form>`
  return `<div data-controller="help-thread">${thread}${form}</div>`
}

describe("help-thread controller", () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it("scrolls the thread to the bottom on connect", async () => {
    const { application, element } = await mountController("help-thread", Controller, threadHtml())
    const thread = element.querySelector("[data-help-thread-target='thread']")
    Object.defineProperty(thread, "scrollHeight", { configurable: true, get: () => 240 })
    thread.scrollTop = 0
    const ctrl = controllerFor(application, element, "help-thread")
    ctrl.connect()
    expect(thread.scrollTop).toBe(240)
  })

  it("scrolls the thread when a child is added", async () => {
    const { element } = await mountController("help-thread", Controller, threadHtml())
    const thread = element.querySelector("[data-help-thread-target='thread']")
    Object.defineProperty(thread, "scrollHeight", { configurable: true, get: () => 400 })
    thread.appendChild(document.createElement("article"))
    await tick()
    expect(thread.scrollTop).toBe(400)
  })

  it("submits the form on Enter and lets Shift+Enter pass through", async () => {
    const { application, element } = await mountController("help-thread", Controller, threadHtml())
    const form = element.querySelector("form")
    form.requestSubmit = vi.fn()
    const ctrl = controllerFor(application, element, "help-thread")
    ctrl.keydown({ key: "Enter", shiftKey: true, preventDefault: vi.fn() })
    expect(form.requestSubmit).not.toHaveBeenCalled()
    const prevent = vi.fn()
    ctrl.keydown({ key: "Enter", shiftKey: false, preventDefault: prevent })
    expect(prevent).toHaveBeenCalled()
    expect(form.requestSubmit).toHaveBeenCalledOnce()
  })

  it("ignores keydown for keys other than Enter", async () => {
    const { application, element } = await mountController("help-thread", Controller, threadHtml())
    const form = element.querySelector("form")
    form.requestSubmit = vi.fn()
    const ctrl = controllerFor(application, element, "help-thread")
    ctrl.keydown({ key: "a", shiftKey: false, preventDefault: vi.fn() })
    expect(form.requestSubmit).not.toHaveBeenCalled()
  })

  it("does not throw when Enter is pressed without a form", async () => {
    const { application, element } = await mountController("help-thread", Controller, threadHtml({ omitForm: true }))
    const ctrl = controllerFor(application, element, "help-thread")
    expect(() => ctrl.keydown({ key: "Enter", shiftKey: false, preventDefault: vi.fn() })).not.toThrow()
    expect(() => ctrl.submit()).not.toThrow()
  })

  it("tolerates a missing thread target", async () => {
    const { application, element } = await mountController("help-thread", Controller, threadHtml({ omitThread: true }))
    const ctrl = controllerFor(application, element, "help-thread")
    expect(ctrl.observer).toBeNull()
    expect(() => ctrl.disconnect()).not.toThrow()
  })

  it("disconnects the mutation observer", async () => {
    const { application, element } = await mountController("help-thread", Controller, threadHtml())
    const ctrl = controllerFor(application, element, "help-thread")
    expect(ctrl.observer).toBeTruthy()
    element.remove()
    await tick()
    expect(ctrl.observer).toBeNull()
    application.stop()
  })
})
