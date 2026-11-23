import { describe, it, expect } from "vitest"
import {
  DEFAULT_ELEMENT_WIDTH,
  DEFAULT_ELEMENT_HEIGHT,
  MIN_ELEMENT_WIDTH,
  MIN_ELEMENT_HEIGHT,
  MAX_ELEMENT_WIDTH,
  MAX_ELEMENT_HEIGHT,
  DEFAULT_ELEMENT_SPACING,
  VERTICAL_SPACING,
  MINIMUM_GAP,
  BRANCH_SPACING,
  ELEMENT_COLORS,
  DEFAULT_LABELS,
  SUPPORTED_ELEMENT_TYPES,
} from "flowchart/constants/elements"

const HEX = /^#[0-9a-fA-F]{6}$/

describe("element dimension constants", () => {
  it("orders width bounds MIN <= DEFAULT <= MAX", () => {
    expect(MIN_ELEMENT_WIDTH).toBeLessThanOrEqual(DEFAULT_ELEMENT_WIDTH)
    expect(DEFAULT_ELEMENT_WIDTH).toBeLessThanOrEqual(MAX_ELEMENT_WIDTH)
  })

  it("orders height bounds MIN <= DEFAULT <= MAX", () => {
    expect(MIN_ELEMENT_HEIGHT).toBeLessThanOrEqual(DEFAULT_ELEMENT_HEIGHT)
    expect(DEFAULT_ELEMENT_HEIGHT).toBeLessThanOrEqual(MAX_ELEMENT_HEIGHT)
  })

  it("has positive spacing constants", () => {
    for (const [name, v] of Object.entries({
      DEFAULT_ELEMENT_SPACING,
      VERTICAL_SPACING,
      MINIMUM_GAP,
      BRANCH_SPACING,
    })) {
      expect(typeof v, name).toBe("number")
      expect(v, name).toBeGreaterThan(0)
    }
  })

  it("BRANCH_SPACING equals element width plus the minimum gap (documented invariant)", () => {
    expect(BRANCH_SPACING).toBe(DEFAULT_ELEMENT_WIDTH + MINIMUM_GAP)
  })
})

describe("ELEMENT_COLORS", () => {
  it("gives every element type a valid hex fill and stroke", () => {
    const entries = Object.entries(ELEMENT_COLORS)
    expect(entries.length).toBeGreaterThan(0)
    for (const [type, scheme] of entries) {
      expect(scheme, type).toHaveProperty("fill")
      expect(scheme, type).toHaveProperty("stroke")
      expect(scheme.fill, `${type}.fill`).toMatch(HEX)
      expect(scheme.stroke, `${type}.stroke`).toMatch(HEX)
    }
  })

  it("covers the core element types", () => {
    for (const type of ["start", "end", "process", "decision", "loop", "subflow"]) {
      expect(ELEMENT_COLORS).toHaveProperty(type)
    }
    expect(ELEMENT_COLORS).not.toHaveProperty("timer")
  })
})

describe("DEFAULT_LABELS", () => {
  it("maps element types to non-empty string labels", () => {
    for (const [type, label] of Object.entries(DEFAULT_LABELS)) {
      expect(typeof label, type).toBe("string")
      expect(label.length).toBeGreaterThan(0)
    }
  })

  it("every labelled type also has a color scheme", () => {
    for (const type of Object.keys(DEFAULT_LABELS)) {
      expect(ELEMENT_COLORS, `color for ${type}`).toHaveProperty(type)
    }
  })

  it("exposes only retained editor element types", () => {
    expect(SUPPORTED_ELEMENT_TYPES).toEqual(
      ["start", "end", "process", "decision", "loop", "subflow"]
    )
  })
})
