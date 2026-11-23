/**
 * ElementIoManager renders the I/O tab for the currently-edited element.
 *
 * Layout:
 *
 *   Inputs
 *   ─────────────────────────────────────
 *    model   [ producer dropdown ▾ ]  (nearest | tombstone)
 *    ...
 *
 *   Outputs
 *   ─────────────────────────────────────
 *    user
 *    token   ⚠ renamed → token_b7e1
 *
 * Producer dropdown lists every reachable predecessor that emits a
 * matching effective key; the first option is `— no producer —` (stores a
 * tombstone override_key=""). Selecting any option writes
 * element.properties.io_overrides.inputs and re-renders.
 *
 * Output rename badges come from override_computer: an element whose pin
 * collides with another emitter is auto-renamed. Read-only.
 */
import { refreshElementPins, subscribeElementPins } from "controllers/property_editor/element_io/io_params_client"
import { computeElementOverrides } from "controllers/property_editor/element_io/override_computer"
import { ElementReachability } from "controllers/property_editor/element_io/reachability"
import {
  renderInputsSection,
  renderOutputsSection,
  renderReadOnlyInputRow,
  renderEditableInputRow,
  NO_PRODUCER_SENTINEL
} from "controllers/property_editor/element_io/renderers"

export class ElementIoManager {
  constructor(controller) {
    this.controller = controller
  }

  async openForElement(element, paneElement) {
    if (!element || !paneElement) return
    const canvas = this.controller.canvas
    if (!canvas) return

    this._currentElement = element
    this._currentPane = paneElement
    this._subscribeToStructureChanges()

    this._openEpoch = (this._openEpoch || 0) + 1
    this._unsubscribePins?.()
    this._unsubscribePins = subscribeElementPins(canvas, element.id, () => this._renderCurrentPins(element, paneElement))

    const cached = canvas.getElementPins(element.id)
    const needsFetch =
      !cached || ((cached.inputs?.length || 0) + (cached.outputs?.length || 0) === 0)
    if (needsFetch) {
      // The subscription renders the accepted result, even if another config
      // request supersedes this one. Never wait for an obsolete HTTP response
      // to hand the winning background result to the active pane.
      await refreshElementPins(canvas, element.id)
    } else {
      await this._renderCurrentPins(element, paneElement)
    }
  }

  async _renderCurrentPins(element, paneElement) {
    const canvas = this.controller.canvas
    element = canvas.elements.find(current => current.id === element.id)
    if (!element) return
    const epoch = (this._openEpoch = (this._openEpoch || 0) + 1)
    const configuration = JSON.stringify(element.properties)
    const pins = canvas.getElementPins(element.id)

    const computed = await computeElementOverrides(canvas, element.id)
    if (epoch !== this._openEpoch || !canvas.elements.includes(element) || configuration !== JSON.stringify(element.properties)) return

    // Viewing a launched diagram must not write even automatically computed
    // overrides. Render against a detached property bag after the await.
    if (this.controller._isCanvasReadOnly?.()) {
      element = { ...element, properties: { ...element.properties } }
    }
    element.properties = element.properties || {}
    element.properties.io_overrides = this._merge(element.properties.io_overrides, computed)

    this._render(element, paneElement, pins)
  }

  updateProducer(elementId, pinName, overrideKey) {
    if (this.controller._isCanvasReadOnly?.()) return
    const canvas = this.controller.canvas
    const el = canvas.elements.find((e) => e.id === elementId)
    if (!el) return
    el.properties = el.properties || {}
    el.properties.io_overrides = el.properties.io_overrides || { inputs: [], outputs: [] }

    const list = el.properties.io_overrides.inputs
    const idx = list.findIndex((x) => x.pin === pinName)
    if (overrideKey === null) {
      if (idx !== -1) list.splice(idx, 1)
    } else {
      const entry = { pin: pinName, override_key: overrideKey }
      if (idx === -1) list.push(entry)
      else list[idx] = entry
    }
    canvas.onchange && canvas.onchange()
  }

  close() {
    this._unsubscribePins?.()
    this._unsubscribePins = null
    const svg = this.controller.canvas?.svg
    if (svg && this._structureListener) {
      svg.removeEventListener("flowchartStructureChanged", this._structureListener)
    }
    this._structureListener = null
    clearTimeout(this._reRenderTimer)
    this._reRenderTimer = null
    this._openEpoch = (this._openEpoch || 0) + 1
    this._currentElement = null
    this._currentPane = null
  }

  _subscribeToStructureChanges() {
    if (this._structureListener) return
    const svg = this.controller.canvas?.svg
    if (!svg) return
    this._structureListener = () => {
      // Re-render on ANY structure change because collision detection depends
      // on the full canvas state (e.g., another element's rename affects this
      // element's input candidates).
      clearTimeout(this._reRenderTimer)
      this._reRenderTimer = setTimeout(() => {
        if (this._currentElement && this._currentPane) {
          this.openForElement(this._currentElement, this._currentPane).catch(() => {})
        }
      }, 150)
    }
    svg.addEventListener("flowchartStructureChanged", this._structureListener)
  }

  _merge(existing, computed) {
    const result = { inputs: [], outputs: [] }
    const exInputs = (existing?.inputs) || []

    const pinsWithUserChoice = new Set(exInputs.map((e) => e.pin))
    for (const entry of exInputs) result.inputs.push(entry)
    for (const entry of computed.inputs) {
      if (!pinsWithUserChoice.has(entry.pin)) result.inputs.push(entry)
    }

    result.outputs = computed.outputs
    return result
  }

  /**
   * Translated label overrides threaded into the plain-function I/O renderers
   * (element_io/renderers.js has no controller reference — see the i18n seam
   * comment there). Mirrors BranchManager#_branchLabels().
   * @private
   */
  _ioLabels() {
    const c = this.controller
    return {
      inputsLabel: c.elementIoInputsLabelValue,
      outputsLabel: c.elementIoOutputsLabelValue,
      noInputsLabel: c.elementIoNoInputsLabelValue,
      noOutputsLabel: c.elementIoNoOutputsLabelValue,
      renamedTitle: c.elementIoRenamedTitleValue,
      renamedBadgeLabel: c.elementIoRenamedBadgeLabelValue,
      configSourceTitle: c.elementIoConfigSourceTitleValue,
      configSourceLabel: c.elementIoConfigSourceLabelValue,
      autoSourceTitle: c.elementIoAutoSourceTitleValue,
      autoSourceLabel: c.elementIoAutoSourceLabelValue,
      noProducerLabel: c.elementIoNoProducerLabelValue,
      producerAriaLabelFormat: c.elementIoProducerAriaLabelFormatValue
    }
  }

  _render(element, pane, pins) {
    const overrides = element.properties.io_overrides || { inputs: [], outputs: [] }
    const reachability = new ElementReachability(this.controller.canvas)
    const labels = this._ioLabels()

    const inputsHtml = renderInputsSection(
      pins.inputs || [],
      overrides.inputs || [],
      (pin, overrideList) => this._renderInputRow(element, pin, overrideList, reachability, labels),
      labels
    )
    const outputsHtml = renderOutputsSection(pins.outputs || [], overrides.outputs || [], labels)

    pane.innerHTML = inputsHtml + outputsHtml

    this._wireInputHandlers(element, pane)
    this.controller._applyReadOnlyState?.()
  }

  _renderInputRow(element, pin, overrideList, reachability, labels) {
    const existing = overrideList.find((e) => e.pin === pin.pin)
    const selectedKey = existing ? existing.override_key : null

    const externals = this._externalCandidates(element, pin, reachability)
    const selfs = this._selfCandidates(element, pin)
    const candidates = externals.concat(selfs)

    if (candidates.length < 2) {
      return renderReadOnlyInputRow(pin, labels)
    }

    return renderEditableInputRow(pin, externals, selfs, selectedKey, labels)
  }

  _externalCandidates(element, pin, reachability) {
    const canvas = this.controller.canvas
    const preds = reachability.predecessors(element.id)
    const out = []
    for (const pid of [...preds].reverse()) {
      if (pid === element.id) continue
      const producer = canvas.elements.find((e) => e.id === pid)
      if (!producer) continue
      out.push(...this._candidatesFromElement(producer, pin))
    }
    return out
  }

  _selfCandidates(element, pin) {
    return this._candidatesFromElement(element, pin)
  }

  _candidatesFromElement(producer, pin) {
    const canvas = this.controller.canvas
    const outs = canvas.getElementPins(producer.id).outputs || []
    const overrideOuts = producer.properties?.io_overrides?.outputs || []
    const result = []
    for (const p of outs) {
      const renamed = overrideOuts.find((o) => o.pin === p.pin)?.renamed_to
      const effective = renamed || p.pin
      if (effective !== pin.pin && !effective.startsWith(`${pin.pin}_`)) continue
      result.push({ effective, label: producer.label || producer.type })
    }
    return result
  }

  _wireInputHandlers(element, pane) {
    pane.querySelectorAll("[data-element-io-producer-select]").forEach((sel) => {
      sel.addEventListener("change", (event) => {
        const row = event.target.closest("[data-element-io-input]")
        if (!row) return
        const pin = row.getAttribute("data-pin")
        const value = event.target.value
        if (value === NO_PRODUCER_SENTINEL) this.updateProducer(element.id, pin, "")
        else this.updateProducer(element.id, pin, value)
      })
    })
  }
}
