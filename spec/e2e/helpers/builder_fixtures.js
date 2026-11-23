import { test as base, expect } from "@playwright/test"
import { randomUUID } from "node:crypto"
import { runRails } from "./rails_runner.js"

function fixtureCall(method, token, kind) {
  const output = runRails(`
    require Rails.root.join("spec/e2e/helpers/builder_fixtures")
    result = BuilderBrowserFixtures.${method}(${JSON.stringify(token)}${kind ? `, ${JSON.stringify(kind)}` : ""})
    puts "BUILDER_FIXTURE=" + result.to_json
  `, { timeout: 60000 })
  const result = output.split("\n").find(line => line.startsWith("BUILDER_FIXTURE="))
  if (!result) throw new Error(`Builder fixture ${method} did not report a result`)
  return JSON.parse(result.slice("BUILDER_FIXTURE=".length))
}

export const test = base.extend({
  builderKind: ["entity", { option: true }],
  builderFixture: async ({ page, builderKind }, use, testInfo) => {
    const errors = []
    page.on("pageerror", error => errors.push({ type: "pageerror", message: error.message, stack: error.stack }))
    page.on("console", message => {
      if (message.type() === "error") errors.push({ type: "console", message: message.text() })
    })
    const token = randomUUID().replaceAll("-", "")
    const fixture = fixtureCall("create", token, builderKind)
    fixture.initialSnapshot = fixture.snapshot
    fixture.snapshot = () => fixtureCall("snapshot", token)
    fixture.errors = errors
    try {
      await testInfo.attach("fixture-created", { body: JSON.stringify(fixture, null, 2), contentType: "application/json" })
      await use(fixture)
    } finally {
      try {
        await testInfo.attach("browser-errors", { body: JSON.stringify(errors, null, 2), contentType: "application/json" })
        await testInfo.attach("fixture-final", { body: JSON.stringify(fixture.snapshot(), null, 2), contentType: "application/json" })
        await testInfo.attach("rendered-dom", {
          body: await page.locator("[data-controller~='flowchart-form'], [data-controller~='flowchart-canvas']").evaluateAll(elements => elements.map(element => element.outerHTML).join("\n")),
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

// Passive observation only: input is supplied exclusively by Playwright's
// pointer/keyboard APIs. Recording isTrusted makes synthetic dispatch unable
// to satisfy the proof.
export async function observeBuilderInput(page) {
  await page.evaluate(() => {
    window.__builderEvents = []
    for (const type of ["mousedown", "mouseup", "dblclick", "dragstart", "dragover", "drop", "dragend", "keydown"]) {
      document.addEventListener(type, event => {
        const target = event.target.closest?.(
          "[data-flowchart-element], [data-element-id], [data-flowchart-canvas-target='canvasContainer'], [data-step-picker], [data-property-editor-target='cancelButton'], svg.flowchart-svg"
        )
        window.__builderEvents.push({
          type,
          trusted: event.isTrusted,
          key: event.key,
          id: target?.getAttribute("data-flowchart-element") || target?.getAttribute("data-element-id") || target?.getAttribute("data-property-editor-target") || null
        })
      }, { capture: true })
    }
  })
  return () => page.evaluate(() => window.__builderEvents)
}

export { expect }
