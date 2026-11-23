import { Controller } from "@hotwired/stimulus"

// New-page layout gallery (Websites::Admin::LayoutPickerComponent). Filters the
// layout cards by chip and search text, hides family groups left empty, and
// mirrors the checked card into the selected-layout summary.
//
// HTML contract (NewPageComponent + LayoutPickerComponent + LayoutSummaryComponent):
//   targets: card, group, filter, search, empty, count,
//            summaryName, summaryDescription, summaryCount, summarySections
//   card data: layoutCategory, layoutSuggested, layoutSearch, layoutName,
//              layoutDescription, layoutCount, layoutSections
//   actions: filter, search, clearSearch, reset, select

const SUMMARY_FIELDS = {
  summaryName: "layoutName",
  summaryDescription: "layoutDescription",
  summaryCount: "layoutCount",
  summarySections: "layoutSections"
}

export default class extends Controller {
  static targets = [
    "card", "group", "filter", "search", "empty", "count",
    "summaryName", "summaryDescription", "summaryCount", "summarySections"
  ]

  static values = {
    filter: { type: String, default: "all" },
    countFormats: { type: Object, default: { one: "{count} layout", other: "{count} layouts" } }
  }

  connect() {
    this.#apply()
    this.#syncSummary()
  }

  filter(event) {
    this.filterValue = event.currentTarget.dataset.filter || "all"
    this.#apply()
  }

  search() {
    this.#apply()
  }

  clearSearch(event) {
    if (!this.hasSearchTarget || !this.searchTarget.value) return
    event.preventDefault()
    this.searchTarget.value = ""
    this.#apply()
  }

  reset() {
    this.filterValue = "all"
    if (this.hasSearchTarget) this.searchTarget.value = ""
    this.#apply()
  }

  select(event) {
    if (event.target?.type !== "radio") return
    this.#syncSummary()
  }

  #apply() {
    const query = this.hasSearchTarget ? this.searchTarget.value.trim().toLocaleLowerCase() : ""
    let visible = 0
    this.cardTargets.forEach((card) => {
      const show = this.#matchesFilter(card) && (!query || (card.dataset.layoutSearch || "").includes(query))
      card.classList.toggle("hidden", !show)
      if (show) visible += 1
    })
    this.groupTargets.forEach((group) => {
      const shown = this.cardTargets.some((card) => group.contains(card) && !card.classList.contains("hidden"))
      group.classList.toggle("hidden", !shown)
    })
    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", visible > 0)
    if (this.hasCountTarget) this.countTarget.textContent = this.#countLabel(visible)
    this.filterTargets.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.filter === this.filterValue))
    })
  }

  #matchesFilter(card) {
    if (this.filterValue === "all") return true
    if (this.filterValue === "suggested") return card.dataset.layoutSuggested === "true"
    return card.dataset.layoutCategory === this.filterValue
  }

  #countLabel(count) {
    const formats = this.countFormatsValue
    const template = (count === 1 && formats.one) || formats.other || ""
    return template.replace("{count}", String(count))
  }

  #syncSummary() {
    const card = this.cardTargets.find((item) => item.querySelector("input[type='radio']")?.checked)
    if (!card) return
    Object.entries(SUMMARY_FIELDS).forEach(([target, key]) => {
      const node = this.targets.find(target)
      if (!node) return
      const value = card.dataset[key] || ""
      node.textContent = value
      node.classList.toggle("hidden", !value)
    })
  }
}
