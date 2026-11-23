import { BaseManager, CSS } from "controllers/entity_form/base_manager"

const MODE_ACTIVE = ["text-accent-text", "bg-accent-subtle", "border-accent", "shadow-sm"]
const MODE_INACTIVE = ["text-text-muted", "bg-transparent", "border-transparent"]
const COUNT_FN = "count"
const MAX_PRECISION = 6
const DEFAULT_PRECISION = 2

export class ComputedManager extends BaseManager {
  selectInputMode(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }
    this.c.attributeMode = "input"
    this.updateModeUI()
  }

  selectComputedMode(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }
    this.c.attributeMode = "computed"
    this.populateRelations()
    this.updateModeUI()
  }

  updateModeUI() {
    const canCompute = this._canCompute()
    this._toggleHidden("valueSourceSection", !canCompute)
    if (this.c.attributeMode === "computed" && !canCompute) {
      this.c.attributeMode = "input"
    }
    const computed = this.c.attributeMode === "computed"
    this._setModeButton(this.hasTarget("modeInputBtn") ? this.c.modeInputBtnTarget : null, !computed)
    this._setModeButton(this.hasTarget("modeComputedBtn") ? this.c.modeComputedBtnTarget : null, computed)
    this._toggleHidden("computedSection", !computed)
    this._toggleHidden("htmlTypeField", computed)
    this._toggleHidden("validatorsSection", computed)
    if (computed) {
      this._toggleHidden("optionsSection", true)
    } else if (this.c.typeManager) {
      this.c.typeManager.htmlTypeChanged()
    }
  }

  _canCompute() {
    return this.parsedOptions().length > 0 && this.c.attributeModalContext !== "association"
  }

  populateRelations() {
    if (!this.hasTarget("computedRelation")) return
    const select = this.c.computedRelationTarget
    const previous = select.value
    const options = this.parsedOptions()
    select.innerHTML = ""

    const placeholder = document.createElement("option")
    placeholder.value = ""
    placeholder.textContent = options.length
      ? this.c.computedRelationPlaceholderValue
      : this.c.computedEmptyHintValue
    select.appendChild(placeholder)

    const format = this.c.computedRelationFormatValue
    options.forEach((relation, index) => {
      const option = document.createElement("option")
      option.value = String(index)
      option.textContent = format
        .replace("{related}", relation.related_entity_label || "")
        .replace("{bridge}", relation.bridge_label || "")
      select.appendChild(option)
    })

    if (previous && [...select.options].some((opt) => opt.value === previous)) {
      select.value = previous
    }
    this.populateAttributes()
    this.populateFilterAttributes()
  }

  relationChanged() {
    this.populateAttributes()
    this.populateFilterAttributes()
  }

  functionChanged() {
    this.populateAttributes()
    this._syncPrecisionState()
  }

  populateAttributes() {
    if (!this.hasTarget("computedAttribute")) return
    const select = this.c.computedAttributeTarget
    const previous = select.value
    const relation = this.selectedRelation()
    const includeNonNumeric = this._functionValue() === COUNT_FN
    select.innerHTML = ""

    const placeholder = document.createElement("option")
    placeholder.value = ""
    placeholder.textContent = this.c.computedAttributePlaceholderValue
    select.appendChild(placeholder)

    if (!relation) return

    const attrs = (relation.attributes || []).filter((attr) => includeNonNumeric || attr.numeric === true)
    attrs.forEach((attr) => {
      const option = document.createElement("option")
      option.value = attr.slug
      option.textContent = attr.label || attr.slug
      select.appendChild(option)
    })

    if (previous && [...select.options].some((opt) => opt.value === previous)) {
      select.value = previous
    }
  }

  filterChanged() {
    this._syncFilterControls()
  }

  populateFilterAttributes() {
    if (!this.hasTarget("computedFilterAttribute")) return
    const select = this.c.computedFilterAttributeTarget
    const previous = select.value
    const relation = this.selectedRelation()
    select.innerHTML = ""

    const placeholder = document.createElement("option")
    placeholder.value = ""
    placeholder.textContent = this.c.computedFilterNoneValue
    select.appendChild(placeholder)

    if (relation) {
      const attrs = relation.attributes || []
      attrs.forEach((attr) => {
        const option = document.createElement("option")
        option.value = attr.slug
        option.textContent = attr.label || attr.slug
        select.appendChild(option)
      })

      if (previous && [...select.options].some((opt) => opt.value === previous)) {
        select.value = previous
      }
    }

    this._syncFilterControls()
  }

  getComputedConfig() {
    const relation = this.selectedRelation()
    const fn = this._functionValue()
    if (!relation || !fn) return null
    const slug = this.hasTarget("computedAttribute") ? this.c.computedAttributeTarget.value : ""
    if (fn !== COUNT_FN && !slug) return null
    const config = {
      bridge_entity_id: relation.bridge_entity_id,
      bridge_role: relation.bridge_role,
      source_slug: slug || "",
      function: fn,
      precision: this._precisionValue(fn)
    }
    const filter = this._filterConfig()
    if (filter) config.filter = filter
    return config
  }

  applyComputedConfig(config) {
    if (!config || typeof config !== "object") return
    this.populateRelations()
    const options = this.parsedOptions()
    const idx = options.findIndex((item) =>
      String(item.bridge_entity_id) === String(config.bridge_entity_id) &&
      item.bridge_role === config.bridge_role
    )
    if (this.hasTarget("computedRelation") && idx >= 0) {
      this.c.computedRelationTarget.value = String(idx)
    }
    if (this.hasTarget("computedFunction") && config.function) {
      this.c.computedFunctionTarget.value = config.function
    }
    this.functionChanged()
    if (this.hasTarget("computedAttribute") && config.source_slug) {
      this.c.computedAttributeTarget.value = config.source_slug
    }
    if (this.hasTarget("computedPrecision") && config.function !== COUNT_FN && config.precision != null) {
      this.c.computedPrecisionTarget.value = String(config.precision)
    }
    this.populateFilterAttributes()
    this._applyFilter(config.filter)
  }

  validate() {
    if (!this.getComputedConfig() || this._filterIncomplete()) return this.c.computedIncompleteMsgValue
    return null
  }

  reset() {
    if (this.hasTarget("computedRelation")) this.c.computedRelationTarget.innerHTML = ""
    if (this.hasTarget("computedAttribute")) this.c.computedAttributeTarget.innerHTML = ""
    if (this.hasTarget("computedFunction")) this.c.computedFunctionTarget.selectedIndex = 0
    if (this.hasTarget("computedPrecision")) {
      this.c.computedPrecisionTarget.value = String(DEFAULT_PRECISION)
      this.c.computedPrecisionTarget.disabled = false
    }
    if (this.hasTarget("computedFilterAttribute")) this.c.computedFilterAttributeTarget.innerHTML = ""
    this._clearFilterControls()
    this.selectInputMode()
  }

  parsedOptions() {
    const raw = this.c.computedOptionsValue
    if (Array.isArray(raw)) return raw
    if (typeof raw === "string") {
      try {
        const parsed = JSON.parse(raw)
        if (Array.isArray(parsed)) return parsed
        if (parsed && typeof parsed === "object") return [parsed]
      } catch { /* ignore malformed JSON */ }
      return []
    }
    if (raw && typeof raw === "object") return [raw]
    return []
  }

  selectedRelation() {
    if (!this.hasTarget("computedRelation")) return null
    const index = this.c.computedRelationTarget.value
    if (index === "") return null
    return this.parsedOptions()[Number(index)] || null
  }

  _functionValue() {
    return this.hasTarget("computedFunction") ? this.c.computedFunctionTarget.value : ""
  }

  _precisionValue(fn) {
    if (fn === COUNT_FN) return DEFAULT_PRECISION
    if (!this.hasTarget("computedPrecision")) return DEFAULT_PRECISION
    const raw = parseInt(this.c.computedPrecisionTarget.value, 10)
    if (!Number.isFinite(raw)) return DEFAULT_PRECISION
    return Math.min(MAX_PRECISION, Math.max(0, raw))
  }

  _filterSlug() {
    return this.hasTarget("computedFilterAttribute") ? this.c.computedFilterAttributeTarget.value : ""
  }

  _filterOp() {
    return this.hasTarget("computedFilterOp") ? this.c.computedFilterOpTarget.value : ""
  }

  _filterValue() {
    return this.hasTarget("computedFilterValue") ? this.c.computedFilterValueTarget.value : ""
  }

  _filterConfig() {
    const slug = this._filterSlug()
    const op = this._filterOp()
    if (!slug || !op) return null
    return { slug, op, value: this._filterValue() }
  }

  _filterIncomplete() {
    const slug = this._filterSlug()
    if (!slug) return false
    return !this._filterOp() || this._filterValue().trim() === ""
  }

  _applyFilter(filter) {
    if (!filter || typeof filter !== "object" || !filter.slug) {
      this._clearFilterControls()
      return
    }
    if (!this.hasTarget("computedFilterAttribute")) return
    this.c.computedFilterAttributeTarget.value = filter.slug
    if (this.c.computedFilterAttributeTarget.value !== filter.slug) {
      this._clearFilterControls()
      return
    }
    this._syncFilterControls()
    if (this.hasTarget("computedFilterOp")) {
      this.c.computedFilterOpTarget.value = filter.op || ""
    }
    if (this.hasTarget("computedFilterValue")) {
      this.c.computedFilterValueTarget.value = filter.value == null ? "" : String(filter.value)
    }
  }

  _clearFilterControls() {
    if (this.hasTarget("computedFilterAttribute")) this.c.computedFilterAttributeTarget.value = ""
    if (this.hasTarget("computedFilterOp")) {
      this.c.computedFilterOpTarget.selectedIndex = 0
      this.c.computedFilterOpTarget.disabled = true
    }
    if (this.hasTarget("computedFilterValue")) {
      this.c.computedFilterValueTarget.value = ""
      this.c.computedFilterValueTarget.disabled = true
    }
  }

  _syncFilterControls() {
    const enabled = this._filterSlug() !== ""
    if (this.hasTarget("computedFilterOp")) {
      this.c.computedFilterOpTarget.disabled = !enabled
      if (!enabled) this.c.computedFilterOpTarget.selectedIndex = 0
    }
    if (this.hasTarget("computedFilterValue")) {
      this.c.computedFilterValueTarget.disabled = !enabled
      if (!enabled) this.c.computedFilterValueTarget.value = ""
    }
  }

  _syncPrecisionState() {
    if (!this.hasTarget("computedPrecision")) return
    const input = this.c.computedPrecisionTarget
    if (this._functionValue() === COUNT_FN) {
      input.value = ""
      input.disabled = true
    } else {
      input.disabled = false
      if (input.value === "") input.value = String(DEFAULT_PRECISION)
    }
  }

  _setModeButton(button, active) {
    if (!button) return
    if (active) {
      button.classList.add(...MODE_ACTIVE)
      button.classList.remove(...MODE_INACTIVE)
    } else {
      button.classList.remove(...MODE_ACTIVE)
      button.classList.add(...MODE_INACTIVE)
    }
  }

  _toggleHidden(targetName, hidden) {
    if (!this.hasTarget(targetName)) return
    const el = this.c[`${targetName}Target`]
    el.classList.toggle(CSS.hidden, hidden)
  }
}
