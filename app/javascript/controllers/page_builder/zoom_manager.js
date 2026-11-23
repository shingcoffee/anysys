import { BaseManager } from "controllers/page_builder/base_manager"

const ZOOM_LEVELS = [50, 75, 100, 125, 150]

export class ZoomManager extends BaseManager {
  constructor(controller) {
    super(controller)
    this.currentZoom = 100
    this.miniMapVisible = false
  }

  zoomIn() {
    const idx = ZOOM_LEVELS.indexOf(this.currentZoom)
    if (idx < ZOOM_LEVELS.length - 1) {
      this.currentZoom = ZOOM_LEVELS[idx + 1]
      this._applyZoom()
    }
  }

  zoomOut() {
    const idx = ZOOM_LEVELS.indexOf(this.currentZoom)
    if (idx > 0) {
      this.currentZoom = ZOOM_LEVELS[idx - 1]
      this._applyZoom()
    }
  }

  zoomReset() {
    this.currentZoom = 100
    this._applyZoom()
  }

  _applyZoom() {
    if (!this.c.hasFieldsContainerTarget) return
    this.c.fieldsContainerTarget.style.transform = `scale(${this.currentZoom / 100})`
    this.c.fieldsContainerTarget.style.transformOrigin = "top center"
    if (this.c.hasZoomLevelTarget) {
      this.c.zoomLevelTarget.textContent = `${this.currentZoom}%`
    }
  }

  toggleMiniMap() {
    this.miniMapVisible = !this.miniMapVisible
    if (this.c.hasMiniMapTarget) {
      this.c.miniMapTarget.classList.toggle("hidden", !this.miniMapVisible)
      if (this.miniMapVisible) this._renderMiniMap()
    }
  }

  _renderMiniMap() {
    if (!this.c.hasMiniMapCanvasTarget) return
    const fields = this.c.currentPageFields || []
    const canvas = this.c.miniMapCanvasTarget
    const blocks = fields.map((f, i) => {
      const color = f.property_type === "layout" ? "bg-violet-200" : "bg-indigo-200"
      const top = (i / Math.max(fields.length, 1)) * 100
      return `<div class="absolute left-1 right-1 h-[3px] ${color} rounded-full" style="top: ${top}%"></div>`
    }).join("")
    canvas.innerHTML = blocks +
      `<div class="absolute left-0 right-0 border border-indigo-400 bg-indigo-100/20 rounded-sm" style="top: 0; height: 30%"></div>`
  }

  // Field search
  openSearch() {
    if (!this.c.hasCanvasAreaTarget) return
    let bar = this.c.canvasAreaTarget.querySelector(".canvas-search-bar")
    if (!bar) {
      bar = document.createElement("div")
      bar.className = "canvas-search-bar absolute top-2 left-1/2 -translate-x-1/2 z-40 bg-white rounded-lg shadow-lg border border-gray-200 px-3 py-2 flex items-center gap-2 w-[300px]"
      bar.innerHTML = `
        <svg class="w-4 h-4 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
        <input type="text" class="flex-1 text-sm border-none outline-none" placeholder="${this.escapeHtml(this.c.searchFieldsPlaceholderValue)}" data-action="input->page-builder#filterCanvasSearch keydown->page-builder#canvasSearchKeydown">
        <span class="text-xs text-gray-400" data-page-builder-target="searchCount"></span>
        <button type="button" class="text-gray-400 hover:text-gray-600" data-action="click->page-builder#closeCanvasSearch">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>
        </button>
      `
      this.c.canvasAreaTarget.style.position = "relative"
      this.c.canvasAreaTarget.appendChild(bar)
    } else {
      bar.classList.remove("hidden")
    }
    bar.querySelector("input").focus()
  }

  closeSearch() {
    const bar = this.c.canvasAreaTarget?.querySelector(".canvas-search-bar")
    if (bar) bar.classList.add("hidden")
    this.c.fieldsContainerTarget?.querySelectorAll(".field-card, .field-group").forEach(card => {
      card.style.opacity = "1"
    })
  }

  filterSearch(event) {
    const query = event.target.value.trim().toLowerCase()
    if (!query) {
      this.c.fieldsContainerTarget?.querySelectorAll(".field-card, .field-group").forEach(card => { card.style.opacity = "1" })
      if (this.c.hasSearchCountTarget) this.c.searchCountTarget.textContent = ""
      return
    }
    let matches = 0, total = 0
    this.c.fieldsContainerTarget?.querySelectorAll(".field-card, .field-group").forEach(card => {
      total++
      const text = card.textContent.toLowerCase()
      if (text.includes(query)) { card.style.opacity = "1"; matches++ }
      else { card.style.opacity = "0.3" }
    })
    if (this.c.hasSearchCountTarget) this.c.searchCountTarget.textContent = this.c.searchOfFormatValue.replace("{matches}", matches).replace("{total}", total)
  }

  searchKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.closeSearch()
    }
  }
}
