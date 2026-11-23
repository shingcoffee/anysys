// Global test setup for Vitest (happy-dom environment).
//
// happy-dom provides document/window but omits a few browser APIs that
// Stimulus controllers touch on connect. Stub the harmless ones so a
// controller can mount without exploding; individual tests override as needed.
import { vi } from "vitest"
import { installSampleActionCatalog } from "./support/action_catalog.js"
import { installSampleElementCatalog } from "./support/element_catalog.js"

// The action / element catalog stores are empty until set*Catalog. Install
// the committed fixtures so step-form / canvas / element-editor specs can
// look up actions and element fields.
installSampleActionCatalog()
installSampleElementCatalog()

// requestAnimationFrame / cancelAnimationFrame — used by several controllers
// for deferred DOM work. Run the callback on a macrotask so tests can await it.
if (!globalThis.requestAnimationFrame) {
  globalThis.requestAnimationFrame = (cb) => setTimeout(() => cb(Date.now()), 0)
  globalThis.cancelAnimationFrame = (id) => clearTimeout(id)
}

// matchMedia — some responsive controllers query it on connect.
if (!globalThis.matchMedia) {
  globalThis.matchMedia = (query) => ({
    matches: false,
    media: query,
    onchange: null,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    addListener: vi.fn(),
    removeListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })
}

// scrollTo / scrollIntoView — no-ops in happy-dom.
globalThis.scrollTo ||= vi.fn()
if (globalThis.Element && !globalThis.Element.prototype.scrollIntoView) {
  globalThis.Element.prototype.scrollIntoView = vi.fn()
}
