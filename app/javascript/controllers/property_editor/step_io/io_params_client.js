import { requestPins } from "controllers/property_editor/pin_request"
import { flowchartUrl } from "flowchart/urls"

/**
 * Fetch pins for every step action on the canvas and seed canvas.stepPins
 * for autocomplete.
 */
async function fetchStepPins(action, config) {
  const url = flowchartUrl(null, "stepIoParams", { __ACTION__: action })
  if (!url) return { inputs: [], outputs: [] }

  try {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content || ""
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
      body: JSON.stringify({ config })
    })
    if (!response.ok) return { inputs: [], outputs: [] }
    return await response.json()
  } catch (e) {
    console.warn("[step_io] io_params fetch failed:", e)
    return { inputs: [], outputs: [] }
  }
}

export async function primeAllStepPins(canvas) {
  const jobs = []
  canvas.iterateStepActions((step) => {
    if (!step.action) return
    jobs.push(requestPins(canvas, `step:${step.id}`, () => {
      const current = canvas.findStepById(step.id)?.step
      return current && [current.action, current.config || {}]
    }, () => fetchStepPins(step.action, step.config || {}), pins => canvas.setStepPins(step.id, pins)))
  })
  await Promise.all(jobs)
}
