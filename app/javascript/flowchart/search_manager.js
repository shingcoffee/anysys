/**
 * SearchManager - Handles searching within flowchart elements
 *
 * Features:
 * - Search by label, description, steps, and conditions
 * - Highlight all matches
 * - Navigate through results
 * - Visual focus with zoom/pan
 */

export class SearchManager {
  constructor(canvas) {
    this.canvas = canvas
    this.results = []
    this.currentIndex = -1
  }

  /**
   * Search for elements matching the query string.
   * Searches in: label, description, steps (action, selectionLabels), and conditions.
   * @param {string} query - Search query
   * @returns {Array<Object>} Array of matching elements
   */
  search(query) {
    this.clearHighlights()

    if (!query.trim()) {
      this.results = []
      this.currentIndex = -1
      return []
    }

    const q = query.toLowerCase()

    this.results = this.canvas.elements.filter(el => {
      // Search in label
      if (el.label?.toLowerCase().includes(q)) return true

      // Search in description
      if (el.properties?.description?.toLowerCase().includes(q)) return true

      // Search in steps
      if (el.properties?.steps?.some(s => {
        // Check action
        if ((s.action || "").toLowerCase().includes(q)) return true
        // Check selectionLabels
        if ((s.selectionLabels || []).join(" ").toLowerCase().includes(q)) return true
        return false
      })) return true

      // Search in condition expression
      if (el.properties?.condition?.expression?.toLowerCase().includes(q)) return true

      return false
    })

    this.currentIndex = this.results.length > 0 ? 0 : -1
    this._highlightResults()

    if (this.currentIndex >= 0) {
      this._focusCurrent()
    }

    return this.results
  }

  /**
   * Navigate to next search result.
   */
  next() {
    if (this.results.length === 0) return
    this.currentIndex = (this.currentIndex + 1) % this.results.length
    this._focusCurrent()
  }

  /**
   * Navigate to previous search result.
   */
  prev() {
    if (this.results.length === 0) return
    this.currentIndex = (this.currentIndex - 1 + this.results.length) % this.results.length
    this._focusCurrent()
  }

  /**
   * Clear search results and highlights.
   */
  clear() {
    this.clearHighlights()
    this.results = []
    this.currentIndex = -1
  }

  /**
   * Remove highlight classes from all elements.
   */
  clearHighlights() {
    this.canvas.svg.querySelectorAll(".search-highlight, .search-current").forEach(el => {
      el.classList.remove("search-highlight", "search-current")
    })
  }

  /**
   * Apply highlight classes to all search results.
   * @private
   */
  _highlightResults() {
    for (const el of this.results) {
      const group = this.canvas.svg.querySelector(`[data-element-id="${el.id}"]`)
      if (group) {
        group.classList.add("search-highlight")
      }
    }
    this._markCurrent()
  }

  /**
   * Mark the current result with a special highlight.
   * @private
   */
  _markCurrent() {
    // Remove existing current marker
    this.canvas.svg.querySelectorAll(".search-current").forEach(el => {
      el.classList.remove("search-current")
    })

    // Add current marker to current result
    if (this.currentIndex >= 0 && this.currentIndex < this.results.length) {
      const el = this.results[this.currentIndex]
      const group = this.canvas.svg.querySelector(`[data-element-id="${el.id}"]`)
      if (group) {
        group.classList.add("search-current")
      }
    }
  }

  /**
   * Focus on the current search result with zoom and pan.
   * @private
   */
  _focusCurrent() {
    this._markCurrent()

    if (this.currentIndex >= 0) {
      const el = this.results[this.currentIndex]
      this.canvas.zoomPanManager.fitToContent([el], 300)
      this.canvas.onZoomChange?.(this.canvas.zoomPanManager.zoomPercent)
    }
  }
}
