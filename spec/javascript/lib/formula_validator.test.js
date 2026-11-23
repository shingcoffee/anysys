import { describe, it, expect, vi } from "vitest"
import { validateFormula } from "lib/formula_validator"

// NOTE: validateFormula's try/catch around `new FormulaEngine(...).evaluate(...)`
// (formula_validator.js:42-46) is defensive: FormulaEngine#evaluate as currently
// written wraps its own tokenize/parse/execute in a try/catch and returns null on
// any error (see formula_engine.js:247-254) rather than rethrowing, and neither
// the constructor nor registerFunctions() throws — so no *real* formula reaches
// the catch. The guard still protects the validator from a future/edge engine
// that throws; the final test below exercises exactly that by mocking
// FormulaEngine#evaluate to throw (isolated via vi.resetModules + vi.doMock so
// the statically-imported validateFormula above keeps using the real engine).

describe("validateFormula", () => {
  it("blank formula is valid with null result", () => {
    const r = validateFormula("", ["a"])
    expect(r).toEqual({ valid: true, errors: [], referencedFields: [], result: null })
  })

  it("valid formula computes a live result and lists referenced fields", () => {
    const r = validateFormula("{qty} * {price}", ["qty", "price"], { qty: 3, price: 2 })
    expect(r.valid).toBe(true)
    expect(r.errors).toEqual([])
    expect(r.referencedFields.sort()).toEqual(["price", "qty"])
    expect(r.result).toBe(6)
  })

  it("flags unknown field references", () => {
    const r = validateFormula("{qty} + {missing}", ["qty"])
    expect(r.valid).toBe(false)
    expect(r.errors).toContain("Unknown field: missing")
  })

  it("flags unknown functions", () => {
    const r = validateFormula("BOGUS(1)", [])
    expect(r.valid).toBe(false)
    expect(r.errors).toContain("Unknown function: BOGUS")
  })

  it("allows every allowlisted function", () => {
    const r = validateFormula("ROUND(SUM(1,2), 1)", [])
    expect(r.valid).toBe(true)
  })

  it("flags unbalanced parentheses", () => {
    const r = validateFormula("SUM(1, 2", [])
    expect(r.errors).toContain("Unbalanced parentheses")
  })

  it("deduplicates referenced fields", () => {
    const r = validateFormula("{a} + {a} + {b}", ["a", "b"], { a: 1, b: 2 })
    expect(r.referencedFields.sort()).toEqual(["a", "b"])
  })

  it("skips evaluation when there are errors (result stays null)", () => {
    const r = validateFormula("{a} + {bad}", ["a"], { a: 1 })
    expect(r.valid).toBe(false)
    expect(r.result).toBeNull()
  })

  it("catches an exception thrown by FormulaEngine#evaluate (defensive guard)", async () => {
    vi.resetModules()
    vi.doMock("lib/formula_engine", () => ({
      FormulaEngine: class {
        evaluate() {
          throw new Error("engine boom")
        }
      },
    }))
    try {
      const { validateFormula: validate } = await import("lib/formula_validator")
      const r = validate("{a}", ["a"], { a: 1 })
      expect(r.valid).toBe(false)
      expect(r.errors).toContain("Evaluation error: engine boom")
      expect(r.result).toBeNull()
      expect(r.referencedFields).toEqual(["a"])
    } finally {
      vi.doUnmock("lib/formula_engine")
      vi.resetModules()
    }
  })
})
