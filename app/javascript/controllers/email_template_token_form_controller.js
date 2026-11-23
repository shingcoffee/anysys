import { Controller } from "@hotwired/stimulus"

// Keep the selected entity field and its editable display name in sync.
export default class extends Controller {
  static targets = ["entity", "attribute", "label"]
  static values = {
    attributes: { type: Object, default: {} },
    blankLabel: { type: String, default: "Select an attribute" }
  }

  connect() {
    this.refreshAttributes()
  }

  changeEntity() {
    this.refreshAttributes()
    this.attributeTarget.selectedIndex = this.attributeTarget.options.length > 1 ? 1 : 0
    this.changeAttribute()
  }

  changeAttribute() {
    this.labelTarget.value = this.attributeTarget.value ? this.attributeTarget.selectedOptions[0].textContent : ""
  }

  refreshAttributes() {
    if (!this.hasEntityTarget || !this.hasAttributeTarget) return

    const entityId = String(this.entityTarget.value || "")
    const options = this.attributesValue[entityId] || []
    const previous = this.attributeTarget.value

    this.attributeTarget.innerHTML = ""
    this.attributeTarget.appendChild(this.#option("", this.blankLabelValue))

    options.forEach((pair) => {
      const label = Array.isArray(pair) ? pair[0] : String(pair)
      const value = Array.isArray(pair) ? pair[1] : String(pair)
      this.attributeTarget.appendChild(this.#option(value, label))
    })

    if (options.some((pair) => (Array.isArray(pair) ? pair[1] : pair) === previous)) {
      this.attributeTarget.value = previous
    }
  }

  #option(value, label) {
    const option = document.createElement("option")
    option.value = value
    option.textContent = label
    return option
  }
}
