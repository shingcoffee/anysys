import { Controller } from "@hotwired/stimulus"

// Provides a print trigger for the invoice detail view.
//
// Usage (added automatically by InvoiceDetailComponent):
//   data-controller="billing-invoice"
//   data-action="billing-invoice#print"
export default class extends Controller {
  print() {
    window.print()
  }
}
