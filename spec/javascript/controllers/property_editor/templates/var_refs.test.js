import { describe, it, expect } from "vitest"
import {
  VAR_REF_PATTERN,
  isVarRefField,
  OUTPUT_VAR_KEYS,
  PAIRED_VALUE_FIELDS,
} from "controllers/property_editor/templates/var_refs"

describe("var_refs — VAR_REF_PATTERN / isVarRefField", () => {
  it.each([
    "resultVar",
    "someVariable",
    "outputKey",
    "myExpression",
    "collection",
    "sourceField",
    "targetField",
  ])("matches var-ref-shaped key %s", (key) => {
    expect(VAR_REF_PATTERN.test(key)).toBe(true)
    expect(isVarRefField(key)).toBe(true)
  })

  it.each(["label", "description", "foo", "fieldSource", "collectionName", ""])(
    "does not match non-var-ref key %s",
    (key) => {
      expect(isVarRefField(key)).toBe(false)
    }
  )

  it("coerces null/undefined to empty string (no match)", () => {
    expect(isVarRefField(null)).toBe(false)
    expect(isVarRefField(undefined)).toBe(false)
  })

  it("anchors suffix patterns — 'Variable' must be at end", () => {
    expect(isVarRefField("VariableName")).toBe(false)
    expect(isVarRefField("nameVariable")).toBe(true)
  })
})

describe("var_refs — exported constants", () => {
  it("OUTPUT_VAR_KEYS holds the recognised output keys", () => {
    expect(OUTPUT_VAR_KEYS).toEqual(["resultVar", "outputKey", "targetVariable"])
  })

  it("PAIRED_VALUE_FIELDS maps field keys to their paired value keys", () => {
    expect(PAIRED_VALUE_FIELDS).toEqual({
      findField: "findValue",
      filterField: "filterValue",
      matchField: "matchValue",
    })
  })
})
