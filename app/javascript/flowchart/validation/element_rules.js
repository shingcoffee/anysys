/**
 * Per-element-type completeness rules for the flowchart validator.
 *
 * Each result is `{ type, field, severity, message, elementId }` (elementId is
 * stamped by runElementRules). Messages come from the `msg` callback (Stimulus
 * values on the canvas mount) with English fallbacks that match
 * flowchart_elements*.yml.
 */

import { hasValue, schemaDefault } from "flowchart/element_config"
import { conditionOperators } from "flowchart/constants/element_registry"

const ERROR = "error"
const WARNING = "warning"

const MESSAGES = {
  tooFewBranches: "Decision requires at least two outgoing connections",
  duplicateMatchValue: "Match values must be unique",
  multipleOtherwise: "Only one Otherwise branch is allowed",
  invalidConditionMatch: "Condition branches must match Yes (true), No (false), or Otherwise",
  missingYesBranch: "Condition routing needs a Yes branch and either No or Otherwise",
  emptyLoopCondition: "Add at least one condition",
  missingCollection: "Collection is required",
  missingReturnValue: "Return Value is required",
  missingFlowchart: "Flowchart is required",
  subflowSelfReference: "Flowchart cannot target itself",
  emptyProcess: "Add at least one step",
  invalidCollectionPath: "collection must be a valid identifier path",
  reservedLoopVariable: "{field} cannot be {name} because that name is reserved for the loop header",
  collidingLoopVariables: "itemVariable and indexVariable must be different"
}

// Mirrors CodeGenerators::ConditionRules; keyed `condition.<code>` in `msg`.
const CONDITION_MESSAGES = {
  invalid_condition: "Conditions must be a flat group of rows",
  empty_condition: "Add at least one condition",
  invalid_row: "Condition row {index} must be a field or record-count row",
  nested_group: "Condition row {index} cannot be a nested group",
  missing_entity: "Condition row {index} needs an entity",
  unknown_count_operator: "Condition row {index} needs a count comparison",
  missing_left: "Condition row {index} needs a value to compare",
  missing_operator: "Condition row {index} needs an operator",
  unknown_operator: "Condition row {index} has an unknown operator",
  missing_right: "Condition row {index} needs a value for {operator}"
}

const UNARY_OPERATORS = ["is_true", "is_false", "is_empty", "is_not_empty", "is_nil"]
const LOOP_HEADER_LOCALS = ["state", "ctx"]

function interpolate(template, tokens) {
  return Object.entries(tokens).reduce((text, [token, value]) => text.split(`{${token}}`).join(String(value)), template)
}

function messageFor(msg, key, fallback, tokens = {}) {
  return interpolate((typeof msg === "function" && msg(key)) || fallback, tokens)
}

function problem(type, field, severity, message, extra = {}) {
  return { type, field, severity, message, ...extra }
}

function present(value) {
  return value !== undefined && value !== null && !(typeof value === "string" && value.trim() === "")
}

function operatorSets() {
  const operators = conditionOperators()
  if (!operators.length) return { known: null, unary: new Set(UNARY_OPERATORS), count: null }
  return {
    known: new Set(operators.map((op) => op.value)),
    unary: new Set(operators.filter((op) => op.unary).map((op) => op.value)),
    count: new Set(operators.filter((op) => op.count).map((op) => op.value))
  }
}

function conditionRowCode(row, ops) {
  if (!row || typeof row !== "object" || Array.isArray(row)) return { code: "invalid_row" }
  if (row.type === "group") return { code: "nested_group" }
  if (row.kind === "query_count") {
    if (!present(row.queryConfig?.entityId)) return { code: "missing_entity" }
    if (ops.count && !ops.count.has(String(row.countOperator ?? ""))) return { code: "unknown_count_operator" }
    return null
  }
  const operator = String(row.operator ?? "").trim()
  if (!present(row.leftOperand)) return { code: "missing_left" }
  if (!operator) return { code: "missing_operator" }
  if (ops.known && !ops.known.has(operator)) return { code: "unknown_operator" }
  if (!ops.unary.has(operator) && !present(row.rightOperand)) return { code: "missing_right", tokens: { operator } }
  // Patterns are Ruby regexps; the server reports invalid_regex.
  return null
}

function conditionProblem(field, code, msg, tokens = {}) {
  return problem("condition_invalid", field, ERROR, messageFor(msg, `condition.${code}`, CONDITION_MESSAGES[code], tokens))
}

/**
 * Client mirror of CodeGenerators::ConditionRules.errors for one field.
 * `onEmpty` builds the problem for a required group without rows.
 */
function conditionGroupProblems(condition, field, msg, { required = false, onEmpty } = {}) {
  if (condition === undefined || condition === null || condition === "") {
    return required ? [onEmpty()] : []
  }
  if (typeof condition !== "object" || condition.type !== "group" || !Array.isArray(condition.conditions)) {
    return [conditionProblem(field, "invalid_condition", msg)]
  }
  if (required && condition.conditions.length === 0) return [onEmpty()]

  const ops = operatorSets()
  return condition.conditions.flatMap((row, index) => {
    const found = conditionRowCode(row, ops)
    return found ? [conditionProblem(field, found.code, msg, { index: index + 1, ...found.tokens })] : []
  })
}

function matchOf(conn) {
  return String(conn?.matchValue ?? "").trim()
}

function endRules({ properties, msg }) {
  if (properties.responseType === "value" && !hasValue(properties, "returnValue")) {
    return [problem("end_no_return_value", "returnValue", ERROR, messageFor(msg, "missingReturnValue", MESSAGES.missingReturnValue))]
  }
  return []
}

function processRules({ properties, msg }) {
  const steps = properties.steps || []
  return steps.length === 0
    ? [problem("empty_process", "steps", WARNING, messageFor(msg, "emptyProcess", MESSAGES.emptyProcess))]
    : []
}

function decisionRules({ properties, outgoing, msg }) {
  const problems = []
  const branches = outgoing || []

  if (branches.length < 2) {
    problems.push(problem("too_few_branches", "branches", ERROR, messageFor(msg, "tooFewBranches", MESSAGES.tooFewBranches)))
  }

  const stripped = branches.map(matchOf)
  if (stripped.filter((match) => match === "").length > 1) {
    problems.push(problem("multiple_otherwise", "branches", ERROR, messageFor(msg, "multipleOtherwise", MESSAGES.multipleOtherwise)))
  }
  if (stripped.length !== new Set(stripped).size) {
    problems.push(problem("duplicate_match_value", "branches", ERROR, messageFor(msg, "duplicateMatchValue", MESSAGES.duplicateMatchValue)))
  }

  const routeBy = properties.routeBy || "condition"
  if (routeBy === "condition") {
    const concrete = stripped.filter((match) => match !== "")
    if (!concrete.every((match) => match === "true" || match === "false")) {
      problems.push(problem("invalid_condition_match", "branches", ERROR, messageFor(msg, "invalidConditionMatch", MESSAGES.invalidConditionMatch)))
    }
    const hasYes = stripped.includes("true")
    const hasNoOrOtherwise = stripped.includes("false") || stripped.includes("")
    if (!hasYes || !hasNoOrOtherwise) {
      problems.push(problem("missing_yes_branch", "branches", ERROR, messageFor(msg, "missingYesBranch", MESSAGES.missingYesBranch)))
    }
    problems.push(...conditionGroupProblems(properties.condition, "condition", msg, {
      required: true,
      onEmpty: () => conditionProblem("condition", "empty_condition", msg)
    }))
  }

  return problems
}

function loopRules({ properties, msg }) {
  const loopType = properties.loopType || schemaDefault("loop", "loopType")

  const problems = conditionGroupProblems(properties.stopWhen, "stopWhen", msg)

  if (loopType === "for_each") {
    const collection = String(properties.collection ?? "").trim()
    if (!collection) {
      problems.unshift(problem("loop_no_collection", "collection", ERROR, messageFor(msg, "missingCollection", MESSAGES.missingCollection)))
    } else if (collection.startsWith("ctx.") || collection.startsWith("ctx[")) {
      problems.unshift(problem("loop_invalid_collection", "collection", ERROR, messageFor(msg, "invalidCollectionPath", MESSAGES.invalidCollectionPath)))
    }
    problems.push(...conditionGroupProblems(properties.skipWhen, "skipWhen", msg), ...loopVariableProblems(properties, msg))
    return problems
  }

  problems.unshift(...conditionGroupProblems(properties.condition, "condition", msg, {
    required: true,
    onEmpty: () => problem("empty_loop_condition", "condition", ERROR, messageFor(msg, "emptyLoopCondition", MESSAGES.emptyLoopCondition))
  }))
  return problems
}

function loopVariableProblems(properties, msg) {
  const problems = []
  const names = {}
  ;[["itemVariable", "item"], ["indexVariable", "index"]].forEach(([field, fallback]) => {
    const name = String(properties[field] ?? "").trim()
    if (LOOP_HEADER_LOCALS.includes(name)) {
      problems.push(problem("loop_reserved_variable", field, ERROR,
        messageFor(msg, "reservedLoopVariable", MESSAGES.reservedLoopVariable, { field, name })))
    }
    names[field] = name && !LOOP_HEADER_LOCALS.includes(name) ? name : fallback
  })
  if (names.itemVariable === names.indexVariable) {
    problems.push(problem("loop_colliding_variables", "itemVariable", ERROR, messageFor(msg, "collidingLoopVariables", MESSAGES.collidingLoopVariables)))
  }
  return problems
}

function subflowRules({ properties, msg, flowchartId }) {
  const target = properties.flowchartId

  if (!target || String(target).trim() === "") {
    return [problem("subflow_no_target", "flowchartId", ERROR, messageFor(msg, "missingFlowchart", MESSAGES.missingFlowchart))]
  }

  if (flowchartId && String(target).trim() === String(flowchartId)) {
    return [problem("subflow_self_reference", "flowchartId", ERROR, messageFor(msg, "subflowSelfReference", MESSAGES.subflowSelfReference))]
  }

  return []
}

export const ELEMENT_RULES = {
  end: endRules,
  process: processRules,
  decision: decisionRules,
  loop: loopRules,
  subflow: subflowRules
}

/**
 * Run the rules registered for an element's type.
 * @param {Object} ctx - { element, properties, incoming, outgoing, msg, flowchartId }
 * @returns {Array<Object>} problem descriptors, each stamped with elementId
 */
export function runElementRules(ctx) {
  const rule = ELEMENT_RULES[ctx.element.type]
  if (!rule) return []
  return rule(ctx).map(found => ({ elementId: ctx.element.id, connectionId: null, ...found }))
}
