import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "backdrop"]

  connect() {
    this.touchStartX = 0
    this.touchCurrentX = 0
    this.isDragging = false

    this.boundTouchStart = this.handleTouchStart.bind(this)
    this.boundTouchMove = this.handleTouchMove.bind(this)
    this.boundTouchEnd = this.handleTouchEnd.bind(this)

    this.panelTarget.addEventListener("touchstart", this.boundTouchStart, { passive: true })
    this.panelTarget.addEventListener("touchmove", this.boundTouchMove, { passive: false })
    this.panelTarget.addEventListener("touchend", this.boundTouchEnd, { passive: true })
  }

  disconnect() {
    this.panelTarget.removeEventListener("touchstart", this.boundTouchStart)
    this.panelTarget.removeEventListener("touchmove", this.boundTouchMove)
    this.panelTarget.removeEventListener("touchend", this.boundTouchEnd)
  }

  open() {
    document.body.style.overflow = "hidden"
    this.backdropTarget.classList.remove("hidden")
    requestAnimationFrame(() => {
      this.backdropTarget.style.opacity = "1"
      this.panelTarget.classList.remove("-translate-x-full")
      this.panelTarget.classList.add("translate-x-0")
    })
  }

  close() {
    document.body.style.overflow = ""
    this.backdropTarget.style.opacity = "0"
    this.panelTarget.classList.remove("translate-x-0")
    this.panelTarget.classList.add("-translate-x-full")
    this.panelTarget.style.transform = ""

    setTimeout(() => {
      this.backdropTarget.classList.add("hidden")
    }, 300)
  }

  handleTouchStart(e) {
    this.touchStartX = e.touches[0].clientX
    this.touchCurrentX = this.touchStartX
    this.isDragging = true
    this.panelTarget.style.transition = "none"
  }

  handleTouchMove(e) {
    if (!this.isDragging) return

    this.touchCurrentX = e.touches[0].clientX
    const diff = this.touchCurrentX - this.touchStartX

    if (diff < 0) {
      e.preventDefault()
      const translateX = Math.max(diff, -this.panelTarget.offsetWidth)
      this.panelTarget.style.transform = `translateX(${translateX}px)`

      const progress = Math.abs(diff) / this.panelTarget.offsetWidth
      this.backdropTarget.style.opacity = String(1 - progress * 0.5)
    }
  }

  handleTouchEnd() {
    if (!this.isDragging) return
    this.isDragging = false

    this.panelTarget.style.transition = ""
    const diff = this.touchCurrentX - this.touchStartX
    const threshold = this.panelTarget.offsetWidth * 0.3

    if (diff < -threshold) {
      this.close()
    } else {
      this.panelTarget.style.transform = ""
      this.backdropTarget.style.opacity = "1"
    }
  }
}
