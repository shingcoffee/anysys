import { escapeHtml } from "utils"

const CSS = Object.freeze({
  hidden: "hidden",
  errorRing: ["ring-2", "ring-red-500", "border-red-500"],
  highlightRing: ["ring-2", "ring-amber-400"]
})

export { CSS, escapeHtml }

export class BaseManager {
  constructor(controller) {
    this.controller = controller
  }

  // Convenience getters
  get c() { return this.controller }

  get customerIdValue() { return this.c.customerIdValue }
  get currentEntityIdValue() { return this.c.currentEntityIdValue }

  // Target access helpers - delegates to controller
  target(name) {
    return this.c[`${name}Target`]
  }

  hasTarget(name) {
    return this.c[`has${name.charAt(0).toUpperCase() + name.slice(1)}Target`]
  }

  generateSlug(name, separator = "_") {
    if (!name) return ""
    return name
      .toString()
      .trim()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9\s\-_]/g, "")
      .replace(/[\s\-_]+/g, separator)
      .replace(new RegExp(`^${separator}|${separator}$`, "g"), "")
  }

  capitalize(str) {
    if (!str) return ""
    return str.charAt(0).toUpperCase() + str.slice(1)
  }

  getTargetValue(targetName) {
    const fullName = `has${this.capitalize(targetName)}Target`
    if (this.c[fullName]) {
      return this.c[`${targetName}Target`].value || ""
    }
    return ""
  }
}
