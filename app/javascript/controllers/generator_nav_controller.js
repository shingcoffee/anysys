import { Controller } from "@hotwired/stimulus"

const ACTIVE_LINK = ["bg-indigo-50", "text-indigo-700", "font-medium"]
const INACTIVE_LINK = ["text-gray-600", "hover:bg-gray-50", "hover:text-gray-900"]
const ACTIVE_ICON = ["text-indigo-500"]
const INACTIVE_ICON = ["text-gray-400"]
const ACTIVE_COUNT = ["text-indigo-500", "bg-indigo-100", "px-1.5", "rounded-full"]
const INACTIVE_COUNT = ["text-gray-400"]

export default class extends Controller {
  static targets = ["link", "groupContent", "chevron"]

  activate(event) {
    this.linkTargets.forEach(link => {
      link.classList.remove(...ACTIVE_LINK)
      link.classList.add(...INACTIVE_LINK)

      const icon = link.querySelector("svg")
      if (icon) {
        icon.classList.remove(...ACTIVE_ICON)
        icon.classList.add(...INACTIVE_ICON)
      }

      const count = link.querySelector("span:last-child")
      if (count) {
        count.classList.remove(...ACTIVE_COUNT)
        count.classList.add(...INACTIVE_COUNT)
      }
    })

    const clicked = event.currentTarget
    clicked.classList.remove(...INACTIVE_LINK)
    clicked.classList.add(...ACTIVE_LINK)

    const icon = clicked.querySelector("svg")
    if (icon) {
      icon.classList.remove(...INACTIVE_ICON)
      icon.classList.add(...ACTIVE_ICON)
    }

    const count = clicked.querySelector("span:last-child")
    if (count) {
      count.classList.remove(...INACTIVE_COUNT)
      count.classList.add(...ACTIVE_COUNT)
    }
  }

  toggle(event) {
    const button = event.currentTarget
    const group = button.closest("[data-generator-nav-target='group']")
    const content = group.querySelector("[data-generator-nav-target='groupContent']")
    const chevron = group.querySelector("[data-generator-nav-target='chevron']")

    if (content) {
      content.classList.toggle("hidden")
    }
    if (chevron) {
      chevron.classList.toggle("rotate-90")
    }
  }
}
