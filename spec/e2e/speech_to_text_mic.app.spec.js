import { expect } from "@playwright/test"
import { isolatedAssistantTest as test } from "./support/assistant_test.js"
import { verifyRecordedTranscription } from "./helpers/speech_runtime.js"
import { waitForAssistantController } from "./helpers/assistant_ui.js"

// App-backed: the assistant mic on /admin/assistant. Chromium on this host has
// no capture device, so getUserMedia throws NotFoundError unless the browser
// is launched with a fake audio input (see the chromium-media project).
const BASE = process.env.APP_BASE_URL

test.use({ ignoreHTTPSErrors: true })

test.describe("assistant microphone", () => {
  test.skip(!BASE, "set APP_BASE_URL to run app-backed e2e (see spec/e2e/README.md)")

  test("clicking the mic starts recording", async ({ page, assistantThread }) => {
    test.setTimeout(90000)
    const response = await page.goto(`${BASE}${assistantThread.path}`)
    expect(response?.ok()).toBeTruthy()

    const button = page.locator("[data-speech-to-text-target='button']").first()
    await expect(button).toBeVisible()
    await waitForAssistantController(page, "speech-to-text")
    await button.click()

    const status = page.locator("[data-speech-to-text-target='status']").first()
    await expect(status).toHaveText("Recording…")
    await expect(button).toHaveAttribute("aria-label", "Stop recording")
    await expect(button).toHaveAttribute("aria-pressed", "true")
    await expect(button).toHaveClass(/btn-danger/)
  })

  test("real recorded audio is decoded and transcribed through the local HTTP provider", async ({ page, request, assistantThread }) => {
    test.setTimeout(120000)
    const response = await page.goto(`${BASE}${assistantThread.path}`)
    expect(response?.ok()).toBeTruthy()
    await verifyRecordedTranscription(page, request, assistantThread.id)
  })
})
