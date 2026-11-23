import { test, expect, observeBuilderInput } from "./helpers/builder_fixtures.js"

// Tier C (app-backed): drives the whole flowchart builder journey in the real
// app — New-form templates, palette HTML5 drag / double-click, step picking,
// toolbar save/versioning, open+Cancel, restore, copy/paste, Backspace in the
// property panel, Validate, and the test runner.
//
// Trusted Playwright pointer/keyboard input only. Canvas state is read via
// page.evaluate on the live flowchartCanvas instance; editor methods are never
// invoked to drive actions.
const BASE = process.env.APP_BASE_URL

const TEMPLATES = {
  blank: {
    types: ["start", "end"],
    actions: [],
    configs: [],
    labels: ["Start", "End"]
  },
  page_record: {
    types: ["start", "process", "process", "process", "end"],
    actions: ["build_contract", "validate_contract", "save_model"],
    configs: [
      { contractClass: "EntityEntryContract", modelVariable: "model" },
      {},
      {}
    ],
    labels: ["Start", "Build Contract", "Validate", "Save Model", "End"]
  }
}

const STEP_DEFAULTS = [
  { value: "new_model", search: "New record", config: { resultVar: "model" } },
  { value: "build_contract", search: "Build Contract", config: { contractClass: "EntityEntryContract", modelVariable: "model" } },
  { value: "validate_contract", search: "Validate the Reform", config: {} },
  { value: "save_model", search: "Save record", config: {} }
]

test.use({ viewport: { width: 1440, height: 1000 } })

test.describe("flowchart builder journey", () => {
  test.skip(!BASE, "set APP_BASE_URL to run app-backed e2e (see spec/e2e/README.md)")

  test.describe("New form templates", () => {
    test.use({ builderKind: "entity" })

    for (const [template, expected] of Object.entries(TEMPLATES)) {
      test(`creates ${template} via the New form and the graph validates`, async ({ page, builderFixture }, testInfo) => {
        test.setTimeout(90_000)
        await createViaNewForm(page, builderFixture, template)
        await waitForCanvas(page)
        const graph = await canvasGraph(page)
        assertTemplateGraph(graph, expected)
        const persisted = builderFixture.snapshot().flowchart
        expect(persisted).toBeTruthy()
        assertTemplateGraph({
          elements: persisted.configuration.elements,
          connections: persisted.configuration.connections
        }, expected)
        expect(persisted.version_count).toBe(1)

        await validateAndExpectNoErrors(page)
        expect(builderFixture.errors).toEqual([])
        await testInfo.attach(`${template}-graph`, {
          body: JSON.stringify({ graph, persisted }, null, 2),
          contentType: "application/json"
        })
      })
    }
  })

  test.describe("blank palette and step picker", () => {
    test.use({ builderKind: "entity" })

    test("drags Process below Start, double-clicks End, and picks step defaults", async ({ page, builderFixture }, testInfo) => {
      test.setTimeout(180_000)
      await createViaNewForm(page, builderFixture, "blank")
      await waitForCanvas(page)
      const events = await observeBuilderInput(page)

      const before = await canvasGraph(page)
      expect(before.elements.map(el => el.type)).toEqual(["start", "end"])
      const start = before.elements.find(el => el.type === "start")
      await dragProcessBelowStart(page, start.id)
      await expect.poll(async () => (await canvasGraph(page)).elements.filter(el => el.type === "process").length).toBe(1)
      const afterDrag = await canvasGraph(page)
      const dragged = afterDrag.elements.find(el => el.type === "process")
      expect(dragged.y).toBeGreaterThan(start.y)

      // One action per Process box: three more processes so each of the four
      // step-picker actions has its own box.
      for (let index = 0; index < 3; index++) {
        await page.locator("[data-controller='element-palette'] [data-flowchart-element='process']").dblclick()
        await expect.poll(async () => (await canvasGraph(page)).elements.filter(el => el.type === "process").length).toBe(index + 2)
      }

      await page.locator("[data-controller='element-palette'] [data-flowchart-element='end']").dblclick()
      await expect.poll(async () => (await canvasGraph(page)).elements.filter(el => el.type === "end").length).toBe(2)

      const emptyProcesses = (await canvasGraph(page)).elements.filter(el => el.type === "process")
      expect(emptyProcesses).toHaveLength(4)
      for (let index = 0; index < STEP_DEFAULTS.length; index++) {
        await pickActionOnProcess(page, emptyProcesses[index].id, STEP_DEFAULTS[index])
      }

      const graph = await canvasGraph(page)
      const processes = graph.elements.filter(el => el.type === "process")
      expect(processes.map(el => el.properties.steps[0].action)).toEqual(STEP_DEFAULTS.map(step => step.value))
      processes.forEach((el, index) => {
        expect(el.properties.steps[0].config ?? {}).toMatchObject(STEP_DEFAULTS[index].config)
      })

      const input = await events()
      expect(input.some(event => event.type === "dragstart" && event.trusted && event.id === "process")).toBe(true)
      expect(input.some(event => event.type === "drop" && event.trusted)).toBe(true)
      expect(input.some(event => event.type === "dblclick" && event.trusted && event.id === "end")).toBe(true)
      expect(builderFixture.errors).toEqual([])
      await testInfo.attach("blank-palette-picker", {
        body: JSON.stringify({ afterDrag, graph, input }, null, 2),
        contentType: "application/json"
      })
    })
  })

  test.describe("seeded blank flowchart", () => {
    test.use({ builderKind: "blank" })

    test("save once writes one new version and unchanged save writes none", async ({ page, builderFixture }, testInfo) => {
      test.setTimeout(90_000)
      await openEditor(page, builderFixture)
      const initialCount = builderFixture.initialSnapshot.flowchart.version_count
      expect(initialCount).toBe(1)

      await page.locator("[data-controller='element-palette'] [data-flowchart-element='process']").dblclick()
      await expect.poll(async () => (await canvasGraph(page)).elements.some(el => el.type === "process")).toBe(true)

      await toolbarSave(page, builderFixture)
      const afterFirst = builderFixture.snapshot().flowchart
      expect(afterFirst.version_count).toBe(initialCount + 1)
      expect(afterFirst.version_id).not.toBe(builderFixture.initialSnapshot.flowchart.version_id)

      await toolbarSave(page, builderFixture)
      const afterSecond = builderFixture.snapshot().flowchart
      expect(afterSecond.version_count).toBe(afterFirst.version_count)
      expect(afterSecond.version_id).toBe(afterFirst.version_id)
      expect(builderFixture.errors).toEqual([])
      await testInfo.attach("save-versions", {
        body: JSON.stringify({ initialCount, afterFirst, afterSecond }, null, 2),
        contentType: "application/json"
      })
    })

    test("restore previous version reloads that canvas", async ({ page, builderFixture }, testInfo) => {
      test.setTimeout(90_000)
      await openEditor(page, builderFixture)
      page.once("dialog", dialog => dialog.accept())

      await page.locator("[data-controller='element-palette'] [data-flowchart-element='process']").dblclick()
      await expect.poll(async () => (await canvasGraph(page)).elements.filter(el => el.type === "process").length).toBe(1)
      await toolbarSave(page, builderFixture)
      const kept = await canvasGraph(page)
      const keptVersion = builderFixture.snapshot().flowchart.versions.at(-1)

      await page.locator("[data-controller='element-palette'] [data-flowchart-element='process']").dblclick()
      await expect.poll(async () => (await canvasGraph(page)).elements.filter(el => el.type === "process").length).toBe(2)
      await toolbarSave(page, builderFixture)

      // Bottom-panel tabs are inside a hidden panel; Validate opens it so History is clickable.
      await page.locator("button[data-action='click->flowchart-canvas#validate']").click()
      await page.locator("[data-flowchart-canvas-target='bottomTab'][data-tab='history']").click()
      const restore = page.locator(`[data-action='click->flowchart-canvas#restoreVersion'][data-version-number='${keptVersion.version_number}']`)
      await expect(restore).toBeVisible()
      await restore.click()
      await expect.poll(async () => (await canvasGraph(page)).elements.filter(el => el.type === "process").length).toBe(1)
      const restored = await canvasGraph(page)
      expect(restored.elements.map(el => el.type)).toEqual(kept.elements.map(el => el.type))
      await expect(page.locator("[data-toolbar-target='saveDot']")).toBeHidden()
      expect(builderFixture.errors).toEqual([])
      await testInfo.attach("restore", {
        body: JSON.stringify({ kept, restored, keptVersion }, null, 2),
        contentType: "application/json"
      })
    })

    test("Run test reports success without a new version", async ({ page, builderFixture }, testInfo) => {
      test.setTimeout(90_000)
      await openEditor(page, builderFixture)
      const before = builderFixture.snapshot().flowchart.version_count

      await page.locator("button[data-action='click->flowchart-canvas#toggleTestPanel']").click()
      const input = page.locator("[data-flowchart-canvas-target='testInput']")
      await expect(input).toBeVisible()
      await input.fill("{}")
      const trace = page.waitForResponse(response => response.request().method() === "POST" && response.url().includes("/traces"))
      await page.locator("[data-flowchart-canvas-target='testRunButton']").click()
      const result = await (await trace).json()
      expect(result.success, appDefect("test runner did not return success", result)).toBe(true)

      const status = page.locator("[data-flowchart-canvas-target='testStatus']")
      await expect(status).toBeVisible()
      await expect(status).toContainClass("bg-green-100")
      expect(builderFixture.snapshot().flowchart.version_count).toBe(before)
      expect(builderFixture.errors).toEqual([])
      await testInfo.attach("test-run", {
        body: JSON.stringify({ before, result }, null, 2),
        contentType: "application/json"
      })
    })
  })

  test.describe("seeded simple flowchart", () => {
    test.use({ builderKind: "simple" })

    test("open + Cancel on Start and a process leaves no unsaved dot", async ({ page, builderFixture }) => {
      test.setTimeout(90_000)
      await openEditor(page, builderFixture)
      const saveDot = page.locator("[data-toolbar-target='saveDot']")
      await expect(saveDot).toBeHidden()

      await openNode(page, "start_1")
      await visibleCancel(page).click()
      await expect(page.locator("[data-flowchart-canvas-target='propertySidebar']")).toBeHidden()
      await expectSaveDotStaysHidden(saveDot)

      await openNode(page, "process_1")
      await visibleCancel(page).click()
      await expect(page.locator("[data-flowchart-canvas-target='propertySidebar']")).toBeHidden()
      await expectSaveDotStaysHidden(saveDot)
      expect(builderFixture.errors).toEqual([])
    })

    test("copy/paste a process twice yields independent copies", async ({ page, builderFixture }, testInfo) => {
      test.setTimeout(90_000)
      await openEditor(page, builderFixture)
      const seeded = await page.evaluate(() => {
        const canvas = document.querySelector('[data-controller*="flowchart-canvas"]').flowchartCanvas
        const step = canvas.elements.find(el => el.id === "process_1").properties.steps[0]
        return { id: step.id, action: step.action, config: { ...step.config } }
      })
      expect(seeded.action).toBe("log")
      expect(seeded.config).toMatchObject({ messageTemplate: "seed-log", logLevel: "info", logger: "rails" })

      const original = page.locator(".element-layer > [data-element-id='process_1']")
      await original.click()
      await page.keyboard.press("Control+c")
      await page.keyboard.press("Control+v")
      await page.keyboard.press("Control+v")
      await expect.poll(async () => (await canvasGraph(page)).elements.filter(el => el.type === "process").length).toBe(3)

      const graph = await canvasGraph(page)
      const processes = graph.elements.filter(el => el.type === "process")
      const ids = processes.map(el => el.id)
      expect(new Set(ids).size).toBe(3)
      expect(ids).toContain("process_1")
      const copies = processes.filter(el => el.id !== "process_1")
      expect(copies).toHaveLength(2)
      copies.forEach(copy => {
        expect(copy.id).not.toBe("process_1")
        expect(copy.x !== processes.find(el => el.id === "process_1").x || copy.y !== processes.find(el => el.id === "process_1").y).toBe(true)
        expect(copy.properties.steps[0].action).toBe("log")
        expect(copy.properties.steps[0].config).toEqual(seeded.config)
      })

      const topCopyId = await page.evaluate(() => {
        const canvas = document.querySelector('[data-controller*="flowchart-canvas"]').flowchartCanvas
        return canvas.selectedElements[0]?.id
      })
      expect(copies.map(el => el.id)).toContain(topCopyId)
      const otherCopyId = copies.find(el => el.id !== topCopyId).id
      const topCopy = page.locator(`.element-layer > [data-element-id='${topCopyId}']`)
      const box = await topCopy.boundingBox()
      expect(box).not.toBeNull()
      await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2)
      await page.mouse.down()
      await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2 + 150, { steps: 24 })
      await page.mouse.up()

      await openNode(page, topCopyId)
      await page.locator("[data-flowchart-canvas-target='propertySidebar'] [data-action='click->property-editor#toggleStep']").click()
      const message = page.locator("[data-flowchart-canvas-target='propertySidebar'] [data-config-input='messageTemplate']")
      await expect(message).toBeVisible()
      await message.fill("copy-log")
      const pending = page.waitForResponse(response =>
        new URL(response.url()).pathname === builderFixture.flowchart_edit_path.replace(/\/edit$/, "") &&
        response.request().method() === "PATCH")
      await page.locator("[data-flowchart-canvas-target='propertySidebar'] [data-property-editor-target='saveButton']").click()
      expect((await pending).ok()).toBe(true)

      const proof = await page.evaluate(({ sourceId, editedId, otherId, originalStepId, originalConfig }) => {
        const canvas = document.querySelector('[data-controller*="flowchart-canvas"]').flowchartCanvas
        const byId = id => canvas.elements.find(el => el.id === id)
        const source = byId(sourceId)
        const edited = byId(editedId)
        const other = byId(otherId)
        const steps = [source, edited, other].map(el => el.properties.steps[0])
        return {
          stepIds: steps.map(step => step.id),
          sourceConfig: { ...source.properties.steps[0].config },
          otherConfig: { ...other.properties.steps[0].config },
          editedConfig: { ...edited.properties.steps[0].config },
          sourceStepId: source.properties.steps[0].id,
          originalStepId,
          originalConfig,
          sharedProperties: source.properties === edited.properties || source.properties === other.properties || edited.properties === other.properties,
          sharedSteps: source.properties.steps === edited.properties.steps || source.properties.steps === other.properties.steps || edited.properties.steps === other.properties.steps,
          sharedStep: source.properties.steps[0] === edited.properties.steps[0] || source.properties.steps[0] === other.properties.steps[0] || edited.properties.steps[0] === other.properties.steps[0],
          sharedConfig: source.properties.steps[0].config === edited.properties.steps[0].config || source.properties.steps[0].config === other.properties.steps[0].config || edited.properties.steps[0].config === other.properties.steps[0].config
        }
      }, { sourceId: "process_1", editedId: topCopyId, otherId: otherCopyId, originalStepId: seeded.id, originalConfig: seeded.config })

      expect(new Set(proof.stepIds).size).toBe(3)
      expect(proof.sourceStepId).toBe(seeded.id)
      expect(proof.sourceConfig).toEqual(seeded.config)
      expect(proof.otherConfig).toEqual(seeded.config)
      expect(proof.editedConfig.messageTemplate).toBe("copy-log")
      expect(proof.sharedProperties).toBe(false)
      expect(proof.sharedSteps).toBe(false)
      expect(proof.sharedStep).toBe(false)
      expect(proof.sharedConfig).toBe(false)
      expect(builderFixture.errors).toEqual([])
      await testInfo.attach("paste-independence", {
        body: JSON.stringify({ seeded, processes, proof }, null, 2),
        contentType: "application/json"
      })
    })

    test("Backspace with the property panel Cancel focused keeps the element", async ({ page, builderFixture }) => {
      test.setTimeout(90_000)
      await openEditor(page, builderFixture)
      await openNode(page, "process_1")
      const cancel = visibleCancel(page)
      await expect(cancel).toBeVisible()
      await cancel.focus()
      await expect(cancel).toBeFocused()
      await page.keyboard.press("Backspace")
      await expect(page.locator(".element-layer > [data-element-id='process_1']")).toHaveCount(1)
      const graph = await canvasGraph(page)
      expect(graph.elements.some(el => el.id === "process_1")).toBe(true)
      expect(builderFixture.errors).toEqual([])
    })
  })

  test.describe("seeded decision flowchart", () => {
    test.use({ builderKind: "decision" })

    test("test panel highlights only the taken branch, numbers badges 1, 2, 3…, and shows the decision branch", async ({ page, builderFixture }, testInfo) => {
      test.setTimeout(120_000)
      await openEditor(page, builderFixture)
      const before = builderFixture.snapshot().flowchart.version_count

      const yesRun = await runTestPanel(page, { params: { amount: "150" } })
      expect(yesRun.success, appDefect("Yes-branch test run did not succeed", yesRun)).toBe(true)
      expectTakenBranch(yesRun, {
        takenId: "process_high",
        skippedId: "process_low",
        branch: "Yes",
        takenLabel: "High value",
        skippedLabel: "Low value"
      })
      await expectBranchOverlay(page, {
        takenId: "process_high",
        skippedId: "process_low",
        badges: { start_1: "1", decision_1: "2", process_high: "3", end_1: "4" }
      })
      await expect(page.locator("[data-flowchart-canvas-target='testOutput']")).toContainText("Check amount → Yes")
      await expect(page.locator("[data-flowchart-canvas-target='testOutput']")).toContainText("High value")
      await expect(page.locator("[data-flowchart-canvas-target='testOutput']")).not.toContainText("Low value")

      const noRun = await runTestPanel(page, { params: { amount: "50" } })
      expect(noRun.success, appDefect("No-branch test run did not succeed", noRun)).toBe(true)
      expectTakenBranch(noRun, {
        takenId: "process_low",
        skippedId: "process_high",
        branch: "No",
        takenLabel: "Low value",
        skippedLabel: "High value"
      })
      await expectBranchOverlay(page, {
        takenId: "process_low",
        skippedId: "process_high",
        badges: { start_1: "1", decision_1: "2", process_low: "3", end_1: "4" }
      })
      await expect(page.locator("[data-flowchart-canvas-target='testOutput']")).toContainText("Check amount → No")
      await expect(page.locator("[data-flowchart-canvas-target='testOutput']")).toContainText("Low value")
      await expect(page.locator("[data-flowchart-canvas-target='testOutput']")).not.toContainText("High value")

      expect(builderFixture.snapshot().flowchart.version_count).toBe(before)
      expect(builderFixture.errors).toEqual([])
      await testInfo.attach("decision-branches", {
        body: JSON.stringify({ before, yesRun, noRun }, null, 2),
        contentType: "application/json"
      })
    })
  })

  test.describe("seeded page_record flowchart", () => {
    test.use({ builderKind: "page_record" })

    test("empty params lists the required-field error in the failure banner", async ({ page, builderFixture }, testInfo) => {
      test.setTimeout(90_000)
      await openEditor(page, builderFixture)
      const before = builderFixture.snapshot().flowchart.version_count

      const result = await runTestPanel(page, { params: {} })
      expect(result.success, appDefect("expected a failing test run for blank required params", result)).toBe(false)
      expect(result.errors, appDefect("traces JSON missing collected errors", result)).toEqual(
        expect.arrayContaining(["First name can't be blank"])
      )

      const banner = page.locator("[data-flowchart-canvas-target='testOutput']")
      await expect(banner).toContainText("First name can't be blank")
      await expect(banner.locator("ul.list-disc li")).toHaveText("First name can't be blank")
      const status = page.locator("[data-flowchart-canvas-target='testStatus']")
      await expect(status).toBeVisible()
      await expect(status).toContainClass("bg-red-100")

      expect(builderFixture.snapshot().flowchart.version_count).toBe(before)
      expect(builderFixture.errors).toEqual([])
      await testInfo.attach("page-record-blank", {
        body: JSON.stringify({ before, result }, null, 2),
        contentType: "application/json"
      })
    })
  })

  test.describe("step form in zh-CN", () => {
    test.use({ builderKind: "blank" })

    test("searches the picker, shows help, clears an enum, gates retry, and paints a server field error", async ({ page, builderFixture }, testInfo) => {
      test.setTimeout(120_000)
      // The cookie the language switcher writes, so editor XHRs (validation) resolve zh-CN too.
      await page.context().addCookies([{ name: "locale", value: "zh-CN", url: BASE }])
      await openEditor(page, builderFixture)

      await page.locator("[data-controller='element-palette'] [data-flowchart-element='process']").dblclick()
      await expect.poll(async () => (await canvasGraph(page)).elements.filter(el => el.type === "process").length).toBe(1)
      const processId = (await canvasGraph(page)).elements.find(el => el.type === "process").id
      await openNode(page, processId)

      const picker = page.locator("[data-step-picker]")
      await picker.locator("input[data-step-picker-search]").fill("HTTP 请求")
      const option = picker.locator("[data-step-picker-option][data-value='api_call']")
      await expect(option).toBeVisible()
      await expect(option).toContainText("向外部服务发起 HTTP 请求。")
      await expect(picker.locator("[data-step-picker-option][data-value='new_model']")).toBeHidden()
      await option.click()
      await expect.poll(async () => stepOf(await canvasGraph(page), processId)?.action).toBe("api_call")

      const step = page.locator("[data-flowchart-canvas-target='propertySidebar'] [data-step-item]")
      const url = step.locator("[data-config-field='url']")
      await expect(url).toContainText("请求地址（Ruby 表达式）。")
      await url.locator("[data-config-input]").fill('"https://example.com/ping"')

      const responseFormat = step.locator("[data-config-field='responseFormat'] select")
      await expect(responseFormat.locator("option[value='']")).toHaveText("无")
      await responseFormat.selectOption("")
      await expect.poll(async () => stepOf(await canvasGraph(page), processId)?.config?.responseFormat ?? "").toBe("")

      const retryField = step.locator("[data-config-field='retryOnTransportError']")
      await step.locator("[data-disclosure]").filter({ has: page.locator("[data-config-field='retryOnTransportError']") })
        .locator("button[data-action*='toggleDisclosure']").click()
      const retry = retryField.locator("[data-config-input]")
      await expect(retry).toBeEnabled()
      await expect(step.locator("[data-step-timeout-hint]")).toHaveText("10 秒后放弃")

      await step.locator("[data-config-field='httpMethod'] select").selectOption("POST")
      await expect(retry).toBeDisabled()
      await expect(retryField.locator("[data-retry-idempotent-hint]")).toHaveText("仅幂等请求可启用重试（安全方法或已填写幂等键）。")
      await step.locator("[data-config-field='idempotencyKey'] [data-config-input]").fill("ctx[:request_id]")
      await expect(retry).toBeEnabled()
      await expect(retryField.locator("[data-retry-idempotent-hint]")).toBeHidden()

      await step.locator("[data-config-field='resultVar'] [data-config-input]").fill("result")
      await page.locator("[data-flowchart-canvas-target='propertySidebar'] [data-property-editor-target='saveButton']").click()
      await expect.poll(async () => stepOf(await canvasGraph(page), processId)?.config?.resultVar).toBe("result")
      await expect(page.locator("[data-flowchart-canvas-target='propertySidebar']")).toBeHidden()

      const validation = page.waitForResponse(response =>
        response.request().method() === "POST" && response.url().includes("/validation"))
      await page.locator("button[data-action='click->flowchart-canvas#validate']").click()
      expect((await validation).ok()).toBe(true)
      const list = page.locator("[data-flowchart-canvas-target='validationList']")
      await expect(list).toContainText("HTTP 请求")
      await expect(list).not.toContainText("api_call")

      const stepProblem = list.locator("button[data-rule='step_config_invalid'][data-field='resultVar']")
      await expect(stepProblem).toContainText("resultVar 不能使用 result")
      await stepProblem.click()
      await expect(page.locator("[data-flowchart-canvas-target='propertySidebar']")).toBeVisible()
      const resultVar = page.locator("[data-flowchart-canvas-target='propertySidebar'] [data-config-field='resultVar']")
      await expect(resultVar.locator("[data-field-error]")).toContainText("result")
      await expect(resultVar.locator("[data-config-input]")).toHaveAttribute("aria-invalid", "true")
      expect(builderFixture.errors).toEqual([])
      await testInfo.attach("step-form-zh", {
        body: JSON.stringify(await canvasGraph(page), null, 2),
        contentType: "application/json"
      })
    })
  })

  test.describe("element palette", () => {
    test.use({ builderKind: "blank" })

    test("has no Timer element", async ({ page, builderFixture }) => {
      test.setTimeout(90_000)
      await openEditor(page, builderFixture)
      const palette = page.locator("[data-controller='element-palette']")
      await expect(palette.locator("[data-flowchart-element='timer']")).toHaveCount(0)
      const types = await palette.locator("[data-element-palette-target='basicElements'] [data-flowchart-element]").evaluateAll(
        elements => elements.map(el => el.getAttribute("data-flowchart-element"))
      )
      expect(types).not.toContain("timer")
      expect(types).toEqual(expect.arrayContaining(["start", "process", "decision", "loop", "end"]))
      expect(builderFixture.errors).toEqual([])
    })
  })

  test.describe("element property editors save/reload", () => {
    test.use({ builderKind: "blank", viewport: { width: 1280, height: 900 } })

    test("End, Loop, and Subflow persist across reload", async ({ page, builderFixture }, testInfo) => {
      test.setTimeout(180_000)
      await openEditor(page, builderFixture)
      expect(builderFixture.launched_flowchart_id).toBeTruthy()

      const endId = (await canvasGraph(page)).elements.find(el => el.type === "end").id
      await openNode(page, endId)
      await expect(page.locator("[data-property-editor-target='tabBar'] [data-tab='general']")).toBeVisible()
      await expect(page.locator("[data-property-editor-target='tabBar'] [data-tab='advanced']")).toHaveCount(0)
      await page.locator("[data-flowchart-canvas-target='propertySidebar'] [name='responseType']").selectOption("value")
      await page.locator("[data-flowchart-canvas-target='propertySidebar'] [name='returnValue']").fill("ctx.result")
      await savePropertyEditor(page, builderFixture)

      await page.locator("[data-controller='element-palette'] [data-flowchart-element='loop']").dblclick()
      const loopId = (await canvasGraph(page)).elements.find(el => el.type === "loop").id
      await openNode(page, loopId)
      await page.locator("[data-flowchart-canvas-target='propertySidebar'] [name='loopType']").selectOption("for_each")
      await page.locator("[data-flowchart-canvas-target='propertySidebar'] [name='collection']").fill("items")
      await page.locator("[data-flowchart-canvas-target='propertySidebar'] [name='maxIterations']").fill("")
      await expect(page.locator("[data-flowchart-canvas-target='propertySidebar'] [name='maxIterations']"))
        .toHaveAttribute("placeholder", /Default: 100|默认：100/)
      await page.locator("[data-property-editor-target='tabBar'] [data-tab='advanced']").click()
      await expect(page.locator("[data-element-field='skipWhen']")).toBeVisible()
      await savePropertyEditor(page, builderFixture)

      const launchedChip = page.locator(
        `[data-element-palette-target='flowchartsList'] [data-flowchart-element='subflow'][data-flowchart-id='${builderFixture.launched_flowchart_id}']`
      )
      await expect(launchedChip).toBeVisible()
      await launchedChip.dblclick()
      const subflowId = (await canvasGraph(page)).elements.find(el => el.type === "subflow").id
      await openNode(page, subflowId)
      await page.locator("[data-property-editor--controls--reference-picker-target='trigger']").click()
      const search = page.locator("[data-property-editor--controls--reference-picker-target='search']")
      await search.fill(builderFixture.launched_flowchart_name)
      const option = page.locator(`[data-reference-option='${builderFixture.launched_flowchart_id}']`)
      await expect(option).toBeVisible()
      await option.click()
      await savePropertyEditor(page, builderFixture)

      await toolbarSave(page, builderFixture)
      await page.reload()
      await waitForCanvas(page)
      const reloaded = await canvasGraph(page)
      const end = reloaded.elements.find(el => el.id === endId)
      const loop = reloaded.elements.find(el => el.id === loopId)
      const subflow = reloaded.elements.find(el => el.id === subflowId)
      expect(end.properties).toMatchObject({ responseType: "value", returnValue: "ctx.result" })
      expect(loop.properties.loopType).toBe("for_each")
      expect(loop.properties.collection).toBe("items")
      expect(Number(loop.properties.maxIterations ?? 100)).toBe(100)
      expect(String(subflow.properties.flowchartId)).toBe(String(builderFixture.launched_flowchart_id))

      await openNode(page, endId)
      await expect(page.locator("[data-flowchart-canvas-target='propertySidebar'] [name='responseType']")).toHaveValue("value")
      await expect(page.locator("[data-flowchart-canvas-target='propertySidebar'] [name='returnValue']")).toHaveValue("ctx.result")
      expect(builderFixture.errors).toEqual([])
      await testInfo.attach("element-editor-roundtrip", {
        body: JSON.stringify({ end, loop, subflow, launched: builderFixture.launched_flowchart_id }, null, 2),
        contentType: "application/json"
      })
    })
  })

  test.describe("element property editors in zh-CN", () => {
    test.use({ builderKind: "blank", viewport: { width: 1280, height: 800 } })

    test("renders translated End/Loop fields in one column without sidebar overflow", async ({ page, builderFixture }) => {
      test.setTimeout(120_000)
      await page.context().addCookies([{ name: "locale", value: "zh-CN", url: BASE }])
      await openEditor(page, builderFixture)

      const endId = (await canvasGraph(page)).elements.find(el => el.type === "end").id
      await openNode(page, endId)
      const sidebar = page.locator("[data-flowchart-canvas-target='propertySidebar']")
      await expect(sidebar).toContainText("响应类型")
      await expect(sidebar.locator("[name='responseType'] option[value='none']")).toHaveText("不返回")
      await expect(sidebar.locator("[name='responseType'] option[value='value']")).toHaveText("返回一个值")
      await sidebar.locator("[name='responseType']").selectOption("value")
      await expect(sidebar).toContainText("返回值")
      await page.setViewportSize({ width: 375, height: 800 })
      await expectSidebarNoOverflow(sidebar)

      await sidebar.locator("[data-property-editor-target='cancelButton']").click()
      await page.setViewportSize({ width: 1280, height: 800 })
      await page.locator("[data-controller='element-palette'] [data-flowchart-element='loop']").dblclick()
      const loopId = (await canvasGraph(page)).elements.find(el => el.type === "loop").id
      await openNode(page, loopId)
      await expect(sidebar).toContainText("循环类型")
      await expect(sidebar.locator("[name='loopType'] option[value='while']")).toHaveText("当条件为真时重复")
      await expect(sidebar.locator("[name='loopType'] option[value='for_each']")).toHaveText("逐项遍历")
      await sidebar.locator("[name='loopType']").selectOption("for_each")
      await expect(sidebar).toContainText("集合")
      await expect(sidebar.locator("[data-tab='advanced']")).toHaveText("高级")
      await page.setViewportSize({ width: 375, height: 800 })
      await expectSidebarNoOverflow(sidebar)
      expect(builderFixture.errors).toEqual([])
    })
  })
})

async function createViaNewForm(page, fixture, template) {
  const loaded = await page.goto(BASE + fixture.new_path)
  expect(loaded?.ok()).toBeTruthy()
  await page.waitForLoadState("networkidle")
  await page.locator(`[data-template='${template}']`).click()
  await page.locator("#flowchart_name").fill(fixture.flowchart_name)
  await Promise.all([
    page.waitForURL(/\/flowcharts\/\d+\/edit/),
    page.locator("form[action$='/flowcharts'] input[type=submit]").click()
  ])
}

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

async function canvasGraph(page) {
  return page.evaluate(() => {
    const canvas = document.querySelector('[data-controller*="flowchart-canvas"]').flowchartCanvas
    return {
      elements: canvas.elements.map(el => ({
        id: el.id, type: el.type, x: el.x, y: el.y, label: el.label, properties: el.properties
      })),
      connections: canvas.connections.map(c => ({
        id: c.id, from: c.from, to: c.to, fromPosition: c.fromPosition, toPosition: c.toPosition,
        label: c.label, properties: c.properties
      }))
    }
  })
}

function assertTemplateGraph(graph, expected) {
  expect(graph.elements.map(el => el.type)).toEqual(expected.types)
  expect(graph.elements.map(el => el.label)).toEqual(expected.labels)
  const processes = graph.elements.filter(el => el.type === "process")
  expect(processes.map(el => el.properties.steps?.[0]?.action)).toEqual(expected.actions)
  processes.forEach((el, index) => {
    expect(el.properties.steps).toHaveLength(1)
    expect(el.properties.steps[0].config).toMatchObject(expected.configs[index])
  })
  const ids = graph.elements.map(el => el.id)
  expect(graph.connections.map(c => [c.from, c.to, c.fromPosition, c.toPosition])).toEqual(
    ids.slice(0, -1).map((from, index) => [from, ids[index + 1], "bottom", "top"])
  )
}

async function dragProcessBelowStart(page, startId) {
  const start = page.locator(`.element-layer > [data-element-id='${startId}']`)
  const canvas = page.locator("[data-flowchart-canvas-target='canvasContainer']")
  const process = page.locator("[data-controller='element-palette'] [data-flowchart-element='process']")
  await expect(start).toBeVisible()
  await expect(process).toBeVisible()
  const startBox = await start.boundingBox()
  const canvasBox = await canvas.boundingBox()
  expect(startBox).not.toBeNull()
  expect(canvasBox).not.toBeNull()
  await process.dragTo(canvas, {
    targetPosition: {
      x: startBox.x + startBox.width / 2 - canvasBox.x,
      y: startBox.y + startBox.height + 40 - canvasBox.y
    }
  })
}

async function openNode(page, elementId) {
  const node = page.locator(`.element-layer > [data-element-id='${elementId}']`)
  await expect(node).toBeVisible()
  await node.dblclick()
  await expect(page.locator("[data-flowchart-canvas-target='propertySidebar']")).toBeVisible()
}

async function pickActionOnProcess(page, elementId, step) {
  await openNode(page, elementId)
  const picker = page.locator("[data-step-picker]")
  await expect(picker).toBeVisible()
  const search = picker.locator("input[data-step-picker-search]")
  await search.click()
  await search.fill(step.search)
  const option = picker.locator(`[data-step-picker-option][data-value='${step.value}']`)
  await expect(option).toBeVisible()
  await option.click()
  await expect.poll(async () => {
    const graph = await canvasGraph(page)
    const el = graph.elements.find(item => item.id === elementId)
    return el?.properties?.steps?.[0]?.action
  }).toBe(step.value)
  await expect.poll(async () => {
    const graph = await canvasGraph(page)
    const el = graph.elements.find(item => item.id === elementId)
    return el?.properties?.steps?.[0]?.config ?? {}
  }).toMatchObject(step.config)
}

function stepOf(graph, elementId) {
  return graph.elements.find(item => item.id === elementId)?.properties?.steps?.[0]
}

function visibleCancel(page) {
  return page.locator("[data-flowchart-canvas-target='propertySidebar'] [data-property-editor-target='cancelButton']")
}

async function expectSaveDotStaysHidden(saveDot) {
  const samples = []
  await expect.poll(async () => {
    samples.push(await saveDot.isHidden())
    if (samples.some(hidden => !hidden)) return false
    return samples.length >= 5
  }, { timeout: 1200, intervals: [200] }).toBe(true)
}

async function savePropertyEditor(page, fixture) {
  const path = fixture.flowchart_edit_path.replace(/\/edit$/, "")
  const pending = page.waitForResponse(response =>
    new URL(response.url()).pathname === path && response.request().method() === "PATCH")
  await page.locator("[data-flowchart-canvas-target='propertySidebar'] [data-property-editor-target='saveButton']").click()
  expect((await pending).ok()).toBe(true)
  await expect(page.locator("[data-flowchart-canvas-target='propertySidebar']")).toBeHidden()
}

async function expectSidebarNoOverflow(sidebar) {
  const geometry = await sidebar.evaluate(el => ({
    clientWidth: el.clientWidth,
    scrollWidth: el.scrollWidth,
    right: el.getBoundingClientRect().right,
    viewportWidth: window.innerWidth
  }))
  expect(geometry.scrollWidth).toBeLessThanOrEqual(geometry.clientWidth + 1)
  expect(geometry.right).toBeLessThanOrEqual(geometry.viewportWidth + 1)
}

async function toolbarSave(page, fixture) {
  const path = fixture.flowchart_edit_path.replace(/\/edit$/, "")
  const pending = page.waitForResponse(response =>
    new URL(response.url()).pathname === path && response.request().method() === "PATCH")
  await page.locator("button[data-action='click->toolbar#save']").click()
  const saved = await pending
  expect(saved.ok()).toBe(true)
}

async function validateAndExpectNoErrors(page) {
  const pending = page.waitForResponse(response =>
    response.request().method() === "POST" && response.url().includes("/validation"))
  await page.locator("button[data-action='click->flowchart-canvas#validate']").click()
  expect((await pending).ok()).toBe(true)
  const list = page.locator("[data-flowchart-canvas-target='validationList']")
  await expect(list).toBeVisible()
  await expect(list.locator("[data-severity='error']")).toHaveCount(0)
}

const OVERLAY_TAKEN = "#22c55e"
const OVERLAY_SKIPPED = "#9ca3af"

async function runTestPanel(page, payload) {
  const input = page.locator("[data-flowchart-canvas-target='testInput']")
  if (!await input.isVisible()) {
    await page.locator("button[data-action='click->flowchart-canvas#toggleTestPanel']").click()
  }
  await expect(input).toBeVisible()
  await input.fill(JSON.stringify(payload))
  const trace = page.waitForResponse(response => response.request().method() === "POST" && response.url().includes("/traces"))
  await page.locator("[data-flowchart-canvas-target='testRunButton']").click()
  const response = await trace
  expect(response.ok(), appDefect("test runner HTTP was not ok", { status: response.status() })).toBe(true)
  return response.json()
}

function expectTakenBranch(result, { takenId, skippedId, branch, takenLabel, skippedLabel }) {
  const ids = (result.trace_nodes || []).map(node => node.element_id).filter(Boolean)
  expect(ids, appDefect("taken branch missing from trace", result)).toEqual(expect.arrayContaining([
    "start_1", "decision_1", takenId, "end_1"
  ]))
  expect(ids).not.toContain(skippedId)
  const decision = (result.trace_nodes || []).find(node => node.element_id === "decision_1")
  expect(decision, appDefect("decision node missing from trace", result)).toMatchObject({
    label: "Check amount",
    branch,
    status: "success"
  })
  const labels = (result.trace_nodes || []).map(node => node.label)
  expect(labels).toContain(takenLabel)
  expect(labels).not.toContain(skippedLabel)
}

async function overlayState(page) {
  return page.evaluate(() => {
    const canvas = document.querySelector('[data-controller*="flowchart-canvas"]').flowchartCanvas
    const layer = canvas._traceOverlayLayer
    if (!layer) return { overlays: [] }
    return {
      overlays: canvas.elements.map(el => {
        const expectedX = el.x - el.width / 2 - 4
        const expectedY = el.y - el.height / 2 - 4
        const rect = [...layer.querySelectorAll("rect.trace-overlay-rect")].find(node =>
          Math.abs(Number(node.getAttribute("x")) - expectedX) < 0.5 &&
          Math.abs(Number(node.getAttribute("y")) - expectedY) < 0.5
        )
        const badgeX = el.x - el.width / 2 + 2
        const badgeY = el.y - el.height / 2 - 2
        const badge = [...layer.querySelectorAll("circle.trace-overlay-order-badge")].find(node =>
          Math.abs(Number(node.getAttribute("cx")) - badgeX) < 0.5 &&
          Math.abs(Number(node.getAttribute("cy")) - badgeY) < 0.5
        )
        return {
          id: el.id,
          fill: rect?.getAttribute("fill") || null,
          badge: badge?.nextSibling?.textContent || null
        }
      })
    }
  })
}

async function expectBranchOverlay(page, { takenId, skippedId, badges }) {
  await expect.poll(async () => overlayState(page), { timeout: 10_000 }).toMatchObject({
    overlays: expect.arrayContaining([
      { id: "start_1", fill: OVERLAY_TAKEN, badge: badges.start_1 },
      { id: "decision_1", fill: OVERLAY_TAKEN, badge: badges.decision_1 },
      { id: takenId, fill: OVERLAY_TAKEN, badge: badges[takenId] },
      { id: skippedId, fill: OVERLAY_SKIPPED, badge: null },
      { id: "end_1", fill: OVERLAY_TAKEN, badge: badges.end_1 }
    ])
  })
}

function appDefect(message, evidence) {
  return `APP DEFECT: ${message} — ${JSON.stringify(evidence)}`
}
