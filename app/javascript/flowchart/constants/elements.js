/**
 * Element configuration constants for the flowchart.
 * Contains settings related to element dimensions, spacing, colors, and labels.
 */

// ===================
// Element Dimensions
// ===================

/** Default element width in pixels */
export const DEFAULT_ELEMENT_WIDTH = 100

/** Default element height in pixels */
export const DEFAULT_ELEMENT_HEIGHT = 45

/** Minimum element width in pixels */
export const MIN_ELEMENT_WIDTH = 60

/** Minimum element height in pixels */
export const MIN_ELEMENT_HEIGHT = 30

/** Maximum element width in pixels */
export const MAX_ELEMENT_WIDTH = 400

/** Maximum element height in pixels */
export const MAX_ELEMENT_HEIGHT = 200

/** Spacing between elements when auto-positioning (in pixels) */
export const DEFAULT_ELEMENT_SPACING = 50

// ===================
// Subflow & Branch Spacing
// ===================

/** Vertical spacing below elements when creating subflows (in pixels) */
export const VERTICAL_SPACING = 120

/** Minimum gap between branch elements (in pixels) */
export const MINIMUM_GAP = 40

/** Center-to-center spacing for branch elements (element width + minimum gap) */
export const BRANCH_SPACING = 140

// ===================
// Element Color Schemes
// ===================

/**
 * Color schemes for each element type.
 * Each type has a fill color and stroke color.
 */
export const ELEMENT_COLORS = {
  start: { fill: "#f0fdf4", stroke: "#10b981" },
  end: { fill: "#fef2f2", stroke: "#ef4444" },
  process: { fill: "#f8fafc", stroke: "#3b82f6" },
  decision: { fill: "#fefce8", stroke: "#f59e0b" },
  loop: { fill: "#faf5ff", stroke: "#a855f7" },
  subflow: { fill: "#ecfeff", stroke: "#06b6d4" }
}

// ===================
// Default Labels
// ===================

/**
 * Default labels for each element type.
 * Used when creating new elements.
 */
export const DEFAULT_LABELS = {
  start: "Start",
  end: "End",
  process: "Process",
  decision: "Decision",
  loop: "Loop",
  subflow: "Subflow"
}

export const SUPPORTED_ELEMENT_TYPES = [
  "start",
  "end",
  "process",
  "decision",
  "loop",
  "subflow"
]
