import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import Controller from "controllers/person_link_picker_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const USERS = [
  { id: 11, name: "Ada Lovelace", email: "ada@example.com" },
  { id: 12, name: "Grace Hopper", email: "grace@example.com" }
]

const html = `
<section data-controller="person-link-picker"
         data-action="keydown->person-link-picker#keydown"
         data-person-link-picker-candidates-url-value="/candidates.json">
  <div>
    <p>helper</p>
    <button type="button" data-person-link-picker-target="trigger" data-action="person-link-picker#open" aria-expanded="false">Link user account</button>
    <div data-person-link-picker-target="panel" class="hidden">
      <input data-person-link-picker-target="search" role="combobox" aria-expanded="false">
      <div data-person-link-picker-target="status" role="status">Type a name or email to find an account.</div>
      <ul data-person-link-picker-target="list" class="hidden" role="listbox" data-action="click->person-link-picker#select"></ul>
    </div>
  </div>
  <div data-person-link-picker-target="confirm" class="hidden">
    <p data-person-link-picker-target="confirmName"></p>
    <form data-person-link-picker-target="form">
      <input type="hidden" name="user_id" data-person-link-picker-target="userId" value="">
      <button type="submit">Link</button>
    </form>
  </div>
</section>
`

function search(el) { return el.querySelector("[data-person-link-picker-target='search']") }
function panel(el) { return el.querySelector("[data-person-link-picker-target='panel']") }
function list(el) { return el.querySelector("[data-person-link-picker-target='list']") }
function status(el) { return el.querySelector("[data-person-link-picker-target='status']") }
function trigger(el) { return el.querySelector("[data-person-link-picker-target='trigger']") }
function confirm(el) { return el.querySelector("[data-person-link-picker-target='confirm']") }
function confirmName(el) { return el.querySelector("[data-person-link-picker-target='confirmName']") }
function userId(el) { return el.querySelector("[data-person-link-picker-target='userId']") }
function options(el) { return [...el.querySelectorAll("[role='option']")] }

function key(controller, keyName, target) {
  const event = { key: keyName, preventDefault: vi.fn(), target }
  controller.keydown(event)
  return event
}

function okResponse(users) {
  return { ok: true, json: async () => ({ users }) }
}

describe("person-link-picker controller", () => {
  let element, controller

  beforeEach(async () => {
    const mounted = await mountController("person-link-picker", Controller, html)
    element = mounted.element
    controller = controllerFor(mounted.application, element, "person-link-picker")
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.restoreAllMocks()
  })

  describe("open / close", () => {
    it("opens the panel, expands ARIA, and focuses search", () => {
      controller.open({ preventDefault: vi.fn() })
      expect(panel(element).classList.contains("hidden")).toBe(false)
      expect(trigger(element).getAttribute("aria-expanded")).toBe("true")
      expect(search(element).getAttribute("aria-expanded")).toBe("true")
      expect(document.activeElement).toBe(search(element))
    })

    it("closes the panel, clears the query, and returns focus to the trigger", () => {
      controller.open({ preventDefault: vi.fn() })
      search(element).value = "ad"
      controller.close()
      expect(panel(element).classList.contains("hidden")).toBe(true)
      expect(search(element).value).toBe("")
      expect(trigger(element).getAttribute("aria-expanded")).toBe("false")
      expect(document.activeElement).toBe(trigger(element))
      expect(status(element).textContent).toBe("Type a name or email to find an account.")
    })
  })

  describe("query debounce and min length", () => {
    it("does not fetch until wait elapses", () => {
      vi.useFakeTimers()
      const spy = vi.spyOn(controller, "fetchUsers").mockImplementation(() => {})
      search(element).value = "ad"
      controller.query()
      expect(spy).not.toHaveBeenCalled()
      vi.advanceTimersByTime(249)
      expect(spy).not.toHaveBeenCalled()
      vi.advanceTimersByTime(1)
      expect(spy).toHaveBeenCalledOnce()
    })

    it("resets the timer when the query changes before wait elapses", () => {
      vi.useFakeTimers()
      const spy = vi.spyOn(controller, "fetchUsers").mockImplementation(() => {})
      search(element).value = "ad"
      controller.query()
      vi.advanceTimersByTime(200)
      search(element).value = "ada"
      controller.query()
      vi.advanceTimersByTime(200)
      expect(spy).not.toHaveBeenCalled()
      vi.advanceTimersByTime(50)
      expect(spy).toHaveBeenCalledOnce()
    })

    it("skips the network when the trimmed query is shorter than minQuery", async () => {
      global.fetch = vi.fn()
      search(element).value = " a "
      await controller.fetchUsers()
      expect(global.fetch).not.toHaveBeenCalled()
      expect(list(element).classList.contains("hidden")).toBe(true)
      expect(status(element).textContent).toBe("Type a name or email to find an account.")
    })
  })

  describe("fetch states", () => {
    it("shows loading, then rows on a 200 with users", async () => {
      let resolve
      global.fetch = vi.fn().mockImplementation(() => new Promise((r) => { resolve = r }))
      search(element).value = "ad"
      const pending = controller.fetchUsers()
      expect(status(element).querySelector(".animate-spin")).toBeTruthy()
      expect(status(element).textContent).toContain("Searching…")
      resolve(okResponse(USERS))
      await pending
      expect(global.fetch).toHaveBeenCalledWith(
        expect.stringContaining("/candidates.json?q=ad"),
        expect.objectContaining({
          credentials: "same-origin",
          headers: { Accept: "application/json" }
        })
      )
      expect(list(element).classList.contains("hidden")).toBe(false)
      expect(options(element).map((o) => o.textContent)).toEqual([
        "Ada Lovelaceada@example.com",
        "Grace Hoppergrace@example.com"
      ])
      expect(status(element).classList.contains("hidden")).toBe(true)
    })

    it("shows the empty label when the payload has no users", async () => {
      global.fetch = vi.fn().mockResolvedValue(okResponse([]))
      search(element).value = "zz"
      await controller.fetchUsers()
      expect(status(element).textContent).toBe("No matching users")
      expect(status(element).getAttribute("role")).toBe("status")
      expect(list(element).classList.contains("hidden")).toBe(true)
    })

    it("defaults to an empty list when the payload omits users", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) })
      search(element).value = "ad"
      await controller.fetchUsers()
      expect(status(element).textContent).toBe("No matching users")
    })

    it("shows the error label on a non-OK response", async () => {
      global.fetch = vi.fn().mockResolvedValue({ ok: false })
      search(element).value = "ad"
      await controller.fetchUsers()
      expect(status(element).textContent).toBe("Could not load users. Try again.")
      expect(status(element).getAttribute("role")).toBe("alert")
    })

    it("shows the error label when fetch throws", async () => {
      global.fetch = vi.fn().mockRejectedValue(new Error("net"))
      search(element).value = "ad"
      await controller.fetchUsers()
      expect(status(element).getAttribute("role")).toBe("alert")
      expect(status(element).textContent).toBe("Could not load users. Try again.")
    })

    it("shows the error label when JSON parsing fails", async () => {
      global.fetch = vi.fn().mockResolvedValue({
        ok: true,
        json: async () => { throw new Error("bad json") }
      })
      search(element).value = "ad"
      await controller.fetchUsers()
      expect(status(element).getAttribute("role")).toBe("alert")
    })

    it("aborts an in-flight request when a new query starts", async () => {
      let firstSignal
      global.fetch = vi.fn()
        .mockImplementationOnce((_url, opts) => {
          firstSignal = opts.signal
          return new Promise((_resolve, reject) => {
            opts.signal.addEventListener("abort", () => {
              const error = new Error("Aborted")
              error.name = "AbortError"
              reject(error)
            })
          })
        })
        .mockResolvedValueOnce(okResponse([]))

      search(element).value = "ad"
      const first = controller.fetchUsers()
      search(element).value = "ada"
      await controller.fetchUsers()
      await first
      expect(firstSignal.aborted).toBe(true)
      expect(status(element).getAttribute("role")).not.toBe("alert")
      expect(status(element).textContent).toBe("No matching users")
    })
  })

  describe("keyboard", () => {
    beforeEach(async () => {
      global.fetch = vi.fn().mockResolvedValue(okResponse(USERS))
      search(element).value = "ad"
      await controller.fetchUsers()
    })

    it("ArrowDown / ArrowUp wrap the highlight and update aria-activedescendant", () => {
      controller.open({ preventDefault: vi.fn() })
      const first = options(element)[0]
      const scroll = vi.spyOn(first, "scrollIntoView")
      const down = key(controller, "ArrowDown", search(element))
      expect(down.preventDefault).toHaveBeenCalled()
      expect(controller.activeIndex).toBe(0)
      expect(first.classList.contains("bg-accent-subtle")).toBe(true)
      expect(first.getAttribute("aria-selected")).toBe("true")
      expect(search(element).getAttribute("aria-activedescendant")).toBe("person-link-option-11")
      expect(scroll).toHaveBeenCalledWith({ block: "nearest" })

      key(controller, "ArrowDown", search(element))
      expect(controller.activeIndex).toBe(1)
      key(controller, "ArrowDown", search(element))
      expect(controller.activeIndex).toBe(0)
      key(controller, "ArrowUp", search(element))
      expect(controller.activeIndex).toBe(1)
    })

    it("ArrowUp from no highlight selects the last option", () => {
      controller.open({ preventDefault: vi.fn() })
      key(controller, "ArrowUp", search(element))
      expect(controller.activeIndex).toBe(1)
    })

    it("ArrowDown opens the panel when it is closed", () => {
      expect(controller.openState).toBe(false)
      key(controller, "ArrowDown", search(element))
      expect(controller.openState).toBe(true)
      expect(controller.activeIndex).toBe(0)
    })

    it("ArrowUp opens the panel when it is closed", () => {
      key(controller, "ArrowUp", search(element))
      expect(controller.openState).toBe(true)
      expect(controller.activeIndex).toBe(1)
    })

    it("Home and End jump to the first and last options", () => {
      controller.open({ preventDefault: vi.fn() })
      const end = key(controller, "End", search(element))
      expect(end.preventDefault).toHaveBeenCalled()
      expect(controller.activeIndex).toBe(1)
      const home = key(controller, "Home", search(element))
      expect(home.preventDefault).toHaveBeenCalled()
      expect(controller.activeIndex).toBe(0)
    })

    it("Enter selects the highlighted row and shows confirm copy", () => {
      controller.open({ preventDefault: vi.fn() })
      key(controller, "ArrowDown", search(element))
      const enter = key(controller, "Enter", search(element))
      expect(enter.preventDefault).toHaveBeenCalled()
      expect(confirm(element).classList.contains("hidden")).toBe(false)
      expect(confirmName(element).textContent).toBe("Link this entry to Ada Lovelace (ada@example.com)?")
      expect(userId(element).value).toBe("11")
      expect(trigger(element).parentElement.hidden).toBe(true)
      expect(document.activeElement).toBe(confirm(element).querySelector('button[type="submit"]'))
    })

    it("Enter does nothing when the picker is closed", () => {
      const enter = key(controller, "Enter", search(element))
      const home = key(controller, "Home", search(element))
      const end = key(controller, "End", search(element))
      expect(enter.preventDefault).not.toHaveBeenCalled()
      expect(home.preventDefault).not.toHaveBeenCalled()
      expect(end.preventDefault).not.toHaveBeenCalled()
      expect(confirm(element).classList.contains("hidden")).toBe(true)
    })

    it("Enter does not choose when no row is highlighted", () => {
      controller.open({ preventDefault: vi.fn() })
      const enter = key(controller, "Enter", search(element))
      expect(enter.preventDefault).toHaveBeenCalled()
      expect(confirm(element).classList.contains("hidden")).toBe(true)
    })

    it("Escape closes an open picker and focuses the trigger", () => {
      controller.open({ preventDefault: vi.fn() })
      const escape = key(controller, "Escape", search(element))
      expect(escape.preventDefault).toHaveBeenCalled()
      expect(controller.openState).toBe(false)
      expect(document.activeElement).toBe(trigger(element))
    })

    it("Escape dismisses the confirm strip and focuses the trigger", () => {
      controller.open({ preventDefault: vi.fn() })
      key(controller, "ArrowDown", search(element))
      key(controller, "Enter", search(element))
      const escape = key(controller, "Escape", confirm(element).querySelector("button"))
      expect(escape.preventDefault).toHaveBeenCalled()
      expect(confirm(element).classList.contains("hidden")).toBe(true)
      expect(userId(element).value).toBe("")
      expect(trigger(element).parentElement.hidden).toBe(false)
      expect(document.activeElement).toBe(trigger(element))
    })

    it("Tab closes the picker without moving focus back to the trigger", () => {
      controller.open({ preventDefault: vi.fn() })
      search(element).focus()
      const tab = key(controller, "Tab", search(element))
      expect(tab.preventDefault).not.toHaveBeenCalled()
      expect(controller.openState).toBe(false)
      expect(document.activeElement).toBe(search(element))
    })

    it("ignores keys that are not part of the combobox map", () => {
      controller.open({ preventDefault: vi.fn() })
      const other = key(controller, "a", search(element))
      expect(other.preventDefault).not.toHaveBeenCalled()
      expect(controller.activeIndex).toBe(-1)
    })
  })

  describe("keyboard with no rows", () => {
    it("does not move highlight, Home, or End when the list is empty", () => {
      controller.open({ preventDefault: vi.fn() })
      const down = key(controller, "ArrowDown", search(element))
      const home = key(controller, "Home", search(element))
      const end = key(controller, "End", search(element))
      expect(down.preventDefault).toHaveBeenCalled()
      expect(home.preventDefault).not.toHaveBeenCalled()
      expect(end.preventDefault).not.toHaveBeenCalled()
      expect(controller.activeIndex).toBe(-1)
    })

    it("does not handle Tab or Escape when the picker is idle", () => {
      const tab = key(controller, "Tab", search(element))
      const escape = key(controller, "Escape", search(element))
      expect(tab.preventDefault).not.toHaveBeenCalled()
      expect(escape.preventDefault).not.toHaveBeenCalled()
    })
  })

  describe("select / cancel / outside", () => {
    beforeEach(async () => {
      global.fetch = vi.fn().mockResolvedValue(okResponse(USERS))
      search(element).value = "ad"
      await controller.fetchUsers()
      controller.open({ preventDefault: vi.fn() })
    })

    it("selects a row on click and fills the confirm strip", () => {
      options(element)[1].dispatchEvent(new Event("click", { bubbles: true }))
      expect(confirmName(element).textContent).toBe("Link this entry to Grace Hopper (grace@example.com)?")
      expect(userId(element).value).toBe("12")
    })

    it("ignores a click that is not on an option", () => {
      list(element).dispatchEvent(new Event("click", { bubbles: true }))
      expect(confirm(element).classList.contains("hidden")).toBe(true)
    })

    it("ignores an option whose id is not in the current results", () => {
      const stray = document.createElement("button")
      stray.setAttribute("role", "option")
      stray.dataset.userId = "999"
      list(element).append(stray)
      stray.dispatchEvent(new Event("click", { bubbles: true }))
      expect(confirm(element).classList.contains("hidden")).toBe(true)
    })

    it("cancel hides confirm and re-opens the search", () => {
      options(element)[0].dispatchEvent(new Event("click", { bubbles: true }))
      controller.cancel()
      expect(confirm(element).classList.contains("hidden")).toBe(true)
      expect(trigger(element).parentElement.hidden).toBe(false)
      expect(controller.openState).toBe(true)
      expect(document.activeElement).toBe(search(element))
    })

    it("closes on an outside click and ignores clicks inside the card", () => {
      document.body.dispatchEvent(new MouseEvent("click", { bubbles: true }))
      expect(controller.openState).toBe(false)
      controller.open({ preventDefault: vi.fn() })
      element.dispatchEvent(new MouseEvent("click", { bubbles: true }))
      expect(controller.openState).toBe(true)
    })

    it("outside click is a no-op when the picker is already closed", () => {
      controller.close()
      document.body.dispatchEvent(new MouseEvent("click", { bubbles: true }))
      expect(controller.openState).toBe(false)
    })
  })

  describe("disconnect", () => {
    it("removes the outside-click listener and aborts an in-flight fetch", async () => {
      const removeSpy = vi.spyOn(document, "removeEventListener")
      let signal
      global.fetch = vi.fn().mockImplementation((_url, opts) => {
        signal = opts.signal
        return new Promise((_resolve, reject) => {
          opts.signal.addEventListener("abort", () => {
            const error = new Error("Aborted")
            error.name = "AbortError"
            reject(error)
          })
        })
      })
      search(element).value = "ad"
      const pending = controller.fetchUsers()
      controller.disconnect()
      await pending
      expect(signal.aborted).toBe(true)
      expect(removeSpy).toHaveBeenCalledWith("click", controller.boundOutside)
      expect(status(element).getAttribute("role")).not.toBe("alert")
    })

    it("clears a pending debounce and is safe when no fetch is in flight", () => {
      vi.useFakeTimers()
      const spy = vi.spyOn(controller, "fetchUsers")
      search(element).value = "ad"
      controller.query()
      controller.disconnect()
      vi.advanceTimersByTime(250)
      expect(spy).not.toHaveBeenCalled()
    })
  })
})
