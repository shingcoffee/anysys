// app/javascript/flowchart/context_variable_provider.js

import { ElementReachability } from "controllers/property_editor/element_io/reachability"
import { flowchartUrl } from "flowchart/urls"

/**
 * ContextVariableProvider — collects available context variables for autocomplete.
 *
 * Returns variables grouped by source:
 * - Implicit keys (always available runtime context)
 * - Upstream element outputs
 * - Prior step outputs within the same element
 */

// i18n overlay for group labels — English default, replaced at runtime by the
// flowchart controller (setContextGroupLabels) with translated copy.
let GROUP_LABELS = {
  alwaysAvailable: "Always Available",
  from: "From '{label}'",
  fromStep: "From '{label}' (this element)"
}

/** Install translated context-variable group labels. */
export function setContextGroupLabels(labels) {
  if (labels && typeof labels === "object") GROUP_LABELS = { ...GROUP_LABELS, ...labels }
}

let _implicitKeysCache = null
let _implicitKeysPromise = null

async function fetchImplicitKeys() {
  if (_implicitKeysCache) return _implicitKeysCache

  if (_implicitKeysPromise) {
    await _implicitKeysPromise
    return _implicitKeysCache || []
  }

  _implicitKeysPromise = (async () => {
    try {
      const url = flowchartUrl(null, "implicitKeys")
      if (!url) return
      const response = await fetch(url)
      if (response.ok) {
        const data = await response.json()
        _implicitKeysCache = data.implicit_keys || []
      } else {
        _implicitKeysCache = []
      }
    } catch (e) {
      console.warn("[ContextVariableProvider] Failed to fetch implicit keys:", e)
      _implicitKeysCache = []
    }
  })()

  try {
    await _implicitKeysPromise
    return _implicitKeysCache || []
  } finally {
    _implicitKeysPromise = null
  }
}

/**
 * Get effective output keys for an element, honoring io_overrides renames.
 */
function getElementEffectiveOutputs(canvas, elementId) {
  const pins = canvas.getElementPins?.(elementId) || { outputs: [] }
  const outputPins = pins.outputs || []
  const element = canvas.elements.find(el => el.id === elementId)
  const overrides = element?.properties?.io_overrides?.outputs || []

  const overrideMap = new Map()
  for (const o of overrides) {
    overrideMap.set(o.pin, o.renamed_to)
  }

  const effectiveKeys = []
  for (const pin of outputPins) {
    const effective = overrideMap.get(pin.pin) || pin.pin
    effectiveKeys.push(effective)
  }

  return effectiveKeys
}

function getStepEffectiveOutputs(canvas, stepId) {
  const pins = canvas.getStepPins?.(stepId) || { outputs: [] }
  return (pins.outputs || []).map((p) => p.pin)
}

/**
 * Get available variables for a given element and step position.
 * @param {Object} canvas - FlowchartCanvas instance
 * @param {string} elementId - Current element ID
 * @param {number} stepIndex - Current step index (-1 for element-level)
 * @returns {Promise<{groups: Array}>}
 */
export async function getAvailableVariables(canvas, elementId, stepIndex = -1) {
  const groups = []

  // 1. Implicit keys (always first)
  const implicitKeys = await fetchImplicitKeys()
  if (implicitKeys.length > 0) {
    groups.push({
      label: GROUP_LABELS.alwaysAvailable,
      source: "implicit",
      variables: [...implicitKeys]
    })
  }

  // 2. Upstream element outputs
  if (canvas && elementId) {
    const reachability = new ElementReachability(canvas)
    const predecessors = reachability.predecessors(elementId)

    // Process in reverse order (farthest first in array, we want nearest last)
    for (const predId of predecessors) {
      const predElement = canvas.elements.find(el => el.id === predId)
      if (!predElement) continue

      const outputs = getElementEffectiveOutputs(canvas, predId)
      if (outputs.length === 0) continue

      const label = predElement.label || predElement.type || predId
      groups.push({
        label: GROUP_LABELS.from.replace("{label}", label),
        source: "element",
        sourceId: predId,
        variables: outputs
      })
    }
  }

  // 3. Prior step outputs within current element
  if (canvas && elementId && stepIndex >= 0) {
    const element = canvas.elements.find(el => el.id === elementId)
    const steps = element?.properties?.steps || []

    for (let i = 0; i < stepIndex && i < steps.length; i++) {
      const step = steps[i]
      if (!step.id) continue

      const outputs = getStepEffectiveOutputs(canvas, step.id)
      if (outputs.length === 0) continue

      const stepLabel = step.selectionLabels?.join(" - ") || step.action || step.id
      groups.push({
        label: GROUP_LABELS.fromStep.replace("{label}", stepLabel),
        source: "step",
        sourceId: step.id,
        variables: outputs
      })
    }
  }

  return { groups }
}

/**
 * Filter variables by search term.
 * @param {{groups: Array}} result - Result from getAvailableVariables
 * @param {string} term - Search term
 * @returns {{groups: Array}}
 */
export function filterVariables(result, term) {
  if (!term || term.trim() === "") return result

  const lowerTerm = term.toLowerCase()
  const filteredGroups = []

  for (const group of result.groups) {
    const filtered = group.variables.filter(v => v.toLowerCase().includes(lowerTerm))
    if (filtered.length > 0) {
      filteredGroups.push({ ...group, variables: filtered })
    }
  }

  return { groups: filteredGroups }
}

// For testing: reset cache
export function _resetCache() {
  _implicitKeysCache = null
  _implicitKeysPromise = null
}
