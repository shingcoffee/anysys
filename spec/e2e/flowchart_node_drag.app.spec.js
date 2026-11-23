import { test, expect, observeDrag } from "./helpers/drag_fixtures.js"

// Tier C (app-backed): exercises flowchart/drag_handler.js in the REAL app.
//
// The flowchart canvas drag is a *mouse-events* engine bound on the generated
// <svg>: mousedown -> _handleElementMouseDown -> _startDrag, mousemove ->
// _handleDragMove -> _moveElementVisually, mouseup -> _endDrag ->
// _finishSingleElementDrag (snap-to-grid + connection re-alignment). It reads
// real cursor geometry through _getSVGPoint (getScreenCTM), so happy-dom cannot
// drive it. Playwright's real Chromium mouse API emits the mouse sequence.
//
// Nodes are SVG groups <g data-element-id="..."> in the element layer;
// element_renderer.updateElementPosition writes their position as
//   transform="translate(x, y)"  (x = element.x - width/2, y = element.y - height/2)
// So a successful drag is observable as: the dragged node's `transform`
// attribute changes (position moved / snapped to a new grid cell).
//
// Every test creates its own draft flowchart through the current model/factory
// helpers. The canvasWrapper selector was verified against the live rendered DOM.
const BASE = process.env.APP_BASE_URL

test.use({ dragKind: "flowchart", viewport: { width: 1440, height: 1000 } })

test.describe("flowchart node drag (drag_handler)", () => {
  test.skip(!BASE, "set APP_BASE_URL to run app-backed e2e (see spec/e2e/README.md)")

  test("mouse-dragging a node moves its canvas position and persists after reload", async ({ page, dragFixture }, testInfo) => {
    test.setTimeout(90_000)
    const response = await page.goto(BASE + dragFixture.flowchart_edit_path)
    expect(response?.ok()).toBeTruthy()
    // The app's asynchronous module graph must finish before canvas bootstrap.
    await page.waitForLoadState("networkidle")

    const canvas = page.locator("[data-flowchart-canvas-target='canvasWrapper'] svg.flowchart-svg")
    await expect(canvas).toBeVisible()
    await expect(canvas.locator(".element-layer > [data-element-id]")).toHaveCount(3)
    const node = canvas.locator("[data-element-id='process_1']")
    await expect(node).toBeVisible()
    // Initial I/O requests can re-render the cards. Measure after bootstrap has
    // settled, so a selection stroke/re-render cannot impersonate movement.
    const transformOf = () => node.getAttribute("transform")
    const before = await transformOf()
    expect(before).toMatch(/^translate\(/)
    const events = await observeDrag(page)

    const box = await node.boundingBox()
    expect(box).not.toBeNull()

    // Mouse-driven drag: press on the node centre (selects + starts the drag),
    // move vertically well past the drag threshold and several grid cells,
    // then release. Vertical alignment guides may preserve the original x.
    const cx = box.x + box.width / 2
    const cy = box.y + box.height / 2
    await page.mouse.move(cx, cy)
    await page.mouse.down()
    await page.mouse.move(cx, cy + 150, { steps: 24 })
    await page.mouse.up()

    await expect.poll(transformOf).not.toBe(before)
    const after = await transformOf()
    const movedBox = await node.boundingBox()
    expect(movedBox.y - box.y).toBeGreaterThan(100)
    const input = await events()
    expect(input.some(event => event.type === "mousedown" && event.trusted && event.id === "process_1")).toBe(true)
    expect(input.some(event => event.type === "mouseup" && event.trusted && event.id === "process_1")).toBe(true)

    const saveResponse = page.waitForResponse(response =>
      new URL(response.url()).pathname === dragFixture.flowchart_edit_path.replace(/\/edit$/, "") && response.request().method() === "PATCH")
    await page.locator("button[data-action='click->toolbar#save']").click()
    const saved = await saveResponse
    expect(saved.ok()).toBe(true)
    const persisted = dragFixture.snapshot()
    expect(persisted.flowchart.version_id).not.toBe(dragFixture.initialSnapshot.flowchart.version_id)
    const element = persisted.flowchart.configuration.elements.find(element => element.id === "process_1")
    expect(element.x).toBe(150)
    expect(element.y - 200).toBeGreaterThan(100)
    expect(after).toBe(`translate(${element.x - element.width / 2}, ${element.y - element.height / 2})`)

    await page.reload()
    await expect(node).toBeVisible()
    await expect.poll(transformOf).toBe(after)
    expect(dragFixture.errors).toEqual([])
    await testInfo.attach("drag-persistence-proof", {
      body: JSON.stringify({ before, after, persisted, reloaded: await transformOf(), box, movedBox, input, saveStatus: saved.status() }, null, 2),
      contentType: "application/json"
    })
  })
})
