import { Controller } from "@hotwired/stimulus"

/**
 * Collapsible Controller
 *
 * Provides expandable/collapsible sections used throughout the page builder.
 * Supports animated icon rotation and programmatic control.
 *
 * Usage:
 *   <div data-controller="collapsible" data-collapsible-open-value="true">
 *     <button data-action="click->collapsible#toggle">
 *       <span data-collapsible-target="icon">chevron</span>
 *       Section Title
 *     </button>
 *     <div data-collapsible-target="content">
 *       Collapsible content here...
 *     </div>
 *   </div>
 *
 * Values:
 *   - open: Boolean (default: true) - Initial state of the collapsible section
 *
 * Targets:
 *   - content: The element to show/hide
 *   - icon: Optional icon element that rotates to indicate state
 */
export default class extends Controller {
  static targets = ["content", "icon"]
  static values = {
    open: { type: Boolean, default: true }
  }

  connect() {
    this.render()
  }

  toggle() {
    this.openValue = !this.openValue
  }

  openValueChanged() {
    this.render()
  }

  render() {
    if (this.hasContentTarget) {
      this.contentTarget.classList.toggle("hidden", !this.openValue)
    }

    if (this.hasIconTarget) {
      this.iconTarget.style.transform = this.openValue ? "rotate(0deg)" : "rotate(-90deg)"
    }
  }

  // Public methods for programmatic control
  open() {
    this.openValue = true
  }

  close() {
    this.openValue = false
  }
}
