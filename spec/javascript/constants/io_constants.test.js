import { describe, it, expect } from "vitest"
import { HIDDEN_IO_VALUES, isHiddenValue, filterHiddenItems } from "constants/io_constants"

describe("io_constants", () => {
  it("HIDDEN_IO_VALUES is a frozen list of the special params", () => {
    expect(Object.isFrozen(HIDDEN_IO_VALUES)).toBe(true)
    expect(HIDDEN_IO_VALUES).toEqual(["all_params", "all params", "ctx"])
  })

  describe("isHiddenValue", () => {
    it("returns true for each hidden value", () => {
      for (const v of HIDDEN_IO_VALUES) expect(isHiddenValue(v)).toBe(true)
    })

    it("returns false for ordinary values", () => {
      expect(isHiddenValue("customer_id")).toBe(false)
      expect(isHiddenValue("")).toBe(false)
      expect(isHiddenValue(undefined)).toBe(false)
    })
  })

  describe("filterHiddenItems", () => {
    it("drops items flagged _hidden", () => {
      const items = [{ value: "a" }, { value: "b", _hidden: true }]
      expect(filterHiddenItems(items)).toEqual([{ value: "a" }])
    })

    it("drops items whose value is a hidden value", () => {
      const items = [{ value: "ctx" }, { value: "keep" }]
      expect(filterHiddenItems(items)).toEqual([{ value: "keep" }])
    })

    it("drops items whose keyword is a hidden value", () => {
      const items = [{ keyword: "all_params" }, { keyword: "ok" }]
      expect(filterHiddenItems(items)).toEqual([{ keyword: "ok" }])
    })

    it("keeps everything when nothing is hidden", () => {
      const items = [{ value: "x" }, { keyword: "y" }]
      expect(filterHiddenItems(items)).toEqual(items)
    })
  })
})
