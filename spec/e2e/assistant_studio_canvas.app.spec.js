import { expect } from "@playwright/test"
import { menuTest as test, menuAssistantPath } from "./helpers/assistant_ui.js"
import { mkdirSync } from "node:fs"
import { fileURLToPath } from "node:url"

const BASE = process.env.APP_BASE_URL
const SHOT_DIR = fileURLToPath(new URL("../../tmp/playwright-assistant-studio", import.meta.url))

test.use({ ignoreHTTPSErrors: true })

const expectNoPageOverflow = async (page) => {
  const geometry = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }))
  expect(geometry.scrollWidth, `horizontal overflow ${geometry.scrollWidth} > ${geometry.clientWidth}`).toBeLessThanOrEqual(
    geometry.clientWidth + 1
  )
}

const dualCardSelector = ".rounded-2xl.border.border-border-subtle.bg-surface.shadow-xs"

test.describe("assistant studio canvas", () => {
  test.skip(!BASE, "set APP_BASE_URL to run app-backed e2e (see spec/e2e/README.md)")

  test("desktop split keeps chat left of a living preview without card chrome", async ({ page }) => {
    test.setTimeout(60_000)
    mkdirSync(SHOT_DIR, { recursive: true })
    await page.setViewportSize({ width: 1280, height: 900 })

    const response = await page.goto(`${BASE}${menuAssistantPath}`)
    expect(response?.ok()).toBeTruthy()

    const chat = page.locator("#assistant-conversation-panel")
    const preview = page.locator("#assistant-preview-panel")
    const composer = page.locator("#ai_assistant_composer")

    await expect(page.getByRole("heading", { name: "AI Assistant" })).toBeVisible()
    await expect(chat).toBeVisible()
    await expect(preview).toBeVisible()
    await expect(composer).toBeVisible()
    await expect(page.getByRole("button", { name: "Send" })).toBeVisible()
    // Copy belongs to the reply it copies, not to a toolbar under the composer.
    await expect(page.locator("[data-role='assistant'] button[data-action='click->ai-assistant#copy']").first()).toBeAttached()
    await expect(page.locator("[data-role='user'] button[data-action='click->ai-assistant#copy']")).toHaveCount(0)
    // exact: the empty pane's "Nothing to preview yet" heading also contains "Preview".
    await expect(page.getByRole("heading", { name: "Preview", exact: true })).toBeVisible()
    await expect(page.locator("[data-dashboard-region='chat']")).toBeVisible()
    await expect(page.locator("[data-dashboard-region='overview']")).toBeVisible()
    await expect(page.getByRole("tablist")).toBeHidden()
    await expect(page.locator(dualCardSelector)).toHaveCount(0)

    const layout = await page.evaluate(() => {
      const chatEl = document.querySelector("#assistant-conversation-panel")
      const previewEl = document.querySelector("#assistant-preview-panel")
      const chatBox = chatEl.getBoundingClientRect()
      const previewBox = previewEl.getBoundingClientRect()
      return {
        chatLeft: chatBox.left,
        chatRight: chatBox.right,
        chatWidth: chatBox.width,
        previewLeft: previewBox.left,
        previewWidth: previewBox.width,
        sameRow: Math.abs(chatBox.top - previewBox.top) < 8,
        // Assert the resolved two-track studio grid rather than a literal arbitrary-value
        // class, so tuning the ratio does not break this test.
        studioTracks: getComputedStyle(chatEl.parentElement).gridTemplateColumns.split(" ").length
      }
    })

    expect(layout.studioTracks).toBe(2)

    expect(layout.sameRow).toBe(true)
    expect(layout.chatLeft).toBeLessThan(layout.previewLeft)
    expect(layout.chatRight).toBeLessThanOrEqual(layout.previewLeft + 2)
    expect(layout.previewWidth).toBeGreaterThanOrEqual(352)
    expect(layout.chatWidth).toBeGreaterThan(layout.previewWidth)
    await expectNoPageOverflow(page)

    await page.screenshot({ path: `${SHOT_DIR}/desktop.png`, fullPage: false })

    const viewLarger = page.getByRole("button", { name: /View larger preview of/ })
    if (await viewLarger.count()) {
      const thumbnail = page.locator("iframe[data-artifact-thumbnail]")
      await expect(thumbnail).toBeVisible()
      // The thumbnail is laid out at a desktop width and scaled down to the rail.
      await expect(thumbnail).toHaveAttribute("src", /embed=1/)
      const fitted = await page.evaluate(() => {
        const viewport = document.querySelector("[data-artifact-preview-target='viewport']")
        const canvas = document.querySelector("[data-artifact-preview-target='canvas']")
        const frame = document.querySelector("iframe[data-artifact-thumbnail]")
        const scale = Number(canvas.style.transform.replace(/[^0-9.]/g, ""))
        return {
          scale,
          canvasWidth: canvas.style.width,
          fitsRail: Math.abs(canvas.getBoundingClientRect().width - viewport.clientWidth) < 2,
          // A window the rail's height, never the page's: a content-tall frame
          // inflates `vh`, and a viewport-sized hero then fills the miniature.
          windowed: Math.abs(frame.contentWindow.innerHeight * scale - viewport.clientHeight) < 2,
          // The rail scrolls the whole framed page rather than clipping it.
          scrolls: viewport.scrollHeight > viewport.clientHeight + 4,
          noSideScroll: viewport.scrollWidth <= viewport.clientWidth + 1
        }
      })
      expect(fitted.canvasWidth).toBe("960px")
      expect(fitted.scale).toBeGreaterThan(0)
      expect(fitted.scale).toBeLessThan(1)
      expect(fitted.fitsRail).toBe(true)
      expect(fitted.windowed).toBe(true)
      expect(fitted.scrolls).toBe(true)
      expect(fitted.noSideScroll).toBe(true)

      const bottom = await page.evaluate(async () => {
        const viewport = document.querySelector("[data-artifact-preview-target='viewport']")
        const framed = document.querySelector("iframe[data-artifact-thumbnail]").contentWindow
        viewport.scrollTop = viewport.scrollHeight
        await new Promise((resolve) => requestAnimationFrame(resolve))
        await new Promise((resolve) => requestAnimationFrame(resolve))
        const page = framed.document.documentElement
        return {
          rail: viewport.scrollTop >= viewport.scrollHeight - viewport.clientHeight - 2,
          // The rail's scroll is handed to the framed page, down to its last pixel.
          framed: framed.scrollY >= page.scrollHeight - framed.innerHeight - 2
        }
      })
      expect(bottom.rail).toBe(true)
      expect(bottom.framed).toBe(true)
      await page.evaluate(() => {
        document.querySelector("[data-artifact-preview-target='viewport']").scrollTop = 0
      })

      await viewLarger.click()
      // Scoped to the preview: the chat list also renders a modal (Delete chat?).
      const dialog = page.locator("dialog[data-artifact-preview-target='dialog']")
      await expect(dialog).toBeVisible()
      // The framed render drops the standalone preview chrome, and stays interactive
      // so the whole page can be scrolled and read.
      const dialogFrame = dialog.locator("[data-artifact-preview-target='frame']")
      await expect(dialogFrame).toHaveAttribute("src", /embed=1/)
      await expect(dialogFrame).not.toHaveAttribute("aria-hidden", "true")
      expect(await dialogFrame.evaluate((el) => getComputedStyle(el).pointerEvents)).toBe("auto")
      await page.screenshot({ path: `${SHOT_DIR}/desktop-preview-dialog.png`, fullPage: false })
      await page.getByRole("button", { name: "Close preview" }).click()
      await expect(dialog).toBeHidden()
    }
  })

  test("tablet and phone reach preview through tabs without overflow", async ({ page }) => {
    test.setTimeout(60_000)
    mkdirSync(SHOT_DIR, { recursive: true })

    for (const viewport of [
      { name: "tablet", width: 768, height: 1024 },
      { name: "phone", width: 390, height: 844 }
    ]) {
      await page.setViewportSize({ width: viewport.width, height: viewport.height })
      const response = await page.goto(`${BASE}${menuAssistantPath}`)
      expect(response?.ok(), viewport.name).toBeTruthy()

      const conversationTab = page.getByRole("tab", { name: "Chat" })
      const previewTab = page.getByRole("tab", { name: "Preview" })
      await expect(conversationTab).toBeVisible()
      await expect(previewTab).toBeVisible()
      await expect(page.locator("#assistant-conversation-panel")).toBeVisible()
      await expect(page.locator("#assistant-preview-panel")).toBeHidden()
      await expect(page.locator("#ai_assistant_composer")).toBeVisible()
      await expectNoPageOverflow(page)
      await page.screenshot({ path: `${SHOT_DIR}/${viewport.name}-conversation.png`, fullPage: false })

      await previewTab.click()
      await expect(previewTab).toHaveAttribute("aria-selected", "true")
      await expect(page.locator("#assistant-preview-panel")).toBeVisible()
      // Visible is not enough: revealing the pane by dropping `hidden` used to
      // leave it `display:block`, which makes flex-col inert and costs the
      // artifact its h-full and its scroll containment.
      expect(
        await page.locator("#assistant-preview-panel").evaluate((el) => getComputedStyle(el).display),
        viewport.name
      ).toBe("flex")
      const paneFills = await page.evaluate(() => {
        const pane = document.querySelector("#assistant-preview-panel")
        const artifact = document.querySelector("#ai_assistant_artifact")
        return artifact.getBoundingClientRect().height >= pane.getBoundingClientRect().height - 1
      })
      expect(paneFills, viewport.name).toBe(true)
      await expect(page.locator("#assistant-conversation-panel")).toBeHidden()
      await expect(page.getByRole("heading", { name: "Preview", exact: true })).toBeVisible()
      await expectNoPageOverflow(page)
      await page.screenshot({ path: `${SHOT_DIR}/${viewport.name}-preview.png`, fullPage: false })
    }
  })
})
