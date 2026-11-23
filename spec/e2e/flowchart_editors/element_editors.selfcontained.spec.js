import { test, expect } from "@playwright/test"
import { bootEditor, nativeSave, tabKeys, assertNoSidebarOverflow } from "./_browser_modules.js"

const WIDTHS = [375, 1280]

async function visibleTabs(page) {
  return tabKeys(page)
}

function branchRows(page) {
  return page.locator("[data-branch-item]")
}

for (const width of WIDTHS) {
  test.describe(`element property editors @ ${width}px`, () => {
    test.use({ viewport: { width, height: 900 } })

    test("Start shows General + I/O only, and Notes persist", async ({ page }) => {
      await bootEditor(page, { type: "start" })
      expect(await visibleTabs(page)).toEqual(["general", "io"])
      await expect(page.locator('[data-tab="advanced"]')).toHaveCount(0)
      await expect(page.locator('[name="label"]')).toBeVisible()
      await page.locator("[data-notes-disclosure] summary").click()
      await page.locator('[name="description"]').fill("HTTP entry")
      await assertNoSidebarOverflow(page)
      const saved = (await nativeSave(page)).elements[0]
      expect(saved.properties.description).toBe("HTTP entry")
      expect(saved.properties).not.toHaveProperty("trigger")
    })

    test("End Nothing / Return a value toggles returnValue on General", async ({ page }) => {
      await bootEditor(page, { type: "end", properties: { responseType: "none" } })
      expect(await visibleTabs(page)).toEqual(["general", "io"])
      await expect(page.locator('[name="responseType"]')).toHaveValue("none")
      await expect(page.locator('[data-element-field="returnValue"]')).toBeHidden()
      await page.locator('[name="responseType"]').selectOption("value")
      await expect(page.locator('[data-element-field="returnValue"]')).toBeVisible()
      await page.locator('[name="returnValue"]').fill("ctx.result")
      await assertNoSidebarOverflow(page)
      const saved = (await nativeSave(page)).elements[0].properties
      expect(saved).toMatchObject({ responseType: "value", returnValue: "ctx.result" })
    })

    test("Process opens on Steps and add/remove still works", async ({ page }) => {
      await bootEditor(page, { type: "process", properties: { steps: [] } })
      expect(await visibleTabs(page)).toEqual(["general", "steps", "io"])
      await expect(page.locator("[data-tab='steps']")).toHaveClass(/bg-white/)
      const mount = page.locator("[data-step-picker-mount]")
      await expect(mount).not.toHaveClass(/hidden/)
      const picker = mount.locator("[data-step-picker]")
      await picker.locator("[data-step-picker-search]").fill("Assign")
      await picker.locator("[data-step-picker-option][data-value='assign_value']").click()
      await expect(page.locator("[data-step-item]")).toHaveCount(1)
      await page.locator('[data-action*="#removeStep"]').click()
      await expect(page.locator("[data-step-item]")).toHaveCount(0)
      await expect(mount).not.toHaveClass(/hidden/)
      await assertNoSidebarOverflow(page)
    })

    test("Decision Yes/No: add, rename, match, Otherwise, remove keeps the box", async ({ page }) => {
      await bootEditor(page, {
        type: "decision",
        properties: { routeBy: "condition" },
        extraElements: [
          { id: "yes_box", type: "process", label: "Yes box", x: 80, y: 240 },
          { id: "no_box", type: "process", label: "No box", x: 320, y: 240 }
        ],
        connections: [
          { from: "__node__", to: "yes_box", fromPort: "port_0", label: "Yes", matchValue: "true" },
          { from: "__node__", to: "no_box", fromPort: "port_1", label: "No", matchValue: "false" }
        ]
      })
      expect(await visibleTabs(page)).toEqual(["general", "branches", "io"])
      await expect(page.locator('[name="routeBy"]')).toHaveValue("condition")
      await expect(branchRows(page)).toHaveCount(2)
      await branchRows(page).nth(0).locator("[data-branch-name]").fill("Approved")
      await page.locator('[data-action="click->property-editor#addBranch"]').click()
      await expect(branchRows(page)).toHaveCount(3)
      await expect(branchRows(page).nth(2).locator("[data-branch-otherwise]")).toBeChecked()
      const addedId = await page.evaluate(() => {
        const { canvasController, node } = window.editorFixture
        const outgoing = canvasController.canvas.connections.filter(c => c.from === node.id)
        return outgoing[outgoing.length - 1].to
      })
      await branchRows(page).nth(2).locator('[data-action*="#removeBranch"]').click()
      await expect(branchRows(page)).toHaveCount(2)
      const leftover = await page.evaluate(({ addedId }) => {
        const { canvasController } = window.editorFixture
        return {
          box: canvasController.canvas.elements.some(el => el.id === addedId),
          edges: canvasController.canvas.connections.filter(c => c.to === addedId).length
        }
      }, { addedId })
      expect(leftover.box).toBe(true)
      expect(leftover.edges).toBe(0)
      await assertNoSidebarOverflow(page)
    })

    test("Decision Route by value plus duplicate / two Otherwise inline errors", async ({ page }) => {
      await bootEditor(page, {
        type: "decision",
        properties: { routeBy: "value", subject: "ctx.status" },
        extraElements: [
          { id: "a", type: "process", label: "A", x: 80, y: 240 },
          { id: "b", type: "process", label: "B", x: 320, y: 240 }
        ],
        connections: [
          { from: "__node__", to: "a", fromPort: "port_0", label: "A", matchValue: "open" },
          { from: "__node__", to: "b", fromPort: "port_1", label: "B", matchValue: "open" }
        ]
      })
      await expect(page.locator('[name="routeBy"]')).toHaveValue("value")
      await expect(page.locator('[name="subject"]')).toHaveValue("ctx.status")
      await page.locator('[data-tab="branches"]').click()
      await page.locator('[data-property-editor-target="saveButton"]').click()
      await expect(page.locator('[data-element-field="branches"] [data-field-error]')).toHaveText("Match values must be unique")
      await expect(page.locator('[data-element-field="branches"] [aria-invalid="true"]')).toHaveCount(1)

      await page.evaluate(() => {
        const { editor, canvasController, node } = window.editorFixture
        canvasController.canvas.connections.filter(conn => conn.from === node.id).forEach(conn => {
          delete conn.matchValue
        })
        editor.branchManager._rebuildBranchRows()
      })
      await expect(branchRows(page).locator("[data-branch-otherwise]:checked")).toHaveCount(2)
      await page.locator('[data-property-editor-target="saveButton"]').click()
      await expect(page.locator('[data-element-field="branches"] [data-field-error]')).toHaveText("Only one Otherwise branch is allowed")
      await assertNoSidebarOverflow(page)
    })

    test("Loop while ⇄ for each, run once first, blank max iterations, advanced stop/skip", async ({ page }) => {
      await bootEditor(page, { type: "loop", properties: { loopType: "while" } })
      expect(await visibleTabs(page)).toEqual(["general", "io", "advanced"])
      await expect(page.locator('[data-element-field="runOnceFirst"]')).toBeVisible()
      await page.locator('[name="runOnceFirst"]').check({ force: true })
      await page.locator('[name="loopType"]').selectOption("for_each")
      await expect(page.locator('[data-element-field="runOnceFirst"]')).toBeHidden()
      await expect(page.locator('[data-element-field="collection"]')).toBeVisible()
      await page.locator('[name="collection"]').fill("items")
      await page.locator('[name="maxIterations"]').fill("")
      await expect(page.locator('[name="maxIterations"]')).toHaveAttribute("placeholder", "Default: 100")
      await page.locator('[data-tab="advanced"]').click()
      await expect(page.locator('[data-element-field="stopWhen"]')).toBeVisible()
      await expect(page.locator('[data-element-field="skipWhen"]')).toBeVisible()
      await page.locator('[data-element-field="skipWhen"] [data-condition-left]').fill("item.skip")
      await page.locator('[data-element-field="skipWhen"] [data-condition-op]').selectOption("is_true")
      await assertNoSidebarOverflow(page)
      const saved = (await nativeSave(page)).elements[0].properties
      expect(saved.loopType).toBe("for_each")
      expect(saved.collection).toBe("items")
      expect(saved).not.toHaveProperty("maxIterations")
      expect(saved.skipWhen.conditions[0]).toMatchObject({
        kind: "field", leftOperand: "item.skip", operator: "is_true", rightOperand: ""
      })
    })

    test("Subflow searchable picker stores the numeric id", async ({ page }) => {
      await bootEditor(page, {
        type: "subflow",
        referenceOptions: [
          { value: "9", label: "Order Processing" },
          { value: "12", label: "Refund Flow" }
        ]
      })
      expect(await visibleTabs(page)).toEqual(["general", "io"])
      await page.locator('[data-property-editor--controls--reference-picker-target="trigger"]').click()
      const search = page.locator('[data-property-editor--controls--reference-picker-target="search"]')
      await search.fill("Refund")
      await expect(page.locator("[data-reference-option='12']")).toBeVisible()
      await expect(page.locator("[data-reference-option='9']")).toBeHidden()
      await page.locator("[data-reference-option='12']").click()
      await assertNoSidebarOverflow(page)
      expect(Number((await nativeSave(page)).elements[0].properties.flowchartId)).toBe(12)
    })

    test("Connection form is label + Notes only", async ({ page }) => {
      await bootEditor(page, { type: "start" })
      await page.evaluate(() => {
        const { editor, canvasController, node } = window.editorFixture
        const process = canvasController.canvas.addElement({ type: "process", label: "Next", x: 220, y: 240 })
        const connection = canvasController.canvas.createConnection(node, process, "bottom", "top", {
          label: "",
          properties: { description: "" }
        })
        editor.openConnectionEditor(connection, canvasController.canvas)
      })
      await expect(page.locator('[data-property-editor-target="tabBar"]')).toBeHidden()
      await expect(page.locator('[name="label"]')).toBeVisible()
      await expect(page.locator('[name="description"]')).toBeVisible()
      await expect(page.locator('[name="priority"]')).toHaveCount(0)
      await page.locator('[name="label"]').fill("Approved")
      await page.locator('[name="description"]').fill("When the check passes")
      await assertNoSidebarOverflow(page)
      const saved = await nativeSave(page)
      const connection = saved.connections[0]
      expect(connection.label).toBe("Approved")
      expect(connection.properties.description).toBe("When the check passes")
      expect(connection.properties).not.toHaveProperty("priority")
    })
  })
}
