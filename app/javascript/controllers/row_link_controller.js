import { Controller } from "@hotwired/stimulus"

// Lets a whole list row open its primary link. Mount on the list container
// (e.g. <tbody>) with data-action="click->row-link#open"; mark each row with
// data-row-link-row and its link with data-row-link-primary. Clicks on
// interactive descendants, modified clicks and text selections are ignored so
// checkboxes, menus, buttons and copy-paste keep working.
const INTERACTIVE = "a, button, input, select, textarea, label, summary, details, [data-row-link-ignore]"

export default class extends Controller {
  open(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    if (event.target.closest(INTERACTIVE)) return
    if (window.getSelection().toString() !== "") return

    const row = event.target.closest("[data-row-link-row]")
    const link = row && row.querySelector("[data-row-link-primary]")
    if (link) link.click()
  }
}
