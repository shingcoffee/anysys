// Shared helper for mounting a single Stimulus controller in happy-dom.
//
// Usage:
//   const { application, element } = await mountController("countable-items-reorder",
//     ControllerClass, `<ol data-controller="countable-items-reorder">…</ol>`)
//   … assert on element / dispatch events …
//
// The identifier must match the data-controller value used in the HTML.
//
// IMPORTANT: happy-dom's `document` persists across tests within a file, and a
// Stimulus Application keeps a live MutationObserver after start(). If we start
// a new Application per test without stopping the previous one, every leaked
// Application re-binds the fresh element and its action handlers fire N times
// (e.g. a single click runs `moveDown` twice → wrong order). So we stop the
// previously-mounted Application before mounting the next one.
import { Application } from "@hotwired/stimulus"

let current = null

export async function mountController(identifier, ControllerClass, html) {
  if (current) {
    current.stop()
    current = null
  }
  document.body.innerHTML = html
  const application = Application.start()
  current = application
  application.register(identifier, ControllerClass)
  // Stimulus connects asynchronously (MutationObserver microtask); give it a tick.
  await new Promise((resolve) => setTimeout(resolve, 0))
  const element = document.querySelector(`[data-controller~="${identifier}"]`)
  return { application, element }
}

// Retrieve the live controller instance for direct method/state assertions.
export function controllerFor(application, element, identifier) {
  return application.getControllerForElementAndIdentifier(element, identifier)
}

// Flush pending microtasks + the macrotask queue. Stimulus value-changed
// callbacks (openValueChanged, etc.) fire asynchronously via a MutationObserver,
// so a test that mutates a value/attribute and then asserts on the resulting DOM
// must `await tick()` first, otherwise it observes stale state.
export function tick() {
  return new Promise((resolve) => setTimeout(resolve, 0))
}

// Dispatch a click that carries a currentTarget, as Stimulus action handlers
// expect. Returns the tick() promise so callers that trigger an async
// value-changed re-render can `await click(el)` to flush it.
export function click(el) {
  el.dispatchEvent(new Event("click", { bubbles: true }))
  return tick()
}
