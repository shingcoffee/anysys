import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "container", "composer", "preview",
    "btnSplit", "btnCompose", "btnPreview"
  ]
  static values = {
    current: { type: String, default: "split" }
  }

  connect() {
    this.updateLayout()
  }

  switchToSplit(event) {
    if (event) event.preventDefault()
    this.currentValue = "split"
  }

  switchToCompose(event) {
    if (event) event.preventDefault()
    this.currentValue = "compose"
  }

  switchToPreview(event) {
    if (event) event.preventDefault()
    this.currentValue = "preview"
  }

  currentValueChanged() {
    this.updateLayout()
  }

  updateLayout() {
    if (!this.hasContainerTarget || !this.hasComposerTarget || !this.hasPreviewTarget) return

    const layout = this.currentValue

    this.containerTarget.className = "grid gap-8 grid-cols-1"

    if (layout === "split") {
      this.containerTarget.classList.add("xl:grid-cols-2")
      this.composerTarget.classList.remove("hidden")
      this.previewTarget.classList.remove("hidden")

      this.activateButton(this.btnSplitTarget)
      this.deactivateButton(this.btnComposeTarget)
      this.deactivateButton(this.btnPreviewTarget)
    } else if (layout === "compose") {
      this.composerTarget.classList.remove("hidden")
      this.previewTarget.classList.add("hidden")

      this.deactivateButton(this.btnSplitTarget)
      this.activateButton(this.btnComposeTarget)
      this.deactivateButton(this.btnPreviewTarget)
    } else if (layout === "preview") {
      this.composerTarget.classList.add("hidden")
      this.previewTarget.classList.remove("hidden")

      this.deactivateButton(this.btnSplitTarget)
      this.deactivateButton(this.btnComposeTarget)
      this.activateButton(this.btnPreviewTarget)
    }
  }

  activateButton(btn) {
    if (!btn) return
    btn.classList.add("bg-primary-50", "text-primary-700", "border-primary-300", "ring-1", "ring-primary-500", "z-10")
    btn.classList.remove("bg-white", "text-gray-700", "border-gray-300", "hover:bg-gray-50")
  }

  deactivateButton(btn) {
    if (!btn) return
    btn.classList.remove("bg-primary-50", "text-primary-700", "border-primary-300", "ring-1", "ring-primary-500", "z-10")
    btn.classList.add("bg-white", "text-gray-700", "border-gray-300", "hover:bg-gray-50")
  }
}
