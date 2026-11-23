import Controller from "controllers/property_editor_controller"
import { FlowchartCanvas } from "flowchart/canvas"
import { defaultPropertiesFor } from "flowchart/element_config"
import { mountController, controllerFor, tick } from "../../../support/stimulus.js"
import "../../../support/scoped_selectors.js"
import "../../../support/mutation_observers.js"

const parsedSelects = new WeakSet()
function initializeParsedSelects() {
  // happy-dom 15.11.7 selects option #2 when parsing a later `selected`
  // attribute (even a three-option standalone select reproduces this). Restore
  // the browser's HTML parsing contract from the actual rendered attributes,
  // once per new select, never from schemas or expected test values. Chromium
  // app specs independently exercise the unmodified markup/selection behavior.
  document.querySelectorAll("select").forEach(select => {
    if (parsedSelects.has(select)) return
    parsedSelects.add(select)
    const selected = select.querySelector("option[selected]") || select.options[0]
    if (selected) select.value = selected.value
  })
}

// Real Stimulus actions, managers, schemas, collectors and SVG canvas. No seam
// mocks: browser-only layout/pointer assertions live in spec/e2e/flowchart_editors.
export async function mountEditor(type, properties = {}, { readOnly = false } = {}) {
  const { application, element } = await mountController("property-editor", Controller, `
    <div data-controller="flowchart-canvas" data-flowchart-canvas-read-only-value="${readOnly}"><div id="canvas"></div></div>
    <div data-controller="property-editor">
      <aside data-property-editor-target="sidebar" class="hidden">
        <span data-property-editor-target="title"></span>
        <nav data-property-editor-target="tabBar"></nav>
        <form data-property-editor-target="form" data-action="submit->property-editor#save">
          ${["General", "Steps", "Io", "Advanced"].map(tab => `<div data-property-editor-target="tabPane${tab}"><div data-property-editor-target="formFields${tab}"></div></div>`).join("")}
          <button type="submit" data-property-editor-target="saveButton">Save</button>
          <button type="button" data-action="property-editor#close">Close</button>
        </form>
      </aside>
    </div>`)
  const controller = controllerFor(application, element, "property-editor")
  const canvas = new FlowchartCanvas(document.querySelector("#canvas"))
  canvas.isReadOnly = readOnly
  const node = { id: `${type}-1`, type, label: `Custom ${type}`, x: 400, y: 80, width: 160, height: 60,
    properties: { ...defaultPropertiesFor(type), ...properties } }
  canvas.elements.push(node)
  canvas.renderElement(node)
  controller.openEditor(node, canvas)
  await tick()
  initializeParsedSelects()
  return {
    application, controller, canvas, node,
    field: name => controller.formTarget.elements.namedItem(name),
    async reopen() {
      // discardAndClose skips C3 snapshot restore so this helper rebuilds the
      // form from the current canvas (already synced). Cancel/close restore is
      // asserted in read_only + property_editor_controller C3 specs.
      controller.discardAndClose()
      controller.openEditor(node, canvas)
      await tick()
      initializeParsedSelects()
    },
    async dispose() {
      controller.discardAndClose()
      element.remove()
      await tick()
      canvas.destroy()
      application.stop()
    }
  }
}

export async function change(input, value) {
  input.value = String(value)
  input.dispatchEvent(new Event("input", { bubbles: true }))
  input.dispatchEvent(new Event("change", { bubbles: true }))
  await tick()
  initializeParsedSelects()
}

export async function press(element) {
  // happy-dom delivers MutationObservers through debounced timers. A queued
  // canvas sync can reset that timer during a single tick, leaving rebuilt
  // buttons unbound under coverage load. Drain pending DOM work before the
  // one real click; do not retry clicks (which could remove a second row).
  await window.happyDOM.waitUntilComplete()
  element.click()
  await tick()
}

export function sync(editor) {
  editor.controller._performSync()
  return editor.node.properties
}
