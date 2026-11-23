import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import Controller from "controllers/admin_table_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const markup = (name = "q", value = "") => `
  <form>
    <div data-controller="admin-table">
      <input name="${name}" value="${value}" data-admin-table-target="searchInput"
             data-action="input->admin-table#debounceSubmit keydown->admin-table#submit">
    </div>
  </form>`

async function mount(name, value) {
  const { application, element } = await mountController("admin-table", Controller, markup(name, value))
  const input = element.querySelector("[data-admin-table-target='searchInput']")
  const requestSubmit = vi.fn()
  input.form.requestSubmit = requestSubmit
  return { controller: controllerFor(application, element, "admin-table"), element, input, requestSubmit }
}

// The controller reads event.target.form; we invoke its actions directly with a
// synthetic event so the (deferred) event.target is stable under fake timers —
// happy-dom nulls a real dispatched event's target once dispatch returns. Mount
// under real timers (mountController awaits a setTimeout(0)), then switch to
// fake timers inside the debounce tests.
describe("admin-table controller", () => {
  let controller, element, input, requestSubmit

  beforeEach(async () => {
    ({ controller, element, input, requestSubmit } = await mount())
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.restoreAllMocks()
  })

  it("submit() submits the input's form immediately", () => {
    controller.submit({ target: input })
    expect(requestSubmit).toHaveBeenCalledOnce()
  })

  it("debounceSubmit() waits 300ms before submitting", () => {
    vi.useFakeTimers()
    controller.debounceSubmit({ target: input })
    expect(requestSubmit).not.toHaveBeenCalled()
    vi.advanceTimersByTime(299)
    expect(requestSubmit).not.toHaveBeenCalled()
    vi.advanceTimersByTime(1)
    expect(requestSubmit).toHaveBeenCalledOnce()
  })

  it("debounceSubmit() coalesces rapid calls into a single submit", () => {
    vi.useFakeTimers()
    controller.debounceSubmit({ target: input })
    vi.advanceTimersByTime(100)
    controller.debounceSubmit({ target: input })
    vi.advanceTimersByTime(100)
    controller.debounceSubmit({ target: input })
    vi.advanceTimersByTime(300)
    expect(requestSubmit).toHaveBeenCalledOnce()
  })

  it("cancels a pending submit when the controller disconnects", () => {
    vi.useFakeTimers()
    controller.debounceSubmit({ target: input })
    element.remove()
    controller.disconnect()
    vi.advanceTimersByTime(300)
    expect(requestSubmit).not.toHaveBeenCalled()
  })

  describe("after the frame re-renders the search box", () => {
    // A turbo-frame swap disconnects the old controller; Application#stop in
    // the mount helper does not, so disconnect explicitly before remounting.
    const rerender = (name, value) => {
      controller.disconnect()
      return mount(name, value)
    }

    it("refocuses the fresh input with the caret at the end", async () => {
      input.value = "ali"
      controller.debounceSubmit({ target: input })

      const fresh = await rerender("q", "ali")

      expect(document.activeElement).toBe(fresh.input)
      expect(fresh.input.selectionStart).toBe(3)
      expect(fresh.input.selectionEnd).toBe(3)
    })

    it("restores characters typed during the request and searches again", async () => {
      input.value = "alice"
      controller.debounceSubmit({ target: input })

      const fresh = await rerender("q", "ali")
      expect(fresh.input.value).toBe("alice")
      expect(document.activeElement).toBe(fresh.input)

      await new Promise((resolve) => setTimeout(resolve, 320))
      expect(fresh.requestSubmit).toHaveBeenCalledOnce()
    })

    it("only restores once", async () => {
      input.value = "ali"
      controller.debounceSubmit({ target: input })
      await rerender("q", "ali")
      document.activeElement.blur()

      const again = await rerender("q", "ali")
      expect(document.activeElement).not.toBe(again.input)
    })

    it("ignores a search box with a different name", async () => {
      input.value = "ali"
      controller.debounceSubmit({ target: input })

      const other = await rerender("term", "")
      expect(document.activeElement).not.toBe(other.input)
      expect(other.input.value).toBe("")
    })

    it("ignores a stale pending search", async () => {
      input.value = "ali"
      const now = Date.now()
      vi.spyOn(Date, "now").mockReturnValue(now)
      controller.debounceSubmit({ target: input })
      Date.now.mockReturnValue(now + 10001)

      const fresh = await rerender("q", "")
      expect(document.activeElement).not.toBe(fresh.input)
      expect(fresh.input.value).toBe("")
    })
  })
})
