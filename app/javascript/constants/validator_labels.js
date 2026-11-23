/**
 * Validator display labels mapping.
 * Maps internal validator keys to user-friendly short labels.
 *
 * NOTE: This must stay in sync with ApplicationHelper::VALIDATOR_LABELS
 */
export const VALIDATOR_LABELS = Object.freeze({
  presence: "Required",
  greater_than_or_equal_to: ">=",
  less_than_or_equal_to: "<=",
  equal_to: "==",
  not_equal_to: "!=",
  greater_than: ">",
  less_than: "<",
  format_email: "Email",
  format_url: "URL",
  format_phone: "Phone",
  format_custom: "Regex",
  length_minimum: "MinLen",
  length_maximum: "MaxLen",
  length_in_range: "LenRange",
  numericality: "Numeric",
  numericality_integer: "Integer",
  inclusion: "InList",
  exclusion: "NotIn",
  acceptance: "Accepted"
})

/**
 * Get the display label for a validator key.
 * Optional `labels` overlay is the Stimulus-provided locale map from the
 * server (`validatorLabelsValue`). Falls back to the English constant.
 * @param {string} validator - The validator key
 * @param {Record<string, string>} [labels]
 * @returns {string} The display label
 */
export function resolveValidatorLabel(validator, labels) {
  if (labels && labels[validator]) return labels[validator]
  return VALIDATOR_LABELS[validator] || validator
}

/**
 * English-only lookup used by specs and as the no-overlay fallback.
 * @param {string} validator - The validator key
 * @returns {string} The display label
 */
export function getValidatorLabel(validator) {
  return resolveValidatorLabel(validator)
}
