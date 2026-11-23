import { Controller } from "@hotwired/stimulus"

// Drives the Page Settings modal's left-rail section navigation: clicking a tab
// reveals its panel and hides the others. Pure UI state — no persistence; the
// controls inside each panel keep their own page-builder actions.
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    // Activate the first section (or whichever panel is already visible).
    const visible = this.panelTargets.find(p => !p.classList.contains("hidden"))
    this.show(visible?.dataset.section || this.tabTargets[0]?.dataset.section)
  }

  select(event) {
    this.show(event.currentTarget.dataset.section)
  }

  show(key) {
    if (!key) return

    this.panelTargets.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.section !== key)
    })

    this.tabTargets.forEach(tab => {
      const active = tab.dataset.section === key
      tab.classList.toggle("bg-indigo-50", active)
      tab.classList.toggle("text-indigo-700", active)
      tab.classList.toggle("text-gray-600", !active)
      tab.classList.toggle("hover:bg-gray-100", !active)
    })
  }
}
