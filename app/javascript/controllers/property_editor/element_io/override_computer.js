/**
 * Computes default io_overrides for a single element:
 *   - Inputs: self output first (if this element emits a matching key), then
 *     nearest reachable predecessor. Self is considered "nearest".
 *   - Outputs: rename only when another writer of the same pin is an ancestor
 *     on the dataflow graph (loop back-edges excluded). Writers on exclusive
 *     branches and terminal Ends keep the original key.
 *
 * Same shape as step.io_overrides:
 *   { inputs:  [{ pin, override_key }, ...],
 *     outputs: [{ pin, renamed_to }, ...] }
 *
 * An input with override_key === "" is a tombstone ("user said no producer").
 */
import { ElementReachability } from "controllers/property_editor/element_io/reachability"

export async function computeElementOverrides(canvas, elementId) {
  const target = (canvas.elements || []).find((e) => e.id === elementId)
  if (!target) return { inputs: [], outputs: [] }

  const reachability = new ElementReachability(canvas)
  const emitted = collectEmittedKeys(canvas)
  const pins = canvas.getElementPins(elementId)

  // Compute output overrides FIRST so we know what this element's renamed keys are.
  const outputs = await computeOutputOverrides(elementId, pins.outputs || [], emitted, reachability)

  // Update the emitted map with the computed renames for THIS element,
  // so input computation sees the correct effective keys for self-references.
  const selfPinMap = emitted.get(elementId) || new Map()
  for (const o of outputs) {
    if (o.renamed_to) {
      selfPinMap.set(o.pin, o.renamed_to)
    }
  }
  emitted.set(elementId, selfPinMap)

  const inputs = computeInputOverrides(target, pins.inputs || [], reachability, emitted)

  return { inputs, outputs }
}

/**
 * Map<element_id, Map<pin, effectiveKey>> — the ctx key each element
 * actually emits for each pin, honoring existing io_overrides already on
 * the element.
 */
function collectEmittedKeys(canvas) {
  const result = new Map()
  canvas.iterateElements((el) => {
    const pins = canvas.getElementPins(el.id)
    const outs = pins.outputs || []
    const overrideList = (el.properties?.io_overrides?.outputs) || []
    const pinToKey = new Map()
    for (const o of outs) {
      const hit = overrideList.find((e) => e.pin === o.pin)
      pinToKey.set(o.pin, hit?.renamed_to || o.pin)
    }
    result.set(el.id, pinToKey)
  })
  return result
}

function computeInputOverrides(element, inputPins, reachability, emitted) {
  const overrides = []
  const preds = reachability.predecessors(element.id)
  const existing = (element.properties?.io_overrides?.inputs) || []
  const tombstoneSet = new Set(
    existing.filter((e) => e.override_key === "").map((e) => e.pin)
  )

  const selfPinMap = emitted.get(element.id)

  for (const pin of inputPins.map((i) => i.pin)) {
    if (tombstoneSet.has(pin)) {
      overrides.push({ pin, override_key: "" })
      continue
    }

    let chosen = null

    // Check self outputs FIRST — if this element emits a matching key,
    // default to its own output (nearest = self).
    for (const [producerPin, effective] of selfPinMap) {
      if (producerPin === pin || effective === pin || effectiveMatches(pin, effective)) {
        chosen = { pid: element.id, effective }
        break
      }
    }

    // Only look at external predecessors if self doesn't emit a match.
    if (!chosen) {
      for (let i = preds.length - 1; i >= 0 && !chosen; i--) {
        const pid = preds[i]
        const pinMap = emitted.get(pid)
        if (!pinMap) continue
        for (const [producerPin, effective] of pinMap) {
          if (producerPin === pin || effective === pin || effectiveMatches(pin, effective)) {
            chosen = { pid, effective }
            break
          }
        }
      }
    }

    if (!chosen) continue
    if (chosen.effective === pin) continue
    overrides.push({ pin, override_key: chosen.effective })
  }
  return overrides
}

function effectiveMatches(pin, effective) {
  return new RegExp(`^${escapeRegExp(pin)}(_[0-9a-f]{4,6})?$`).test(effective)
}

async function computeOutputOverrides(elementId, outputPins, emitted, reachability) {
  const ancestors = new Set(reachability.predecessors(elementId))
  const overrides = []

  for (const outputPin of outputPins) {
    const pin = outputPin.pin
    let ancestorWrites = false
    for (const [id, pinMap] of emitted) {
      if (id === elementId) continue
      if (pinMap.has(pin) && ancestors.has(id)) {
        ancestorWrites = true
        break
      }
    }
    if (!ancestorWrites) continue
    const suffix = await shortHash(`${elementId}:${pin}`, 4)
    overrides.push({ pin, renamed_to: `${pin}_${suffix}` })
  }
  return overrides
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

async function shortHash(input, length) {
  if (crypto?.subtle) {
    const data = new TextEncoder().encode(input)
    const digest = await crypto.subtle.digest("SHA-1", data)
    return [...new Uint8Array(digest)]
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("")
      .slice(0, length)
  }
  // Fallback for non-secure contexts (HTTP on non-localhost): deterministic djb2-style hash
  let h = 5381
  for (let i = 0; i < input.length; i++) {
    h = ((h << 5) + h + input.charCodeAt(i)) >>> 0
  }
  return h.toString(16).padStart(8, "0").slice(0, length)
}
