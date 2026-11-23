import { Controller } from "@hotwired/stimulus"

// Redirects the browser to the PSP's H5 payment URL shortly after mount.
// Registered as `payments--h5-redirect` via eager-loading.
export default class extends Controller {
  static values = { url: String }

  connect() {
    setTimeout(() => { window.location = this.urlValue }, 300)
  }
}
