const CSS = Object.freeze({
  hidden: "hidden"
})

export { CSS }

export class BaseManager {
  constructor(controller) {
    this.controller = controller
  }

  get c() { return this.controller }

  get customerIdValue() { return this.c.customerIdValue }
  get idValue() { return this.c.idValue }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text || ""
    return div.innerHTML
  }

  generateSlug(text) {
    return text.toLowerCase()
      .replace(/[^a-z0-9]+/g, "_")
      .replace(/^_|_$/g, "")
  }

  formatLabel(type) {
    return type.charAt(0).toUpperCase() + type.slice(1).replace(/_/g, " ")
  }
}
