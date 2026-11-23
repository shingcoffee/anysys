import { describe, it, expect, vi } from "vitest"
import { FormulaEngine, normalizeFormula } from "lib/formula_engine"

// Convenience: evaluate a formula against a value bag.
const evalWith = (formula, values = {}) => new FormulaEngine(values).evaluate(formula)

describe("FormulaEngine — evaluate() guards", () => {
  it("returns null for empty/blank/undefined formulas", () => {
    expect(evalWith("")).toBeNull()
    expect(evalWith("   ")).toBeNull()
    expect(new FormulaEngine().evaluate(undefined)).toBeNull()
  })

  it("swallows malformed formulas and returns null (logs a warning)", () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {})
    expect(evalWith("SUM(")).toBeNull()   // never-closed call
    expect(evalWith("(1 + 2")).toBeNull() // missing RPAREN
    expect(warn).toHaveBeenCalled()
    warn.mockRestore()
  })

  it("swallows a leading operator (unexpected token) and returns null", () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {})
    expect(evalWith("+1")).toBeNull()
    expect(warn).toHaveBeenCalled()
    warn.mockRestore()
  })
})

describe("FormulaEngine — tokenize()", () => {
  it("silently skips characters that match no token rule", () => {
    // "@" isn't a digit, quote, brace, letter, or known operator/punctuation —
    // the tokenizer drops it and parsing continues with the surrounding tokens.
    expect(evalWith("1 @ 2")).toBe(1)
  })
})

describe("FormulaEngine — execute() called directly on hand-built nodes", () => {
  it("returns null for a falsy node", () => {
    const e = new FormulaEngine()
    expect(e.execute(null)).toBeNull()
    expect(e.execute(undefined)).toBeNull()
  })

  it("returns null for an unrecognized node type", () => {
    expect(new FormulaEngine().execute({ type: "MYSTERY" })).toBeNull()
  })

  it("returns null for an unrecognized BINARY operator", () => {
    const node = { type: "BINARY", operator: "BOGUS", left: { type: "LITERAL", value: 1 }, right: { type: "LITERAL", value: 2 } }
    expect(new FormulaEngine().execute(node)).toBeNull()
  })
})

describe("FormulaEngine — arithmetic & precedence", () => {
  it("respects * / % over + -", () => {
    expect(evalWith("2 + 3 * 4")).toBe(14)
    expect(evalWith("10 - 6 / 2")).toBe(7)
    expect(evalWith("7 % 4 + 1")).toBe(4)
  })

  it("honors parentheses", () => {
    expect(evalWith("(2 + 3) * 4")).toBe(20)
  })

  it("division by zero yields 0 (not Infinity)", () => {
    expect(evalWith("5 / 0")).toBe(0)
  })

  it("decimals tokenize correctly", () => {
    expect(evalWith("1.5 + 2.25")).toBe(3.75)
  })
})

describe("FormulaEngine — field references {id}", () => {
  it("resolves {field} tokens from the value bag", () => {
    expect(evalWith("{qty} * {price}", { qty: 3, price: 2.5 })).toBe(7.5)
  })

  it("bare identifiers also resolve from values", () => {
    expect(evalWith("qty + 1", { qty: 4 })).toBe(5)
  })

  it("unknown identifier evaluates to null", () => {
    expect(evalWith("{missing} + 1", {})).toBeNull()
  })
})

describe("FormulaEngine — comparisons & null semantics", () => {
  it("numeric comparisons return booleans", () => {
    expect(evalWith("3 > 2")).toBe(true)
    expect(evalWith("2 >= 2")).toBe(true)
    expect(evalWith("1 < 0")).toBe(false)
    expect(evalWith("2 <= 2")).toBe(true)
    expect(evalWith("2 != 3")).toBe(true)
  })

  it("== / != on null operands compare identity, others short-circuit to null", () => {
    expect(evalWith("{x} == 0", {})).toBe(false)      // null == 0 -> false
    expect(evalWith("{x} != 5", {})).toBe(true)
    expect(evalWith("{x} + 5", {})).toBeNull()        // arithmetic w/ null -> null
    expect(evalWith("{x} > 5", {})).toBeNull()
  })

  it("loose equality matches across types", () => {
    expect(evalWith('{v} == "5"', { v: 5 })).toBe(true)
  })
})

describe("FormulaEngine — math functions", () => {
  const cases = [
    ["SUM(1, 2, 3)", 6],
    ["SUM(1, {a}, 3)", 6, { a: 2 }],
    ["SUBTRACT(10, 4)", 6],
    ["MULTIPLY(2, 3, 4)", 24],
    ["DIVIDE(10, 4)", 2.5],
    ["DIVIDE(10, 0)", 0],
    ["MIN(3, 1, 2)", 1],
    ["MAX(3, 1, 2)", 3],
    ["AVERAGE(2, 4, 6)", 4],
    ["ROUND(3.14159, 2)", 3.14],
    ["ROUND(3.6)", 4],
    ["FLOOR(3.9)", 3],
    ["CEIL(3.1)", 4],
    ["ABS(0 - 5)", 5],
    ["MOD(7, 3)", 1],
  ]
  it.each(cases)("%s => %s", (formula, expected, values) => {
    expect(evalWith(formula, values || {})).toBe(expected)
  })

  it("SUM ignores non-numeric args (treated as 0)", () => {
    expect(evalWith('SUM(1, "x", 2)')).toBe(3)
  })

  it("MULTIPLY ignores non-numeric args (treated as 0)", () => {
    expect(evalWith('MULTIPLY(2, "x", 3)')).toBe(0)
  })
})

describe("FormulaEngine — logic functions", () => {
  it("IF branches on truthiness", () => {
    expect(evalWith("IF(1, 10, 20)")).toBe(10)
    expect(evalWith("IF(0, 10, 20)")).toBe(20)
  })

  it("AND / OR / NOT", () => {
    expect(evalWith("AND(1, 1)")).toBe(true)
    expect(evalWith("AND(1, 0)")).toBe(false)
    expect(evalWith("OR(0, 1)")).toBe(true)
    expect(evalWith("NOT(0)")).toBe(true)
  })

  it("SWITCH matches a case, else returns trailing default or null", () => {
    expect(evalWith('SWITCH({s}, "a", 1, "b", 2, 99)', { s: "b" })).toBe(2)
    expect(evalWith('SWITCH({s}, "a", 1, 99)', { s: "z" })).toBe(99)   // default
    expect(evalWith('SWITCH({s}, "a", 1)', { s: "z" })).toBeNull()      // no default
  })
})

describe("FormulaEngine — text functions", () => {
  it("CONCAT / UPPER / LOWER / TRIM / LENGTH / LEFT / RIGHT", () => {
    expect(evalWith('CONCAT("a", "b", "c")')).toBe("abc")
    expect(evalWith('UPPER("aB")')).toBe("AB")
    expect(evalWith('LOWER("aB")')).toBe("ab")
    expect(evalWith('TRIM("  hi  ")')).toBe("hi")
    expect(evalWith('LENGTH("hello")')).toBe(5)
    expect(evalWith('LEFT("hello", 2)')).toBe("he")
    expect(evalWith('RIGHT("hello", 2)')).toBe("lo")
  })

  it("UPPER coerces null/undefined to empty string", () => {
    expect(evalWith("UPPER({x})", {})).toBe("")
  })

  it("LOWER / TRIM / LENGTH / LEFT / RIGHT also coerce null/undefined to empty string", () => {
    expect(evalWith("LOWER({x})", {})).toBe("")
    expect(evalWith("TRIM({x})", {})).toBe("")
    expect(evalWith("LENGTH({x})", {})).toBe(0)
    expect(evalWith("LEFT({x}, 2)", {})).toBe("")
    expect(evalWith("RIGHT({x}, 2)", {})).toBe("")
  })
})

describe("FormulaEngine — date functions", () => {
  it("YEAR / MONTH / DAY extract from a date string", () => {
    expect(evalWith('YEAR("2026-07-07")')).toBe(2026)
    expect(evalWith('MONTH("2026-07-07")')).toBe(7)   // 1-based
    expect(evalWith('DAY("2026-07-07")')).toBe(7)
  })

  it("DATE_DIFF across units", () => {
    expect(evalWith('DATE_DIFF("2026-01-11", "2026-01-01", "days")')).toBe(10)
    expect(evalWith('DATE_DIFF("2026-03-01", "2026-01-01", "months")')).toBe(2)
    expect(evalWith('DATE_DIFF("2027-01-01", "2026-01-01", "years")')).toBe(1)
    expect(evalWith('DATE_DIFF("2026-01-01T02:00:00", "2026-01-01T00:00:00", "hours")')).toBe(2)
    expect(evalWith('DATE_DIFF("2026-01-01T00:30:00", "2026-01-01T00:00:00", "minutes")')).toBe(30)
    expect(evalWith('DATE_DIFF("2026-01-01T00:00:30", "2026-01-01T00:00:00", "seconds")')).toBe(30)
    // Unrecognized unit falls back to the days calculation (default branch)
    expect(evalWith('DATE_DIFF("2026-01-11", "2026-01-01", "bogus")')).toBe(10)
  })

  it("DATE_ADD returns a shifted Date", () => {
    const d = evalWith('DATE_ADD("2026-01-01", 5, "days")')
    expect(d instanceof Date).toBe(true)
    expect(d.getDate()).toBe(6)
  })

  it("DATE_ADD across months/years/hours/minutes units", () => {
    expect(evalWith('DATE_ADD("2026-01-01", 2, "months")').getMonth()).toBe(2) // March (0-based)
    expect(evalWith('DATE_ADD("2026-01-01", 1, "years")').getFullYear()).toBe(2027)
    expect(evalWith('DATE_ADD("2026-01-01T00:00:00", 3, "hours")').getHours()).toBe(3)
    expect(evalWith('DATE_ADD("2026-01-01T00:00:00", 15, "minutes")').getMinutes()).toBe(15)
  })

  it("TODAY / NOW return Date objects", () => {
    expect(evalWith("TODAY()") instanceof Date).toBe(true)
    expect(evalWith("NOW()") instanceof Date).toBe(true)
  })

  it("unknown function returns null and warns", () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {})
    expect(evalWith("BOGUS(1)")).toBeNull()
    expect(warn).toHaveBeenCalledWith(expect.stringContaining("Unknown function"))
    warn.mockRestore()
  })
})

describe("normalizeFormula", () => {
  it("wraps known bare identifiers in {…}, leaves functions/numbers alone", () => {
    expect(normalizeFormula("qty * price + 2", ["qty", "price"])).toBe("{qty} * {price} + 2")
  })

  it("does not wrap function names", () => {
    expect(normalizeFormula("SUM(qty, 1)", ["qty"])).toBe("SUM({qty}, 1)")
  })

  it("leaves unknown identifiers untouched", () => {
    expect(normalizeFormula("qty + foo", ["qty"])).toBe("{qty} + foo")
  })

  it("returns falsy input unchanged", () => {
    expect(normalizeFormula("", [])).toBe("")
    expect(normalizeFormula(null)).toBeNull()
  })
})
