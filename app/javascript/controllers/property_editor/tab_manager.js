/**
 * TabManager Module
 * Manages tab state, visibility, and badge updates for the property editor.
 * Tab keys come from the element catalog (`types[type].tabs`).
 */

import { elementTabs, elementFields } from "flowchart/constants/element_registry"
import { isFieldApplicable, schemaFor } from "flowchart/element_config"

export class TabManager {
  static TAB_ORDER = ["general", "steps", "branches", "io", "advanced"]

  /**
   * @param {Object} controller - The property editor controller instance
   */
  constructor(controller) {
    this.controller = controller
    this.activeTab = "general"
    this.tabBarContainer = null
    this.tabPanes = {}
    this.currentElementType = null
  }

  /**
   * Initialize the tab manager with references to DOM elements
   * @param {HTMLElement} tabBarContainer - The container for tab buttons
   * @param {Object} tabPanes - Map of tab panes { general, steps, io, advanced }
   */
  init(tabBarContainer, tabPanes) {
    this.tabBarContainer = tabBarContainer
    this.tabPanes = tabPanes
  }

  /**
   * Configure tabs for a specific element type
   * @param {string} elementType
   */
  configureForElementType(elementType) {
    this.currentElementType = elementType
    const visibleTabs = this._getVisibleTabs(elementType)
    this.activeTab = this._defaultTab(elementType, visibleTabs)

    if (!this.tabBarContainer) return

    let pillContainer = this.tabBarContainer.querySelector("[data-tab-pills]")
    if (!pillContainer) {
      this.tabBarContainer.innerHTML = ""
      pillContainer = document.createElement("div")
      pillContainer.dataset.tabPills = ""
      pillContainer.classList.add("flex", "gap-1", "p-1", "bg-slate-100", "rounded-lg", "w-full")
      this.tabBarContainer.appendChild(pillContainer)
    }
    pillContainer.innerHTML = ""

    visibleTabs.forEach((tabKey) => {
      const label = this._labelFor(tabKey, elementType)
      const button = this._createTabButton(tabKey, label)
      pillContainer.appendChild(button)
    })

    this._showPane(this.activeTab)
    this.controller?.onTabActivated?.(this.activeTab)
  }

  /**
   * Switch to a different tab
   * @param {string} tabKey
   */
  switchTo(tabKey) {
    if (this.activeTab === tabKey) return

    this.activeTab = tabKey
    this._updateTabButtons()
    this._showPane(tabKey)
    this.controller?.onTabActivated?.(tabKey)
  }

  /**
   * Update badge counts on tabs
   * @param {Object} counts - { steps, branches, inputs, outputs }
   */
  updateBadges(counts) {
    const buttons = this.tabBarContainer?.querySelectorAll("button[data-tab]") || []
    buttons.forEach((button) => {
      const tabKey = button.dataset.tab
      const baseLabel = button.dataset.tabLabel || button.textContent.trim()
      let badgeText = ""
      if ((tabKey === "branches" || tabKey === "steps") && this.currentElementType === "decision") {
        const count = counts.branches || counts.steps || 0
        if (count > 0) badgeText = ` (${count})`
      }
      button.textContent = baseLabel + badgeText
    })
  }

  /**
   * Get the pane element for a specific tab
   * @param {string} tabKey
   * @returns {HTMLElement|null}
   */
  getPane(tabKey) {
    return this.tabPanes[this._paneKey(tabKey)] || this.tabPanes[tabKey] || null
  }

  _paneKey(tabKey) {
    return tabKey === "branches" ? "steps" : tabKey
  }

  _defaultTab(elementType, visibleTabs) {
    if (elementType === "process" && visibleTabs.includes("steps")) return "steps"
    if (elementType === "decision" && visibleTabs.includes("branches")) return "branches"
    if (visibleTabs.includes("general")) return "general"
    return visibleTabs[0] || "general"
  }

  _hasVisibleAdvancedField(elementType) {
    const fields = elementFields(elementType).filter((field) => field.group === "advanced")
    if (fields.length === 0) return false
    const properties = this.controller?.currentElement?.properties || {}
    const schema = schemaFor(elementType)
    return fields.some((field) => isFieldApplicable(field.visibleWhen, properties, schema))
  }

  _labelFor(tabKey, elementType) {
    const c = this.controller
    if (tabKey === "steps") return c.tabStepsLabelValue
    if (tabKey === "branches") return c.tabBranchesLabelValue
    return {
      general: c.tabGeneralLabelValue,
      io: c.tabIoLabelValue,
      advanced: c.tabAdvancedLabelValue
    }[tabKey]
  }

  _getVisibleTabs(elementType) {
    const declared = elementTabs(elementType)
    const ordered = TabManager.TAB_ORDER.filter((tabKey) => declared.includes(tabKey))
    const tabs = ordered.length ? ordered : (declared.length ? declared : ["general"])
    if (tabs.includes("advanced") && !this._hasVisibleAdvancedField(elementType)) {
      return tabs.filter((tabKey) => tabKey !== "advanced")
    }
    return tabs
  }

  _createTabButton(tabKey, label) {
    const button = document.createElement("button")
    button.type = "button"
    button.dataset.tab = tabKey
    button.classList.add(
      "flex-1", "py-1", "px-2", "text-xs", "font-medium",
      "rounded-md", "transition-all", "duration-150", "whitespace-nowrap",
      "text-center"
    )

    if (tabKey === this.activeTab) {
      button.classList.add("bg-white", "text-slate-900", "shadow-sm", "ring-1", "ring-black/5")
    } else {
      button.classList.add("text-slate-500", "hover:text-slate-700", "hover:bg-white/50")
    }

    button.addEventListener("click", () => this.switchTo(tabKey))
    button.textContent = label
    button.dataset.tabLabel = label
    return button
  }

  _updateTabButtons() {
    const buttons = this.tabBarContainer?.querySelectorAll("button[data-tab]") || []

    buttons.forEach((button) => {
      const tabKey = button.dataset.tab
      const isActive = tabKey === this.activeTab

      button.classList.remove(
        "bg-white", "text-slate-900", "shadow-sm", "ring-1", "ring-black/5",
        "text-slate-500", "hover:text-slate-700", "hover:bg-white/50"
      )

      if (isActive) {
        button.classList.add("bg-white", "text-slate-900", "shadow-sm", "ring-1", "ring-black/5")
      } else {
        button.classList.add("text-slate-500", "hover:text-slate-700", "hover:bg-white/50")
      }
    })
  }

  _showPane(tabKey) {
    const activePane = this.getPane(tabKey)
    const seen = new Set()
    Object.keys(this.tabPanes).forEach((key) => {
      const pane = this.tabPanes[key]
      if (!pane || seen.has(pane)) return
      seen.add(pane)
      if (pane === activePane) {
        pane.classList.remove("hidden")
      } else {
        pane.classList.add("hidden")
      }
    })
  }
}

export default TabManager
