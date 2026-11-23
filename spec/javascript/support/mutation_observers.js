import { beforeAll, afterAll } from "vitest"
import { observeMutations } from "happy-dom/lib/PropertySymbol.js"

// happy-dom 15.11.7's MutationObserverListener stores its forwarding callback
// ONLY in a WeakRef. A GC can silently stop a live observer: observe body,
// append once, await a turn, gc(), append again => only the first is delivered.
// Retain that callback for the listener's lifetime, matching native DOM. This
// adapter changes neither observed records nor Stimulus action/event handling;
// Chromium runs the same production modules without any compatibility adapter.
const callbacks = new WeakMap()
let observe
beforeAll(() => {
  observe = Node.prototype[observeMutations]
  Node.prototype[observeMutations] = function (listener) {
    callbacks.set(listener, listener.callback.deref())
    return observe.call(this, listener)
  }
})
afterAll(() => { Node.prototype[observeMutations] = observe })
