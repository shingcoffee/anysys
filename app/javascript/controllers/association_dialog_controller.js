import { Controller } from "@hotwired/stimulus"

// An association card (Admin::Entities::AssociationSectionComponent), on the
// entry detail page or a user profile. Its Add / Edit links open their form
// in the entity-quick-add-dialog outlet instead of navigating; once the
// dialog reports the save, the current page reloads and scrolls back to this
// card. Without the outlet the links navigate as usual.
export default class extends Controller {
  static outlets = ["entity-quick-add-dialog"]

  open(event) {
    if (!this.hasEntityQuickAddDialogOutlet) return

    event.preventDefault()
    this.entityQuickAddDialogOutlet.open({
      url: event.currentTarget.href,
      title: event.params.title,
      onCreated: () => this.reload()
    })
  }

  reload() {
    const id = this.element.id
    if (!window.Turbo) {
      window.location.reload()
      return
    }

    document.addEventListener("turbo:load", () => document.getElementById(id)?.scrollIntoView(), { once: true })
    window.Turbo.visit(window.location.pathname + window.location.search, { action: "replace" })
  }
}
