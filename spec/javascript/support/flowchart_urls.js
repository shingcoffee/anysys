// Test seam for flowchartUrl: inject URLs via the live canvas data attribute.
// Never use a module-level registry — that leaks across Turbo visits.

export function applyFlowchartUrls(urls) {
  let el = document.querySelector('[data-controller~="flowchart-canvas"]')
  if (!el) {
    el = document.createElement("div")
    el.setAttribute("data-controller", "flowchart-canvas")
    el.setAttribute("data-flowchart-urls-seam", "true")
    document.body.appendChild(el)
  }
  if (!urls || typeof urls !== "object" || Object.keys(urls).length === 0) {
    el.removeAttribute("data-flowchart-canvas-urls-value")
    return el
  }
  el.setAttribute("data-flowchart-canvas-urls-value", JSON.stringify(urls))
  return el
}

export function clearFlowchartUrls() {
  document.querySelectorAll('[data-flowchart-urls-seam="true"]').forEach((el) => el.remove())
  document.querySelectorAll('[data-controller~="flowchart-canvas"]').forEach((el) => {
    el.removeAttribute("data-flowchart-canvas-urls-value")
  })
}
