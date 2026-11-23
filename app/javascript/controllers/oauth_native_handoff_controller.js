import { Controller } from "@hotwired/stimulus"

// Hands the browser off to the desktop GUI's loopback callback. Turbo Drive
// will not follow a 302 to 127.0.0.1 from the app origin; this controller
// assigns window.location after the interstitial has painted.
export default class extends Controller {
  static values = { url: String }

  connect() {
    if (!this.urlValue) return

    setTimeout(() => { window.location = this.urlValue }, 300)
  }
}
