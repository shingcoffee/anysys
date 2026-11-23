/**
 * OverrideValidator — walks every element's io_overrides and removes stale
 * entries whose override_key / renamed_to no longer line up with the
 * current canvas state. Silent: no toasts, no markers. On next render the
 * override_computer re-defaults to nearest / new rename.
 *
 * Rules:
 *   - inputs[].override_key: drop entry if no reachable upstream element
 *     AND the element itself do not emit that effective key. Tombstone ("")
 *     is preserved.
 *   - outputs[].renamed_to: recompute. If the element no longer collides
 *     with any other emitter, drop it. If collision still exists (possibly
 *     with a different peer), the existing renamed_to is still valid (it
 *     is derived from elementId:pin and stays stable).
 */
import { ElementReachability } from "controllers/property_editor/element_io/reachability"

export function validateOverrides(canvas) {
  const reachability = new ElementReachability(canvas)
  const emitted = collectEmitted(canvas)

  canvas.iterateElements((el) => {
    const overrides = el.properties?.io_overrides
    if (!overrides) return

    const updated = { inputs: [], outputs: [] }

    for (const entry of overrides.inputs || []) {
      if (entry.override_key === "") {
        updated.inputs.push(entry)
        continue
      }
      const producerIds = [el.id, ...reachability.predecessors(el.id)]
      const stillReachable = producerIds.some((pid) => {
        const map = emitted.get(pid)
        if (!map) return false
        for (const effective of map.values()) {
          if (effective === entry.override_key) return true
        }
        return false
      })
      if (stillReachable) updated.inputs.push(entry)
    }

    for (const entry of overrides.outputs || []) {
      const myKeys = emitted.get(el.id)
      if (!myKeys || !myKeys.has(entry.pin)) continue
      if (anyOtherEmits(entry.pin, el.id, emitted)) updated.outputs.push(entry)
    }

    el.properties.io_overrides = updated
  })
}

function collectEmitted(canvas) {
  const map = new Map()
  canvas.iterateElements((el) => {
    const pins = canvas.getElementPins(el.id)
    const outs = pins.outputs || []
    const overrideList = (el.properties?.io_overrides?.outputs) || []
    const pinToKey = new Map()
    for (const o of outs) {
      const hit = overrideList.find((e) => e.pin === o.pin)
      pinToKey.set(o.pin, hit?.renamed_to || o.pin)
    }
    map.set(el.id, pinToKey)
  })
  return map
}

function anyOtherEmits(pin, selfId, emitted) {
  for (const [id, pinMap] of emitted) {
    if (id === selfId) continue
    if (pinMap.has(pin)) return true
  }
  return false
}
