import { Controller } from "@hotwired/stimulus"

/**
 * Dropdown Controller
 *
 * A simple dropdown menu controller for showing/hiding menus.
 * Used throughout the application for entity selectors, action menus, etc.
 *
 * Usage:
 *   <div data-controller="dropdown">
 *     <button data-action="click->dropdown#toggle">Toggle</button>
 *     <div data-dropdown-target="menu" class="hidden">Menu content</div>
 *   </div>
 */
export default class extends Controller {
  static targets = ["menu"]

  connect() {
    // Close dropdown when clicking outside
    this.boundClickOutside = this.clickOutside.bind(this)
    document.addEventListener("click", this.boundClickOutside)

    // Close dropdown on escape key
    this.boundKeydown = this.keydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("click", this.boundClickOutside)
    document.removeEventListener("keydown", this.boundKeydown)
  }

  toggle(event) {
    event.stopPropagation()

    if (this.menuTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.menuTarget.classList.remove("hidden")
    this.element.setAttribute("data-dropdown-open", "true")
  }

  close() {
    this.menuTarget.classList.add("hidden")
    this.element.removeAttribute("data-dropdown-open")
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  keydown(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }
}
