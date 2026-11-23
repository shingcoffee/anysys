import { describe, it, expect } from "vitest"
import { Application } from "@hotwired/stimulus"
import { application } from "controllers/application"

// application.js is a tiny bootstrap: it starts a single Stimulus Application,
// disables debug, and exposes it as window.Stimulus. There is no behavior to
// drive beyond confirming that wiring.
describe("controllers/application bootstrap", () => {
  it("exports a started Stimulus Application", () => {
    expect(application).toBeInstanceOf(Application)
  })

  it("disables debug mode", () => {
    expect(application.debug).toBe(false)
  })

  it("exposes the application on window.Stimulus", () => {
    expect(window.Stimulus).toBe(application)
  })
})
