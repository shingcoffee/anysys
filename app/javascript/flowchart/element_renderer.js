/**
 * ElementRenderer - Handles element rendering for the flowchart canvas.
 * Provides SVG shape creation for flowchart elements.
 */

import {
  createGroup,
  createRect,
  createEllipse,
  createPolygon,
  createPath,
  createText,
  createLine,
  createSvgElement,
  createCircle
} from "utils"
import { ELEMENT_COLORS } from "flowchart/constants"
import { getActionConfig } from "flowchart/constants/action_registry"

// Shape configuration
const SHAPE_CONFIG = {
  strokeWidth: 2,
  cornerRadius: 4,
  fontSize: { default: 11, decision: 10 },
  // Horizontal room kept free on each side of the label; the diamond narrows
  // towards its corners, so its label gets a wider inset.
  labelPadding: { default: 10, decision: 20 },
  fontFamily: "system-ui, -apple-system, sans-serif",
  labelColor: "#333333"
}

const ELLIPSIS = "…"
const WIDE_CHARACTER = /[\u1100-\u115F\u2E80-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFF60\uFFE0-\uFFE6\u{20000}-\u{3FFFD}]/u

/**
 * Estimated rendered width of `text` in px: CJK and full-width characters
 * count 1 em, everything else 0.6 em.
 * @param {string} text
 * @param {number} fontSize
 * @returns {number}
 */
export function estimateTextWidth(text, fontSize) {
  let ems = 0
  for (const character of text) ems += WIDE_CHARACTER.test(character) ? 1 : 0.6
  return ems * fontSize
}

let cachedMeasureContext

export function resetTextMeasureContext() {
  cachedMeasureContext = undefined
}

/**
 * Measure rendered text width using an offscreen 2D canvas when available
 * (accurate proportional glyph metrics in real browsers), falling back to
 * `estimateTextWidth` in headless DOM environments without 2D canvas support.
 */
export function measureRenderedTextWidth(text, fontSize, fontFamily = SHAPE_CONFIG.fontFamily) {
  if (cachedMeasureContext === undefined) {
    cachedMeasureContext = document.createElement("canvas").getContext?.("2d") ?? null
  }
  if (!cachedMeasureContext) return estimateTextWidth(text, fontSize)
  cachedMeasureContext.font = `${fontSize}px ${fontFamily}`
  return cachedMeasureContext.measureText(text).width
}

/**
 * Shorten `text` until it (plus "…") fits `maxWidth`.
 * @param {string} text
 * @param {number} maxWidth
 * @param {number} fontSize
 * @param {Function} [measure] - (text, fontSize) => px; defaults to estimateTextWidth
 * @returns {{ text: string, truncated: boolean }}
 */
export function truncateLabel(text, maxWidth, fontSize, measure = estimateTextWidth) {
  if (!text || measure(text, fontSize) <= maxWidth) return { text, truncated: false }
  const characters = Array.from(text)
  while (characters.length > 0 && measure(characters.join("") + ELLIPSIS, fontSize) > maxWidth) {
    characters.pop()
  }
  return { text: characters.join("") + ELLIPSIS, truncated: true }
}

/**
 * ElementRendererMixin - Mixin for element rendering functionality.
 * Applied to FlowchartCanvas prototype.
 */
export const ElementRendererMixin = {
  /**
   * Render an element to the canvas.
   */
  renderElement(element) {
    const defaultColors = ELEMENT_COLORS[element.type] || ELEMENT_COLORS.process

    // Use custom style if present, otherwise use default colors
    const colors = element.properties?.style?.fill && element.properties?.style?.stroke
      ? { fill: element.properties.style.fill, stroke: element.properties.style.stroke }
      : defaultColors

    const group = this._createElementGroup(element)

    group.appendChild(this._createShape(element, colors))
    group.appendChild(this._createLabel(element))

    const subflowToggle = this._createSubflowToggle(element)
    if (subflowToggle) group.appendChild(subflowToggle)

    // Add comment indicator if element has comments
    if (element.properties?.comments?.trim()) {
      const dotX = element.width - 8
      const dotY = 8
      const dot = createCircle(dotX, dotY, 4, {
        fill: "#fbbf24",
        stroke: "#f59e0b",
        "stroke-width": "1"
      })
      group.appendChild(dot)
    }

    this._attachElementEvents(group, element)

    // Store rendered dimensions for change detection in updateElementPosition
    group.dataset.renderedWidth = element.width
    group.dataset.renderedHeight = element.height

    this.elementLayer.appendChild(group)
  },

  /**
   * Update an element's visual position and dimensions.
   * If the element's width/height have changed since last render, the shape
   * and label are rebuilt to match the new dimensions.
   */
  updateElementPosition(element) {
    const group = this.elementLayer.querySelector(`[data-element-id="${element.id}"]`)
    if (!group) return

    const x = element.x - element.width / 2
    const y = element.y - element.height / 2
    group.setAttribute("transform", `translate(${x}, ${y})`)

    // Check if dimensions changed by comparing with rendered shape
    const currentWidth = parseFloat(group.dataset.renderedWidth || 0)
    const currentHeight = parseFloat(group.dataset.renderedHeight || 0)

    if (currentWidth !== element.width || currentHeight !== element.height) {
      // Rebuild shape and label for new dimensions
      const defaultColors = ELEMENT_COLORS[element.type] || ELEMENT_COLORS.process
      const colors = element.properties?.style?.fill && element.properties?.style?.stroke
        ? { fill: element.properties.style.fill, stroke: element.properties.style.stroke }
        : defaultColors

      // Remove existing shape and label elements (keep the group)
      while (group.firstChild) {
        group.removeChild(group.firstChild)
      }

      group.appendChild(this._createShape(element, colors))
      group.appendChild(this._createLabel(element))

      const subflowToggle = this._createSubflowToggle(element)
      if (subflowToggle) group.appendChild(subflowToggle)

      // Add comment indicator if element has comments
      if (element.properties?.comments?.trim()) {
        const dotX = element.width - 8
        const dotY = 8
        const dot = createCircle(dotX, dotY, 4, {
          fill: "#fbbf24",
          stroke: "#f59e0b",
          "stroke-width": "1"
        })
        group.appendChild(dot)
      }

      // Store rendered dimensions for future comparison
      group.dataset.renderedWidth = element.width
      group.dataset.renderedHeight = element.height
    }
  },

  /**
   * Mark an element with a validation ring (error or warning).
   * Mirrors the selection-outline approach: an extra SVG node appended to the
   * element's group `[data-element-id]`, tagged `data-validation-ring` so it
   * can be found and cleared without touching the shape itself.
   * An existing error ring is never downgraded to a warning.
   */
  setValidationState(elementId, severity) {
    if (!elementId) return
    const group = this.elementLayer.querySelector(`[data-element-id="${CSS.escape(String(elementId))}"]`)
    if (!group) return

    const existing = group.querySelector("[data-validation-ring]")
    if (existing) {
      if (existing.dataset.validationSeverity === "error") return // error wins
      existing.remove()
    }

    const width = parseFloat(group.dataset.renderedWidth || 0) || (group.getBBox?.().width ?? 0)
    const height = parseFloat(group.dataset.renderedHeight || 0) || (group.getBBox?.().height ?? 0)
    if (!width || !height) return

    const pad = 4
    const ring = createRect(-pad, -pad, width + pad * 2, height + pad * 2, {
      fill: "none",
      stroke: severity === "warning" ? "#eab308" : "#ef4444",
      "stroke-width": 2,
      rx: SHAPE_CONFIG.cornerRadius + 2,
      ry: SHAPE_CONFIG.cornerRadius + 2,
      "pointer-events": "none"
    })
    ring.dataset.validationRing = "true"
    ring.dataset.validationSeverity = severity
    group.appendChild(ring)
  },

  /**
   * Remove all validation rings from the canvas.
   */
  clearValidationStates() {
    this.elementLayer.querySelectorAll("[data-validation-ring]").forEach(node => node.remove())
  },

  /**
   * Get tooltip text for an element.
   */
  _getTooltipText(element) {
    if (element.type === "process" && element.properties?.steps?.length > 0) {
      const stepNames = this._getStepDisplayNames(element.properties.steps)
      return stepNames.join("\n")
    }
    return element.label || element.type
  },

  /**
   * Show custom tooltip for an element.
   */
  _showElementTooltip(element, event) {
    this._hideElementTooltip()

    const tooltipText = this._getTooltipText(element)
    if (!tooltipText) return

    const tooltip = document.createElement("div")
    tooltip.className = "flowchart-tooltip"
    tooltip.style.cssText = `
      position: fixed;
      z-index: 10000;
      padding: 6px 10px;
      background: #1f2937;
      color: #f9fafb;
      font-size: 12px;
      font-family: system-ui, -apple-system, sans-serif;
      border-radius: 6px;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
      pointer-events: none;
      white-space: pre-line;
      max-width: 280px;
      line-height: 1.4;
      opacity: 0;
      transition: opacity 0.1s ease-in-out;
    `
    tooltip.textContent = tooltipText

    document.body.appendChild(tooltip)

    const x = event.clientX + 12
    const y = event.clientY + 12

    const rect = tooltip.getBoundingClientRect()
    const maxX = window.innerWidth - rect.width - 10
    const maxY = window.innerHeight - rect.height - 10

    tooltip.style.left = `${Math.min(x, maxX)}px`
    tooltip.style.top = `${Math.min(y, maxY)}px`

    requestAnimationFrame(() => {
      tooltip.style.opacity = "1"
    })

    this._activeTooltip = tooltip
  },

  /**
   * Hide the active tooltip.
   */
  _hideElementTooltip() {
    if (this._activeTooltip) {
      this._activeTooltip.remove()
      this._activeTooltip = null
    }
  },

  /**
   * Update tooltip position during mouse move.
   */
  _updateTooltipPosition(event) {
    if (!this._activeTooltip) return

    const x = event.clientX + 12
    const y = event.clientY + 12

    const rect = this._activeTooltip.getBoundingClientRect()
    const maxX = window.innerWidth - rect.width - 10
    const maxY = window.innerHeight - rect.height - 10

    this._activeTooltip.style.left = `${Math.min(x, maxX)}px`
    this._activeTooltip.style.top = `${Math.min(y, maxY)}px`
  },

  /**
   * Get display names for steps.
   */
  _getStepDisplayNames(steps) {
    return steps.map(step => {
      // Use selectionLabels if available (e.g., ["Validate", "Contract"] → "Validate Contract")
      if (step.selectionLabels && Array.isArray(step.selectionLabels) && step.selectionLabels.length > 0) {
        const baseName = step.selectionLabels.join(" ")
        const modelName = step.modelName || ""
        return modelName ? `${baseName}: ${modelName}` : baseName
      }
      // Catalog label (already translated), else the stored action key.
      const actionLabel = getActionConfig(step.action)?.label || step.action || ""
      const modelName = step.modelName || ""
      const subAction = step.subAction ? ` (${step.subAction})` : ""

      if (modelName) {
        return `${actionLabel}: ${modelName}${subAction}`
      }
      return `${actionLabel}${subAction}`
    })
  },

  /**
   * Create the container group for an element.
   */
  _createElementGroup(element) {
    const translateX = element.x - element.width / 2
    const translateY = element.y - element.height / 2

    const attrs = {
      "data-element-id": element.id,
      "data-element-type": element.type,
      transform: `translate(${translateX}, ${translateY})`
    }

    if (element.properties?._expandedFromSubflow) {
      attrs["data-expanded-subflow"] = element.properties._expandedFromSubflow
    }

    const group = createGroup(attrs)
    group.style.cursor = this.canMutate?.() === false ? "pointer" : "move"

    return group
  },

  /**
   * Create the shape for an element based on its type.
   */
  _createShape(element, colors) {
    const shapeCreators = {
      start: this._createOvalShape,
      end: this._createOvalShape,
      decision: this._createDiamondShape,
      loop: this._createLoopShape,
      subflow: this._createSubflowShape
    }

    const creator = shapeCreators[element.type] || this._createRectShape
    return creator.call(this, element, colors)
  },

  /**
   * Create the label for an element: a group holding the (possibly
   * truncated) text and, when truncated, a <title> with the full label.
   */
  _createLabel(element) {
    const key = element.type === "decision" ? "decision" : "default"
    const fontSize = SHAPE_CONFIG.fontSize[key]
    const fullLabel = element.label || ""
    const availableWidth = element.width - SHAPE_CONFIG.labelPadding[key] * 2
    const { text, truncated } = truncateLabel(fullLabel, availableWidth, fontSize, measureRenderedTextWidth)

    const label = createGroup({ "data-element-label": "true" })
    if (truncated) {
      const title = createSvgElement("title")
      title.textContent = fullLabel
      label.appendChild(title)
    }
    label.appendChild(createText(text, element.width / 2, element.height / 2, {
      "text-anchor": "middle",
      "dominant-baseline": "middle",
      fill: SHAPE_CONFIG.labelColor,
      "font-size": fontSize,
      "font-family": SHAPE_CONFIG.fontFamily
    }))
    return label
  },

  /**
   * Attach mouse events to an element group.
   */
  _createSubflowToggle(element) {
    if (this.isReadOnly) return null
    if (element.type !== "subflow" || !element.properties?.flowchartId) return null

    const expanded = Boolean(element.properties._subflowExpanded)
    const title = expanded
      ? this.labels?.collapseSubflowTitle
      : this.labels?.expandSubflowTitle

    const size = 16
    const x = element.width - size - 4
    const y = 4
    const toggle = createGroup()
    toggle.setAttribute("data-subflow-toggle", "true")
    toggle.setAttribute("role", "button")
    toggle.setAttribute("title", title ?? "")
    toggle.style.cursor = "pointer"

    toggle.appendChild(createRect(x, y, size, size, {
      fill: "#ecfeff",
      stroke: "#06b6d4",
      "stroke-width": "1",
      rx: 3,
      ry: 3
    }))
    const cx = x + size / 2
    const cy = y + size / 2
    toggle.appendChild(createLine(cx - 4, cy, cx + 4, cy, {
      stroke: "#0e7490",
      "stroke-width": "1.5"
    }))
    if (!expanded) {
      toggle.appendChild(createLine(cx, cy - 4, cx, cy + 4, {
        stroke: "#0e7490",
        "stroke-width": "1.5"
      }))
    }
    return toggle
  },

  _attachElementEvents(group, element) {
    const canvas = this

    group.addEventListener("mousedown", (e) => {
      if (e.target.closest("[data-handle-position]")) return
      if (e.target.closest("[data-subflow-toggle]")) {
        e.stopPropagation()
        return
      }
      if (e.ctrlKey || e.metaKey || e.shiftKey) return

      if (!canvas._isElementSelected(element)) {
        canvas._clearSelection()
        canvas._addToSelection(element)
      }

      canvas._hideElementTooltip()
    })

    group.addEventListener("click", (e) => {
      const toggle = e.target.closest("[data-subflow-toggle]")
      if (!toggle) return
      e.stopPropagation()
      e.preventDefault()
      if (canvas.isReadOnly) return
      canvas.onSubflowToggle?.(element)
    })

    group.addEventListener("mouseenter", (e) => {
      if (canvas.isDragging) return
      canvas._showElementTooltip(element, e)
    })

    group.addEventListener("mousemove", (e) => {
      canvas._updateTooltipPosition(e)
    })

    group.addEventListener("mouseleave", () => {
      canvas._hideElementTooltip()
    })
  },

  // ===================
  // Shape Creators
  // ===================

  _createRectShape(element, colors) {
    return createRect(0, 0, element.width, element.height, {
      fill: colors.fill,
      stroke: colors.stroke,
      "stroke-width": SHAPE_CONFIG.strokeWidth,
      rx: SHAPE_CONFIG.cornerRadius,
      ry: SHAPE_CONFIG.cornerRadius
    })
  },

  _createOvalShape(element, colors) {
    return createEllipse(
      element.width / 2,
      element.height / 2,
      element.width / 2,
      element.height / 2,
      {
        fill: colors.fill,
        stroke: colors.stroke,
        "stroke-width": SHAPE_CONFIG.strokeWidth
      }
    )
  },

  _createDiamondShape(element, colors) {
    const { width: w, height: h } = element
    const points = [
      `${w / 2},0`,
      `${w},${h / 2}`,
      `${w / 2},${h}`,
      `0,${h / 2}`
    ]

    return createPolygon(points, {
      fill: colors.fill,
      stroke: colors.stroke,
      "stroke-width": SHAPE_CONFIG.strokeWidth
    })
  },

  _createLoopShape(element, colors) {
    const { width: w, height: h } = element
    const inset = w * 0.15

    const group = createGroup()

    const points = [
      `${inset},0`,
      `${w - inset},0`,
      `${w},${h / 2}`,
      `${w - inset},${h}`,
      `${inset},${h}`,
      `0,${h / 2}`
    ]

    group.appendChild(createPolygon(points, {
      fill: colors.fill,
      stroke: colors.stroke,
      "stroke-width": SHAPE_CONFIG.strokeWidth
    }))

    const arrowGroup = createGroup({ transform: `translate(${w - 20}, 6)` })
    arrowGroup.appendChild(createPath("M8 2a6 6 0 0 1 0 8M4 6l4-4v8", {
      fill: "none",
      stroke: colors.stroke,
      "stroke-width": "1.5",
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
      opacity: "0.6"
    }))
    group.appendChild(arrowGroup)

    return group
  },

  _createSubflowShape(element, colors) {
    const { width: w, height: h, id } = element
    const inset = 8
    const group = createGroup()

    const gradientId = `subflow-gradient-${id}`
    const defs = createSvgElement("defs")
    const gradient = createSvgElement("linearGradient", {
      id: gradientId,
      x1: "0%", y1: "0%", x2: "0%", y2: "100%"
    })
    gradient.appendChild(createSvgElement("stop", { offset: "0%", "stop-color": "#f0fdfa" }))
    gradient.appendChild(createSvgElement("stop", { offset: "100%", "stop-color": colors.fill }))
    defs.appendChild(gradient)
    group.appendChild(defs)

    group.appendChild(createRect(2, 2, w, h, {
      fill: "rgba(0, 0, 0, 0.08)",
      rx: SHAPE_CONFIG.cornerRadius,
      ry: SHAPE_CONFIG.cornerRadius
    }))

    group.appendChild(createRect(0, 0, w, h, {
      fill: `url(#${gradientId})`,
      stroke: colors.stroke,
      "stroke-width": SHAPE_CONFIG.strokeWidth,
      rx: SHAPE_CONFIG.cornerRadius,
      ry: SHAPE_CONFIG.cornerRadius
    }))

    const bandColor = "rgba(6, 182, 212, 0.15)"
    group.appendChild(createRect(0, 0, inset, h, {
      fill: bandColor,
      rx: SHAPE_CONFIG.cornerRadius,
      ry: SHAPE_CONFIG.cornerRadius
    }))
    group.appendChild(createRect(w - inset, 0, inset, h, {
      fill: bandColor,
      rx: SHAPE_CONFIG.cornerRadius,
      ry: SHAPE_CONFIG.cornerRadius
    }))

    const lineAttrs = {
      stroke: colors.stroke,
      "stroke-width": "1.5",
      "stroke-dasharray": "4,2"
    }
    group.appendChild(createLine(inset, 0, inset, h, lineAttrs))
    group.appendChild(createLine(w - inset, 0, w - inset, h, lineAttrs))

    return group
  }
}

/**
 * ElementRenderer class - Standalone class for element rendering.
 * Can be used for composition pattern in the future.
 */
export class ElementRenderer {
  constructor(canvas) {
    this.canvas = canvas
    this._activeTooltip = null
  }

  renderElement(element) {
    ElementRendererMixin.renderElement.call(this.canvas, element)
  }

  updateElementPosition(element) {
    ElementRendererMixin.updateElementPosition.call(this.canvas, element)
  }
}

export default ElementRenderer
