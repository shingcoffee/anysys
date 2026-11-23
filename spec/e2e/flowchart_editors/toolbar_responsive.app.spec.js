import { test, expect } from "@playwright/test"
import { writeFile } from "node:fs/promises"

const BASE = process.env.APP_BASE_URL
const EDIT_PATH = process.env.FLOWCHART_EDIT_PATH

test.describe("flowchart toolbar / responsive Rails layout", () => {
  test.skip(!BASE || !EDIT_PATH, "set APP_BASE_URL and FLOWCHART_EDIT_PATH to an editable flowchart")

  for (const width of [320, 1440]) {
    for (const locale of ["en", "zh-CN"]) {
      test(`Save and editor regions stay within ${width}px (${locale})`, async ({ page }, testInfo) => {
        await page.setViewportSize({ width, height: 900 })
        await page.route("**/*", route => {
          const url = new URL(route.request().url())
          return url.protocol.startsWith("http") && url.origin !== new URL(BASE).origin ? route.abort() : route.continue()
        })
        const url = new URL(EDIT_PATH, BASE)
        url.searchParams.set("locale", locale)
        const response = await page.goto(url.href, { waitUntil: "domcontentloaded" })
        expect(response?.status()).toBe(200)
        await page.waitForFunction(() => {
          const root = document.querySelector('[data-controller~="flowchart-canvas"]')
          return window.Stimulus?.getControllerForElementAndIdentifier(root, "flowchart-canvas")?.isCanvasReady
        })
        await page.evaluate(() => document.fonts.ready)

        const toolbar = page.locator('[data-controller~="toolbar"]')
        const save = toolbar.locator('button[data-action="click->toolbar#save"]')
        await expect(save).toBeVisible()
        const geometry = await save.evaluate(button => {
          const box = element => {
            const rect = element.getBoundingClientRect()
            return { left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom, width: rect.width }
          }
          const saveBox = box(button)
          const clippingAncestors = []
          for (let ancestor = button.parentElement; ancestor; ancestor = ancestor.parentElement) {
            const bounds = box(ancestor)
            const overflow = getComputedStyle(ancestor).overflowX
            if (["hidden", "clip", "auto", "scroll"].includes(overflow) &&
                (saveBox.left < bounds.left - 0.5 || saveBox.right > bounds.right + 0.5)) {
              clippingAncestors.push({ tag: ancestor.tagName, overflow, ...bounds })
            }
          }
          // Deliberately measure the page's editor regions, not the closed
          // off-canvas navigation drawer or the scrollable SVG graph itself.
          const regions = [
            ["header", "header"], ["main", "#main-content"],
            ["editor", '[data-controller~="flowchart-canvas"]'],
            ["toolbar", '[data-controller~="toolbar"]'],
            ["palette", '[data-controller~="element-palette"]'],
            ["canvas", '[data-flowchart-canvas-target="canvasContainer"]']
          ].map(([name, selector]) => ({ name, ...box(document.querySelector(selector)) }))
          const controls = [...button.closest('[data-controller~="toolbar"]').querySelectorAll("button")]
            .filter(control => control.getClientRects().length > 0)
            .map(control => ({ action: control.dataset.action, ...box(control) }))
          return {
            viewportWidth: innerWidth, documentWidth: document.documentElement.scrollWidth,
            mainWidth: document.querySelector("#main-content").clientWidth,
            mainScrollWidth: document.querySelector("#main-content").scrollWidth,
            save: saveBox, clippingAncestors, regions, controls,
            stylesheets: [...document.querySelectorAll('link[rel="stylesheet"]')].map(link => link.href)
          }
        })
        console.log(`FLOWCHART_TOOLBAR_GEOMETRY=${JSON.stringify({ locale, ...geometry })}`)
        const screenshotPath = testInfo.outputPath("responsive-editor.png")
        const geometryPath = testInfo.outputPath("toolbar-geometry.json")
        await page.screenshot({ path: screenshotPath })
        await writeFile(geometryPath, JSON.stringify({ locale, ...geometry }, null, 2))
        await testInfo.attach("toolbar-geometry", { path: geometryPath, contentType: "application/json" })
        await testInfo.attach("responsive-editor", { path: screenshotPath, contentType: "image/png" })

        expect(geometry.save.left).toBeGreaterThanOrEqual(0)
        expect(geometry.save.right).toBeLessThanOrEqual(width)
        expect(geometry.save.top).toBeGreaterThanOrEqual(0)
        expect(geometry.save.bottom).toBeLessThanOrEqual(900)
        expect(geometry.clippingAncestors).toEqual([])
        expect(geometry.documentWidth).toBeLessThanOrEqual(width)
        expect(geometry.mainScrollWidth).toBeLessThanOrEqual(geometry.mainWidth)
        for (const region of [...geometry.regions, ...geometry.controls]) {
          expect(region.left, JSON.stringify(region)).toBeGreaterThanOrEqual(-0.5)
          expect(region.right, JSON.stringify(region)).toBeLessThanOrEqual(width + 0.5)
          expect(region.width, JSON.stringify(region)).toBeGreaterThan(0)
        }
        await save.click({ trial: true })
      })
    }
  }
})
