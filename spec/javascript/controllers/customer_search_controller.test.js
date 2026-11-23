import { describe, it, expect, vi, afterEach } from "vitest"
import Controller from "controllers/customer_search_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

// NOTE: happy-dom v15.11.7's HTMLFormElement#contains() is broken (always
// returns false, even for real descendants — see the comment in
// auto_submit_controller.test.js for the empirical proof). Stimulus's
// input->customer-search#submit action dispatch never reaches the controller
// on a <form> root in this environment, so we drive the controller's `submit()`
// method directly via the live controller instance instead of dispatching a DOM
// "input" event — this still exercises the real debounce/requestSubmit logic.
const html = (wait) => `
  <form data-controller="customer-search"
        ${wait != null ? `data-customer-search-wait-value="${wait}"` : ""}>
    <input name="q" type="text">
  </form>`

// The mount helper awaits a real setTimeout(0), so we must mount BEFORE switching
// to fake timers — otherwise the connect tick never fires.
const mountThenFake = async (wait) => {
  const mounted = await mountController("customer-search", Controller, html(wait))
  vi.useFakeTimers()
  return mounted
}

describe("customer-search controller", () => {
  afterEach(() => vi.useRealTimers())

  it("debounces and calls requestSubmit after the wait window", async () => {
    const { application, element } = await mountThenFake()
    const controller = controllerFor(application, element, "customer-search")
    element.requestSubmit = vi.fn()

    controller.submit()
    expect(element.requestSubmit).not.toHaveBeenCalled()

    vi.advanceTimersByTime(250) // default wait
    expect(element.requestSubmit).toHaveBeenCalledOnce()
  })

  it("coalesces rapid inputs into a single submit (resets the timer)", async () => {
    const { application, element } = await mountThenFake()
    const controller = controllerFor(application, element, "customer-search")
    element.requestSubmit = vi.fn()

    controller.submit()
    vi.advanceTimersByTime(200)
    controller.submit() // resets timer
    vi.advanceTimersByTime(200)
    expect(element.requestSubmit).not.toHaveBeenCalled() // 400ms elapsed but timer reset
    vi.advanceTimersByTime(50)
    expect(element.requestSubmit).toHaveBeenCalledOnce()
  })

  it("honours a custom wait value", async () => {
    const { application, element } = await mountThenFake(1000)
    const controller = controllerFor(application, element, "customer-search")
    element.requestSubmit = vi.fn()

    controller.submit()
    vi.advanceTimersByTime(999)
    expect(element.requestSubmit).not.toHaveBeenCalled()
    vi.advanceTimersByTime(1)
    expect(element.requestSubmit).toHaveBeenCalledOnce()
  })

  it("clears the pending timer on disconnect (no submit fires)", async () => {
    const { application, element } = await mountThenFake()
    const controller = controllerFor(application, element, "customer-search")
    element.requestSubmit = vi.fn()
    controller.submit()

    // application.stop() only tears down the top-level MutationObserver — it does
    // NOT synchronously disconnect already-connected controllers (Router#stop just
    // calls ScopeObserver#stop). Normally removing the element from the DOM is
    // what triggers Stimulus's disconnect lifecycle via the MutationObserver's
    // childList callback, but happy-dom's HTMLFormElement#remove() is ALSO broken
    // in this environment (throws "not a child of this node" — the same proxy-
    // identity issue as #contains(), see the NOTE above) so we can't drive
    // disconnect that way for a <form> root. Call disconnect() directly instead —
    // it still exercises the controller's real timer-clearing logic.
    controller.disconnect()

    vi.advanceTimersByTime(500)
    expect(element.requestSubmit).not.toHaveBeenCalled()
  })
})
