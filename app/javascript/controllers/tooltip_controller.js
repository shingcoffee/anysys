import { Controller } from "@hotwired/stimulus"

// Instant tooltips.
//
// Native HTML `title` tooltips only appear after a ~1s browser-imposed delay.
// This controller renders an immediate, body-positioned tooltip for any
// descendant carrying a `title` (or `data-tooltip`) attribute, so toolbar
// hints show the moment the pointer enters the element.
//
// The tooltip is appended to <body> and positioned with fixed coordinates so
// it is never clipped by overflow-scrolling containers (e.g. the palette).
export default class extends Controller {
  connect() {
    this.tooltip = null
    this.currentTarget = null
    this.onOver = this.show.bind(this)
    this.onOut = this.hide.bind(this)
    this.onLeave = this.remove.bind(this)

    // Strip native `title`s (they carry the delay we want to avoid) into our
    // own `data-tooltip`, preserving accessibility via `aria-label`.
    this.element.querySelectorAll("[title]").forEach((el) => {
      const text = el.getAttribute("title")
      if (!text) return
      el.dataset.tooltip = text
      if (!el.getAttribute("aria-label")) el.setAttribute("aria-label", text)
      el.removeAttribute("title")
    })

    this.element.addEventListener("mouseover", this.onOver)
    this.element.addEventListener("mouseout", this.onOut)
    this.element.addEventListener("mousedown", this.onLeave)
    this.element.addEventListener("mouseleave", this.onLeave)
  }

  disconnect() {
    this.element.removeEventListener("mouseover", this.onOver)
    this.element.removeEventListener("mouseout", this.onOut)
    this.element.removeEventListener("mousedown", this.onLeave)
    this.element.removeEventListener("mouseleave", this.onLeave)
    this.remove()
  }

  show(event) {
    const target = event.target.closest("[data-tooltip]")
    if (!target || !this.element.contains(target)) return
    if (this.currentTarget === target) return
    if (target.dataset.tooltipOverflow === "true" && !this._isOverflowing(target)) return
    this.render(target, target.dataset.tooltip)
    // Set AFTER render: render() calls remove(), which resets currentTarget to
    // null — so assigning before render would leave the de-dup guard above dead
    // (a repeat hover on the same target would re-render every time).
    this.currentTarget = target
  }

  hide(event) {
    // Ignore pointer moves that stay within the same trigger element.
    const related = event.relatedTarget
    if (this.currentTarget && related && this.currentTarget.contains(related)) return
    this.remove()
  }

  _isOverflowing(target) {
    return target.scrollWidth > target.clientWidth || target.scrollHeight > target.clientHeight
  }

  render(target, text) {
    this.remove()

    const multiline = target.dataset.tooltipMultiline === "true"
    const tip = document.createElement("div")
    tip.textContent = text
    tip.className = multiline
      ? "pointer-events-none fixed z-[100] px-2.5 py-1.5 text-xs font-medium " +
        "text-white bg-slate-900 rounded-md shadow-lg whitespace-pre-line text-left max-w-xs leading-relaxed"
      : "pointer-events-none fixed z-[100] px-2 py-1 text-xs font-medium " +
        "text-white bg-slate-900 rounded shadow-lg whitespace-nowrap"
    tip.style.opacity = "0"
    document.body.appendChild(tip)

    const rect = target.getBoundingClientRect()
    const tipRect = tip.getBoundingClientRect()

    let left = rect.left + rect.width / 2 - tipRect.width / 2
    left = Math.max(4, Math.min(left, window.innerWidth - tipRect.width - 4))

    let top = rect.bottom + 6
    // Flip above the trigger if it would overflow the viewport bottom.
    if (top + tipRect.height > window.innerHeight - 4) {
      top = rect.top - tipRect.height - 6
    }

    tip.style.left = `${left}px`
    tip.style.top = `${top}px`
    tip.style.opacity = "1"
    this.tooltip = tip
  }

  remove() {
    if (this.tooltip) {
      this.tooltip.remove()
      this.tooltip = null
    }
    this.currentTarget = null
  }
}
