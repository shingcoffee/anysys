import { describe, it, expect } from "vitest"
import { PositionCalculator } from "controllers/flowchart_canvas/position_calculator"

describe("PositionCalculator — constants", () => {
  it("exposes default spacing/dimensions", () => {
    expect(PositionCalculator.DEFAULT_SPACING).toBe(50)
    expect(PositionCalculator.DEFAULT_HEIGHT).toBe(45)
    expect(PositionCalculator.DEFAULT_WIDTH).toBe(100)
  })
})

describe("PositionCalculator._isVerticalConnection / _isHorizontalConnection", () => {
  it("vertical requires from top|bottom AND to top|bottom", () => {
    expect(PositionCalculator._isVerticalConnection("bottom", "top")).toBe(true)
    expect(PositionCalculator._isVerticalConnection("top", "bottom")).toBe(true)
    expect(PositionCalculator._isVerticalConnection("bottom", "left")).toBe(false)
    expect(PositionCalculator._isVerticalConnection("right", "top")).toBe(false)
  })

  it("horizontal requires from left|right AND to left|right", () => {
    expect(PositionCalculator._isHorizontalConnection("right", "left")).toBe(true)
    expect(PositionCalculator._isHorizontalConnection("left", "right")).toBe(true)
    expect(PositionCalculator._isHorizontalConnection("bottom", "left")).toBe(false)
    expect(PositionCalculator._isHorizontalConnection("right", "top")).toBe(false)
  })
})

describe("PositionCalculator.calculateExpansionOffset", () => {
  it("offsets by the difference between the subflow element and the minimum child coords", () => {
    const subflow = { x: 200, y: 300 }
    const children = [{ x: 50, y: 80 }, { x: 120, y: 200 }, { x: 90, y: 60 }]
    expect(PositionCalculator.calculateExpansionOffset(subflow, children)).toEqual({
      offsetX: 200 - 50,
      offsetY: 300 - 60,
    })
  })

  it("treats missing coords as 0", () => {
    const subflow = { x: 10, y: 10 }
    const children = [{}, { x: 5 }]
    expect(PositionCalculator.calculateExpansionOffset(subflow, children)).toEqual({
      offsetX: 10,
      offsetY: 10,
    })
  })
})

describe("PositionCalculator.calculateChildShiftForExpansion", () => {
  it("pushes an overlapping child below the end element and aligns X on a vertical link", () => {
    const end = { x: 100, y: 100, height: 40 }
    const child = { x: 50, y: 120, height: 40 }
    // endBottom = 120, childTop = 100, required = 170 -> shiftY = 70; vertical -> shiftX = 50
    expect(PositionCalculator.calculateChildShiftForExpansion(end, child, { toPosition: "top" }))
      .toEqual({ shiftX: 50, shiftY: 70 })
  })

  it("does not shift X when the connection is not vertical", () => {
    const end = { x: 100, y: 100, height: 40 }
    const child = { x: 50, y: 120, height: 40 }
    const { shiftX, shiftY } = PositionCalculator.calculateChildShiftForExpansion(end, child, { toPosition: "left" })
    expect(shiftX).toBe(0)
    expect(shiftY).toBe(70)
  })

  it("leaves a child that already clears the spacing gap in place (shiftY 0)", () => {
    const end = { x: 100, y: 100, height: 40 }
    const child = { x: 100, y: 400, height: 40 } // childTop 380 > required 170
    expect(PositionCalculator.calculateChildShiftForExpansion(end, child, {}))
      .toEqual({ shiftX: 0, shiftY: 0 })
  })

  it("falls back to DEFAULT_HEIGHT when height is absent", () => {
    const end = { x: 0, y: 0 }
    const child = { x: 0, y: 0 }
    // endBottom = 22.5, childTop = -22.5, required = 72.5 -> shiftY = 95
    expect(PositionCalculator.calculateChildShiftForExpansion(end, child, {}))
      .toEqual({ shiftX: 0, shiftY: 95 })
  })
})

describe("PositionCalculator.calculateChildShiftForFold", () => {
  it("vertical: aligns X and always drops the child below the subflow", () => {
    const restored = { x: 100, y: 100, height: 40 }
    const child = { x: 60, y: 500, height: 40 }
    // shiftX = 40; subflowBottom = 120, childTop = 480, required = 170 -> shiftY = -310
    expect(PositionCalculator.calculateChildShiftForFold(restored, child, { fromPosition: "bottom", toPosition: "top" }))
      .toEqual({ shiftX: 40, shiftY: -310 })
  })

  it("horizontal from the right: aligns Y and pushes child to the right", () => {
    const restored = { x: 100, y: 100, width: 80 }
    const child = { x: 300, y: 200, width: 80 }
    // shiftY = -100; subflowRight = 140, childLeft = 260, required = 190 -> shiftX = -70
    expect(PositionCalculator.calculateChildShiftForFold(restored, child, { fromPosition: "right", toPosition: "left" }))
      .toEqual({ shiftX: -70, shiftY: -100 })
  })

  it("horizontal from the left: aligns Y and pushes child to the left", () => {
    const restored = { x: 100, y: 100, width: 80 }
    const child = { x: 300, y: 200, width: 80 }
    // shiftY = -100; subflowLeft = 60, childRight = 340, required = 10 -> shiftX = -330
    expect(PositionCalculator.calculateChildShiftForFold(restored, child, { fromPosition: "left", toPosition: "right" }))
      .toEqual({ shiftX: -330, shiftY: -100 })
  })

  it("neither vertical nor horizontal yields no shift", () => {
    const restored = { x: 100, y: 100 }
    const child = { x: 300, y: 200 }
    expect(PositionCalculator.calculateChildShiftForFold(restored, child, { fromPosition: "bottom", toPosition: "left" }))
      .toEqual({ shiftX: 0, shiftY: 0 })
  })

  it("defaults fromPosition/toPosition to bottom/top when the connection omits them", () => {
    const restored = { x: 100, y: 100, height: 40 }
    const child = { x: 60, y: 500, height: 40 }
    // Same fixture as the explicit vertical case above, but conn has neither position set.
    expect(PositionCalculator.calculateChildShiftForFold(restored, child, {}))
      .toEqual({ shiftX: 40, shiftY: -310 })
  })

  it("vertical fold falls back to DEFAULT_HEIGHT when height is absent", () => {
    const restored = { x: 100, y: 100 }
    const child = { x: 100, y: 0 }
    // subflowBottom = 122.5, childTop = -22.5, required = 172.5 -> shiftY = 195
    expect(PositionCalculator.calculateChildShiftForFold(restored, child, { fromPosition: "bottom", toPosition: "top" }))
      .toEqual({ shiftX: 0, shiftY: 195 })
  })

  it("horizontal fold falls back to DEFAULT_WIDTH when width is absent", () => {
    const restored = { x: 100, y: 100 }
    const child = { x: 300, y: 200 }
    // subflowRight = 150, childLeft = 250, required = 200 -> shiftX = -50
    expect(PositionCalculator.calculateChildShiftForFold(restored, child, { fromPosition: "right", toPosition: "left" }))
      .toEqual({ shiftX: -50, shiftY: -100 })
  })
})

describe("PositionCalculator.calculateChildShiftForRestore", () => {
  it("vertical: aligns X and drops the child below the subflow", () => {
    const subflow = { x: 100, y: 100, height: 40 }
    const child = { x: 40, y: 120, height: 40 }
    // shiftX = 60; subflowBottom = 120, childTop = 100, required = 170 -> shiftY = 70
    expect(PositionCalculator.calculateChildShiftForRestore(subflow, child, { fromPosition: "bottom", toPosition: "top" }))
      .toEqual({ shiftX: 60, shiftY: 70 })
  })

  it("non-vertical connection produces no shift", () => {
    const subflow = { x: 100, y: 100 }
    const child = { x: 40, y: 120 }
    expect(PositionCalculator.calculateChildShiftForRestore(subflow, child, { fromPosition: "right", toPosition: "left" }))
      .toEqual({ shiftX: 0, shiftY: 0 })
  })

  it("vertical: falls back to DEFAULT_HEIGHT when height is absent", () => {
    const subflow = { x: 100, y: 100 }
    const child = { x: 40, y: 0 }
    // subflowBottom = 122.5, childTop = -22.5, required = 172.5 -> shiftY = 195
    expect(PositionCalculator.calculateChildShiftForRestore(subflow, child, { fromPosition: "bottom", toPosition: "top" }))
      .toEqual({ shiftX: 60, shiftY: 195 })
  })

  it("defaults fromPosition/toPosition to bottom/top when the connection omits them", () => {
    const subflow = { x: 100, y: 100, height: 40 }
    const child = { x: 40, y: 120, height: 40 }
    // Same fixture as the explicit vertical case above, but conn has neither position set.
    expect(PositionCalculator.calculateChildShiftForRestore(subflow, child, {}))
      .toEqual({ shiftX: 60, shiftY: 70 })
  })
})
