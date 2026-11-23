import { describe, it, expect } from "vitest"
// The barrel re-exports the three constants submodules. Assert the aggregate
// surface stays wired (the concrete values are covered by the submodule specs).
import * as barrel from "flowchart/constants"
import { GRID_SIZE, ELEMENT_COLORS, setElementCatalog, elementType } from "flowchart/constants"

describe("flowchart/constants barrel", () => {
  it("re-exports canvas constants", () => {
    expect(barrel.GRID_SIZE).toBe(15)
    expect(GRID_SIZE).toBe(15)
    expect(barrel.ZOOM_STEP).toBeGreaterThan(0)
  })

  it("re-exports element constants", () => {
    expect(barrel.DEFAULT_ELEMENT_WIDTH).toBe(100)
    expect(ELEMENT_COLORS.start).toMatchObject({ fill: expect.any(String), stroke: expect.any(String) })
  })

  it("re-exports the element catalog store", () => {
    expect(typeof setElementCatalog).toBe("function")
    expect(typeof elementType).toBe("function")
  })
})
