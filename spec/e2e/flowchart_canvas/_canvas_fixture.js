import { expect } from "@playwright/test"
import { readdirSync } from "node:fs"
import { ACTION_CATALOG, ELEMENT_CATALOG, EDITOR_URLS } from "../flowchart_editors/_browser_modules.js"

// Mirror the app's bare ESM imports for the static Playwright server.
const sourceRoot = new URL("../../../app/javascript/", import.meta.url)
const imports = Object.fromEntries(readdirSync(sourceRoot, { recursive: true })
  .filter(path => path.endsWith(".js"))
  .map(path => [path.replace(/\.js$/, ""), `/app/javascript/${path}`]))
imports.utils = "/app/javascript/utils/index.js"
imports["@hotwired/stimulus"] = "/node_modules/@hotwired/stimulus/dist/stimulus.js"

export const GRID = 15
export const snap = value => Math.round(value / GRID) * GRID

export const SUBFLOW_ID = 9
export const SUBFLOW_CONFIGURATION = {
  elements: [
    { id: "s_start", type: "start", x: 100, y: 60, width: 100, height: 45, label: "Inner start", properties: {} },
    { id: "s_work", type: "process", x: 100, y: 150, width: 100, height: 45, label: "Inner work", properties: { steps: [{ id: "st1", action: "log", config: { messageTemplate: "x" } }] } },
    { id: "s_end", type: "end", x: 100, y: 240, width: 100, height: 45, label: "Inner end", properties: {} }
  ],
  connections: [
    { id: "s_c1", from: "s_start", to: "s_work", fromPosition: "bottom", toPosition: "top" },
    { id: "s_c2", from: "s_work", to: "s_end", fromPosition: "bottom", toPosition: "top" }
  ]
}

const json = body => ({ status: 200, contentType: "application/json", body: JSON.stringify(body) })

/**
 * Serve the editor's HTTP surface from memory. `saves` collects PATCH bodies;
 * `respondToSave(body)` may return a custom Playwright fulfil object.
 */
async function routeEditorHttp(page, { validationProblems = [], respondToSave } = {}) {
  const saves = []
  await page.route(url => url.pathname.startsWith("/81721200/admin/maintenance/flowcharts"), async route => {
    const request = route.request()
    const url = new URL(request.url())
    const path = url.pathname
    if (path.endsWith("/io_params")) return route.fulfill(json({ inputs: [], outputs: [] }))
    if (path.includes("/reference_options/")) return route.fulfill(json({ options: [{ value: String(SUBFLOW_ID), label: "Order Processing" }] }))
    if (path.endsWith("/implicit_keys.json")) return route.fulfill(json({ keys: [] }))
    if (path.endsWith("/validation")) return route.fulfill(json({ problems: validationProblems }))
    if (path.endsWith(`/flowcharts/${SUBFLOW_ID}.json`)) {
      return route.fulfill(json({ id: SUBFLOW_ID, configuration: JSON.stringify(SUBFLOW_CONFIGURATION) }))
    }
    if (path.endsWith("/flowcharts.json")) return route.fulfill(json([{ id: SUBFLOW_ID, name: "Order Processing" }]))
    if (path.endsWith("/flowcharts/1") && request.method() === "PATCH") {
      const body = request.postDataJSON()
      saves.push(body)
      return route.fulfill(respondToSave?.(body, saves.length) ?? json({ success: true, version_id: 100 + saves.length }))
    }
    return route.fulfill({ status: 404, body: "" })
  })
  return saves
}

/**
 * Boot the real FlowchartCanvasController (+ property editor and palette)
 * on the static fixture with `configuration` and wait until it is ready.
 */
export async function bootCanvas(page, { configuration, readOnly = false, values = {}, ...http } = {}) {
  const errors = []
  page.on("pageerror", error => errors.push(error.message))
  const saves = await routeEditorHttp(page, http)
  await page.goto("http://127.0.0.1:3011/spec/e2e/flowchart_canvas/fixture.html")
  await page.addScriptTag({ type: "importmap", content: JSON.stringify({ imports }) })
  await page.evaluate(async ({ configuration, readOnly, values, elementCatalog, actionCatalog, urls }) => {
    const [
      { Application },
      { default: Canvas },
      { default: Editor },
      { default: Palette },
      { default: ReferencePicker }
    ] = await Promise.all([
      import("@hotwired/stimulus"),
      import("controllers/flowchart_canvas_controller"),
      import("controllers/property_editor_controller"),
      import("controllers/element_palette_controller"),
      import("controllers/property_editor/controls/reference_picker_controller")
    ])
    const root = document.querySelector('[data-controller="flowchart-canvas"]')
    root.dataset.flowchartCanvasElementCatalogValue = JSON.stringify(elementCatalog)
    root.dataset.flowchartCanvasActionCatalogValue = JSON.stringify(actionCatalog)
    root.dataset.flowchartCanvasUrlsValue = JSON.stringify(urls)
    root.dataset.flowchartCanvasReadOnlyValue = String(readOnly)
    if (configuration) root.dataset.flowchartCanvasConfigurationValue = JSON.stringify(configuration)
    for (const [name, value] of Object.entries(values)) root.dataset[name] = value
    const application = Application.start()
    application.register("flowchart-canvas", Canvas)
    application.register("property-editor", Editor)
    application.register("element-palette", Palette)
    application.register("property-editor--controls--reference-picker", ReferencePicker)
    window.Stimulus = application
    await new Promise(resolve => {
      const check = () => {
        const controller = application.getControllerForElementAndIdentifier(root, "flowchart-canvas")
        controller?.isCanvasReady ? resolve() : requestAnimationFrame(check)
      }
      check()
    })
  }, { configuration, readOnly, values, elementCatalog: ELEMENT_CATALOG, actionCatalog: ACTION_CATALOG, urls: EDITOR_URLS })
  await expect(page.locator("svg.flowchart-svg")).toBeVisible()
  return { saves, errors }
}

/** Plain-data snapshot of the live canvas. */
export function graph(page) {
  return page.evaluate(() => {
    const canvas = document.querySelector('[data-controller="flowchart-canvas"]').flowchartCanvas
    return {
      elements: canvas.elements.map(({ id, type, x, y, width, height, label }) => ({ id, type, x, y, width, height, label })),
      connections: canvas.connections.map(({ id, from, to, fromPort, fromPosition, toPosition, label }) => ({ id, from, to, fromPort, fromPosition, toPosition, label })),
      selected: canvas.selectedElements.map(el => el.id)
    }
  })
}

export const positions = async page => Object.fromEntries((await graph(page)).elements.map(el => [el.id, { x: el.x, y: el.y }]))

export function controllerState(page) {
  return page.evaluate(() => {
    const root = document.querySelector('[data-controller="flowchart-canvas"]')
    const controller = window.Stimulus.getControllerForElementAndIdentifier(root, "flowchart-canvas")
    return {
      undoDepth: controller.undoRedoManager.undoStack.length,
      redoDepth: controller.undoRedoManager.redoStack.length,
      unsaved: controller.hasUnsavedChanges,
      previewMode: controller.canvas.previewMode
    }
  })
}

/** Client point of an SVG (canvas) coordinate, through the live screen CTM. */
export function clientPoint(page, x, y) {
  return page.evaluate(({ x, y }) => {
    const svg = document.querySelector("svg.flowchart-svg")
    const point = new DOMPoint(x, y).matrixTransform(svg.getScreenCTM())
    return { x: point.x, y: point.y }
  }, { x, y })
}

/** SVG (canvas) coordinate under a client point, through the live screen CTM. */
export function svgPoint(page, x, y) {
  return page.evaluate(({ x, y }) => {
    const svg = document.querySelector("svg.flowchart-svg")
    const point = new DOMPoint(x, y).matrixTransform(svg.getScreenCTM().inverse())
    return { x: point.x, y: point.y }
  }, { x, y })
}

export const node = (page, id) => page.locator(`.element-layer > [data-element-id="${id}"]`)

/** Trusted mouse drag of an element's centre by (dx, dy) client pixels. */
export async function dragBy(page, id, dx, dy, { modifiers = [] } = {}) {
  const box = await node(page, id).boundingBox()
  const x = box.x + box.width / 2
  const y = box.y + box.height / 2
  for (const key of modifiers) await page.keyboard.down(key)
  await page.mouse.move(x, y)
  await page.mouse.down()
  await page.mouse.move(x + dx / 2, y + dy / 2, { steps: 8 })
  await page.mouse.move(x + dx, y + dy, { steps: 8 })
  await page.mouse.up()
  for (const key of modifiers) await page.keyboard.up(key)
  return { from: { x, y }, to: { x: x + dx, y: y + dy } }
}

/** Move the mouse onto a connection's midpoint; returns that SVG point. */
export async function hoverConnectionMidpoint(page, connectionId) {
  const midpoint = await page.evaluate(id => {
    const canvas = document.querySelector('[data-controller="flowchart-canvas"]').flowchartCanvas
    return canvas._connectionMidpoint(canvas.connections.find(c => c.id === id))
  }, connectionId)
  const client = await clientPoint(page, midpoint.x, midpoint.y)
  await page.mouse.move(client.x - 40, client.y)
  await page.mouse.move(client.x, client.y, { steps: 5 })
  return midpoint
}

export const box = (id, type, x, y, label = id, extra = {}) =>
  ({ id, type, x, y, width: 100, height: 45, label, properties: {}, ...extra })

export const edge = (id, from, to, extra = {}) =>
  ({ id, from, to, fromPosition: "bottom", toPosition: "top", ...extra })

export { expect }
