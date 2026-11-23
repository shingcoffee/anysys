import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "trigger", "frame", "loading", "failure", "viewport", "stage", "canvas", "sheet", "thumbnail"]

  static values = {
    frameWidth: { type: Number, default: 1280 },
    frameHeight: { type: Number, default: 1400 }
  }

  connect() {
    this.fallbackFocus = this.element.closest("[data-assistant-workspace-target='panel']")
    this.rescale = () => this.scaleThumbnail()
    this.watchViewport()
  }

  disconnect() {
    this.unwatchViewport()
    if (this.hasDialogTarget && this.dialogTarget.open) this.restoreFocus()
  }

  // The thumbnail iframe is a desktop-width browser window scaled down to the
  // rail, exactly as tall as the rail shows. It is never stretched to the page:
  // a frame as tall as its content makes `vh` grow with the page, so a hero sized
  // in viewport units swallowed the whole miniature.
  watchViewport() {
    if (!this.hasViewportTarget || !this.hasCanvasTarget) return

    if (typeof ResizeObserver === "function") {
      this.resizeObserver = new ResizeObserver(this.rescale)
      this.resizeObserver.observe(this.viewportTarget)
    } else {
      window.addEventListener("resize", this.rescale)
    }

    this.thumbnailLoaded()
  }

  unwatchViewport() {
    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
      this.resizeObserver = null
    } else {
      window.removeEventListener("resize", this.rescale)
    }
  }

  // The frame often finishes loading before Stimulus connects, so this also runs
  // on connect.
  thumbnailLoaded() {
    // The rail's own scrollbar is the one to use; the framed page's would only
    // narrow its layout.
    this.#framedDocument()?.documentElement?.style.setProperty("scrollbar-width", "none")
    this.scaleThumbnail()
  }

  scaleThumbnail() {
    if (!this.hasViewportTarget || !this.hasCanvasTarget) return

    const width = this.viewportTarget.clientWidth
    if (!width) return

    const scale = width / this.frameWidthValue
    const stageHeight = this.viewportTarget.clientHeight || Math.round(this.frameHeightValue * scale)
    this.scale = scale
    this.canvasTarget.style.width = `${this.frameWidthValue}px`
    this.canvasTarget.style.height = `${Math.ceil(stageHeight / scale)}px`
    this.canvasTarget.style.transform = `scale(${scale})`
    if (this.hasStageTarget) this.stageTarget.style.height = `${stageHeight}px`

    // Measured after the resize above, because the page's height can depend on
    // the window's. The sheet carries the scaled page height — that is what gives
    // the rail its scroll extent — while the sticky stage stays in view over it.
    const pageHeight = this.#measurePageHeight() || this.frameHeightValue
    if (this.hasSheetTarget) {
      this.sheetTarget.style.height = `${Math.max(Math.round(pageHeight * scale), stageHeight)}px`
    }
    this.syncScroll()
  }

  // Scrolling the rail scrolls the framed page by the same distance at full size,
  // so sticky headers and lazy images behave as they would in a browser.
  syncScroll() {
    if (!this.scale || !this.hasThumbnailTarget) return

    try {
      this.thumbnailTarget.contentWindow?.scrollTo({
        top: this.viewportTarget.scrollTop / this.scale,
        behavior: "instant"
      })
    } catch {
      // A preview served from another origin cannot be scrolled; it stays at its top.
    }
  }

  #measurePageHeight() {
    const doc = this.#framedDocument()
    return doc?.documentElement?.scrollHeight || doc?.body?.scrollHeight || null
  }

  #framedDocument() {
    if (!this.hasThumbnailTarget) return null

    try {
      const doc = this.thumbnailTarget.contentDocument
      if (!doc || doc.readyState !== "complete" || doc.URL === "about:blank") return null
      return doc
    } catch {
      // A preview served from another origin cannot be read; keep the defaults.
      return null
    }
  }

  open(event) {
    this.returnFocus = event.currentTarget || (this.hasTriggerTarget ? this.triggerTarget : null)
    this.loadFrame()

    if (typeof this.dialogTarget.showModal === "function") {
      this.dialogTarget.showModal()
    } else {
      this.dialogTarget.setAttribute("open", "")
    }
  }

  close() {
    if (typeof this.dialogTarget.close === "function") {
      this.dialogTarget.close()
    } else {
      this.dialogTarget.removeAttribute("open")
    }

    this.restoreFocus()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  cancel(event) {
    event.preventDefault()
    this.close()
  }

  loaded() {
    this.loadingTarget.classList.add("hidden")
    this.failureTarget.classList.add("hidden")
    this.failureTarget.classList.remove("flex")
    this.frameTarget.classList.remove("opacity-0")
  }

  failed() {
    this.loadingTarget.classList.add("hidden")
    this.failureTarget.classList.remove("hidden")
    this.failureTarget.classList.add("flex")
    this.frameTarget.classList.add("opacity-0")
  }

  retry() {
    this.frameTarget.removeAttribute("src")
    return this.loadFrame()
  }

  async loadFrame() {
    if (this.frameTarget.hasAttribute("src")) return

    this.showLoading()
    const url = this.frameTarget.dataset.artifactPreviewSrc

    try {
      const response = await fetch(url, {
        method: "HEAD",
        credentials: "same-origin"
      })
      if (!response.ok) {
        this.failed()
        return
      }

      this.frameTarget.setAttribute("src", url)
    } catch {
      this.failed()
    }
  }

  showLoading() {
    this.loadingTarget.classList.remove("hidden")
    this.failureTarget.classList.add("hidden")
    this.failureTarget.classList.remove("flex")
    this.frameTarget.classList.add("opacity-0")
  }

  restoreFocus() {
    const target = this.returnFocus?.isConnected ? this.returnFocus : this.fallbackFocus
    target?.focus?.()
  }
}
