import { ELEMENT_COLORS } from "flowchart/constants"
import { elementLabel } from "flowchart/constants/element_registry"
import { escapeHtml } from "utils"

/**
 * BottomPanelMixin
 * Provides the tabbed bottom panel (problems, test, history, elements), the
 * elements-list renderer, element-focus action, trace-step focus, and toast
 * notifications. Apply with:
 *   Object.assign(FlowchartCanvasController.prototype, BottomPanelMixin)
 */
export const BottomPanelMixin = {
  // ----- Test panel delegates -----

  toggleTestPanel() { this._toggleBottomTab("test") },
  openTestPanel() { this.openBottomPanel("test") },
  closeTestPanel() { this.closeBottomPanel() },

  async runTest() {
    await this._testRunner?.run()
  },

  clearTraceOverlay() {
    this._testRunner?.clear()
  },

  focusTraceStep(event) {
    const elementId = event.currentTarget.dataset.elementId
    if (elementId) this._focusElementById(elementId)
  },

  selectTestHistoryRun(event) {
    const index = Number.parseInt(event.currentTarget.dataset.historyIndex, 10)
    if (!Number.isNaN(index)) this._testRunner?.selectHistory(index)
  },

  loadTestHistoryInput(event) {
    const index = Number.parseInt(event.currentTarget.dataset.historyIndex, 10)
    if (!Number.isNaN(index)) this._testRunner?.useHistoryInput(index)
  },

  validateTestInput() {
    this._testRunner?.validateInput()
  },

  // ----- Elements panel -----

  toggleElementsPanel() { this._toggleBottomTab("elements") },
  openElementsPanel() { this.openBottomPanel("elements") },
  closeElementsPanel() { this.closeBottomPanel() },

  _renderElementsList() {
    const elements = this.canvas.elements
    const connections = this.canvas.connections

    if (this.hasElementsCountTarget) {
      this.elementsCountTarget.textContent = `(${elements.length})`
    }

    if (!this.hasElementsListTarget) return

    const incomingCounts = {}
    const outgoingCounts = {}
    for (const c of connections) {
      outgoingCounts[c.from] = (outgoingCounts[c.from] || 0) + 1
      incomingCounts[c.to] = (incomingCounts[c.to] || 0) + 1
    }

    this.elementsListTarget.innerHTML = elements.map(el => {
      const incoming = incomingCounts[el.id] || 0
      const outgoing = outgoingCounts[el.id] || 0
      const color = ELEMENT_COLORS[el.type]?.stroke || "#6b7280"
      const connectionsText = this.elementConnectionsFormatValue
        .replaceAll("{incoming}", () => String(incoming))
        .replaceAll("{outgoing}", () => String(outgoing))
      return `
        <tr class="hover:bg-slate-50 cursor-pointer" data-action="click->flowchart-canvas#focusElement" data-element-id="${escapeHtml(el.id)}">
          <td class="px-4 py-2 whitespace-nowrap">
            <span class="inline-flex items-center">
              <span class="w-2.5 h-2.5 rounded-full mr-2" style="background-color: ${color}"></span>
              <span class="text-xs text-slate-500">${escapeHtml(elementLabel(el.type) ?? el.type)}</span>
            </span>
          </td>
          <td class="px-4 py-2 font-medium text-slate-900">${escapeHtml(el.label || this.unnamedElementLabelValue)}</td>
          <td class="px-4 py-2 text-slate-500">
            <span class="text-xs">${escapeHtml(connectionsText)}</span>
          </td>
        </tr>
      `
    }).join("")
  },

  focusElement(event) {
    const elementId = event.currentTarget.dataset.elementId
    const element = this.canvas.elements.find(el => el.id === elementId)
    if (element) {
      this.canvas.selectedElements.forEach(el => this.canvas._setElementSelected(el, false))
      this.canvas.selectedElements = []
      this.canvas.selectedElements.push(element)
      this.canvas._setElementSelected(element, true)
      if (this.canvas.canMutate?.() !== false) {
        this.canvas.showConnectionHandles([element])
      }
      this.canvas.zoomPanManager.fitToContent([element], 300)
      this._updateZoomDisplay()
      this._updateAlignmentToolbar()
    }
  },

  // ----- Tabbed bottom panel core -----

  _toggleBottomTab(tabName) {
    if (this.hasBottomPanelTarget && !this.bottomPanelTarget.classList.contains("hidden") && this._activeBottomTab === tabName) {
      this.closeBottomPanel()
    } else {
      this.openBottomPanel(tabName)
    }
  },

  openBottomPanel(tabName) {
    if (!this.hasBottomPanelTarget) return

    this.bottomPanelTarget.classList.remove("hidden")
    this._activateBottomTab(tabName)

    // Tab-specific initialization
    if (tabName === "history") {
      this.loadVersions()
    } else if (tabName === "elements") {
      this._renderElementsList()
    }

    this._activeBottomTab = tabName
  },

  closeBottomPanel() {
    if (!this.hasBottomPanelTarget) return
    this.bottomPanelTarget.classList.add("hidden")
  },

  switchBottomTab(event) {
    const tabName = event.currentTarget.dataset.tab
    if (!tabName) return

    // If clicking the already-active tab while panel is open, close the panel
    if (this._activeBottomTab === tabName && this.hasBottomPanelTarget && !this.bottomPanelTarget.classList.contains("hidden")) {
      this.closeBottomPanel()
      return
    }

    this.openBottomPanel(tabName)
  },

  _activateBottomTab(tabName) {
    // Update tab button styles
    this.bottomTabTargets.forEach(tab => {
      const isActive = tab.dataset.tab === tabName
      tab.classList.toggle("border-indigo-500", isActive)
      tab.classList.toggle("text-indigo-600", isActive)
      tab.classList.toggle("border-transparent", !isActive)
      tab.classList.toggle("text-slate-500", !isActive)
    })

    // Show/hide tab content
    if (this.hasBottomPanelTarget) {
      this.bottomPanelTarget.querySelectorAll("[data-tab-content]").forEach(content => {
        const isActive = content.dataset.tabContent === tabName
        content.classList.toggle("hidden", !isActive)
      })
    }
  },

  // ----- Toast notifications -----

  showToast(message, type = "info") {
    if (!this.hasToastContainerTarget) return

    const colorMap = {
      info: "bg-blue-600 text-white",
      warning: "bg-amber-500 text-white",
      error: "bg-red-600 text-white"
    }
    const colors = colorMap[type] || colorMap.info

    const toast = document.createElement("div")
    toast.className = `pointer-events-auto px-4 py-2 rounded-lg shadow-lg text-sm font-medium ${colors} transition-all duration-300 ease-in-out opacity-0 translate-y-2`
    toast.textContent = message

    this.toastContainerTarget.appendChild(toast)

    requestAnimationFrame(() => {
      toast.classList.remove("opacity-0", "translate-y-2")
      toast.classList.add("opacity-100", "translate-y-0")
    })

    setTimeout(() => {
      toast.classList.remove("opacity-100", "translate-y-0")
      toast.classList.add("opacity-0", "-translate-y-2")
      setTimeout(() => toast.remove(), 300)
    }, 3000)
  }
}
