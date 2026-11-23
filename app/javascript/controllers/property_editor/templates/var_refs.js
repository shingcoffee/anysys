/**
 * Variable-reference detection helpers and constants.
 * VAR_REF_PATTERN is the single source of truth for "this field references a
 * context variable/expression"; field builders and condition builders share it.
 */

/**
 * Round-2 shared helpers — variable-reference detection and var-pick button.
 * VAR_REF_PATTERN is the single source of truth for "this field references a
 * context variable/expression"; field builders and condition builders share it.
 */
export const VAR_REF_PATTERN = /Var$|Variable$|Key$|Expression$|^collection$|^sourceField$|^targetField$/

export function isVarRefField(fieldKey) {
  return VAR_REF_PATTERN.test(String(fieldKey || ""))
}

/**
 * Output-variable configSchema keys recognised by the resultVar auto-suggest
 * and the picker dropdown's "Used in this element" group. Deliberately
 * excludes targetVar/responseVar this round (see plan resolution #7).
 */
export const OUTPUT_VAR_KEYS = ["resultVar", "outputKey", "targetVariable"]

/**
 * entityField config keys whose selected column types advise a paired value
 * input. Verified against the action registry: find_model (model_actions.js),
 * filter/find/partition collection actions and match_field predicates
 * (data_actions.js). Keys NOT listed (sortField, groupBy, distinctField,
 * aggregateField, groupField) have no paired value input.
 */
export const PAIRED_VALUE_FIELDS = {
  findField: "findValue",
  filterField: "filterValue",
  matchField: "matchValue"
}
