// app/javascript/lib/formula_validator.js
import { FormulaEngine } from "lib/formula_engine"

const FUNCTION_ALLOWLIST = new Set([
  "SUM", "SUBTRACT", "MULTIPLY", "DIVIDE", "MIN", "MAX", "AVERAGE", "ROUND", "FLOOR", "CEIL", "ABS", "MOD",
  "IF", "AND", "OR", "NOT", "SWITCH",
  "CONCAT", "UPPER", "LOWER", "TRIM", "LENGTH", "LEFT", "RIGHT",
  "TODAY", "NOW", "YEAR", "MONTH", "DAY", "DATE_DIFF", "DATE_ADD"
])

const FIELD_REF = /\{([a-zA-Z0-9_]+)\}/g

// Returns { valid, errors:[], referencedFields:[], result }
// fieldIds: Set/array of valid field ids; sampleValues: {field_id: value} for live preview.
export function validateFormula(formula, fieldIds = [], sampleValues = {}) {
  const errors = []
  const known = new Set(fieldIds)
  const referencedFields = []

  if (!formula || !formula.trim()) {
    return { valid: true, errors, referencedFields, result: null }
  }

  let m
  FIELD_REF.lastIndex = 0
  while ((m = FIELD_REF.exec(formula))) {
    referencedFields.push(m[1])
    if (!known.has(m[1])) errors.push(`Unknown field: ${m[1]}`)
  }

  ;(formula.match(/\b([A-Z_]+)\s*\(/g) || []).forEach(tok => {
    const fn = tok.replace(/\s*\($/, "")
    if (!FUNCTION_ALLOWLIST.has(fn)) errors.push(`Unknown function: ${fn}`)
  })

  const open = (formula.match(/\(/g) || []).length
  const close = (formula.match(/\)/g) || []).length
  if (open !== close) errors.push("Unbalanced parentheses")

  let result = null
  if (errors.length === 0) {
    try {
      result = new FormulaEngine(sampleValues).evaluate(formula)
    } catch (e) {
      errors.push(`Evaluation error: ${e.message}`)
    }
  }

  return { valid: errors.length === 0, errors, referencedFields: [...new Set(referencedFields)], result }
}
