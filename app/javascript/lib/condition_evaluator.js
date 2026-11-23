export class ConditionEvaluator {
  constructor(fieldValues = {}) {
    this.values = fieldValues
  }

  evaluateCondition(condition) {
    const fieldValue = this.values[condition.field_id]
    const compareValue = condition.value

    switch (condition.operator) {
      case 'equals':
        return fieldValue == compareValue

      case 'not_equals':
        return fieldValue != compareValue

      case 'contains':
        return String(fieldValue ?? '').includes(compareValue)

      case 'not_contains':
        return !String(fieldValue ?? '').includes(compareValue)

      case 'starts_with':
        return String(fieldValue ?? '').startsWith(compareValue)

      case 'ends_with':
        return String(fieldValue ?? '').endsWith(compareValue)

      case 'greater_than':
        if (fieldValue === null || fieldValue === undefined || fieldValue === '') return false
        return Number(fieldValue) > Number(compareValue)

      case 'less_than':
        if (fieldValue === null || fieldValue === undefined || fieldValue === '') return false
        return Number(fieldValue) < Number(compareValue)

      case 'greater_or_equal':
        if (fieldValue === null || fieldValue === undefined || fieldValue === '') return false
        return Number(fieldValue) >= Number(compareValue)

      case 'less_or_equal':
        if (fieldValue === null || fieldValue === undefined || fieldValue === '') return false
        return Number(fieldValue) <= Number(compareValue)

      case 'between': {
        if (fieldValue === null || fieldValue === undefined || fieldValue === '') return false
        const num = Number(fieldValue)
        return num >= Number(compareValue[0]) && num <= Number(compareValue[1])
      }

      case 'is_empty':
        return fieldValue === null || fieldValue === undefined || fieldValue === ''

      case 'is_not_empty':
        return fieldValue !== null && fieldValue !== undefined && fieldValue !== ''

      case 'is_selected':
        if (Array.isArray(fieldValue)) {
          return fieldValue.includes(compareValue)
        }
        return fieldValue === compareValue

      case 'is_not_selected':
        if (Array.isArray(fieldValue)) {
          return !fieldValue.includes(compareValue)
        }
        return fieldValue !== compareValue

      case 'matches_regex':
        try {
          if (fieldValue === null || fieldValue === undefined) {
            return false
          }
          return new RegExp(compareValue).test(String(fieldValue))
        } catch (_e) {
          return false
        }

      default:
        return false
    }
  }

  // Main entry point for evaluating a full condition tree
  evaluate(conditions) {
    if (!conditions?.groups?.length) {
      return true  // No conditions = always true
    }

    const groupResults = conditions.groups.map(group => this.evaluateGroup(group))

    return conditions.logic === 'all'
      ? groupResults.every(Boolean)
      : groupResults.some(Boolean)
  }

  // Evaluate a single group of conditions
  evaluateGroup(group) {
    if (!group?.items?.length) {
      return true
    }

    const itemResults = group.items.map(item => this.evaluateCondition(item))

    return group.logic === 'all'
      ? itemResults.every(Boolean)
      : itemResults.some(Boolean)
  }
}
