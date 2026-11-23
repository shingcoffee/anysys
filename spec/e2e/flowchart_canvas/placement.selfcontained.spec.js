import { test } from "@playwright/test"
import {
  bootCanvas, graph, positions, controllerState, clientPoint, svgPoint, node, dragBy,
  hoverConnectionMidpoint, box, edge, snap, GRID, expect
} from "./_canvas_fixture.js"

// Real-browser geometry for the Phase 5 canvas: placement, selection drag,
// edge "+" insert, Tidy layout, ResizeObserver viewBox and arrow nudging.
// Trusted Playwright mouse/keyboard input drives every interaction; canvas
// state is only read through page.evaluate.

test.use({ viewport: { width: 1280, height: 800 } })

const CHAIN = {
  elements: [
    box("a", "process", 307, 97, "Alpha"),
    box("b", "process", 292, 233, "Bravo"),
    box("c", "process", 318, 352, "Charlie")
  ],
  connections: [edge("ab", "a", "b"), edge("bc", "b", "c")]
}

const transformOf = (page, id) => node(page, id).getAttribute("transform")

test.describe("placement — nothing moves except what the user moves", () => {
  test("load keeps stored off-grid positions (no auto-align)", async ({ page }) => {
    const { errors } = await bootCanvas(page, { configuration: CHAIN })
    expect(await positions(page)).toEqual({ a: { x: 307, y: 97 }, b: { x: 292, y: 233 }, c: { x: 318, y: 352 } })
    for (const el of CHAIN.elements) {
      expect(await transformOf(page, el.id)).toBe(`translate(${el.x - 50}, ${el.y - 22.5})`)
    }
    expect(errors).toEqual([])
  })

  test("palette drag drops exactly where released, on empty canvas and next to a box", async ({ page }) => {
    await bootCanvas(page, { configuration: CHAIN })
    const before = await positions(page)
    const container = await page.getByTestId("canvas-container").boundingBox()

    // Far from every box: plain addElement at the drop point.
    const far = { x: 1000, y: 250 }
    await page.locator('[data-controller="element-palette"] [data-flowchart-element="decision"]')
      .dragTo(page.getByTestId("canvas-container"), { targetPosition: { x: far.x - container.x, y: far.y - container.y } })
    await expect.poll(async () => (await graph(page)).elements.length).toBe(4)
    const farTarget = await svgPoint(page, far.x, far.y)
    const decision = (await graph(page)).elements.find(el => el.type === "decision")
    expect({ x: decision.x, y: decision.y }).toEqual({ x: snap(farTarget.x), y: snap(farTarget.y) })
    const decisionBox = await node(page, decision.id).boundingBox()
    expect(Math.abs(decisionBox.x + decisionBox.width / 2 - far.x)).toBeLessThanOrEqual(GRID / 2)
    expect(Math.abs(decisionBox.y + decisionBox.height / 2 - far.y)).toBeLessThanOrEqual(GRID / 2)

    // 60 px right of "c": the drop targets c (insert-next-to) and still lands where released.
    const cCentre = await clientPoint(page, before.c.x, before.c.y)
    const near = { x: cCentre.x + 125, y: cCentre.y + 70 }
    await page.locator('[data-controller="element-palette"] [data-flowchart-element="end"]')
      .dragTo(page.getByTestId("canvas-container"), { targetPosition: { x: near.x - container.x, y: near.y - container.y } })
    await expect.poll(async () => (await graph(page)).elements.length).toBe(5)
    const nearTarget = await svgPoint(page, near.x, near.y)
    const after = await graph(page)
    const end = after.elements.find(el => el.type === "end")
    expect({ x: end.x, y: end.y }).toEqual({ x: snap(nearTarget.x), y: snap(nearTarget.y) })
    expect(after.connections.some(c => c.from === "c" && c.to === end.id)).toBe(true)

    const moved = await positions(page)
    for (const id of ["a", "b", "c"]) expect(moved[id]).toEqual(before[id])
  })

  test("a dragged box lands where released (grid-snapped), also zoomed and panned", async ({ page }) => {
    await bootCanvas(page, { configuration: CHAIN })
    await dragBy(page, "c", 263, 131)
    let now = await positions(page)
    expect(now.c).toEqual({ x: snap(318 + 263), y: snap(352 + 131) })
    expect(now.a).toEqual({ x: 307, y: 97 })
    expect(now.b).toEqual({ x: 292, y: 233 })

    await page.evaluate(() => {
      const root = document.querySelector('[data-controller="flowchart-canvas"]')
      const controller = window.Stimulus.getControllerForElementAndIdentifier(root, "flowchart-canvas")
      for (let i = 0; i < 5; i++) controller.zoomIn()
    })
    const svgBox = await page.locator("svg.flowchart-svg").boundingBox()
    await page.mouse.move(svgBox.x + 300, svgBox.y + 300)
    await page.mouse.wheel(40, 60)
    const zoom = await page.evaluate(() => document.querySelector('[data-controller="flowchart-canvas"]').flowchartCanvas.zoomPanManager.zoom)
    expect(zoom).toBeCloseTo(1.5, 5)

    const start = (await positions(page)).c
    await dragBy(page, "c", -150, 90)
    now = await positions(page)
    expect(now.c).toEqual({ x: snap(start.x - 150 / zoom), y: snap(start.y + 90 / zoom) })
    expect(now.a).toEqual({ x: 307, y: 97 })
    expect(now.b).toEqual({ x: 292, y: 233 })
  })
})

test.describe("selection — drag moves only the selection", () => {
  test("dragging the head of a chain leaves its downstream boxes in place", async ({ page }) => {
    await bootCanvas(page, { configuration: CHAIN })
    await dragBy(page, "a", 240, 0)
    expect(await positions(page)).toEqual({
      a: { x: snap(307 + 240), y: snap(97) }, b: { x: 292, y: 233 }, c: { x: 318, y: 352 }
    })
    expect((await graph(page)).selected).toEqual(["a"])
  })

  test("Shift+click adds to the selection and the group moves rigidly; the rest stays", async ({ page }) => {
    await bootCanvas(page, { configuration: CHAIN })
    await node(page, "a").click()
    await node(page, "c").click({ modifiers: ["Shift"] })
    expect((await graph(page)).selected).toEqual(["a", "c"])

    await dragBy(page, "c", 200, 40)
    const now = await positions(page)
    const dx = now.c.x - 318
    const dy = now.c.y - 352
    expect(now.c).toEqual({ x: snap(318 + 200), y: snap(352 + 40) })
    expect(now.a).toEqual({ x: 307 + dx, y: 97 + dy })
    expect(now.b).toEqual({ x: 292, y: 233 })
  })

  test("Shift+marquee adds to the selection; Ctrl/Cmd+A selects every box", async ({ page }) => {
    await bootCanvas(page, { configuration: CHAIN })
    await node(page, "a").click()
    const from = await clientPoint(page, 200, 190)
    const to = await clientPoint(page, 420, 270)
    await page.keyboard.down("Shift")
    await page.mouse.move(from.x, from.y)
    await page.mouse.down()
    await page.mouse.move(to.x, to.y, { steps: 10 })
    await page.mouse.up()
    await page.keyboard.up("Shift")
    expect((await graph(page)).selected.sort()).toEqual(["a", "b"])

    const empty = await clientPoint(page, 700, 600)
    await page.mouse.click(empty.x, empty.y)
    expect((await graph(page)).selected).toEqual([])
    await page.keyboard.press("ControlOrMeta+a")
    expect((await graph(page)).selected.sort()).toEqual(["a", "b", "c"])
    await expect(page.locator(".element-layer > g.selected")).toHaveCount(3)
  })
})

test.describe('edge "+" insert', () => {
  test("inserts the chosen box at the connection midpoint, rewires A→new→B, one undo step", async ({ page }) => {
    await bootCanvas(page, { configuration: CHAIN })
    const before = await controllerState(page)
    const midpoint = await hoverConnectionMidpoint(page, "bc")
    const button = page.locator('[data-edge-insert-for="bc"]')
    await expect(button).toBeVisible()
    const buttonBox = await button.boundingBox()
    const client = await clientPoint(page, midpoint.x, midpoint.y)
    expect(Math.abs(buttonBox.x + buttonBox.width / 2 - client.x)).toBeLessThanOrEqual(1)
    expect(Math.abs(buttonBox.y + buttonBox.height / 2 - client.y)).toBeLessThanOrEqual(1)

    await button.click()
    const menu = page.locator('[data-edge-insert-menu="bc"] [role="menu"]')
    await expect(menu).toBeVisible()
    await expect(menu.locator("[data-edge-insert-type]")).not.toHaveCount(0)
    await expect(menu.locator('[data-edge-insert-type="start"], [data-edge-insert-type="end"]')).toHaveCount(0)
    await menu.locator('[data-edge-insert-type="process"]').click()

    const after = await graph(page)
    const inserted = after.elements.find(el => !["a", "b", "c"].includes(el.id))
    expect(inserted.type).toBe("process")
    expect({ x: inserted.x, y: inserted.y }).toEqual({ x: snap(midpoint.x), y: snap(midpoint.y) })
    expect(after.connections.some(c => c.id === "bc")).toBe(false)
    expect(after.connections.some(c => c.from === "b" && c.to === inserted.id)).toBe(true)
    expect(after.connections.some(c => c.from === inserted.id && c.to === "c")).toBe(true)
    expect(after.selected).toEqual([inserted.id])
    expect(await positions(page)).toMatchObject({ a: { x: 307, y: 97 }, b: { x: 292, y: 233 }, c: { x: 318, y: 352 } })
    await expect(page.locator('[data-flowchart-canvas-target="propertySidebar"]')).toBeVisible()
    expect((await controllerState(page)).undoDepth).toBe(before.undoDepth + 1)

    const empty = await clientPoint(page, 60, 500)
    await page.mouse.click(empty.x, empty.y)
    await page.keyboard.press("ControlOrMeta+z")
    const undone = await graph(page)
    expect(undone.elements.map(el => el.id)).toEqual(["a", "b", "c"])
    expect(undone.connections.map(c => c.id)).toEqual(["ab", "bc"])
  })

  test("is never shown on a read-only canvas", async ({ page }) => {
    await bootCanvas(page, { configuration: CHAIN, readOnly: true })
    await hoverConnectionMidpoint(page, "bc")
    await page.waitForTimeout(300)
    await expect(page.locator("[data-edge-insert-for]")).toHaveCount(0)
    await hoverConnectionMidpoint(page, "ab")
    await page.waitForTimeout(300)
    await expect(page.locator("[data-edge-insert-for]")).toHaveCount(0)
  })
})

test.describe("Tidy layout", () => {
  const MESSY = {
    elements: [
      box("start", "start", 412, 64, "Start"),
      box("check", "decision", 233, 371, "Check"),
      box("yes", "process", 701, 158, "Yes path"),
      box("no", "process", 98, 512, "No path"),
      box("end", "end", 615, 610, "End"),
      box("orphan", "process", 905, 92, "Orphan")
    ],
    connections: [
      edge("c1", "start", "check"),
      edge("c2", "check", "yes", { fromPort: "port_0", label: "Yes", matchValue: "true" }),
      edge("c3", "check", "no", { fromPort: "port_1", label: "No", matchValue: "false" }),
      edge("c4", "yes", "end"),
      edge("c5", "no", "end")
    ]
  }

  test("is one undo step and redo re-applies it", async ({ page }) => {
    await bootCanvas(page, { configuration: MESSY })
    const original = await positions(page)
    const before = await controllerState(page)

    await page.getByTestId("tidy").click()
    const tidied = await positions(page)
    expect(tidied).not.toEqual(original)
    expect(tidied.start.y).toBeLessThan(tidied.check.y)
    expect(tidied.yes.x).toBeLessThan(tidied.no.x)
    expect(tidied.yes.y).toBe(tidied.no.y)
    expect(tidied.end.y).toBeGreaterThan(tidied.yes.y)
    expect(tidied.orphan.y).toBeGreaterThan(tidied.end.y)
    expect((await controllerState(page)).undoDepth).toBe(before.undoDepth + 1)

    const svgBox = await page.locator("svg.flowchart-svg").boundingBox()
    await page.mouse.click(svgBox.x + 20, svgBox.y + 20)
    await page.keyboard.press("ControlOrMeta+z")
    expect(await positions(page)).toEqual(original)
    await page.keyboard.press("ControlOrMeta+y")
    expect(await positions(page)).toEqual(tidied)
  })
})

test.describe("resize drift", () => {
  async function viewState(page) {
    return page.evaluate(() => {
      const canvas = document.querySelector('[data-controller="flowchart-canvas"]').flowchartCanvas
      const svg = canvas.svg
      const svgRect = svg.getBoundingClientRect()
      const groupRect = canvas.elementLayer.querySelector('[data-element-id="b"]').getBoundingClientRect()
      const [vx, vy, vw, vh] = svg.getAttribute("viewBox").split(" ").map(Number)
      return {
        viewBox: { vx, vy, vw, vh },
        client: { width: svg.clientWidth, height: svg.clientHeight },
        zoom: canvas.zoomPanManager.zoom,
        offset: { left: groupRect.left - svgRect.left, top: groupRect.top - svgRect.top },
        size: { width: groupRect.width, height: groupRect.height }
      }
    })
  }

  test("the viewBox follows the container size without moving or scaling content", async ({ page }) => {
    await bootCanvas(page, { configuration: CHAIN })
    await page.evaluate(() => {
      const root = document.querySelector('[data-controller="flowchart-canvas"]')
      const controller = window.Stimulus.getControllerForElementAndIdentifier(root, "flowchart-canvas")
      for (let i = 0; i < 3; i++) controller.zoomIn()
    })
    const svgBox = await page.locator("svg.flowchart-svg").boundingBox()
    await page.mouse.move(svgBox.x + 200, svgBox.y + 200)
    await page.mouse.wheel(-30, 45)
    const initial = await viewState(page)
    expect(initial.zoom).toBeCloseTo(1.3, 5)

    for (const size of [{ width: 900, height: 650 }, { width: 1500, height: 900 }, { width: 700, height: 500 }, { width: 1280, height: 800 }]) {
      await page.setViewportSize(size)
      await expect.poll(async () => {
        const state = await viewState(page)
        return Math.abs(state.viewBox.vw * state.zoom - state.client.width) < 0.01 &&
          Math.abs(state.viewBox.vh * state.zoom - state.client.height) < 0.01 &&
          state.client.width === size.width - 200
      }).toBe(true)
      const state = await viewState(page)
      expect(state.viewBox.vx).toBeCloseTo(initial.viewBox.vx, 6)
      expect(state.viewBox.vy).toBeCloseTo(initial.viewBox.vy, 6)
      expect(state.viewBox.vw).toBeCloseTo(state.client.width / state.zoom, 6)
      expect(state.viewBox.vh).toBeCloseTo(state.client.height / state.zoom, 6)
      expect(state.offset.left).toBeCloseTo(initial.offset.left, 1)
      expect(state.offset.top).toBeCloseTo(initial.offset.top, 1)
      expect(state.size.width).toBeCloseTo(initial.size.width, 1)
      expect(state.size.height).toBeCloseTo(initial.size.height, 1)
    }

    const start = (await positions(page)).b
    await dragBy(page, "b", 130, -65)
    expect((await positions(page)).b).toEqual({ x: snap(start.x + 130 / 1.3), y: snap(start.y - 65 / 1.3) })
  })
})

test.describe("arrow nudge", () => {
  test("moves the selection one grid step per arrow, one undo entry per burst", async ({ page }) => {
    await bootCanvas(page, { configuration: CHAIN })
    await node(page, "a").click()
    await node(page, "b").click({ modifiers: ["Shift"] })
    const depth = (await controllerState(page)).undoDepth
    const path = () => page.locator('[data-connection-id="bc"] path.connection-line').getAttribute("d")
    const pathBefore = await path()

    await page.keyboard.press("ArrowRight")
    await page.keyboard.press("ArrowRight")
    await page.keyboard.press("ArrowRight")
    expect(await positions(page)).toEqual({
      a: { x: 307 + 3 * GRID, y: 97 }, b: { x: 292 + 3 * GRID, y: 233 }, c: { x: 318, y: 352 }
    })
    expect(await path()).not.toBe(pathBefore)
    expect((await controllerState(page)).undoDepth).toBe(depth + 1)
    expect((await controllerState(page)).unsaved).toBe(true)

    await page.keyboard.press("ControlOrMeta+z")
    expect(await positions(page)).toEqual({ a: { x: 307, y: 97 }, b: { x: 292, y: 233 }, c: { x: 318, y: 352 } })
  })

  test("Shift+arrow nudges by 5× grid as one undo entry", async ({ page }) => {
    await bootCanvas(page, { configuration: CHAIN })
    await node(page, "c").click()
    const depth = (await controllerState(page)).undoDepth
    await page.keyboard.down("Shift")
    await page.keyboard.press("ArrowDown")
    await page.keyboard.press("ArrowLeft")
    await page.keyboard.up("Shift")
    expect((await positions(page)).c).toEqual({ x: 318 - 5 * GRID, y: 352 + 5 * GRID })
    expect((await controllerState(page)).undoDepth).toBe(depth + 1)
    await page.keyboard.press("ControlOrMeta+z")
    expect((await positions(page)).c).toEqual({ x: 318, y: 352 })
  })

  test("a 500 ms pause ends the burst: the next burst is its own undo entry", async ({ page }) => {
    await bootCanvas(page, { configuration: CHAIN })
    await node(page, "a").click()
    const depth = (await controllerState(page)).undoDepth
    await page.keyboard.press("ArrowRight")
    await page.keyboard.press("ArrowRight")
    await page.waitForTimeout(700)
    await page.keyboard.press("ArrowDown")
    expect((await positions(page)).a).toEqual({ x: 307 + 2 * GRID, y: 97 + GRID })
    expect((await controllerState(page)).undoDepth).toBe(depth + 2)
    await page.keyboard.press("ControlOrMeta+z")
    expect((await positions(page)).a).toEqual({ x: 307 + 2 * GRID, y: 97 })
  })

  test("is blocked on a read-only canvas", async ({ page }) => {
    await bootCanvas(page, { configuration: CHAIN, readOnly: true })
    await node(page, "a").click()
    expect((await graph(page)).selected).toEqual(["a"])
    await page.keyboard.press("ArrowRight")
    await page.keyboard.press("Shift+ArrowDown")
    expect(await positions(page)).toEqual({ a: { x: 307, y: 97 }, b: { x: 292, y: 233 }, c: { x: 318, y: 352 } })
    expect((await controllerState(page)).unsaved).toBe(false)
  })
})
