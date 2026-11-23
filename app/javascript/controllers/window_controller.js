import { Controller } from "@hotwired/stimulus"

/**
 * Window Controller
 * Provides simple window-level actions for use in views.
 */
export default class extends Controller {
  close() {
    window.close()
  }
}
