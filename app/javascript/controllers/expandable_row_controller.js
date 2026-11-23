import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggleButton", "detailPanel"]

  toggle(event) {
    event.preventDefault()
    const panelId = event.currentTarget.dataset.expandableRowPanel
    const panel = this.detailPanelTargets.find(
      p => p.dataset.expandableRowId === panelId
    )
    if (!panel) return

    const isHidden = panel.classList.contains("hidden")
    // Close all panels in this controller scope first
    this.detailPanelTargets.forEach(p => p.classList.add("hidden"))
    // Toggle the clicked panel
    if (isHidden) {
      panel.classList.remove("hidden")
    }
  }
}
