import { BaseManager } from "controllers/entity_form/base_manager"

const SELECTION_TYPES = ["select", "radio", "checkbox"]

const CONFIG_TYPE_MAP = {
  "select": "selection",
  "radio": "selection",
  "checkbox": "selection",
  "file": "file",
  "image": "file"
}

// English defaults only — TypeManager reads the translated map via
// this.c.htmlTypeLabelsValue (Object Value on entity_form_controller.js);
// this constant seeds that Value's `default:` and backstops direct
// `new TypeManager({})` calls in specs. Keep in sync with
// entity_form_controller.js's `htmlTypeLabels` value default.
const HTML_TYPE_LABELS = {
  'text': 'Text Input', 'textarea': 'Textarea', 'search': 'Search',
  'password': 'Password', 'hidden': 'Hidden',
  'select': 'Dropdown', 'radio': 'Radio', 'checkbox': 'Checkbox',
  'number': 'Number', 'range': 'Range',
  'date': 'Date', 'time': 'Time', 'datetime-local': 'DateTime',
  'month': 'Month', 'week': 'Week',
  'email': 'Email', 'tel': 'Phone', 'url': 'URL',
  'file': 'File', 'image': 'Image', 'color': 'Color'
}

export { SELECTION_TYPES, CONFIG_TYPE_MAP, HTML_TYPE_LABELS }

export class TypeManager extends BaseManager {
  htmlTypeChanged() {
    if (!this.c.hasModalHtmlTypeTarget || !this.c.hasOptionsSectionTarget) return
    const htmlType = this.c.modalHtmlTypeTarget.value
    if (this.c.referenceManager) this.c.referenceManager.syncAvailability(htmlType)
    const configType = CONFIG_TYPE_MAP[htmlType]
    if (configType) {
      this.showConfigSection(configType)
    } else {
      this.hideConfigSection()
    }
    this.c.inclusionManuallyRemoved = false
    this.c.validatorManager.filterValidatorsByHtmlType(htmlType)
    this.c.validatorManager.syncInclusionValidator()
  }

  showConfigSection(configType) {
    this.c.optionsSectionTarget.classList.remove("hidden")
    this.hideAllConfigContainers()
    const targetName = `has${this.capitalize(configType)}ConfigTarget`
    if (this.c[targetName]) {
      this.c[`${configType}ConfigTarget`].classList.remove("hidden")
    }
    if (configType === "selection" && this.c.hasOptionsContainerTarget && this.c.optionsContainerTarget.children.length === 0) {
      this.c.addOption()
    }
  }

  hideConfigSection() {
    if (!this.c.hasOptionsSectionTarget) return
    this.c.optionsSectionTarget.classList.add("hidden")
    this.hideAllConfigContainers()
  }

  hideAllConfigContainers() {
    if (this.c.hasSelectionConfigTarget) this.c.selectionConfigTarget.classList.add("hidden")
    if (this.c.hasFileConfigTarget) this.c.fileConfigTarget.classList.add("hidden")
  }

  formatHtmlTypeName(htmlType) {
    if (!htmlType || htmlType === "") return this.c.htmlTypeNaLabelValue ?? "N/A"
    const labels = this.c.htmlTypeLabelsValue || HTML_TYPE_LABELS
    return labels[htmlType] || htmlType
  }

  getConfigForType(htmlType) {
    const configType = CONFIG_TYPE_MAP[htmlType]
    switch (configType) {
      case "selection": {
        if (this.c.optionsSourceMode === "entity_entries") return this.c.referenceManager.getConfig()
        if (this.c.optionsSourceMode === "constant") {
          const constantId = this.c.hasConstantSelectTarget ? this.c.constantSelectTarget.value : ""
          if (constantId) {
            const constant = this.c.constants.find(c => c.id == constantId)
            if (constant) {
              return {
                source: "constant",
                constant_id: parseInt(constantId),
                constant_name: constant.name,
                options: constant.options || []
              }
            }
          }
          return null
        } else {
          const options = this.c.validatorManager.getSelectedOptions()
          return options.length > 0 ? { source: "manual", options } : null
        }
      }
      case "file":
        return this.getFileConfig()
      default:
        return null
    }
  }

  getSelectedOptions() {
    if (!this.c.hasOptionsContainerTarget) return []
    const htmlType = this.c.hasModalHtmlTypeTarget ? this.c.modalHtmlTypeTarget.value : ""
    if (!SELECTION_TYPES.includes(htmlType)) return []
    return Array.from(
      this.c.optionsContainerTarget.querySelectorAll("[data-option-item]")
    ).map(item => {
      const label = item.querySelector("[data-option-label]")?.value.trim() || ""
      const value = item.querySelector("[data-option-value]")?.value.trim() || ""
      const defaultInput = item.querySelector("[data-option-default]")
      const isDefault = defaultInput?.checked || false
      return { label, value, default: isDefault }
    }).filter(opt => opt.label || opt.value)
  }

  getFileConfig() {
    const accept = this.c.hasConfigAcceptTarget ? this.c.configAcceptTarget.value.trim() : ""
    const multiple = this.c.hasConfigMultipleTarget ? this.c.configMultipleTarget.checked : false
    if (!accept && !multiple) return null
    return { accept: accept || null, multiple }
  }
}
