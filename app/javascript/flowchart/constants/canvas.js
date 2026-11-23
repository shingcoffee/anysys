/**
 * Canvas configuration constants for the flowchart.
 * Contains settings related to canvas dimensions, grid, alignment, and animation.
 */

// ===================
// Grid Configuration
// ===================

/** Grid snap size in pixels */
export const GRID_SIZE = 15

// ===================
// Canvas Dimensions
// ===================

/** Padding around canvas content in pixels */
export const CANVAS_PADDING = 200

/** Extent for guide lines and large canvas features (in pixels) */
export const GUIDE_EXTENT = 10000

// ===================
// Alignment & Connection
// ===================

/** Threshold for alignment guides to appear (in pixels) */
export const ALIGNMENT_THRESHOLD = 25

/** Radius of connection handle circles (in pixels) */
export const CONNECTION_HANDLE_RADIUS = 6

/** Threshold distance for connection snapping (in pixels) */
export const CONNECTION_THRESHOLD = 30

// ===================
// Animation Configuration
// ===================

/** Default animation duration in milliseconds */
export const ANIMATION_DURATION = 300

// ===================
// Zoom & Pan Configuration
// ===================

/** Minimum zoom level (25%) */
export const MIN_ZOOM = 0.25

/** Maximum zoom level (200%) */
export const MAX_ZOOM = 2.0

/** Zoom increment per scroll step */
export const ZOOM_STEP = 0.1

/** Default zoom level (100%) */
export const DEFAULT_ZOOM = 1.0
