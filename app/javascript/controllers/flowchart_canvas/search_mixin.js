/**
 * SearchMixin
 * Provides element-search bar open/close, input handling, navigation, and
 * result-count display. Apply with:
 *   Object.assign(FlowchartCanvasController.prototype, SearchMixin)
 */
export const SearchMixin = {
  openSearch() {
    if (!this.hasSearchBarTarget) return

    this.searchBarTarget.classList.remove("hidden")

    // Focus the input after a brief delay to ensure visibility
    requestAnimationFrame(() => {
      if (this.hasSearchInputTarget) {
        this.searchInputTarget.focus()
        this.searchInputTarget.select()
      }
    })
  },

  closeSearch() {
    if (!this.hasSearchBarTarget) return

    this.searchBarTarget.classList.add("hidden")
    if (this.searchManager) {
      this.searchManager.clear()
    }
    this._updateSearchCount()
  },

  handleSearchInput(event) {
    // Debounce search to avoid excessive searches while typing
    if (this._searchDebounceTimer) {
      clearTimeout(this._searchDebounceTimer)
    }

    this._searchDebounceTimer = setTimeout(() => {
      this._performSearch(event.target.value)
    }, 200)
  },

  handleSearchKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.closeSearch()
    } else if (event.key === "Enter") {
      event.preventDefault()
      if (event.shiftKey) {
        this.searchPrev()
      } else {
        this.searchNext()
      }
    }
  },

  searchNext() {
    if (this.searchManager) {
      this.searchManager.next()
      this._updateSearchCount()
    }
  },

  searchPrev() {
    if (this.searchManager) {
      this.searchManager.prev()
      this._updateSearchCount()
    }
  },

  _performSearch(query) {
    if (!this.searchManager) return

    const _results = this.searchManager.search(query)
    this._updateSearchCount()
  },

  _updateSearchCount() {
    if (!this.hasSearchCountTarget || !this.searchManager) return

    const { results, currentIndex } = this.searchManager
    if (results.length === 0) {
      this.searchCountTarget.textContent = this.searchCountZeroValue
    } else {
      this.searchCountTarget.textContent = this.searchCountFormatValue
        .replace("{current}", currentIndex + 1)
        .replace("{total}", results.length)
    }
  }
}
