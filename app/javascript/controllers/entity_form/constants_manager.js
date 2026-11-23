import { BaseManager, escapeHtml } from "controllers/entity_form/base_manager"

// The options-source switch, in button order.
const OPTION_SOURCES = [
  { mode: "manual", button: "manualOptionsBtn", section: "manualOptionsSection" },
  { mode: "constant", button: "constantOptionsBtn", section: "constantOptionsSection" },
  { mode: "entity_entries", button: "entityRecordsOptionsBtn", section: "entityRecordsOptionsSection" }
]
const ACTIVE_CLASSES = ["text-accent-text", "bg-accent-subtle", "border-accent", "shadow-sm"]
const INACTIVE_CLASSES = ["text-text-muted", "bg-transparent", "border-transparent"]

export class ConstantsManager extends BaseManager {
  async loadConstants() {
    if (!this.c.hasCustomerIdValue) return
    try {
      const response = await fetch(`/${this.customerIdValue}/admin/maintenance/constants.json`)
      if (!response.ok) return
      this.c.constants = await response.json()
      this.populateConstantSelect()
    } catch (_error) {
      /* silently ignore */
    }
  }

  populateConstantSelect() {
    if (!this.c.hasConstantSelectTarget) return
    while (this.c.constantSelectTarget.options.length > 1) this.c.constantSelectTarget.remove(1)
    this.c.constants.forEach(constant => {
      const option = document.createElement("option")
      option.value = constant.id
      option.textContent = this.c.constantOptionCountLabelValue
        .replace("{name}", constant.name)
        .replace("{count}", constant.options?.length || 0)
      option.dataset.constantData = JSON.stringify(constant)
      this.c.constantSelectTarget.appendChild(option)
    })
  }

  selectManualOptions(event) {
    event.preventDefault()
    this.c.optionsSourceMode = "manual"
    this.updateOptionsSourceUI()
    this.c.validatorManager.syncInclusionValidator()
  }

  selectConstantOptions(event) {
    event.preventDefault()
    this.c.optionsSourceMode = "constant"
    this.updateOptionsSourceUI()
    this.c.validatorManager.syncInclusionValidator()
  }

  updateOptionsSourceUI() {
    if (!this.c.hasManualOptionsBtnTarget || !this.c.hasConstantOptionsBtnTarget) return
    OPTION_SOURCES.forEach(({ mode, button, section }) => {
      const active = this.c.optionsSourceMode === mode
      if (this.hasTarget(button)) {
        this.target(button).classList.add(...(active ? ACTIVE_CLASSES : INACTIVE_CLASSES))
        this.target(button).classList.remove(...(active ? INACTIVE_CLASSES : ACTIVE_CLASSES))
      }
      if (this.hasTarget(section)) this.target(section).classList.toggle("hidden", !active)
    })
  }

  constantChanged(event) {
    const select = event.target
    const selectedOption = select.options[select.selectedIndex]
    if (!selectedOption || !selectedOption.dataset.constantData) {
      this.hideConstantPreview()
      return
    }
    const constant = JSON.parse(selectedOption.dataset.constantData)
    this.showConstantPreview(constant)
    this.c.validatorManager.syncInclusionValidator()
  }

  showConstantPreview(constant) {
    if (!this.c.hasConstantPreviewTarget) return
    const options = constant.options || []
    if (this.c.hasConstantOptionsCountTarget) {
      const template = options.length !== 1 ? this.c.optionCountPluralLabelValue : this.c.optionCountSingularLabelValue
      this.c.constantOptionsCountTarget.textContent = template.replace("{count}", options.length)
    }
    if (this.c.hasConstantPreviewListTarget) {
      this.c.constantPreviewListTarget.innerHTML = options.map(option => `
        <span class="badge badge-accent">
          ${escapeHtml(option)}
        </span>
      `).join('')
    }
    this.c.constantPreviewTarget.classList.remove("hidden")
  }

  hideConstantPreview() {
    if (!this.c.hasConstantPreviewTarget) return
    this.c.constantPreviewTarget.classList.add("hidden")
  }
}
