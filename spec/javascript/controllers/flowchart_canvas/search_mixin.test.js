import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { SearchMixin } from "controllers/flowchart_canvas/search_mixin"
import { mixinHost } from "../../support/flowchart.js"

// A fake searchManager recording navigation calls; results/currentIndex drive
// the count-display text.
function makeManager(results = [], currentIndex = 0) {
  return { results, currentIndex, search: vi.fn(() => results), next: vi.fn(), prev: vi.fn(), clear: vi.fn() }
}

function host(extra = {}) {
  document.body.innerHTML = `
    <div data-bar class="hidden"><input data-input><span data-count></span></div>`
  const searchBar = document.querySelector("[data-bar]")
  const searchInput = document.querySelector("[data-input]")
  const searchCount = document.querySelector("[data-count]")
  searchInput.focus = vi.fn()
  searchInput.select = vi.fn()
  return mixinHost(SearchMixin, {
    hasSearchBarTarget: true,
    searchBarTarget: searchBar,
    hasSearchInputTarget: true,
    searchInputTarget: searchInput,
    hasSearchCountTarget: true,
    searchCountTarget: searchCount,
    searchManager: makeManager(),
    ...extra,
  })
}

describe("SearchMixin — open/close", () => {
  it("openSearch un-hides the bar and focuses the input on the next frame", async () => {
    const h = host()
    h.openSearch()
    expect(h.searchBarTarget.classList.contains("hidden")).toBe(false)
    await new Promise(r => setTimeout(r, 0)) // requestAnimationFrame shim
    expect(h.searchInputTarget.focus).toHaveBeenCalled()
    expect(h.searchInputTarget.select).toHaveBeenCalled()
  })

  it("openSearch no-ops without a search bar target", () => {
    const h = host({ hasSearchBarTarget: false })
    expect(() => h.openSearch()).not.toThrow()
  })

  it("closeSearch hides the bar, clears the manager and refreshes the count", () => {
    const mgr = makeManager()
    const h = host({ searchManager: mgr })
    h.searchBarTarget.classList.remove("hidden")
    h.closeSearch()
    expect(h.searchBarTarget.classList.contains("hidden")).toBe(true)
    expect(mgr.clear).toHaveBeenCalled()
    expect(h.searchCountTarget.textContent).toBe("0 of 0")
  })

  it("closeSearch no-ops without a search bar target", () => {
    const h = host({ hasSearchBarTarget: false })
    expect(() => h.closeSearch()).not.toThrow()
  })
})

describe("SearchMixin — input debounce", () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  it("debounces handleSearchInput and performs the search after 200ms", () => {
    const mgr = makeManager([{ id: "a" }], 0)
    const h = host({ searchManager: mgr })
    h.handleSearchInput({ target: { value: "foo" } })
    h.handleSearchInput({ target: { value: "foob" } })
    expect(mgr.search).not.toHaveBeenCalled()
    vi.advanceTimersByTime(200)
    expect(mgr.search).toHaveBeenCalledTimes(1)
    expect(mgr.search).toHaveBeenCalledWith("foob")
    expect(h.searchCountTarget.textContent).toBe("1 of 1")
  })

  it("_performSearch no-ops without a searchManager", () => {
    const h = host({ searchManager: null })
    h.handleSearchInput({ target: { value: "foo" } })
    expect(() => vi.advanceTimersByTime(200)).not.toThrow()
  })
})

describe("SearchMixin — keyboard", () => {
  it("Escape closes the search", () => {
    const h = host()
    const spy = vi.spyOn(h, "closeSearch")
    h.handleSearchKeydown({ key: "Escape", preventDefault: vi.fn() })
    expect(spy).toHaveBeenCalled()
  })

  it("Enter goes to next, Shift+Enter goes to prev", () => {
    const mgr = makeManager([{ id: "a" }, { id: "b" }], 0)
    const h = host({ searchManager: mgr })
    h.handleSearchKeydown({ key: "Enter", shiftKey: false, preventDefault: vi.fn() })
    expect(mgr.next).toHaveBeenCalled()
    h.handleSearchKeydown({ key: "Enter", shiftKey: true, preventDefault: vi.fn() })
    expect(mgr.prev).toHaveBeenCalled()
  })
})

describe("SearchMixin — count display", () => {
  it("shows '1-based current of total' when there are results", () => {
    const h = host({ searchManager: makeManager([{}, {}, {}], 1) })
    h._updateSearchCount()
    expect(h.searchCountTarget.textContent).toBe("2 of 3")
  })

  it("searchNext / searchPrev delegate and refresh the count", () => {
    const mgr = makeManager([{}, {}], 0)
    const h = host({ searchManager: mgr })
    h.searchNext(); expect(mgr.next).toHaveBeenCalled()
    h.searchPrev(); expect(mgr.prev).toHaveBeenCalled()
  })

  it("_updateSearchCount no-ops when count target or manager is absent", () => {
    const h = host({ hasSearchCountTarget: false })
    expect(() => h._updateSearchCount()).not.toThrow()
  })
})
