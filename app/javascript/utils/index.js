/**
 * Shared utility functions for the Anysys application.
 * Organized by category: DOM, String, Math, and SVG utilities.
 */

// ===================
// DOM Utilities
// ===================

/**
 * Get CSRF token from meta tag for secure AJAX requests.
 * @returns {string} The CSRF token or empty string if not found
 */
export function getCSRFToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content || ""
}

/**
 * Escape HTML special characters to prevent XSS attacks.
 * Escapes &, <, >, ", and ' for safe use in HTML content and attributes.
 * @param {*} text - The text to escape
 * @returns {string} HTML-escaped string
 */
export function escapeHtml(text) {
  if (text == null) return ""
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

// ===================
// String Utilities
// ===================

/**
 * Fuzzy match a pattern against a string.
 * Returns true if all characters in pattern appear in order in str.
 * @param {string} str - The string to search in
 * @param {string} pattern - The pattern to match
 * @returns {boolean} Whether the pattern matches
 */
export function fuzzyMatch(str, pattern) {
  if (!str || !pattern) return false
  if (str.includes(pattern)) return true

  let patternIndex = 0
  for (let i = 0; i < str.length && patternIndex < pattern.length; i++) {
    if (str[i] === pattern[patternIndex]) patternIndex++
  }
  return patternIndex === pattern.length
}

/**
 * Generate a unique ID with optional prefix.
 * @param {string} prefix - Prefix for the ID (default: "el")
 * @returns {string} Unique identifier
 */
export function generateId(prefix = "el") {
  return `${prefix}_${Math.random().toString(36).slice(2, 11)}`
}

/**
 * Generate a stable unique id for a process step.
 * Prefers crypto.randomUUID for uniqueness, but falls back to a short
 * random suffix when unavailable (e.g. non-secure contexts). The "step_"
 * prefix keeps ids readable when inspecting the flowchart JSON.
 * @returns {string} Unique step identifier
 */
export function generateStepId() {
  const rand = (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function")
    ? crypto.randomUUID()
    : Math.random().toString(36).slice(2, 14)
  return `step_${rand}`
}

// ===================
// Math Utilities
// ===================

/**
 * Snap a value to the nearest grid position.
 * @param {number} value - The value to snap
 * @param {number} gridSize - The grid size
 * @returns {number} Snapped value
 */
export function snapToGrid(value, gridSize) {
  return Math.round(value / gridSize) * gridSize
}

/**
 * Calculate Euclidean distance between two points.
 * @param {number} x1 - First point X
 * @param {number} y1 - First point Y
 * @param {number} x2 - Second point X
 * @param {number} y2 - Second point Y
 * @returns {number} Distance between points
 */
export function distance(x1, y1, x2, y2) {
  return Math.hypot(x2 - x1, y2 - y1)
}

/**
 * Clamp a value between min and max bounds.
 * @param {number} value - The value to clamp
 * @param {number} min - Minimum bound
 * @param {number} max - Maximum bound
 * @returns {number} Clamped value
 */
export function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

// ===================
// SVG Utilities
// ===================

const SVG_NS = "http://www.w3.org/2000/svg"

/**
 * Create an SVG element with attributes.
 * @param {string} tagName - SVG element tag name
 * @param {Object} attrs - Attributes to set
 * @returns {SVGElement} Created SVG element
 */
export function createSvgElement(tagName, attrs = {}) {
  const el = document.createElementNS(SVG_NS, tagName)
  setAttributes(el, attrs)
  return el
}

/**
 * Set multiple attributes on an element.
 * @param {Element} el - Target element
 * @param {Object} attrs - Attributes to set (null values are skipped)
 */
export function setAttributes(el, attrs) {
  Object.entries(attrs).forEach(([key, value]) => {
    if (value != null) {
      el.setAttribute(key, value)
    }
  })
}

/**
 * Create an SVG group element.
 * @param {Object} attrs - Attributes to set
 * @returns {SVGGElement} Created group element
 */
export function createGroup(attrs = {}) {
  return createSvgElement("g", attrs)
}

/**
 * Create an SVG rect element.
 * @param {number} x - X position
 * @param {number} y - Y position
 * @param {number|string} width - Width
 * @param {number|string} height - Height
 * @param {Object} attrs - Additional attributes
 * @returns {SVGRectElement} Created rect element
 */
export function createRect(x, y, width, height, attrs = {}) {
  return createSvgElement("rect", { x, y, width, height, ...attrs })
}

/**
 * Create an SVG circle element.
 * @param {number} cx - Center X
 * @param {number} cy - Center Y
 * @param {number} r - Radius
 * @param {Object} attrs - Additional attributes
 * @returns {SVGCircleElement} Created circle element
 */
export function createCircle(cx, cy, r, attrs = {}) {
  return createSvgElement("circle", { cx, cy, r, ...attrs })
}

/**
 * Create an SVG ellipse element.
 * @param {number} cx - Center X
 * @param {number} cy - Center Y
 * @param {number} rx - X radius
 * @param {number} ry - Y radius
 * @param {Object} attrs - Additional attributes
 * @returns {SVGEllipseElement} Created ellipse element
 */
export function createEllipse(cx, cy, rx, ry, attrs = {}) {
  return createSvgElement("ellipse", { cx, cy, rx, ry, ...attrs })
}

/**
 * Create an SVG line element.
 * @param {number} x1 - Start X
 * @param {number} y1 - Start Y
 * @param {number} x2 - End X
 * @param {number} y2 - End Y
 * @param {Object} attrs - Additional attributes
 * @returns {SVGLineElement} Created line element
 */
export function createLine(x1, y1, x2, y2, attrs = {}) {
  return createSvgElement("line", { x1, y1, x2, y2, ...attrs })
}

/**
 * Create an SVG path element.
 * @param {string} d - Path data string
 * @param {Object} attrs - Additional attributes
 * @returns {SVGPathElement} Created path element
 */
export function createPath(d, attrs = {}) {
  return createSvgElement("path", { d, ...attrs })
}

/**
 * Create an SVG polygon element.
 * @param {string|Array} points - Points as string or array
 * @param {Object} attrs - Additional attributes
 * @returns {SVGPolygonElement} Created polygon element
 */
export function createPolygon(points, attrs = {}) {
  const pointsStr = Array.isArray(points) ? points.join(" ") : points
  return createSvgElement("polygon", { points: pointsStr, ...attrs })
}

/**
 * Create an SVG text element.
 * @param {string} content - Text content
 * @param {number} x - X position
 * @param {number} y - Y position
 * @param {Object} attrs - Additional attributes
 * @returns {SVGTextElement} Created text element
 */
export function createText(content, x, y, attrs = {}) {
  const text = createSvgElement("text", { x, y, ...attrs })
  text.textContent = content
  return text
}
