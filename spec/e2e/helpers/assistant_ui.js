import { test as base, expect } from "@playwright/test"

export const menuAssistantPath = `/81721200/admin/assistant?conversation=${process.env.E2E_ASSISTANT_CONVERSATION_ID || ""}`

// Visibility is not readiness: route interception and Turbo replacement can
// leave rendered controls visible while child controllers are still importing.
export async function waitForAssistantController(page, identifier = "ai-assistant") {
  await page.waitForFunction(identifier => {
    const mount = document.querySelector(`[data-controller~='${identifier}']`)
    return mount && !!window.Stimulus?.getControllerForElementAndIdentifier(mount, identifier)
  }, identifier)
}

export async function waitForAssistantStreams(page) {
  const sources = page.locator("[data-controller~='ai-assistant'] > turbo-cable-stream-source")
  await expect(sources).toHaveCount(2)
  // Turbo Rails sets this only after Action Cable confirms the subscription.
  // A mounted controller can send before these broadcasts are receivable.
  for (const source of await sources.all()) await expect(source).toHaveAttribute("connected", "", { timeout: 60000 })
}

// Real Rails rendering and mention reads; menu/layout checks never enqueue a
// provider job. This uses the same page.route fixture boundary as settings UI.
export const menuTest = base.extend({
  assistantRequestGuard: [async ({ context }, use) => {
    const writes = []
    await context.route("**/*", async route => {
      const request = route.request()
      const url = new URL(request.url())
      if (!["GET", "HEAD"].includes(request.method()) && /\/admin\/(?:modules\/ai_assistant|assistant)\//.test(url.pathname)) {
        writes.push({ method: request.method(), path: url.pathname })
        return route.fulfill({ status: 204, body: "" })
      }
      return route.continue()
    })
    await use(writes)
    expect(writes, "menu/layout checks must not post assistant turns or vendor jobs").toEqual([])
  }, { auto: true }]
})
