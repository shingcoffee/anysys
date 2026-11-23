import { test } from "@playwright/test"
import {
  bootCanvas, graph, positions, controllerState, clientPoint, node, dragBy, box, edge, snap, expect
} from "./_canvas_fixture.js"

// Real-browser rendering checks for the Phase 5 canvas: CJK label truncation
// with real fonts, the responsive minimap, whole-group re-render after a
// property edit, and the test-run overlay clearing on edit.

test.use({ viewport: { width: 1280, height: 800 } })

test.describe("zh-CN label truncation", () => {
  const LONG = "根据客户等级计算订单折扣并发送通知邮件"
  const CONFIG = {
    elements: [
      box("p", "process", 200, 120, LONG),
      box("d", "decision", 420, 120, LONG),
      box("s", "subflow", 640, 120, LONG, { properties: { flowchartId: 9 } }),
      box("short", "process", 200, 260, "审核订单")
    ],
    connections: []
  }

  test("long Chinese labels stay inside process/decision/subflow with … and a full-text <title>", async ({ page }, testInfo) => {
    await bootCanvas(page, { configuration: CONFIG })
    await page.evaluate(() => document.fonts.ready)
    const measured = await page.evaluate(async () => {
      const { estimateTextWidth } = await import("flowchart/element_renderer")
      const canvas = document.querySelector('[data-controller="flowchart-canvas"]').flowchartCanvas
      return canvas.elements.map(el => {
        const group = canvas.elementLayer.querySelector(`[data-element-id="${el.id}"]`)
        const text = group.querySelector("[data-element-label] text")
        const fontSize = Number(text.getAttribute("font-size"))
        const probe = text.cloneNode()
        probe.textContent = el.label
        group.appendChild(probe)
        const fullWidth = probe.getComputedTextLength()
        probe.remove()
        const bbox = text.getBBox()
        const toggle = group.querySelector("[data-subflow-toggle]")?.getBBox()
        return {
          id: el.id,
          type: el.type,
          width: el.width,
          height: el.height,
          shown: text.textContent,
          title: group.querySelector("[data-element-label] > title")?.textContent ?? null,
          fontSize,
          bbox: { x: bbox.x, y: bbox.y, width: bbox.width, height: bbox.height },
          fullWidth,
          estimatedFullWidth: estimateTextWidth(el.label, fontSize),
          toggle: toggle ? { x: toggle.x, y: toggle.y, width: toggle.width, height: toggle.height } : null
        }
      })
    })
    await testInfo.attach("label-geometry", { body: JSON.stringify(measured, null, 2), contentType: "application/json" })

    for (const label of measured.filter(m => m.id !== "short")) {
      expect(label.shown.endsWith("…"), label.id).toBe(true)
      expect(LONG.startsWith(label.shown.slice(0, -1)), label.id).toBe(true)
      expect(label.title, label.id).toBe(LONG)
      // CJK estimate (1 em per glyph) within 5 % of the real font.
      expect(Math.abs(label.estimatedFullWidth - label.fullWidth) / label.fullWidth, label.id).toBeLessThan(0.05)
      const { x, y, width, height } = label.bbox
      if (label.type === "decision") {
        const inside = ([px, py]) => Math.abs(px - label.width / 2) / (label.width / 2) + Math.abs(py - label.height / 2) / (label.height / 2) <= 1
        for (const corner of [[x, y], [x + width, y], [x, y + height], [x + width, y + height]]) {
          expect(inside(corner), `${label.id} corner ${corner}`).toBe(true)
        }
      } else {
        // Process border / subflow side bands are 8 px wide.
        expect(x, label.id).toBeGreaterThanOrEqual(8)
        expect(x + width, label.id).toBeLessThanOrEqual(label.width - 8)
        expect(y, label.id).toBeGreaterThanOrEqual(0)
        expect(y + height, label.id).toBeLessThanOrEqual(label.height)
      }
    }

    const short = measured.find(m => m.id === "short")
    expect(short.shown).toBe("审核订单")
    expect(short.title).toBeNull()
  })
})

test.describe("minimap", () => {
  const SPREAD = {
    elements: [
      box("top", "start", 120, 60, "Start"),
      box("mid", "process", 900, 700, "Middle"),
      box("far", "end", 1700, 1300, "End")
    ],
    connections: []
  }

  async function minimapState(page) {
    return page.evaluate(() => {
      const container = document.querySelector('[data-flowchart-canvas-target="minimapContainer"]')
      const svg = container.querySelector("svg")
      const containerRect = container.getBoundingClientRect()
      const svgRect = svg.getBoundingClientRect()
      return {
        container: { left: containerRect.left, top: containerRect.top, clientWidth: container.clientWidth, clientHeight: container.clientHeight },
        svg: { left: svgRect.left, top: svgRect.top, width: svgRect.width, height: svgRect.height, attrWidth: Number(svg.getAttribute("width")), attrHeight: Number(svg.getAttribute("height")) },
        rects: [...svg.querySelectorAll("g:nth-of-type(2) > rect")].map(rect => {
          const r = rect.getBoundingClientRect()
          return { x: r.left + r.width / 2, y: r.top + r.height / 2 }
        })
      }
    })
  }

  const viewportCentre = page => page.evaluate(() => {
    const zpm = document.querySelector('[data-controller="flowchart-canvas"]').flowchartCanvas.zoomPanManager
    return { x: zpm.panX + zpm.viewWidth / 2, y: zpm.panY + zpm.viewHeight / 2 }
  })

  async function expectClickCentres(page, rectIndex, element) {
    const state = await minimapState(page)
    const target = state.rects[rectIndex]
    await page.mouse.click(target.x, target.y)
    const centre = await viewportCentre(page)
    // One minimap pixel is ~1/scale canvas units; allow two of them.
    const scale = await page.evaluate(() => window.Stimulus.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller="flowchart-canvas"]'), "flowchart-canvas"
    ).minimapManager._scale)
    expect(Math.abs(centre.x - element.x)).toBeLessThanOrEqual(2 / scale)
    expect(Math.abs(centre.y - element.y)).toBeLessThanOrEqual(2 / scale)
  }

  test("fills its 160×120 box below sm, centres on click, follows a resize across sm, sits above the bottom panel", async ({ page }) => {
    await page.setViewportSize({ width: 500, height: 700 })
    await bootCanvas(page, { configuration: SPREAD })

    let state = await minimapState(page)
    expect([state.container.clientWidth, state.container.clientHeight]).toEqual([158, 118])
    expect([state.svg.attrWidth, state.svg.attrHeight]).toEqual([158, 118])
    expect(state.svg.width).toBeCloseTo(158, 0)
    expect(state.svg.height).toBeCloseTo(118, 0)
    expect(state.svg.left).toBeCloseTo(state.container.left + 1, 0)
    expect(state.svg.top).toBeCloseTo(state.container.top + 1, 0)
    expect(state.rects).toHaveLength(3)
    for (const rect of state.rects) {
      expect(rect.x).toBeGreaterThan(state.svg.left)
      expect(rect.x).toBeLessThan(state.svg.left + state.svg.width)
      expect(rect.y).toBeGreaterThan(state.svg.top)
      expect(rect.y).toBeLessThan(state.svg.top + state.svg.height)
    }
    await expectClickCentres(page, 1, { x: 900, y: 700 })
    await expectClickCentres(page, 2, { x: 1700, y: 1300 })

    await page.setViewportSize({ width: 1000, height: 700 })
    await expect.poll(async () => {
      const s = await minimapState(page)
      return [s.container.clientWidth, s.container.clientHeight, s.svg.attrWidth, s.svg.attrHeight]
    }).toEqual([198, 138, 198, 138])
    await expectClickCentres(page, 0, { x: 120, y: 60 })

    await page.setViewportSize({ width: 500, height: 700 })
    await expect.poll(async () => {
      const s = await minimapState(page)
      return [s.svg.attrWidth, s.svg.attrHeight]
    }).toEqual([158, 118])

    await page.evaluate(() => {
      const root = document.querySelector('[data-controller="flowchart-canvas"]')
      window.Stimulus.getControllerForElementAndIdentifier(root, "flowchart-canvas").openBottomPanel("problems")
    })
    const panel = page.locator('[data-flowchart-canvas-target="bottomPanel"]')
    await expect(panel).toBeVisible()
    state = await minimapState(page)
    const panelBox = await panel.boundingBox()
    expect(state.svg.top + state.svg.height).toBeLessThanOrEqual(panelBox.y)
    const hit = await page.evaluate(({ x, y }) => {
      const target = document.elementFromPoint(x, y)
      return !!target?.closest('[data-flowchart-canvas-target="minimapContainer"]')
    }, { x: state.svg.left + state.svg.width / 2, y: state.svg.top + state.svg.height / 2 })
    expect(hit).toBe(true)
    await page.locator('[data-flowchart-canvas-target="bottomTab"][data-tab="elements"]').click()
    await expect(page.locator('[data-tab-content="elements"]')).toBeVisible()
    await expectClickCentres(page, 1, { x: 900, y: 700 })
  })
})

test.describe("re-render after a property edit", () => {
  const CONFIG = {
    elements: [
      box("p1", "process", 260, 120, "First"),
      box("p2", "process", 260, 260, "Second"),
      box("p3", "process", 350, 280, "Third")
    ],
    connections: [edge("c1", "p1", "p2")]
  }

  test("keeps selection outline, validation ring, z-order and resize handles; hover and drag work on the new group", async ({ page }) => {
    await bootCanvas(page, { configuration: CONFIG })
    await page.getByTestId("validate").click()
    await expect(node(page, "p2").locator("[data-validation-ring]")).toHaveCount(1)

    await node(page, "p2").dblclick()
    await expect(page.locator('[data-flowchart-canvas-target="propertySidebar"]')).toBeVisible()
    expect((await graph(page)).selected).toEqual(["p2"])
    await expect(page.locator('[data-resize-handle][data-resize-element-id="p2"]')).toHaveCount(4)
    const before = await page.evaluate(() => {
      const canvas = document.querySelector('[data-controller="flowchart-canvas"]').flowchartCanvas
      const group = canvas.elementLayer.querySelector('[data-element-id="p2"]')
      group.__beforeEdit = true
      return {
        index: [...canvas.elementLayer.children].indexOf(group),
        ring: group.querySelector("[data-validation-ring]").dataset.validationSeverity
      }
    })

    await page.locator('[data-tab="general"]').click()
    await page.locator('[data-flowchart-canvas-target="propertySidebar"] input[name="label"]').fill("Renamed box")
    await expect(node(page, "p2").locator("[data-element-label] text")).toHaveText("Renamed box")

    const after = await page.evaluate(() => {
      const canvas = document.querySelector('[data-controller="flowchart-canvas"]').flowchartCanvas
      const group = canvas.elementLayer.querySelector('[data-element-id="p2"]')
      const handles = [...canvas.handleLayer.querySelectorAll('[data-resize-handle][data-resize-element-id="p2"] .resize-handle')]
        .map(handle => handle.getBoundingClientRect())
      const rect = group.querySelector("rect").getBoundingClientRect()
      return {
        fresh: !group.__beforeEdit,
        selected: group.classList.contains("selected"),
        ring: group.querySelector("[data-validation-ring]")?.dataset.validationSeverity ?? null,
        index: [...canvas.elementLayer.children].indexOf(group),
        handleCentres: handles.map(h => [Math.round(h.left + h.width / 2), Math.round(h.top + h.height / 2)]).sort(),
        corners: [[rect.left, rect.top], [rect.right, rect.top], [rect.left, rect.bottom], [rect.right, rect.bottom]]
          .map(([x, y]) => [Math.round(x), Math.round(y)]).sort()
      }
    })
    expect(after.fresh).toBe(true)
    expect(after.selected).toBe(true)
    expect(after.ring).toBe(before.ring)
    expect(after.index).toBe(before.index)
    expect(after.handleCentres).toHaveLength(4)
    after.handleCentres.forEach((centre, i) => {
      expect(Math.abs(centre[0] - after.corners[i][0])).toBeLessThanOrEqual(2)
      expect(Math.abs(centre[1] - after.corners[i][1])).toBeLessThanOrEqual(2)
    })

    const groupBox = await node(page, "p2").boundingBox()
    await page.mouse.move(groupBox.x + 20, groupBox.y + 10)
    await page.mouse.move(groupBox.x + 30, groupBox.y + 15)
    await expect(page.locator(".flowchart-tooltip")).toHaveText("Renamed box")

    await dragBy(page, "p2", -120, 135)
    // Vertical connection from p1 (x: 260) aligns p2's X with p1 while snapping Y
    expect((await positions(page)).p2).toEqual({ x: 260, y: snap(260 + 135) })
    expect(await node(page, "p2").getAttribute("transform")).toBe(`translate(${260 - 50}, ${snap(395) - 22.5})`)
  })

  test("two separate edits of the same field are two undo entries", async ({ page }) => {
    await bootCanvas(page, { configuration: CONFIG })
    await node(page, "p1").dblclick()
    const label = page.locator('[data-flowchart-canvas-target="propertySidebar"] input[name="label"]')
    const title = page.locator('[data-property-editor-target="title"]')
    await page.locator('[data-tab="general"]').click()
    const depth = (await controllerState(page)).undoDepth
    await label.fill("One")
    await title.click()
    await expect(node(page, "p1").locator("[data-element-label] text")).toHaveText("One")
    await label.fill("Two")
    await title.click()
    await expect(node(page, "p1").locator("[data-element-label] text")).toHaveText("Two")
    expect((await controllerState(page)).undoDepth).toBe(depth + 2)
  })
})

test.describe("test-run trace overlay", () => {
  test("disappears after dragging an element", async ({ page }) => {
    await bootCanvas(page, {
      configuration: {
        elements: [box("start", "start", 260, 80, "Start"), box("work", "process", 260, 200, "Work"), box("end", "end", 260, 320, "End")],
        connections: [edge("c1", "start", "work"), edge("c2", "work", "end")]
      }
    })
    await page.evaluate(() => {
      const canvas = document.querySelector('[data-controller="flowchart-canvas"]').flowchartCanvas
      canvas.showTraceOverlay([
        { element_id: "start", status: "success" },
        { element_id: "work", status: "success" },
        { element_id: "end", status: "success" }
      ])
    })
    const overlay = page.locator("svg.flowchart-svg .trace-overlay-layer")
    await expect(overlay).toHaveCount(1)
    await expect(overlay.locator("rect.trace-overlay-rect")).toHaveCount(3)

    // A click without movement is not an edit: the overlay stays.
    await node(page, "work").click()
    await expect(overlay).toHaveCount(1)

    await dragBy(page, "work", 0, 90)
    expect((await positions(page)).work).toEqual({ x: 260, y: snap(200 + 90) })
    await expect(overlay).toHaveCount(0)
  })
})
