import { describe, it, expect, vi } from "vitest"
import Controller from "controllers/auto_submit_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

// NOTE: happy-dom v15.11.7's HTMLFormElement#contains() is broken — it returns
// false even for a genuine descendant (confirmed empirically: `form.contains(x)`
// is false while `x.parentElement === form` is true, and even `form.contains(form)`
// itself is false). Stimulus's action dispatch (Binding#willBeInvokedByEvent)
// relies on Node#contains() to match a bubbled event back to the controller's
// scope element, so no dispatched DOM event ever reaches an action bound on (or
// under) a <form data-controller="..."> element in this environment — this is
// an environment limitation, not a bug in auto_submit_controller.js. We work
// around it by invoking the controller's action method directly (via the live
// controller instance), which still exercises the controller's real logic.
const html = `<form data-controller="auto-submit">
                <input name="enabled" type="checkbox" data-action="change->auto-submit#submit">
              </form>`

describe("auto-submit controller", () => {
  it("submit() calls requestSubmit when available", async () => {
    const { application, element } = await mountController("auto-submit", Controller, html)
    const controller = controllerFor(application, element, "auto-submit")
    element.requestSubmit = vi.fn()

    controller.submit()

    expect(element.requestSubmit).toHaveBeenCalledOnce()
  })

  it("submit() falls back to submit() when requestSubmit is unavailable", async () => {
    const { application, element } = await mountController("auto-submit", Controller, html)
    const controller = controllerFor(application, element, "auto-submit")
    element.requestSubmit = undefined
    element.submit = vi.fn()

    controller.submit()

    expect(element.submit).toHaveBeenCalledOnce()
  })
})
