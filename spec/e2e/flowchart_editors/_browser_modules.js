import { expect } from "@playwright/test"
import { readdirSync, readFileSync } from "node:fs"

// Mirror the app's bare ESM imports for the existing static Playwright server.
const sourceRoot = new URL("../../../app/javascript/", import.meta.url)
const imports = Object.fromEntries(readdirSync(sourceRoot, { recursive: true })
  .filter(path => path.endsWith(".js"))
  .map(path => [path.replace(/\.js$/, ""), `/app/javascript/${path}`]))
imports.utils = "/app/javascript/utils/index.js"
imports["@hotwired/stimulus"] = "/node_modules/@hotwired/stimulus/dist/stimulus.js"

export const ELEMENT_CATALOG = JSON.parse(readFileSync(new URL(
  "../../../spec/javascript/fixtures/element_catalog.sample.json", import.meta.url
)))
export const ACTION_CATALOG = JSON.parse(readFileSync(new URL(
  "../../../spec/javascript/fixtures/action_catalog.sample.json", import.meta.url
)))

export const EDITOR_URLS = {
  update: "/81721200/admin/maintenance/flowcharts/1",
  versions: "/81721200/admin/maintenance/flowcharts/1/versions",
  validation: "/81721200/admin/maintenance/flowcharts/1/validation",
  traces: "/81721200/admin/maintenance/flowcharts/1/traces",
  document: "/81721200/admin/maintenance/flowcharts/1/document",
  list: "/81721200/admin/maintenance/flowcharts.json",
  implicitKeys: "/81721200/admin/maintenance/flowcharts/validation/implicit_keys.json",
  stepIoParams: "/81721200/admin/maintenance/flowcharts/step_actions/__ACTION__/io_params",
  elementIoParams: "/81721200/admin/maintenance/flowcharts/element_types/__TYPE__/io_params",
  referenceOptions: "/81721200/admin/maintenance/flowcharts/reference_options/__SOURCE__.json"
}

export async function loadEditorFixture(page) {
  await page.goto("http://127.0.0.1:3011/spec/e2e/flowchart_editors/fixture.html")
  await page.addScriptTag({ type: "importmap", content: JSON.stringify({ imports }) })
}

export async function bootEditor(page, {
  type = "process",
  properties = {},
  label,
  connections = [],
  extraElements = [],
  referenceOptions = [{ value: "9", label: "Order Processing" }]
} = {}) {
  await page.route("**/81721200/admin/maintenance/flowcharts/reference_options/**", async route => {
    await route.fulfill({ json: { options: referenceOptions } })
  })
  await loadEditorFixture(page)
  await page.evaluate(async ({ type, properties, label, connections, extraElements, elementCatalog, actionCatalog, urls }) => {
    const [
      { Application },
      { default: Editor },
      { default: Canvas },
      { default: ReferencePicker },
      { default: Conditions }
    ] = await Promise.all([
      import("@hotwired/stimulus"),
      import("controllers/property_editor_controller"),
      import("controllers/flowchart_canvas_controller"),
      import("controllers/property_editor/controls/reference_picker_controller"),
      import("controllers/property_editor/controls/conditions_controller")
    ])
    const root = document.querySelector('[data-controller="flowchart-canvas"]')
    root.dataset.flowchartCanvasElementCatalogValue = JSON.stringify(elementCatalog)
    root.dataset.flowchartCanvasActionCatalogValue = JSON.stringify(actionCatalog)
    root.dataset.flowchartCanvasUrlsValue = JSON.stringify(urls)
    const application = Application.start()
    application.register("property-editor", Editor)
    application.register("flowchart-canvas", Canvas)
    application.register("property-editor--controls--reference-picker", ReferencePicker)
    application.register("property-editor--controls--conditions", Conditions)
    window.editorApp = application
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))
    const canvasController = application.getControllerForElementAndIdentifier(root, "flowchart-canvas")
    const editor = application.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller="property-editor"]'),
      "property-editor"
    )
    const node = canvasController.canvas.addElement({
      type,
      properties,
      label: label || `Browser ${type}`
    })
    extraElements.forEach((item, index) => canvasController.canvas.addElement({
      ...item,
      x: item.x ?? 240 + index * 180,
      y: item.y ?? 240
    }))
    connections.forEach(connection => {
      const from = canvasController.canvas.elements.find(el => el.id === (connection.from === "__node__" ? node.id : connection.from))
      const to = canvasController.canvas.elements.find(el => el.id === connection.to)
      if (from && to) {
        canvasController.canvas.createConnection(from, to, connection.fromPort || "bottom", connection.toPort || "top", {
          label: connection.label || "",
          matchValue: connection.matchValue,
          description: connection.description || ""
        })
      }
    })
    editor.openEditor(node, canvasController.canvas)
    window.editorFixture = { editor, canvasController, node }
  }, { type, properties, label, connections, extraElements, elementCatalog: ELEMENT_CATALOG, actionCatalog: ACTION_CATALOG, urls: EDITOR_URLS })
}

export async function nativeSave(page) {
  const payloads = []
  await page.route("**/81721200/admin/maintenance/flowcharts/1", async route => {
    if (route.request().method() !== "PATCH") {
      await route.continue()
      return
    }
    payloads.push(JSON.parse(route.request().postDataJSON().flowchart.configuration))
    await route.fulfill({ json: { success: true } })
  })
  await page.locator('[data-property-editor-target="saveButton"]').click()
  await expect.poll(() => payloads.length).toBe(1)
  await expect(page.locator('[data-property-editor-target="saveButton"]')).toContainText("Saved!")
  return payloads[0]
}

export function tabKeys(page) {
  return page.locator('[data-property-editor-target="tabBar"] button[data-tab]').evaluateAll(
    buttons => buttons.map(button => button.dataset.tab)
  )
}

export async function assertNoSidebarOverflow(page) {
  const geometry = await page.locator('[data-property-editor-target="sidebar"]').evaluate(sidebar => {
    const rect = sidebar.getBoundingClientRect()
    return {
      clientWidth: sidebar.clientWidth,
      scrollWidth: sidebar.scrollWidth,
      right: rect.right,
      viewportWidth: window.innerWidth
    }
  })
  expect(geometry.scrollWidth).toBeLessThanOrEqual(geometry.clientWidth + 1)
  expect(geometry.right).toBeLessThanOrEqual(geometry.viewportWidth + 1)
}

export { expect }
