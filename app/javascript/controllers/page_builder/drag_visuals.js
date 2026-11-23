import { BaseManager } from "controllers/page_builder/base_manager"

// Controlled drag visuals: one floating ghost + one animated insertion
// indicator + source placeholder feedback + container zone highlighting.
//
// Ghost is positioned in viewport space with pointer-grab offset so the
// cursor lands exactly where the user picked up the card.
//
// Indicator glides between slots via CSS transitions on left/top/width/height;
// position is only written when a value actually changes to avoid spurious
// re-triggers each rAF tick.
//
// Container highlight dims the canvas and adds a ring to the active nested
// drop target, providing clear visual feedback when nesting is active.
export class DragVisuals extends BaseManager {
  // -------------------------------------------------------------------------
  // Ghost
  // -------------------------------------------------------------------------

  // `node`  = HTMLElement to clone (reorder drag), or null for sidebar chip.
  // `label` = chip label when node is null.
  // `grab`  = { x, y } pointer offset within the source element at pointerdown.
  showGhost(node, label, grab = { x: 16, y: 16 }) {
    if (!this.c.hasDragPreviewTarget) return
    const ghost = this.c.dragPreviewTarget

    // Store grab offset for moveGhost calls.
    this._grab = grab

    ghost.innerHTML = ""

    if (node) {
      // ---- Reorder ghost: cloned card with lifted appearance ----
      const rect  = node.getBoundingClientRect()
      const clone = node.cloneNode(true)

      // Strip any source-dimming classes the original may carry.
      clone.classList.remove("opacity-40", "opacity-50")

      // Lifted card styling — Tailwind utilities only.
      clone.style.width = `${rect.width}px`
      clone.style.margin = "0"
      ghost.appendChild(clone)

      // Apply lift classes to the ghost wrapper itself.
      // No rotation: a tilt skews wide full-width cards awkwardly. A clean
      // lifted card (subtle scale + soft shadow + ring) reads as professional.
      ghost.classList.add(
        "scale-[1.02]",
        "opacity-95",
        "shadow-[0_12px_32px_-4px_rgba(79,70,229,0.45)]",
        "ring-2",
        "ring-indigo-400/60",
        "rounded-lg",
        "origin-top-left",
        "cursor-grabbing"
      )
    } else {
      // ---- New-field chip ghost ----
      ghost.innerHTML = `<div class="flex items-center gap-2 px-3 py-2 bg-indigo-600 text-white rounded-lg shadow-[0_8px_24px_-4px_rgba(79,70,229,0.55)] ring-1 ring-indigo-400/40 text-sm font-medium cursor-grabbing select-none">
        <svg class="w-3.5 h-3.5 text-indigo-200 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4"/>
        </svg>
        <span data-ghost-label></span>
      </div>`
      // Set label via textContent — never innerHTML. `label` comes from a
      // data-* attribute which decodes ERB's HTML-escaping, so interpolating it
      // into innerHTML would allow stored HTML in a field name to execute (XSS).
      const labelEl = ghost.querySelector("[data-ghost-label]")
      if (labelEl) labelEl.textContent = label || this.c.dragGhostFieldFallbackLabelValue

      ghost.classList.add(
        "scale-[1.04]",
        "opacity-95",
        "origin-top-left",
        "cursor-grabbing"
      )
    }

    // Position at 0,0; moveGhost will immediately translate to correct spot.
    ghost.style.left      = "0px"
    ghost.style.top       = "0px"
    ghost.style.transform = ""

    ghost.classList.remove("opacity-0")
    ghost.classList.add("opacity-100")
  }

  // Called every rAF tick — transform ONLY, no layout reads.
  // Uses grab offset so the visual card coincides with where the user grabbed.
  moveGhost(x, y, grab) {
    if (!this.c.hasDragPreviewTarget) return
    const g = grab || this._grab || { x: 16, y: 16 }
    this.c.dragPreviewTarget.style.transform = `translate(${x - g.x}px, ${y - g.y}px)`
  }

  hideGhost() {
    if (!this.c.hasDragPreviewTarget) return
    const ghost = this.c.dragPreviewTarget

    ghost.classList.add("opacity-0")
    ghost.classList.remove(
      "opacity-100",
      "opacity-95",
      "scale-[1.02]",
      "scale-[1.04]",
      "shadow-[0_12px_32px_-4px_rgba(79,70,229,0.45)]",
      "ring-2",
      "ring-indigo-400/60",
      "rounded-lg",
      "origin-top-left",
      "cursor-grabbing"
    )
    ghost.innerHTML       = ""
    ghost.style.transform = ""
    this._grab            = null
  }

  // -------------------------------------------------------------------------
  // Insertion indicator
  // -------------------------------------------------------------------------

  // target = { orientation, rect:{left,top,width,height} } in viewport coords.
  // Only writes style properties when they actually change so the CSS
  // transition on [left,top,width,height] fires only on slot boundary
  // crossings, not every rAF tick.
  showIndicator(target) {
    if (!this.c.hasDropIndicatorTarget) return
    if (!target || !target.rect) { this.hideIndicator(); return }

    const ind = this.c.dropIndicatorTarget
    const r   = target.rect

    const left   = r.left
    const top    = r.top
    const width  = Math.max(r.width, 2)
    const height = Math.max(r.height, 2)

    // Only write changed values to avoid re-triggering the CSS transition on
    // every rAF tick while the pointer remains within the same slot.
    if (this._indLeft   !== left)   { ind.style.left   = `${left}px`;   this._indLeft   = left   }
    if (this._indTop    !== top)    { ind.style.top    = `${top}px`;    this._indTop    = top    }
    if (this._indWidth  !== width)  { ind.style.width  = `${width}px`;  this._indWidth  = width  }
    if (this._indHeight !== height) { ind.style.height = `${height}px`; this._indHeight = height }

    // Swap target → render as a full-card DROP ZONE; otherwise a thin LINE.
    this._applyIndicatorMode(target.mode === "swap" ? "zone" : "line", target.orientation)

    ind.classList.remove("opacity-0")
    ind.classList.add("opacity-100")
  }

  // Toggle the indicator between a thin insertion LINE and a full-card drop
  // ZONE highlight (swap target). Class tokens are switched only on change.
  _applyIndicatorMode(mode, orientation) {
    const ind = this.c.dropIndicatorTarget
    if (this._indMode !== mode) {
      this._indMode = mode
      const LINE = ["bg-indigo-500", "rounded-full", "shadow-[0_0_8px_2px_rgba(99,102,241,0.5)]"]
      const ZONE = ["bg-indigo-500/15", "ring-2", "ring-indigo-500", "rounded-lg", "shadow-[0_0_0_4px_rgba(99,102,241,0.20)]"]
      if (mode === "zone") {
        ind.classList.remove(...LINE); ind.classList.add(...ZONE)
        if (this._capA) { this._capA.style.display = "none"; this._capB.style.display = "none" }
      } else {
        ind.classList.remove(...ZONE); ind.classList.add(...LINE)
        if (this._capA) { this._capA.style.display = ""; this._capB.style.display = "" }
      }
    }
    if (mode === "line") this._ensureEndCaps(ind, orientation)
  }

  hideIndicator() {
    if (!this.c.hasDropIndicatorTarget) return
    const ind = this.c.dropIndicatorTarget
    ind.classList.remove("opacity-100")
    ind.classList.add("opacity-0")
    // Reset cached values so next show forces a write.
    this._indLeft = this._indTop = this._indWidth = this._indHeight = null
  }

  // End-cap dots are two small filled circles at both ends of the indicator.
  // We lazily create them once and re-use across slot changes.
  _ensureEndCaps(ind, orientation) {
    if (!this._capA) {
      this._capA = document.createElement("div")
      this._capB = document.createElement("div")
      const base = [
        "absolute", "rounded-full", "bg-indigo-500",
        "shadow-[0_0_4px_2px_rgba(99,102,241,0.6)]"
      ]
      this._capA.className = base.join(" ")
      this._capB.className = base.join(" ")
      ind.appendChild(this._capA)
      ind.appendChild(this._capB)
    }

    // horizontal line (between rows) — dots at left-center and right-center.
    if (orientation === "horizontal") {
      const dot = "w-1.5 h-1.5"
      const _va  = "-translate-y-1/2 -translate-x-1/2"
      const _vb  = "-translate-y-1/2 translate-x-1/2"
      this._capA.className = `absolute rounded-full bg-indigo-500 shadow-[0_0_4px_2px_rgba(99,102,241,0.6)] ${dot} left-0 top-1/2 -translate-x-1/2 -translate-y-1/2`
      this._capB.className = `absolute rounded-full bg-indigo-500 shadow-[0_0_4px_2px_rgba(99,102,241,0.6)] ${dot} right-0 top-1/2 translate-x-1/2 -translate-y-1/2`
    } else {
      // vertical line (between side-by-side fields) — dots at top-center and bottom-center.
      const dot = "w-1.5 h-1.5"
      this._capA.className = `absolute rounded-full bg-indigo-500 shadow-[0_0_4px_2px_rgba(99,102,241,0.6)] ${dot} top-0 left-1/2 -translate-x-1/2 -translate-y-1/2`
      this._capB.className = `absolute rounded-full bg-indigo-500 shadow-[0_0_4px_2px_rgba(99,102,241,0.6)] ${dot} bottom-0 left-1/2 -translate-x-1/2 translate-y-1/2`
    }
  }

  // -------------------------------------------------------------------------
  // Container drop-zone highlight (nesting feedback)
  // -------------------------------------------------------------------------

  // Highlight the container element that is the active drop zone.
  // containerKey examples: "group:gA", "column:fieldX:0"
  highlightContainer(containerKey) {
    if (containerKey === this._highlightedKey) return  // no change

    this._clearContainerHighlight()

    if (!containerKey || containerKey === "page") return

    const el = this._findContainerEl(containerKey)
    if (!el) return

    el.classList.add(
      "ring-2", "ring-indigo-400", "ring-offset-1",
      "bg-indigo-50/40", "rounded-lg", "transition-all"
    )
    this._highlightedEl  = el
    this._highlightedKey = containerKey
  }

  _clearContainerHighlight() {
    if (this._highlightedEl) {
      this._highlightedEl.classList.remove(
        "ring-2", "ring-indigo-400", "ring-offset-1",
        "bg-indigo-50/40", "rounded-lg", "transition-all"
      )
      this._highlightedEl  = null
      this._highlightedKey = null
    }
  }

  _findContainerEl(containerKey) {
    if (containerKey.startsWith("group:")) {
      const id = containerKey.slice("group:".length)
      return document.querySelector(`[data-group-fields-container="${id}"]`)
    }
    if (containerKey.startsWith("column:")) {
      const parts = containerKey.split(":")
      // key is "column:<parentFieldId>:<colIndex>"
      const parentId = parts[1]
      const colIdx   = parts[2]
      return document.querySelector(
        `[data-parent-field-id="${parentId}"] [data-column-index="${colIdx}"]`
      ) || document.querySelector(
        `[data-column-index="${colIdx}"][data-parent-field-id="${parentId}"]`
      )
    }
    return null
  }

  // -------------------------------------------------------------------------
  // Source placeholder feedback
  // -------------------------------------------------------------------------

  // Replace flat opacity-40 with a "left behind placeholder" look.
  markSource(ids) {
    if (!this.c.hasFieldsContainerTarget) return
    ids.forEach(id => {
      const card = this.c.fieldsContainerTarget.querySelector(`[data-field-id="${id}"]`)
      if (!card) return
      card.classList.add(
        "opacity-50",
        "outline",
        "outline-2",
        "outline-dashed",
        "outline-indigo-300",
        "outline-offset-2",
        "transition-all"
      )
    })
  }

  clearSource() {
    if (!this.c.hasFieldsContainerTarget) return
    this.c.fieldsContainerTarget
      .querySelectorAll(".outline-dashed")
      .forEach(el => {
        el.classList.remove(
          "opacity-50",
          "outline",
          "outline-2",
          "outline-dashed",
          "outline-indigo-300",
          "outline-offset-2",
          "transition-all"
        )
      })
    // Also clear any old flat-opacity dimming from previous versions.
    this.c.fieldsContainerTarget
      .querySelectorAll(".opacity-40")
      .forEach(el => el.classList.remove("opacity-40"))
    this._clearContainerHighlight()
  }
}
