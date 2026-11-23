import { describe, it, expect } from "vitest"
import {
  GRID_SIZE,
  CANVAS_PADDING,
  GUIDE_EXTENT,
  ALIGNMENT_THRESHOLD,
  CONNECTION_HANDLE_RADIUS,
  CONNECTION_THRESHOLD,
  ANIMATION_DURATION,
  MIN_ZOOM,
  MAX_ZOOM,
  ZOOM_STEP,
  DEFAULT_ZOOM,
} from "flowchart/constants/canvas"

describe("canvas constants", () => {
  it("exposes positive numeric pixel/time constants", () => {
    for (const [name, v] of Object.entries({
      GRID_SIZE,
      CANVAS_PADDING,
      GUIDE_EXTENT,
      ALIGNMENT_THRESHOLD,
      CONNECTION_HANDLE_RADIUS,
      CONNECTION_THRESHOLD,
      ANIMATION_DURATION,
    })) {
      expect(typeof v, name).toBe("number")
      expect(v, name).toBeGreaterThan(0)
    }
  })

  it("orders zoom bounds MIN < DEFAULT < MAX with a positive step", () => {
    expect(MIN_ZOOM).toBeGreaterThan(0)
    expect(MIN_ZOOM).toBeLessThan(DEFAULT_ZOOM)
    expect(DEFAULT_ZOOM).toBeLessThan(MAX_ZOOM)
    expect(ZOOM_STEP).toBeGreaterThan(0)
    expect(ZOOM_STEP).toBeLessThan(MAX_ZOOM - MIN_ZOOM)
  })

  it("uses the documented concrete values", () => {
    expect(GRID_SIZE).toBe(15)
    expect(DEFAULT_ZOOM).toBe(1.0)
    expect(MIN_ZOOM).toBe(0.25)
    expect(MAX_ZOOM).toBe(2.0)
  })
})
