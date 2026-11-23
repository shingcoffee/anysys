import { describe, it, expect, vi, beforeEach } from "vitest"
import Controller from "controllers/token_autocomplete_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const TOKENS = [
  { label: "First name", group: "Catalog" },
  { label: "Last name", group: "Catalog" },
  { label: "Unsubscribe link", group: "Custom" }
]

const html = `
  <div data-controller="token-autocomplete"
       data-token-autocomplete-tokens-value='${JSON.stringify(TOKENS)}'
       data-token-autocomplete-no-matches-value="No matching tokens">
    <input type="text" data-token-autocomplete-target="input">
  </div>`

const mount = async (markup = html) => {
  const { application, element } = await mountController("token-autocomplete", Controller, markup)
  const ctrl = controllerFor(application, element, "token-autocomplete")
  const input = element.querySelector("input")
  return { application, ctrl, element, input }
}

// Types into the input (moving the caret) and fires the input event the
// controller listens to.
const type = (input, value) => {
  input.value = value
  input.setSelectionRange(value.length, value.length)
  input.dispatchEvent(new Event("input", { bubbles: true }))
}

const menu = (element) => element.querySelector(".token-autocomplete-menu")
const options = (element) => [...element.querySelectorAll(".token-autocomplete-option")]
const keydown = (input, key) => input.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }))

describe("token-autocomplete controller", () => {
  beforeEach(() => {
    Element.prototype.scrollIntoView = vi.fn()
  })

  it("creates a hidden menu on connect", async () => {
    const { element } = await mount()
    expect(menu(element)).toBeTruthy()
    expect(menu(element).classList.contains("hidden")).toBe(true)
    expect(menu(element).getAttribute("role")).toBe("listbox")
  })

  it("falls back to the first input child when no target is marked", async () => {
    const { ctrl, input } = await mount(`
      <div data-controller="token-autocomplete"
           data-token-autocomplete-tokens-value='${JSON.stringify(TOKENS)}'>
        <input type="text">
      </div>`)
    expect(ctrl._input).toBe(input)
  })

  it("opens with every token when {{ is typed", async () => {
    const { element, input } = await mount()
    type(input, "Hi {{")
    expect(menu(element).classList.contains("hidden")).toBe(false)
    expect(options(element)).toHaveLength(3)
    expect(options(element)[0].textContent).toContain("First name")
    expect(options(element)[0].textContent).toContain("Catalog")
  })

  it("filters case-insensitively as the query grows", async () => {
    const { element, input } = await mount()
    type(input, "Hi {{NA")
    const labels = options(element).map((o) => o.querySelector("span").textContent)
    expect(labels).toEqual(["First name", "Last name"])
  })

  it("matches labels containing spaces", async () => {
    const { element, input } = await mount()
    type(input, "{{first na")
    expect(options(element)).toHaveLength(1)
    expect(options(element)[0].textContent).toContain("First name")
  })

  it("shows the translated no-matches label when nothing fits", async () => {
    const { element, input } = await mount()
    type(input, "{{zzz")
    expect(options(element)).toHaveLength(0)
    expect(element.querySelector(".token-autocomplete-empty").textContent).toBe("No matching tokens")
  })

  it("stays closed without a {{ trigger", async () => {
    const { element, input } = await mount()
    type(input, "plain subject")
    expect(menu(element).classList.contains("hidden")).toBe(true)
  })

  it("closes once the token is completed with }}", async () => {
    const { element, input } = await mount()
    type(input, "{{fir")
    expect(menu(element).classList.contains("hidden")).toBe(false)
    type(input, "{{fir}}")
    expect(menu(element).classList.contains("hidden")).toBe(true)
  })

  it("stays closed when the caret is outside the unfinished run", async () => {
    const { element, input } = await mount()
    input.value = "{{First name}} welcome"
    input.setSelectionRange(3, 3)
    input.dispatchEvent(new Event("input", { bubbles: true }))
    expect(menu(element).classList.contains("hidden")).toBe(true)
  })

  it("handles a null selectionStart without crashing", async () => {
    const { element, input } = await mount()
    Object.defineProperty(input, "selectionStart", { value: null, configurable: true })
    type(input, "{{")
    expect(menu(element).classList.contains("hidden")).toBe(true)
  })

  it("navigates options with ArrowDown/ArrowUp, wrapping around", async () => {
    const { element, input } = await mount()
    type(input, "{{")
    keydown(input, "ArrowDown")
    expect(options(element)[1].className).toContain("bg-surface-hover")
    keydown(input, "ArrowDown")
    keydown(input, "ArrowDown")
    expect(options(element)[0].className).toContain("bg-surface-hover")
    keydown(input, "ArrowUp")
    expect(options(element)[2].className).toContain("bg-surface-hover")
    expect(Element.prototype.scrollIntoView).toHaveBeenCalled()
  })

  it("ignores arrow keys when there are no matches", async () => {
    const { element, input } = await mount()
    type(input, "{{zzz")
    keydown(input, "ArrowDown")
    expect(element.querySelector(".token-autocomplete-empty")).toBeTruthy()
  })

  it("inserts the active option on Enter, replacing the partial query", async () => {
    const { element, input } = await mount()
    const events = []
    input.addEventListener("input", () => events.push(input.value))
    type(input, "Hi {{fir")
    keydown(input, "Enter")
    expect(input.value).toBe("Hi {{First name}}")
    expect(input.selectionStart).toBe("Hi {{First name}}".length)
    expect(menu(element).classList.contains("hidden")).toBe(true)
    // input re-dispatched for the preview controller
    expect(events[events.length - 1]).toBe("Hi {{First name}}")
  })

  it("preserves text after the caret on insert", async () => {
    const { input } = await mount()
    input.value = "{{fir} tail"
    input.setSelectionRange(5, 5)
    input.dispatchEvent(new Event("input", { bubbles: true }))
    keydown(input, "Enter")
    expect(input.value).toBe("{{First name}}} tail")
  })

  it("inserts via mousedown on an option", async () => {
    const { element, input } = await mount()
    type(input, "{{uns")
    options(element)[0].dispatchEvent(new MouseEvent("mousedown", { bubbles: true, cancelable: true }))
    expect(input.value).toBe("{{Unsubscribe link}}")
  })

  it("Enter with no matches is a no-op", async () => {
    const { input } = await mount()
    type(input, "{{zzz")
    keydown(input, "Enter")
    expect(input.value).toBe("{{zzz")
  })

  it("closes on Escape", async () => {
    const { element, input } = await mount()
    type(input, "{{")
    keydown(input, "Escape")
    expect(menu(element).classList.contains("hidden")).toBe(true)
  })

  it("closes on blur", async () => {
    const { element, input } = await mount()
    type(input, "{{")
    input.dispatchEvent(new FocusEvent("blur"))
    expect(menu(element).classList.contains("hidden")).toBe(true)
  })

  it("does not intercept keys while closed", async () => {
    const { input } = await mount()
    const event = new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })
    input.dispatchEvent(event)
    expect(event.defaultPrevented).toBe(false)
  })

  it("renders an empty-state menu when the token list is empty", async () => {
    const { element, input } = await mount(`
      <div data-controller="token-autocomplete">
        <input type="text" data-token-autocomplete-target="input">
      </div>`)
    type(input, "{{")
    expect(element.querySelector(".token-autocomplete-empty").textContent).toBe("No matching tokens")
  })

  it("uses a null-safe caret fallback when inserting", async () => {
    const { ctrl, input } = await mount()
    type(input, "{{fi")
    Object.defineProperty(input, "selectionStart", { value: null, configurable: true })
    ctrl._input.focus()
    input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
    expect(input.value).toContain("{{First name}}")
  })

  it("removes listeners and the menu on disconnect", async () => {
    const { ctrl, element, input } = await mount()
    type(input, "{{")
    ctrl.disconnect()
    expect(element.querySelector(".token-autocomplete-menu")).toBeNull()
    type(input, "{{fi")
    expect(element.querySelector(".token-autocomplete-menu")).toBeNull()
  })
})
