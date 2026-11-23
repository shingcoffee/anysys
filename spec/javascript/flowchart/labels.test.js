import { describe, it, expect } from "vitest"
import { DEFAULT_UNIQUE_LABEL_FORMAT, uniqueLabel } from "flowchart/labels"

const labelled = (...labels) => labels.map((label, i) => ({ id: `el${i}`, label }))

describe("uniqueLabel", () => {
  it("keeps a label no element uses", () => {
    expect(uniqueLabel(labelled("Start"), "End")).toBe("End")
    expect(uniqueLabel([], "  End  ")).toBe("End")
    expect(uniqueLabel(undefined, "End")).toBe("End")
  })

  it("numbers a taken label from 2, skipping numbers already used (case-insensitive)", () => {
    expect(uniqueLabel(labelled("End"), "End")).toBe("End 2")
    expect(uniqueLabel(labelled("end", "END 2", " End 3 "), "End")).toBe("End 4")
  })

  it("restarts from the root of a label already in the format", () => {
    expect(uniqueLabel(labelled("End", "End 2"), "End 2")).toBe("End 3")
    expect(uniqueLabel(labelled("Check 4"), "Check 4")).toBe("Check 2")
  })

  it("returns a blank label unchanged — blanks are never duplicates", () => {
    expect(uniqueLabel(labelled("", null, undefined), "")).toBe("")
    expect(uniqueLabel(labelled(""), null)).toBe("")
  })

  it("uses a translated format, falling back to the default when it has no {n}", () => {
    expect(uniqueLabel(labelled("结束"), "结束", "{label}（{n}）")).toBe("结束（2）")
    expect(uniqueLabel(labelled("结束", "结束（2）"), "结束（2）", "{label}（{n}）")).toBe("结束（3）")
    expect(uniqueLabel(labelled("End"), "End", "{label}")).toBe("End 2")
    expect(uniqueLabel(labelled("End"), "End", "")).toBe("End 2")
    expect(DEFAULT_UNIQUE_LABEL_FORMAT).toBe("{label} {n}")
  })

  it("treats regex and replacement characters in labels and formats literally", () => {
    expect(uniqueLabel(labelled("Cost $& (a+b)"), "Cost $& (a+b)")).toBe("Cost $& (a+b) 2")
    expect(uniqueLabel(labelled("a{n}"), "a{n}")).toBe("a{n} 2")
    expect(uniqueLabel(labelled("x"), "x", "[{label}].{n}")).toBe("[x].2")
    expect(uniqueLabel(labelled("[x].2"), "[x].2", "[{label}].{n}")).toBe("[x].3")
  })
})
