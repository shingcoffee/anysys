import { describe, it, expect, vi, afterEach } from "vitest"
import Controller from "controllers/template_preview_controller"
import { mountController, controllerFor } from "../support/stimulus.js"

const html = (value = "", debounce) =>
  `<div data-controller="template-preview" ${debounce != null ? `data-template-preview-debounce-value="${debounce}"` : ""}>` +
  `<textarea data-template-preview-target="source" data-action="input->template-preview#sourceChanged">${value}</textarea>` +
  `<iframe data-template-preview-target="preview"></iframe>` +
  `</div>`

const srcdoc = (el) => el.querySelector("[data-template-preview-target='preview']").srcdoc

// mountController awaits a real setTimeout(0) for Stimulus's connect tick.
// Activating fake timers BEFORE mounting (as a global beforeEach would) captures
// that setTimeout too, so it never fires and the test times out. Mount first
// (real timers), then switch to fake timers for the rest of the test.
const mountThenFake = async (value, debounce) => {
  const mounted = await mountController("template-preview", Controller, html(value, debounce))
  vi.useFakeTimers()
  return mounted
}

describe("template-preview controller", () => {
  afterEach(() => vi.useRealTimers())

  it("renders the wrapped source into the iframe srcdoc on connect", async () => {
    // NOTE: happy-dom mis-parses markup embedded inside a <textarea>...</textarea>
    // seed string as real child elements instead of RCDATA text (a real browser
    // keeps "<h1>Hi</h1>" as literal textarea.value text; happy-dom strips the
    // tags down to "Hi"). Use tag-free seed content here so the assertion isn't
    // coupled to that parsing quirk; the debounced-update test below sets
    // `.value` directly via JS (bypassing HTML parsing) and does verify tags
    // survive in the wrapped output.
    const { element } = await mountThenFake("Hi")
    expect(srcdoc(element)).toContain("<!DOCTYPE html>")
    expect(srcdoc(element)).toContain("<body>Hi</body>")
  })

  it("shows a placeholder when the source is empty", async () => {
    const { element } = await mountThenFake("")
    expect(srcdoc(element)).toContain("Start typing HTML to see preview")
  })

  it("sourceChanged debounces before updating the preview", async () => {
    const { application, element } = await mountThenFake("", 300)
    const ctrl = controllerFor(application, element, "template-preview")
    element.querySelector("textarea").value = "<p>Later</p>"
    ctrl.sourceChanged()
    // Not yet applied
    expect(srcdoc(element)).not.toContain("<p>Later</p>")
    vi.advanceTimersByTime(300)
    expect(srcdoc(element)).toContain("<p>Later</p>")
  })

  it("wrapContent embeds the html between body tags with base styles", async () => {
    const { application, element } = await mountThenFake("")
    const ctrl = controllerFor(application, element, "template-preview")
    const out = ctrl.wrapContent("<span>x</span>")
    expect(out).toContain("<body><span>x</span></body>")
    expect(out).toContain("font-family")
  })
})
