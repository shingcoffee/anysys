import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "group", "groupToggle", "groupChevron", "groupBody",
    "industryRow", "industryChevron", "industryPanel", "industryBadge", "industryCount"
  ]

  static values = {
    baseUrl: String,
    // i18n seam: English defaults byte-identical to the former hardcoded copy.
    loadingTemplatesLabel: { type: String, default: "Loading templates..." },
    loadFailedMessage: { type: String, default: "Failed to load templates. Please try again." }
  }

  connect() {
    this.expandedIndustry = null
    this.loadedPanels = new Set()
  }

  // ── Group accordion ──────────────────────────────────────────────

  toggleGroup(event) {
    const idx = event.currentTarget.dataset.groupIndex
    const body = this.groupBodyTargets.find(el => el.dataset.groupIndex === idx)
    const chevron = this.groupChevronTargets.find(el => el.dataset.groupIndex === idx)
    if (!body) return

    const isOpen = !body.classList.contains("hidden")
    body.classList.toggle("hidden", isOpen)
    chevron?.classList.toggle("rotate-90", !isOpen)
  }

  // ── Industry accordion ───────────────────────────────────────────

  async toggleIndustry(event) {
    const industry = event.currentTarget.dataset.industry
    const panel = this.industryPanelTargets.find(el => el.dataset.industry === industry)
    const chevron = this.industryChevronTargets.find(el => el.dataset.industry === industry)
    if (!panel) return

    // Collapse previously expanded industry
    if (this.expandedIndustry && this.expandedIndustry !== industry) {
      this.collapseIndustry(this.expandedIndustry)
    }

    const isOpen = !panel.classList.contains("hidden")
    if (isOpen) {
      this.collapseIndustry(industry)
      return
    }

    // Expand
    chevron?.classList.add("rotate-90")
    panel.classList.remove("hidden")
    this.expandedIndustry = industry

    // Lazy load template cards if not already loaded
    if (!this.loadedPanels.has(industry)) {
      panel.innerHTML = this.loadingHTML()
      await this.fetchTemplateCards(industry, panel)
    }
  }

  collapseIndustry(industry) {
    const panel = this.industryPanelTargets.find(el => el.dataset.industry === industry)
    const chevron = this.industryChevronTargets.find(el => el.dataset.industry === industry)
    panel?.classList.add("hidden")
    chevron?.classList.remove("rotate-90")
    if (this.expandedIndustry === industry) this.expandedIndustry = null
  }

  // ── Lazy load server-rendered template cards ───────────────────

  async fetchTemplateCards(industry, panel) {
    try {
      const response = await fetch(`${this.baseUrlValue}/${industry}/template_cards`, {
        headers: { "Accept": "text/html" }
      })
      if (!response.ok) throw new Error("Failed to load")
      const html = await response.text()
      panel.innerHTML = html
      this.loadedPanels.add(industry)
    } catch {
      panel.innerHTML = `
        <div class="mx-5 mb-4 p-4 text-center text-sm text-red-600 bg-red-50 rounded-lg border border-red-200">
          ${this.loadFailedMessageValue}
        </div>`
    }
  }

  // ── Handle count changes from child panel controller ───────────

  handleCountChanged(event) {
    const { industry, count } = event.detail
    this.updateBadgeCount(industry, count)
  }

  updateBadgeCount(industry, count) {
    const countEls = this.industryCountTargets.filter(el => el.dataset.industry === industry)
    countEls.forEach(el => { el.textContent = count })

    const badges = this.industryBadgeTargets.filter(el => el.dataset.industry === industry)
    badges.forEach(badge => {
      badge.classList.toggle("bg-indigo-100", count > 0)
      badge.classList.toggle("text-indigo-700", count > 0)
      badge.classList.toggle("bg-gray-100", count === 0)
      badge.classList.toggle("text-gray-400", count === 0)
    })
  }

  // ── Helpers ──────────────────────────────────────────────────────

  loadingHTML() {
    return `
      <div class="mx-5 mb-4 rounded-xl border border-gray-200 bg-gray-50/50 p-8 flex items-center justify-center">
        <svg class="animate-spin h-5 w-5 text-indigo-500 mr-3" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
        </svg>
        <span class="text-sm text-gray-500">${this.loadingTemplatesLabelValue}</span>
      </div>`
  }
}
