import { Controller } from "@hotwired/stimulus"

// Manages the Payment Method tab UI interactions.
//
// Currently used as a lightweight namespace controller (data-controller="payment-method")
// so future targets/actions (e.g. optimistic remove, inline status updates) can be
// added without changing the template structure.
//
// The confirm-before-remove UX relies on Turbo's built-in data-turbo-confirm attribute
// on each button_to form, so no explicit JS confirm handler is needed here.
export default class extends Controller {
  static targets = ["removeButton"]
}
