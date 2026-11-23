/**
 * LabelDerivationMixin — auto-derives human-readable canvas labels from element
 * properties. Apply with:
 *   Object.assign(PropertyEditorController.prototype, LabelDerivationMixin)
 */
import { elementDefaultLabel } from "flowchart/constants/element_registry"

export const LabelDerivationMixin = {
  /**
   * Derive label from properties based on element type.
   * A label is automatic when it is blank, equals the translated defaultLabel,
   * or equals the label derived from the previous settings.
   * @param {Object} properties - The collected properties
   * @param {string} explicitLabel - Label explicitly typed by the user
   * @returns {string|undefined} - Derived label or undefined
   */
  _deriveLabelFromProperties(properties, explicitLabel) {
    if (explicitLabel !== undefined && explicitLabel !== "") {
      return explicitLabel
    }

    const type = this.currentElement?.type
    if (!type) return undefined

    switch (type) {
      case "process":
        return this._deriveLabelFromSteps(properties.steps)
      case "decision":
        return this._summarizeCondition(properties.condition) || undefined
      case "start":
        return this._deriveLabelForStart()
      case "end":
        return this._deriveLabelForEnd(properties)
      case "loop":
        return this._deriveLabelForLoop(properties)
      case "subflow":
        return this._deriveLabelForSubflow()
      default:
        return undefined
    }
  },

  _deriveLabelForStart() {
    return elementDefaultLabel("start") || this.deriveStartFallbackValue
  },

  _deriveLabelForEnd(properties) {
    const responseType = properties.responseType || "none"
    if (responseType === "value") {
      const returnValue = properties.returnValue || ""
      return returnValue
        ? this.deriveReturnWithValueFormatValue.replace("{value}", returnValue)
        : this.deriveReturnValueFallbackValue
    }
    return elementDefaultLabel("end") || this.deriveEndFallbackValue
  },

  _deriveLabelForLoop(properties) {
    const loopType = properties.loopType || "while"
    if (loopType === "for_each") {
      const collection = properties.collection || ""
      return collection
        ? this.deriveForEachWithCollectionFormatValue.replace("{collection}", collection)
        : this.deriveForEachFallbackValue
    }
    const expr = this._extractConditionExpression(properties.condition)
    if (properties.runOnceFirst) {
      return expr
        ? this.deriveRunOnceFirstWithExprFormatValue.replace("{expr}", expr)
        : this.deriveRunOnceFirstFallbackValue
    }
    return expr
      ? this.deriveWhileWithExprFormatValue.replace("{expr}", expr)
      : this.deriveWhileFallbackValue
  },

  _extractConditionExpression(condition) {
    return this._summarizeCondition(condition)
  },

  _deriveLabelForSubflow() {
    return elementDefaultLabel("subflow") || this.deriveSubflowFallbackValue
  },

  /**
   * Derive a label from steps by combining their selectionLabels.
   * @param {Array} steps
   * @returns {string|undefined}
   */
  _deriveLabelFromSteps(steps) {
    if (!steps || steps.length === 0) return undefined

    const stepLabels = steps
      .map((step) => {
        if (step.selectionLabels && Array.isArray(step.selectionLabels)) {
          return step.selectionLabels.join(" - ")
        }
        return step.action || ""
      })
      .filter((label) => label.length > 0)

    if (stepLabels.length === 0) return undefined
    return this._ensureUniqueLabel(stepLabels.join(", "))
  },

  _ensureUniqueLabel(baseLabel) {
    if (!this.canvas?.elements) return baseLabel

    const currentId = this.currentElement?.id
    const existingLabels = new Set(
      this.canvas.elements
        .filter((el) => el.id !== currentId)
        .map((el) => el.label)
    )

    if (!existingLabels.has(baseLabel)) return baseLabel

    let suffix = 2
    let uniqueLabel = `${baseLabel} ${suffix}`
    while (existingLabels.has(uniqueLabel)) {
      suffix++
      uniqueLabel = `${baseLabel} ${suffix}`
    }
    return uniqueLabel
  },

  /**
   * Build a concise human-readable summary of a condition in the current group
   * shape — field rows and record-count rows joined by per-join AND/OR.
   */
  _summarizeCondition(cond, depth = 0) {
    if (!cond || typeof cond !== "object") return ""

    if (cond.type === "group") {
      const joins = cond.joins || []
      const parts = (cond.conditions || []).map((m) => {
        const s = this._summarizeCondition(m, depth + 1)
        return (m && m.type === "group" && s) ? `(${s})` : s
      }).filter(Boolean)
      if (!parts.length) return ""
      let out = parts[0]
      for (let i = 1; i < parts.length; i++) out += ` ${joins[i - 1] || "AND"} ${parts[i]}`
      return depth === 0 ? this._truncateLabel(out) : out
    }

    if (cond.kind === "query_count") {
      const qc = cond.queryConfig || {}
      const entity = qc.entityName || `#${qc.entityId ?? "?"}`
      return `count(${entity}) ${cond.countOperator || ">"} ${cond.countValue ?? 0}`
    }

    const left = cond.leftOperand || ""
    if (!left) return ""
    if (!cond.operator) return left
    const op = /^[<>=!]+$/.test(cond.operator) ? cond.operator : cond.operator.replace(/_/g, " ")
    const right = cond.rightOperand ? ` ${cond.rightOperand}` : ""
    return `${left} ${op}${right}`
  },

  _truncateLabel(s) {
    return s.length > 48 ? `${s.slice(0, 47)}…` : s
  }
}
