import { Controller } from "@hotwired/stimulus"

/**
 * Generator Search Controller
 *
 * Fuzzy search across all generators by name, category, and description.
 * When searching, hides the category list and shows matching generators
 * as clickable results. When cleared, restores the category list.
 */
export default class extends Controller {
  static targets = ["input", "categoryList", "searchResults", "resultList", "resultCount", "noResults"]
  static values = {
    index: Array,

    // ── i18n seam: English default keeps JS specs green without any
    // data-*-value attribute; the mounting nav (sidebar_component.html.erb)
    // supplies the translated string via
    // data-generator-search-result-count-format-value="<%= t(...) %>". ──
    resultCountFormat: { type: String, default: "{count} found" }
  }

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase()

    if (query === "") {
      this.showCategories()
      return
    }

    this.showSearchResults(query)
  }

  showCategories() {
    if (this.hasCategoryListTarget) this.categoryListTarget.classList.remove("hidden")
    if (this.hasSearchResultsTarget) this.searchResultsTarget.classList.add("hidden")
  }

  showSearchResults(query) {
    if (this.hasCategoryListTarget) this.categoryListTarget.classList.add("hidden")
    if (this.hasSearchResultsTarget) this.searchResultsTarget.classList.remove("hidden")

    const tokens = query.split(/\s+/).filter(t => t.length > 0)
    const results = this.indexValue.filter(gen => this.fuzzyMatch(gen, tokens))

    if (this.hasResultCountTarget) {
      this.resultCountTarget.textContent = this.resultCountFormatValue.replace("{count}", results.length)
    }

    if (this.hasNoResultsTarget) {
      this.noResultsTarget.classList.toggle("hidden", results.length > 0)
    }

    if (this.hasResultListTarget) {
      this.resultListTarget.innerHTML = results.map(gen => this.renderResult(gen, tokens)).join("")
    }
  }

  fuzzyMatch(gen, tokens) {
    const searchable = `${gen.name} ${gen.category} ${gen.description}`.toLowerCase()
    return tokens.every(token => searchable.includes(token))
  }

  renderResult(gen, tokens) {
    const name = this.highlightMatches(gen.name, tokens)
    const category = gen.category.replace(/_/g, " ")
    const desc = gen.description.length > 60
      ? gen.description.substring(0, 60) + "..."
      : gen.description

    return `
      <a href="${gen.path}"
         class="block px-3 py-2 rounded-md hover:bg-gray-50 transition-colors group mb-0.5">
        <div class="flex items-center gap-2">
          <span class="font-mono text-xs font-medium text-gray-900 group-hover:text-indigo-600">${name}</span>
          <span class="text-[9px] text-gray-400 bg-gray-100 px-1.5 py-0.5 rounded capitalize">${this.escapeHtml(category)}</span>
        </div>
        <p class="text-[10px] text-gray-400 mt-0.5 leading-relaxed truncate">${this.escapeHtml(desc)}</p>
      </a>
    `
  }

  highlightMatches(text, tokens) {
    let escaped = this.escapeHtml(text)
    tokens.forEach(token => {
      if (token.length < 2) return
      const regex = new RegExp(`(${token.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")})`, "gi")
      escaped = escaped.replace(regex, '<mark class="bg-amber-100 text-amber-800 rounded px-0.5">$1</mark>')
    })
    return escaped
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
