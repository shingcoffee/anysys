import { test } from "@playwright/test"
import {
  bootCanvas, graph, positions, controllerState, node, dragBy, hoverConnectionMidpoint,
  box, edge, SUBFLOW_ID, expect
} from "./_canvas_fixture.js"

// Subflow preview mode with trusted input: expanding a subflow is a read-only
// preview (notice shown, every mutation blocked, nothing marked unsaved) and
// folding the last expansion restores the exact pre-expansion graph.

test.use({ viewport: { width: 1280, height: 800 } })

const PARENT = {
  elements: [
    box("start", "start", 307, 82, "Start"),
    box("sub", "subflow", 322, 211, "Order Processing", { properties: { flowchartId: SUBFLOW_ID } }),
    box("after", "process", 298, 343, "After"),
    box("end", "end", 313, 467, "End")
  ],
  connections: [edge("c1", "start", "sub"), edge("c2", "sub", "after"), edge("c3", "after", "end")]
}

const configuration = page => page.evaluate(() =>
  structuredClone(document.querySelector('[data-controller="flowchart-canvas"]').flowchartCanvas.getConfiguration()))

async function expand(page) {
  await node(page, "sub").locator("[data-subflow-toggle]").click()
  await expect(node(page, "sub_sub_s_start")).toHaveCount(1)
  await expect(node(page, "sub_sub_s_start").locator(".fold-icon")).toHaveCount(1)
}

test.describe("subflow preview", () => {
  test("expanding shows the notice, blocks editing, and folding restores the exact graph without marking unsaved", async ({ page }) => {
    const { errors } = await bootCanvas(page, { configuration: PARENT })
    const notice = page.locator('[data-flowchart-canvas-target="previewNotice"]')
    const original = await configuration(page)
    const before = await controllerState(page)
    await expect(notice).toBeHidden()

    await expand(page)
    await expect(notice).toBeVisible()
    let state = await controllerState(page)
    expect(state.previewMode).toBe(true)
    expect(state.unsaved).toBe(false)
    expect(state.undoDepth).toBe(before.undoDepth)
    const expanded = await graph(page)
    expect(expanded.elements.map(el => el.id)).not.toContain("sub")
    expect(expanded.elements.map(el => el.id)).toEqual(expect.arrayContaining(["sub_sub_s_start", "sub_sub_s_work", "sub_sub_s_end"]))
    const previewPositions = await positions(page)

    await dragBy(page, "sub_sub_s_work", 150, 60)
    await dragBy(page, "after", -120, 0)
    expect(await positions(page)).toEqual(previewPositions)

    await node(page, "after").click()
    await page.keyboard.press("ArrowRight")
    await page.keyboard.press("Shift+ArrowDown")
    await page.keyboard.press("Delete")
    await page.keyboard.press("Backspace")
    await page.waitForTimeout(600)
    expect(await positions(page)).toEqual(previewPositions)

    await page.locator("[data-controller='element-palette'] [data-flowchart-element='process']").dblclick()
    await hoverConnectionMidpoint(page, "c3")
    await page.waitForTimeout(300)
    await expect(page.locator("[data-edge-insert-for]")).toHaveCount(0)

    const blocked = await graph(page)
    expect(blocked.elements).toEqual(expanded.elements)
    expect(blocked.connections).toEqual(expanded.connections)
    state = await controllerState(page)
    expect(state.unsaved).toBe(false)
    expect(state.undoDepth).toBe(before.undoDepth)

    await node(page, "sub_sub_s_start").locator(".fold-icon").click()
    await expect(notice).toBeHidden()
    expect(await configuration(page)).toEqual(original)
    state = await controllerState(page)
    expect(state.previewMode).toBe(false)
    expect(state.unsaved).toBe(false)
    expect(state.undoDepth).toBe(before.undoDepth)
    await expect(page.getByTestId("unsaved")).toBeHidden()

    // Editing works again once folded.
    await dragBy(page, "after", -120, 0)
    expect((await positions(page)).after).not.toEqual({ x: 298, y: 343 })
    expect((await controllerState(page)).unsaved).toBe(true)
    expect(errors).toEqual([])
  })
})
