/**
 * Resolve flowchart editor fetch URLs from the server-provided urls value
 * (controller.urlsValue or the live canvas data-flowchart-canvas-urls-value).
 * Never construct tenant paths in JS. Never keep module-level URL state —
 * a leftover registry would leak across Turbo visits.
 */

function urlsFromController(controller) {
  const urls = controller?.urlsValue
  return urls && typeof urls === "object" ? urls : null
}

function urlsFromDom() {
  const el = document.querySelector('[data-controller~="flowchart-canvas"]')
  if (!el) return null
  const raw = el.getAttribute("data-flowchart-canvas-urls-value")
  if (!raw) return null
  try {
    const parsed = JSON.parse(raw)
    return parsed && typeof parsed === "object" ? parsed : null
  } catch (_e) {
    return null
  }
}

export function flowchartUrl(controller, name, replacements = {}) {
  const src = controller != null ? urlsFromController(controller) : urlsFromDom()
  let url = src?.[name]
  if (!url) return null
  for (const [token, value] of Object.entries(replacements)) {
    url = url.split(token).join(encodeURIComponent(String(value)))
  }
  return url
}

export function flowchartShowUrl(controller, flowchartId) {
  const list = flowchartUrl(controller, "list")
  if (!list || !flowchartId) return null
  return list.replace(/\.json(\?.*)?$/, `/${encodeURIComponent(String(flowchartId))}.json$1`)
}
