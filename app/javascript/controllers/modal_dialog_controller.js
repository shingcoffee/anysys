import { Controller } from "@hotwired/stimulus"

// A trigger and its in-page modal (ModalDialogComponent) under one element.
// The open value shows the dialog on connect, e.g. when the server
// re-renders the form inside it with errors.
export default class extends Controller {
  static targets = ["dialog"]
  static values = { open: Boolean }

  connect() {
    if (this.openValue) this.open()
  }

  open() {
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
