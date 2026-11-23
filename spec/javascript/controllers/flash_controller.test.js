import { describe, it, expect, vi, afterEach } from "vitest"
import Controller from "controllers/flash_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = (auto) => `
  <div data-controller="flash" ${auto ? 'data-flash-auto-dismiss-value="true"' : ""}>Flash message</div>`

// Fake timers must be active before connect() so the auto-dismiss setTimeout is
// captured by the fake clock. The mount helper awaits a setTimeout(0); flush it
// with advanceTimersByTimeAsync so the controller finishes connecting.
const fakeMount = async (auto) => {
  vi.useFakeTimers()
  const promise = mountController("flash", Controller, html(auto))
  await vi.advanceTimersByTimeAsync(0)
  return promise
}

describe("flash controller", () => {
  afterEach(() => vi.useRealTimers())

  it("dismiss() fades out then removes the element after 300ms", async () => {
    const { application, element } = await fakeMount(false)
    const ctrl = controllerFor(application, element, "flash")
    expect(document.body.contains(element)).toBe(true)

    ctrl.dismiss()

    expect(element.style.opacity).toBe("0")
    expect(element.style.maxHeight).toBe("0")
    expect(document.body.contains(element)).toBe(true) // not yet removed
    vi.advanceTimersByTime(300)
    expect(document.body.contains(element)).toBe(false)
  })

  it("auto-dismisses after 5s when autoDismiss is set", async () => {
    const { element } = await fakeMount(true)
    expect(document.body.contains(element)).toBe(true)
    vi.advanceTimersByTime(5000) // triggers dismiss()
    expect(element.style.opacity).toBe("0")
    vi.advanceTimersByTime(300) // removal
    expect(document.body.contains(element)).toBe(false)
  })

  it("does NOT auto-dismiss when autoDismiss is unset", async () => {
    const { element } = await fakeMount(false)
    vi.advanceTimersByTime(10000)
    expect(document.body.contains(element)).toBe(true)
    expect(element.style.opacity).toBe("")
  })

  it("clears the auto-dismiss timer on disconnect", async () => {
    const { element } = await fakeMount(true)

    // application.stop() only tears down the top-level MutationObserver — it does
    // NOT synchronously disconnect already-connected controllers (Router#stop just
    // calls ScopeObserver#stop). Removing the element from the DOM is what actually
    // triggers Stimulus's disconnect lifecycle, via the MutationObserver's
    // childList callback — but that callback fires on a real macrotask that vi's
    // fake timers don't intercept, so flush it with a real setTimeout(0) tick.
    element.remove()
    vi.useRealTimers()
    await new Promise((resolve) => setTimeout(resolve, 0))
    vi.useFakeTimers()

    vi.advanceTimersByTime(10000)
    expect(element.style.opacity).toBe("") // dismiss() never ran: disconnect cleared the timer
  })
})
