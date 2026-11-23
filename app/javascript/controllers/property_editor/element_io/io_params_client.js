import { requestPins, subscribePinResults } from "controllers/property_editor/pin_request"
import { flowchartUrl } from "flowchart/urls"

/**
 * Fetch extracted pins for a single element_type + properties from the
 * server. Always resolves with { inputs: [...], outputs: [...] } — network
 * / server errors are swallowed so the I/O tab still renders cleanly.
 */
export async function fetchElementPins(elementType, properties) {
  if (!elementType) return { inputs: [], outputs: [] }

  const url = flowchartUrl(null, "elementIoParams", { __TYPE__: elementType })
  if (!url) return { inputs: [], outputs: [] }

  try {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content || ""
    const response = await fetch(
      url,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
        body: JSON.stringify({ properties: properties || {} })
      }
    )
    if (!response.ok) return { inputs: [], outputs: [] }
    return await response.json()
  } catch (e) {
    console.warn("[element_io] io_params fetch failed:", e)
    return { inputs: [], outputs: [] }
  }
}

/** Bulk prime: fetch pins for every element currently on the canvas. */
export async function primeAllElementPins(canvas) {
  const jobs = []
  canvas.iterateElements((el) => {
    if (!el || !el.type || !el.id) return
    jobs.push(refreshElementPins(canvas, el.id))
  })
  await Promise.all(jobs)
}

/** Re-fetch pins for a single element by id (post-edit refresh). */
export async function refreshElementPins(canvas, elementId) {
  const el = (canvas.elements || []).find((e) => e.id === elementId)
  if (!el) return
  return requestPins(canvas, `element:${elementId}`, () => {
    const current = canvas.elements.find(element => element.id === elementId)
    return current && [current.type, current.properties || {}]
  }, () => fetchElementPins(el.type, el.properties || {}), pins => canvas.setElementPins(elementId, pins))
}

export function subscribeElementPins(canvas, elementId, listener) {
  return subscribePinResults(canvas, `element:${elementId}`, listener)
}
