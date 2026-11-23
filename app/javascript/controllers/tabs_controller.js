import { Controller } from "@hotwired/stimulus"

// Tab/panel switcher. The active/inactive tab styling is supplied by the host
// element via the Stimulus Classes API (data-tabs-active-class /
// data-tabs-inactive-class), so the class strings live only in the view.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static classes = ["active", "inactive"]
  static values = { active: { type: String, default: "" } }

  connect() {
    if (this.activeValue) {
      this.show(this.activeValue)
    } else if (this.tabTargets.length > 0) {
      this.show(this.tabTargets[0].dataset.tabsId)
    }
  }

  select(event) {
    event.preventDefault()
    const id = event.currentTarget.dataset.tabsId
    if (id) this.show(id)
  }

  show(id) {
    this.tabTargets.forEach(tab => {
      const active = tab.dataset.tabsId === id
      this.activeClasses.forEach(cls => tab.classList.toggle(cls, active))
      this.inactiveClasses.forEach(cls => tab.classList.toggle(cls, !active))
      tab.setAttribute("aria-selected", active ? "true" : "false")
    })

    this.panelTargets.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.tabsId !== id)
    })

    this.activeValue = id
  }
}
