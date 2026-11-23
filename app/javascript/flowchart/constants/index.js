/**
 * Central re-export point for all flowchart constants.
 * Import from this file to access any constant.
 *
 * @example
 * import { GRID_SIZE, ELEMENT_COLORS } from "./constants"
 */

export * from "flowchart/constants/canvas"
export * from "flowchart/constants/elements"
export * from "flowchart/constants/element_registry"
// Catalog-derived property helpers (defaults, coercion, applicability).
export {
  getDefaultPropertiesForType,
  defaultPropertiesFor,
  coerceElementProperties,
  pruneInapplicableProperties,
  persistableProperties,
  normalizeElementProperties,
  isFieldApplicable,
  intProperty,
  hasValue,
  schemaDefault,
  schemaFor
} from "flowchart/element_config"
