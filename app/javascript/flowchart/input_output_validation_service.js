// app/javascript/flowchart/input_output_validation_service.js

import { ElementReachability } from "controllers/property_editor/element_io/reachability"
import { flowchartUrl } from "flowchart/urls"

// English default only — this plain class has no controller reference, so
// the caller (ValidationMixin, which has `this.<name>Value`) threads the
// translated string in via the `messages` constructor param, sourced from
// flowchart_canvas_controller.js's `validationMissingInputFormat` Value.
// Falling back to this default keeps existing
// `new InputOutputValidationService(canvas)` calls/specs byte-identical when
// `messages` is omitted. Mirrors the `templates/*.js` DEFAULT_LABELS seam
// used elsewhere in the codebase.
const DEFAULT_MESSAGES = {
  missingInputFormat: 'Input "{key}" has no upstream output'
}

/**
 * Client-side input/output validation service.
 * Validates that all element inputs have corresponding outputs from reachable upstream elements.
 */
export class InputOutputValidationService {
  static _implicitKeysCache = null
  static _implicitKeysPromise = null

  constructor(canvas, messages = {}) {
    this.canvas = canvas
    this.messages = { ...DEFAULT_MESSAGES, ...messages }
    this.implicitKeys = new Set()
  }

  /**
   * Load implicit keys from server. Caches result for subsequent calls.
   */
  async loadImplicitKeys() {
    if (InputOutputValidationService._implicitKeysCache) {
      this.implicitKeys = InputOutputValidationService._implicitKeysCache
      return
    }

    if (InputOutputValidationService._implicitKeysPromise) {
      await InputOutputValidationService._implicitKeysPromise
      this.implicitKeys = InputOutputValidationService._implicitKeysCache ?? new Set()
      return
    }

    InputOutputValidationService._implicitKeysPromise = this._fetchImplicitKeys()
    try {
      await InputOutputValidationService._implicitKeysPromise
      this.implicitKeys = InputOutputValidationService._implicitKeysCache ?? new Set()
    } finally {
      InputOutputValidationService._implicitKeysPromise = null
    }
  }

  async _fetchImplicitKeys() {
    try {
      const url = flowchartUrl(null, "implicitKeys")
      if (!url) return
      const response = await fetch(url)
      if (response.ok) {
        const data = await response.json()
        InputOutputValidationService._implicitKeysCache = new Set(data.implicit_keys || [])
      } else {
        InputOutputValidationService._implicitKeysCache = new Set()
      }
    } catch (e) {
      console.warn("[InputOutputValidationService] Failed to load implicit keys:", e)
      InputOutputValidationService._implicitKeysCache = new Set()
    }
  }

  /**
   * Validate all elements and return errors.
   * @returns {Array<{elementId: string, type: string, message: string}>}
   */
  validate() {
    const errors = []
    const reachability = new ElementReachability(this.canvas)
    const elementOutputs = this._collectElementOutputs()

    this.canvas.iterateElements((element) => {
      const elementErrors = this._validateElementInputs(element, reachability, elementOutputs)
      errors.push(...elementErrors)
    })

    return errors
  }

  _collectElementOutputs() {
    const outputs = new Map()

    this.canvas.iterateElements((element) => {
      const pins = this.canvas.getElementPins(element.id)
      const outputPins = pins?.outputs || []
      const overrideList = element.properties?.io_overrides?.outputs || []

      const overrideMap = new Map()
      for (const o of overrideList) {
        overrideMap.set(o.pin, o.renamed_to)
      }

      const effectiveOutputs = new Set()
      for (const pin of outputPins) {
        const pinName = pin.pin
        const effectiveKey = overrideMap.get(pinName) || pinName
        effectiveOutputs.add(effectiveKey)
      }

      outputs.set(element.id, effectiveOutputs)
    })

    return outputs
  }

  _validateElementInputs(element, reachability, elementOutputs) {
    const errors = []
    const pins = this.canvas.getElementPins(element.id)
    const inputPins = pins?.inputs || []
    const outputPins = pins?.outputs || []

    const overrideList = element.properties?.io_overrides?.inputs || []
    const overrideMap = new Map()
    for (const o of overrideList) {
      overrideMap.set(o.pin, o.override_key)
    }

    const predecessorIds = reachability.predecessors(element.id)
    const availableOutputs = new Set()
    for (const predId of predecessorIds) {
      const predOutputs = elementOutputs.get(predId)
      if (predOutputs) {
        for (const key of predOutputs) {
          availableOutputs.add(key)
        }
      }
    }

    const ownRawOutputs = new Set(outputPins.map((p) => p.pin))
    const ownEffectiveOutputs = elementOutputs.get(element.id) || new Set()

    for (const pin of inputPins) {
      const pinName = pin.pin
      const overridden = overrideMap.has(pinName)
      const effectiveKey = overridden ? overrideMap.get(pinName) : pinName

      // Skip tombstone (empty string means user said no producer needed)
      if (effectiveKey === "") continue

      // Skip implicit keys
      if (this.implicitKeys.has(effectiveKey)) continue

      // Self-reference: element's own output can satisfy its own input.
      // Without an input override, raw pin pairs with raw self-write (runtime
      // rewrites both sides consistently through output rename). With an
      // input override, the effective key must match the effective self-output.
      if (!overridden && ownRawOutputs.has(pinName)) continue
      if (ownEffectiveOutputs.has(effectiveKey)) continue

      // Check if available in upstream outputs
      if (availableOutputs.has(effectiveKey)) continue

      errors.push({
        elementId: element.id,
        type: "missing_input",
        // Raw key: the Problems panel escapes the finished message once.
        message: this.messages.missingInputFormat.replace("{key}", () => effectiveKey),
        // Raw pin name — the I/O tab rows render data-pin with the RAW pin
        // (renderers.js), so click-to-fix anchors must match it, not the
        // effective (possibly overridden) key.
        meta: { pinKey: pinName }
      })
    }

    return errors
  }
}
