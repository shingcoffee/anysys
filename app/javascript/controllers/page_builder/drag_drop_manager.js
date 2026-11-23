import { BaseManager } from "controllers/page_builder/base_manager"

// Residual drag helpers shared by the pointer-events engine. Native HTML5 DnD
// has been replaced by DragEngine / DropResolver / DragVisuals / DropMutations.
export class DragDropManager extends BaseManager {
  // Build the new-field payload from a sidebar item's data attributes.
  _sidebarData(element) {
    return {
      type: element.dataset.fieldType,
      label: element.dataset.fieldLabel || element.dataset.propertyName,
      propertySlug: element.dataset.propertySlug,
      propertyType: element.dataset.propertyType,
      htmlType: element.dataset.propertyHtmlType,
      source: element.dataset.source || null,
      sourceSection: element.dataset.sourceSection || null,
      options: element.dataset.fieldOptions ? JSON.parse(element.dataset.fieldOptions) : null,
      dynamicOptions: element.dataset.dynamicOptions ? JSON.parse(element.dataset.dynamicOptions) : null
    }
  }

  // -------------------------------------------------------------------------
  // FLIP helpers
  // -------------------------------------------------------------------------

  // Snapshot the current viewport positions of every .field-card on the canvas.
  // Returns a Map<fieldId, DOMRect>.  Called BEFORE the DOM re-render.
  captureCardRects() {
    const map = new Map()
    if (!this.c.hasFieldsContainerTarget) return map
    this.c.fieldsContainerTarget
      .querySelectorAll(".field-card[data-field-id]")
      .forEach(card => {
        map.set(card.dataset.fieldId, card.getBoundingClientRect())
      })
    return map
  }

  // Animate cards from their old positions (prevRects) to the new DOM positions.
  //
  // - For existing cards that moved: FLIP (translate from old→new, animate to 0).
  // - For the dropped card (droppedId) that is NEW (no prevRect): animate a
  //   brief scale+translate entrance from the drop point so it appears to land
  //   where it was released.
  //
  // Respects `prefers-reduced-motion` — skips transitions when set.
  flipFromRects(prevRects, { droppedId, dropPoint } = {}) {
    if (!this.c.hasFieldsContainerTarget) return

    const reducedMotion =
      typeof window !== "undefined" &&
      window.matchMedia &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches

    // Read new positions in a single synchronous pass (all getBoundingClientRect
    // calls happen here, before any writes).
    const newRects = new Map()
    this.c.fieldsContainerTarget
      .querySelectorAll(".field-card[data-field-id]")
      .forEach(card => {
        newRects.set(card.dataset.fieldId, card.getBoundingClientRect())
      })

    // Write phase: apply transforms.
    requestAnimationFrame(() => {
      const cards = this.c.fieldsContainerTarget
        ? [...this.c.fieldsContainerTarget.querySelectorAll(".field-card[data-field-id]")]
        : []

      cards.forEach(card => {
        const id      = card.dataset.fieldId
        const newRect = newRects.get(id)
        if (!newRect) return

        const prevRect = prevRects.get(id)

        if (!prevRect) {
          // ---- New / dropped card entrance animation ----
          if (id !== droppedId) return  // skip non-dropped new cards
          if (reducedMotion) return

          let startDx = 0
          let startDy = -12

          if (dropPoint) {
            startDx = dropPoint.x - (newRect.left + newRect.width / 2)
            startDy = dropPoint.y - (newRect.top  + newRect.height / 2)
            // Clamp so very large offsets (e.g. sidebar drags) don't look wild.
            const maxOffset = 120
            startDx = Math.max(-maxOffset, Math.min(maxOffset, startDx))
            startDy = Math.max(-maxOffset, Math.min(maxOffset, startDy))
          }

          // Set initial displaced state — NO transition.
          card.style.transition = ""
          card.style.transform  = `translate(${startDx}px, ${startDy}px) scale(0.96)`
          card.style.opacity    = "0.6"

          // Animate to natural position on the very next frame.
          requestAnimationFrame(() => {
            card.style.transition = "transform 240ms cubic-bezier(0.2, 0.8, 0.2, 1), opacity 180ms ease-out"
            card.style.transform  = ""
            card.style.opacity    = ""
            this._clearAfterTransition(card, 360)
          })
          return
        }

        // ---- FLIP for existing cards that changed position ----
        const dx = prevRect.left - newRect.left
        const dy = prevRect.top  - newRect.top

        if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5) return  // didn't move

        if (reducedMotion) return

        // Apply inverse transform (no transition) so card appears in old place.
        card.style.transition = ""
        card.style.transform  = `translate(${dx}px, ${dy}px)`

        // On the next rAF, activate transition and remove the transform so it
        // glides from old→new position.
        requestAnimationFrame(() => {
          card.style.transition = "transform 220ms cubic-bezier(0.2, 0.8, 0.2, 1)"
          card.style.transform  = ""
          this._clearAfterTransition(card, 320)
        })
      })
    })
  }

  // Clear inline animation styles once the transition ends, GUARDED by a
  // fallback timeout (> animation duration) so a card never keeps a stale
  // inline `transition` if transitionend doesn't fire (e.g. the card's parent
  // becomes display:none, or a new drop interrupts it) — otherwise every future
  // style change on that reused card would animate unexpectedly. Idempotent.
  _clearAfterTransition(card, fallbackMs) {
    let done = false
    const cleanup = () => {
      if (done) return
      done = true
      card.style.transition = ""
      card.style.transform  = ""
      card.style.opacity    = ""
      card.removeEventListener("transitionend", cleanup)
    }
    card.addEventListener("transitionend", cleanup, { once: true })
    setTimeout(cleanup, fallbackMs)
  }
}
