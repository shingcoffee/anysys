import { BaseManager } from "controllers/page_builder/base_manager"

export class ViewportManager extends BaseManager {
  setViewport(event) {
    const viewport = event.currentTarget.dataset.viewport
    this.c.viewportValue = viewport
    this.updateViewportUI()
    this.c.fieldManager.renderFields()
  }

  updateViewportUI() {
    const viewport = this.c.viewportValue
    const maxWidths = { mobile: "375px", tablet: "768px", desktop: "800px" }
    const labels = { mobile: "375px", tablet: "768px", desktop: "100%" }

    if (this.c.hasCanvasFrameTarget) {
      this.c.canvasFrameTarget.style.maxWidth = maxWidths[viewport]
      this.c.canvasFrameTarget.dataset.viewport = viewport
    }

    if (this.c.hasViewportSizeTarget) {
      this.c.viewportSizeTarget.textContent = labels[viewport]
    }

    this.c.viewportBtnTargets.forEach(btn => {
      const isActive = btn.dataset.viewport === viewport
      btn.classList.toggle("text-gray-700", isActive)
      btn.classList.toggle("bg-white", isActive)
      btn.classList.toggle("shadow-sm", isActive)
      btn.classList.toggle("text-gray-500", !isActive)
    })
  }
}
