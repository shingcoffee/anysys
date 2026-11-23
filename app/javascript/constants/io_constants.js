/**
 * IO Manager Constants
 *
 * Shared constants for input/output operations in the property editor.
 */

/**
 * Values that should be hidden from UI but preserved in data.
 * These represent special system parameters that shouldn't be manually edited.
 */
export const HIDDEN_IO_VALUES = Object.freeze([
  "all_params",
  "all params",
  "ctx"
])

/**
 * Check if a value should be hidden from the UI.
 * @param {string} value - The value to check
 * @returns {boolean} True if the value should be hidden
 */
export function isHiddenValue(value) {
  return HIDDEN_IO_VALUES.includes(value)
}

/**
 * Filter out hidden values from an array of items.
 * @param {Array} items - Array of objects with 'value' or 'keyword' property
 * @returns {Array} Filtered array without hidden values
 */
export function filterHiddenItems(items) {
  return items.filter(item => {
    if (item._hidden) return false
    if (isHiddenValue(item.value)) return false
    if (isHiddenValue(item.keyword)) return false
    return true
  })
}
