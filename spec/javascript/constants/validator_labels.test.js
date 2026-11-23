import { describe, it, expect } from "vitest"
import { VALIDATOR_LABELS, getValidatorLabel, resolveValidatorLabel } from "constants/validator_labels"

describe("validator_labels", () => {
  it("VALIDATOR_LABELS is frozen", () => {
    expect(Object.isFrozen(VALIDATOR_LABELS)).toBe(true)
  })

  it("maps known validator keys to short labels", () => {
    expect(getValidatorLabel("presence")).toBe("Required")
    expect(getValidatorLabel("greater_than_or_equal_to")).toBe(">=")
    expect(getValidatorLabel("format_email")).toBe("Email")
    expect(getValidatorLabel("length_in_range")).toBe("LenRange")
    expect(getValidatorLabel("numericality_integer")).toBe("Integer")
  })

  it("falls back to the raw key for unknown validators", () => {
    expect(getValidatorLabel("some_new_validator")).toBe("some_new_validator")
  })

  it("prefers a Stimulus overlay map when the key is present", () => {
    expect(resolveValidatorLabel("presence", { presence: "必填" })).toBe("必填")
  })

  it("falls back to English when the overlay omits the key", () => {
    expect(resolveValidatorLabel("presence", {})).toBe("Required")
    expect(resolveValidatorLabel("presence", null)).toBe("Required")
  })

  it("every mapped value is a non-empty string", () => {
    for (const [k, v] of Object.entries(VALIDATOR_LABELS)) {
      expect(typeof v, k).toBe("string")
      expect(v.length, k).toBeGreaterThan(0)
    }
  })
})
