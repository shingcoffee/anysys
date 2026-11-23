// controllers/index.js is the importmap eager-load bootstrap: it imports the shared
// Stimulus `application` and the framework-provided `eagerLoadControllersFrom` loader
// (from `@hotwired/stimulus-loading`, an importmap-pinned dependency not installed as
// an npm package) and immediately invokes the loader with ("controllers", application).
// That invocation IS the module's entire behavior, so we mock both side-effecting
// dependencies and assert the wiring actually happens on import.
import { describe, it, expect, vi } from "vitest"

const eagerLoadControllersFrom = vi.fn()
vi.mock("@hotwired/stimulus-loading", () => ({ eagerLoadControllersFrom }))

const application = { fake: "application" }
vi.mock("controllers/application", () => ({ application }))

describe("controllers/index.js", () => {
  it("eager-loads controllers from the 'controllers' importmap root into the shared application", async () => {
    await import("controllers/index.js")

    expect(eagerLoadControllersFrom).toHaveBeenCalledTimes(1)
    expect(eagerLoadControllersFrom).toHaveBeenCalledWith("controllers", application)
  })
})
