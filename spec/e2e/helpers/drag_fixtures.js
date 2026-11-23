import { test as base, expect } from "@playwright/test"
import { randomUUID } from "node:crypto"
import { runRails } from "./rails_runner.js"

function fixtureCall(method, token, kind, endResponse) {
  const output = runRails(`
    require Rails.root.join("spec/e2e/helpers/drag_fixtures")
    result = DragBrowserFixtures.${method}(${JSON.stringify(token)}${kind ? `, ${JSON.stringify(kind)}, ${JSON.stringify(endResponse)}` : ""})
    puts "DRAG_FIXTURE=" + result.to_json
  `, { timeout: 60000 })
  const result = output.split("\n").find(line => line.startsWith("DRAG_FIXTURE="))
  if (!result) throw new Error(`Drag fixture ${method} did not report a result`)
  return JSON.parse(result.slice("DRAG_FIXTURE=".length))
}

export const test = base.extend({
  dragKind: ["entity", { option: true }],
  flowchartEndResponse: ["none", { option: true }],
  dragFixture: async ({ page, dragKind, flowchartEndResponse }, use, testInfo) => {
    const errors = []
    page.on("pageerror", error => errors.push({ type: "pageerror", message: error.message, stack: error.stack }))
    page.on("console", message => {
      if (message.type() === "error") errors.push({ type: "console", message: message.text() })
    })
    const token = randomUUID().replaceAll("-", "")
    const fixture = fixtureCall("create", token, dragKind, flowchartEndResponse)
    fixture.initialSnapshot = fixture.snapshot
    fixture.snapshot = () => fixtureCall("snapshot", token)
    fixture.errors = errors
    try {
      await testInfo.attach("fixture-created", { body: JSON.stringify(fixture, null, 2), contentType: "application/json" })
      await use(fixture)
    } finally {
      try {
        await testInfo.attach("browser-errors", { body: JSON.stringify(errors, null, 2), contentType: "application/json" })
        await testInfo.attach("drag-input", { body: JSON.stringify(await page.evaluate(() => window.__dragEvents || []), null, 2), contentType: "application/json" })
        await testInfo.attach("fixture-final", { body: JSON.stringify(fixture.snapshot(), null, 2), contentType: "application/json" })
        await testInfo.attach("rendered-dom", {
          body: await page.locator("[data-controller~='entity-form'], [data-controller~='flowchart-canvas']").evaluateAll(elements => elements.map(element => element.outerHTML).join("\n")),
          contentType: "text/html"
        })
        await testInfo.attach("final-browser", { body: await page.screenshot(), contentType: "image/png" })
      } finally {
        const cleanup = fixtureCall("cleanup", token)
        await testInfo.attach("fixture-cleanup", { body: JSON.stringify(cleanup, null, 2), contentType: "application/json" })
        expect(cleanup.remaining_entities).toBe(0)
        expect(cleanup.remaining_flowcharts).toBe(0)
        expect(cleanup.baseline).toEqual(fixture.baseline)
      }
    }
  }
})

// Passive observation only: input is supplied exclusively by Playwright's mouse
// API. Recording isTrusted makes synthetic dispatch unable to satisfy the proof.
export async function observeDrag(page) {
  await page.evaluate(() => {
    window.__dragEvents = []
    for (const type of ["mousedown", "mousemove", "mouseup", "dragstart", "dragover", "drop", "dragend"]) {
      document.addEventListener(type, event => {
        const target = event.target.closest?.("[data-attribute-item], [data-element-id], svg.flowchart-svg")
        if (target) window.__dragEvents.push({
          type, trusted: event.isTrusted, x: event.clientX, y: event.clientY,
          id: target.getAttribute("data-attr-name-slug") || target.getAttribute("data-element-id")
        })
      }, { capture: true })
    }
  })
  return () => page.evaluate(() => window.__dragEvents)
}

export { expect }
