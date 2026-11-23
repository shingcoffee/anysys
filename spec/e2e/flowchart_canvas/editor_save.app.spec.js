import { test, expect } from "../helpers/builder_fixtures.js"

// Tier C (app-backed): Phase 5 behaviour that needs the real editor and
// server — the stale-head 409 banner (reload / overwrite) and Ctrl/Cmd+S,
// the translated subflow preview notice, and validation-list de-duplication.
// Trusted Playwright input only; canvas state is read via page.evaluate.
const BASE = process.env.APP_BASE_URL

const COPY = {
  en: {
    conflict: "This flowchart was saved elsewhere (another tab or user) after you opened it. Reload to get the latest version, or overwrite it with your changes.",
    reload: "Reload",
    overwrite: "Overwrite",
    preview: "Previewing a subflow — fold it to edit"
  },
  "zh-CN": {
    conflict: "打开后，此流程图已在别处（其他标签页或用户）保存。请重新加载以获取最新版本，或用您的修改覆盖。",
    reload: "重新加载",
    overwrite: "覆盖",
    preview: "正在预览子流程，收起后可继续编辑"
  }
}

test.use({ viewport: { width: 1440, height: 1000 }, builderKind: "blank" })

test.describe("flowchart editor — save, preview and validation (app)", () => {
  test.skip(!BASE, "set APP_BASE_URL to run app-backed e2e (see spec/e2e/README.md)")

  for (const locale of ["en", "zh-CN"]) {
    test(`stale head → 409 banner (${locale}); Overwrite saves over it; Ctrl/Cmd+S saves`, async ({ page, builderFixture }) => {
      test.setTimeout(120_000)
      await page.context().addCookies([{ name: "locale", value: locale, url: BASE }])
      const other = await page.context().newPage()
      await openEditor(page, builderFixture)
      await openEditor(other, builderFixture)
      const startVersions = builderFixture.snapshot().flowchart.version_count

      await addFromPalette(other, "process")
      expect((await saveWithShortcut(other, builderFixture)).status()).toBe(200)
      expect(builderFixture.snapshot().flowchart.version_count).toBe(startVersions + 1)

      await addFromPalette(page, "decision")
      const conflict = await saveWithShortcut(page, builderFixture)
      expect(conflict.status()).toBe(409)
      const banner = page.locator("[data-flowchart-canvas-target='saveConflictBanner']")
      await expect(banner).toBeVisible()
      await expect(banner.locator("[data-flowchart-canvas-target='saveConflictMessage']")).toHaveText(COPY[locale].conflict)
      await expect(banner.getByRole("button", { name: COPY[locale].reload })).toBeVisible()
      await expect(page.locator("[data-toolbar-target='saveDot']")).toBeVisible()
      expect(builderFixture.snapshot().flowchart.version_count).toBe(startVersions + 1)

      const overwrite = page.waitForResponse(response => isUpdate(response, builderFixture))
      await banner.getByRole("button", { name: COPY[locale].overwrite }).click()
      expect((await overwrite).status()).toBe(200)
      await expect(banner).toBeHidden()
      await expect(page.locator("[data-toolbar-target='saveDot']")).toBeHidden()
      const saved = builderFixture.snapshot().flowchart
      expect(saved.version_count).toBe(startVersions + 2)
      expect(saved.configuration.elements.map(el => el.type).sort()).toEqual(["decision", "end", "start"])
      expect(builderFixture.errors.filter(error => !isExpectedConflictLog(error))).toEqual([])
    })
  }

  test("Reload after a conflict discards local edits without a leave prompt and shows the latest head", async ({ page, builderFixture }) => {
    test.setTimeout(120_000)
    const dialogs = []
    page.on("dialog", dialog => { dialogs.push(dialog.type()); dialog.dismiss() })
    const other = await page.context().newPage()
    await openEditor(page, builderFixture)
    await openEditor(other, builderFixture)

    await addFromPalette(other, "loop")
    expect((await saveWithShortcut(other, builderFixture)).status()).toBe(200)
    await addFromPalette(page, "decision")
    expect((await saveWithShortcut(page, builderFixture)).status()).toBe(409)

    await Promise.all([
      page.waitForEvent("load"),
      page.locator("[data-flowchart-canvas-target='saveConflictBanner']").getByRole("button", { name: COPY.en.reload }).click()
    ])
    await waitForCanvas(page)
    expect(dialogs).toEqual([])
    expect((await canvasTypes(page)).sort()).toEqual(["end", "loop", "start"])
    await expect(page.locator("[data-flowchart-canvas-target='saveConflictBanner']")).toBeHidden()
  })

  for (const locale of ["en", "zh-CN"]) {
    test(`subflow preview shows the translated notice and expand/fold leave the editor clean (${locale})`, async ({ page, builderFixture }) => {
      test.setTimeout(120_000)
      await page.context().addCookies([{ name: "locale", value: locale, url: BASE }])
      await openEditor(page, builderFixture)
      const chip = page.locator(
        `[data-element-palette-target='flowchartsList'] [data-flowchart-element='subflow'][data-flowchart-id='${builderFixture.launched_flowchart_id}']`
      )
      await expect(chip).toBeVisible()
      await chip.dblclick()
      const subflowId = await page.evaluate(() =>
        document.querySelector('[data-controller*="flowchart-canvas"]').flowchartCanvas.elements.find(el => el.type === "subflow").id)
      await page.locator("button[data-action='click->toolbar#save']").click()
      const saveDot = page.locator("[data-toolbar-target='saveDot']")
      await expect(saveDot).toBeHidden()
      const collapsed = await canvasConfiguration(page)

      const notice = page.locator("[data-flowchart-canvas-target='previewNotice']")
      await expect(notice).toBeHidden()
      await page.locator(`.element-layer > [data-element-id='${subflowId}'] [data-subflow-toggle]`).click()
      await expect(notice).toBeVisible()
      await expect(notice).toHaveText(COPY[locale].preview)
      const fold = page.locator(".element-layer .fold-icon")
      await expect(fold).toHaveCount(1)
      await expect(saveDot).toBeHidden()

      await fold.click()
      await expect(notice).toBeHidden()
      await expect(saveDot).toBeHidden()
      expect(await canvasConfiguration(page)).toEqual(collapsed)
      expect(builderFixture.errors).toEqual([])
    })
  }

  test('a second End is labelled "End 2" and the issue list has one row per fault', async ({ page, builderFixture }) => {
    test.setTimeout(120_000)
    await openEditor(page, builderFixture)
    await addFromPalette(page, "end")
    const labels = await page.evaluate(() =>
      document.querySelector('[data-controller*="flowchart-canvas"]').flowchartCanvas.elements
        .filter(el => el.type === "end").map(el => el.label))
    expect(labels).toEqual(["End", "End 2"])

    const validation = page.waitForResponse(response =>
      response.request().method() === "POST" && response.url().includes("/validation"))
    await page.locator("button[data-action='click->flowchart-canvas#validate']").click()
    expect((await validation).ok()).toBe(true)
    const rows = page.locator("[data-flowchart-canvas-target='validationList'] button[data-action='click->flowchart-canvas#focusValidationIssue']")
    await expect(rows.first()).toBeVisible()
    const issues = await rows.evaluateAll(buttons => buttons.map(button => ({
      key: [button.dataset.elementId, button.dataset.connectionId, button.dataset.rule, button.dataset.field].join("|"),
      text: button.textContent.replace(/\s+/g, " ").trim()
    })))
    expect(new Set(issues.map(issue => issue.key)).size).toBe(issues.length)
    expect(new Set(issues.map(issue => issue.text)).size).toBe(issues.length)
    expect(issues.some(issue => issue.key.includes("duplicate_label"))).toBe(false)
    expect(builderFixture.errors).toEqual([])
  })
})

async function openEditor(page, fixture) {
  const loaded = await page.goto(BASE + fixture.flowchart_edit_path)
  expect(loaded?.ok()).toBeTruthy()
  await waitForCanvas(page)
}

async function waitForCanvas(page) {
  await page.waitForFunction(() => {
    const root = document.querySelector('[data-controller~="flowchart-canvas"]')
    return root && window.Stimulus?.getControllerForElementAndIdentifier(root, "flowchart-canvas")?.isCanvasReady
  })
  await expect(page.locator("[data-flowchart-canvas-target='canvasWrapper'] svg.flowchart-svg")).toBeVisible()
}

// Chrome logs every non-2xx fetch; the 409 is the behaviour under test.
const isExpectedConflictLog = error =>
  error.type === "console" && error.message.includes("status of 409 (Conflict)")

function isUpdate(response, fixture) {
  return new URL(response.url()).pathname === fixture.flowchart_edit_path.replace(/\/edit$/, "") &&
    response.request().method() === "PATCH"
}

async function addFromPalette(page, type) {
  const before = (await canvasTypes(page)).length
  await page.locator(`[data-controller='element-palette'] [data-flowchart-element='${type}']`).dblclick()
  await expect.poll(async () => (await canvasTypes(page)).length).toBe(before + 1)
}

// Ctrl/Cmd+S must save from anywhere on the page and suppress the browser's
// Save Page dialog (defaultPrevented once every listener has run).
async function saveWithShortcut(page, fixture) {
  const pending = page.waitForResponse(response => isUpdate(response, fixture))
  const prevented = page.evaluate(() => new Promise(resolve => {
    const listener = event => {
      if (event.key.toLowerCase() !== "s") return
      window.removeEventListener("keydown", listener)
      resolve(event.defaultPrevented)
    }
    window.addEventListener("keydown", listener)
  }))
  await page.keyboard.press("ControlOrMeta+s")
  expect(await prevented).toBe(true)
  return pending
}

function canvasTypes(page) {
  return page.evaluate(() =>
    document.querySelector('[data-controller*="flowchart-canvas"]').flowchartCanvas.elements.map(el => el.type))
}

function canvasConfiguration(page) {
  return page.evaluate(() =>
    structuredClone(document.querySelector('[data-controller*="flowchart-canvas"]').flowchartCanvas.getConfiguration()))
}
