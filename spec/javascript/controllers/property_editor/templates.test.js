import { describe, it, expect } from "vitest"
import * as barrel from "controllers/property_editor/templates"

// The barrel re-exports every symbol from the category modules. Assert the
// full public surface is reachable through the single import path the app uses.
describe("templates barrel", () => {
  it("re-exports common builders", () => {
    for (const name of ["buildEmptyState", "buildSectionHeader", "buildCompactItem"]) {
      expect(typeof barrel[name]).toBe("function")
    }
  })

  it("re-exports var-ref helpers + constants", () => {
    expect(typeof barrel.isVarRefField).toBe("function")
    expect(barrel.VAR_REF_PATTERN).toBeInstanceOf(RegExp)
    expect(Array.isArray(barrel.OUTPUT_VAR_KEYS)).toBe(true)
    expect(barrel.PAIRED_VALUE_FIELDS).toBeTypeOf("object")
  })

  it("re-exports type-validation helpers", () => {
    for (const name of [
      "columnTypeOf",
      "looksLikeExpression",
      "buildTypeChip",
      "upsertTypeChip",
      "applySoftTypeValidation",
      "wireSoftTypeValidation",
    ]) {
      expect(typeof barrel[name]).toBe("function")
    }
  })

  it("re-exports condition, field, step, and branch builders", () => {
    for (const name of [
      "buildDisclosureSection",
      "buildSetCountBadge",
      "buildVarPickButton",
      "getColorClasses",
      "buildStepPickerTemplate",
      "buildEntityColumnSelect",
      "buildStepConfigFieldsHTML",
      "configFieldKey",
      "configFieldType",
      "matchesWhen",
      "buildStepItemTemplate",
      "buildBranchItemTemplate",
    ]) {
      expect(typeof barrel[name]).toBe("function")
    }
  })

  it("the re-exported function is the same identity as the source module's", async () => {
    const common = await import("controllers/property_editor/templates/common")
    expect(barrel.buildCompactItem).toBe(common.buildCompactItem)
  })
})
