/**
 * DependencyOverlayMixin provides dependency badge HTML generation and the
 * SVG overlay that visualises rule connections between fields.
 * Apply to a class using Object.assign(YourClass.prototype, DependencyOverlayMixin)
 */
export const DependencyOverlayMixin = {
  // =========================================================================
  // Dependency Badges & SVG Overlay
  // =========================================================================

  _getDependencyBadgeHtml(field) {
    const rules = this.c.configuration.rules || []
    const hasConditions = rules.some(r => r.actions?.some(a => a.target_id === field.id))
    const isReferenced = rules.some(r => r.conditions?.groups?.some(g => g.items?.some(item => item.field_id === field.id)))

    if (!hasConditions && !isReferenced) return ""

    const color = hasConditions ? "text-orange-500" : "text-purple-500"
    const tooltip = hasConditions ? "Has conditional visibility rules" : "Referenced by other fields' rules"

    return `<span class="${color} cursor-pointer flex-shrink-0" title="${tooltip}"
                  data-action="click->page-builder#showDependencyLines" data-field-id="${field.id}">
      <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"/>
      </svg>
    </span>`
  },

  showDependencyLines(event) {
    event.stopPropagation()
    const fieldId = event.currentTarget.dataset.fieldId
    this._removeDependencyOverlay()

    const rules = this.c.configuration.rules || []
    const connections = []

    rules.forEach(rule => {
      const actionFieldIds = rule.actions?.map(a => a.target_id) || []
      const conditionFieldIds = rule.conditions?.groups?.flatMap(g => g.items?.map(item => item.field_id) || []) || []

      if (actionFieldIds.includes(fieldId)) {
        conditionFieldIds.forEach(cid => connections.push({ from: cid, to: fieldId, color: "orange" }))
      }
      if (conditionFieldIds.includes(fieldId)) {
        actionFieldIds.forEach(aid => connections.push({ from: fieldId, to: aid, color: "purple" }))
      }
    })

    if (connections.length === 0) return

    const container = this.c.fieldsContainerTarget
    const containerRect = container.getBoundingClientRect()
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    svg.setAttribute("class", "dependency-overlay absolute inset-0 pointer-events-none z-40")
    svg.setAttribute("width", container.scrollWidth)
    svg.setAttribute("height", container.scrollHeight)
    container.style.position = "relative"
    container.appendChild(svg)

    connections.forEach(({ from, to, color }) => {
      const fromEl = container.querySelector(`[data-field-id="${from}"]`)
      const toEl = container.querySelector(`[data-field-id="${to}"]`)
      if (!fromEl || !toEl) return

      const fromRect = fromEl.getBoundingClientRect()
      const toRect = toEl.getBoundingClientRect()
      const x1 = fromRect.right - containerRect.left
      const y1 = fromRect.top + fromRect.height / 2 - containerRect.top
      const x2 = toRect.left - containerRect.left
      const y2 = toRect.top + toRect.height / 2 - containerRect.top

      const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
      const midX = (x1 + x2) / 2
      path.setAttribute("d", `M ${x1} ${y1} C ${midX} ${y1}, ${midX} ${y2}, ${x2} ${y2}`)
      path.setAttribute("fill", "none")
      path.setAttribute("stroke", color === "orange" ? "#f97316" : "#a855f7")
      path.setAttribute("stroke-width", "2")
      path.setAttribute("stroke-dasharray", "6 3")
      path.setAttribute("opacity", "0.6")
      svg.appendChild(path)
    })

    this._dismissDependency = (e) => {
      if (!e.target.closest(".dependency-overlay") && !e.target.closest("[data-action*='showDependencyLines']")) {
        this._removeDependencyOverlay()
      }
    }
    this._dismissDependencyKey = (e) => {
      if (e.key === "Escape") this._removeDependencyOverlay()
    }
    document.addEventListener("click", this._dismissDependency)
    document.addEventListener("keydown", this._dismissDependencyKey)
  },

  _removeDependencyOverlay() {
    const overlay = this.c.fieldsContainerTarget?.querySelector(".dependency-overlay")
    if (overlay) overlay.remove()
    if (this._dismissDependency) document.removeEventListener("click", this._dismissDependency)
    if (this._dismissDependencyKey) document.removeEventListener("keydown", this._dismissDependencyKey)
    this._dismissDependency = null
    this._dismissDependencyKey = null
  },

  // Public teardown hook — called from page_builder_controller#disconnect so
  // document-level overlay listeners don't leak across Turbo navigations.
  cleanup() {
    this._removeDependencyOverlay()
  }
}
