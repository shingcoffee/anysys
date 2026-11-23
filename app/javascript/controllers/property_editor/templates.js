/**
 * Templates barrel — re-exports all symbols from category modules.
 * All consumers (branch_manager.js, step_manager.js, form_builder.js,
 * context_autocomplete_controller.js) continue importing from this path
 * without modification.
 */

export * from "controllers/property_editor/templates/common"
export * from "controllers/property_editor/templates/var_refs"
export * from "controllers/property_editor/templates/type_validation"
export * from "controllers/property_editor/templates/conditions"
export * from "controllers/property_editor/templates/fields"
export * from "controllers/property_editor/templates/step"
export * from "controllers/property_editor/templates/branch"
