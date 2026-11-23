/**
 * Branch Manager — Decision Branches tab.
 * Rows are outgoing connections in port order. Branch data lives on the
 * connection (`label`, `matchValue`); removing a row drops the connection only.
 */

import { escapeHtml } from "utils"
import { buildBranchItemTemplate } from "controllers/property_editor/templates/branch"
import { buildSectionHeader, buildEmptyState } from "controllers/property_editor/templates/common"
import { BaseManager } from "controllers/property_editor/base_manager"
import { CanvasOperationsMixin } from "controllers/property_editor/branch_manager/canvas_operations"
import { outgoingDecisionConnections } from "flowchart/dynamic_ports"

export class BranchManager extends BaseManager {
  constructor(controller) {
    super(controller, "branchIndex")
    this._routeByUndo = null
    this._lastRouteBy = null
    this._formWatchBound = false
  }

  _outgoingConnections() {
    const decisionId = this.controller.currentElement?.id
    return outgoingDecisionConnections(this.controller.canvas?.connections, decisionId)
  }

  _routeBy() {
    const form = this.controller.formTarget
    const fromForm = form?.querySelector('[name="routeBy"]')?.value
    if (fromForm) return fromForm
    return this.controller.currentElement?.properties?.routeBy || "condition"
  }

  _defaultBranchName(index) {
    const format = String(this.controller.branchFallbackNameFormatValue || "")
    return format.replace("{index}", String(index))
  }

  _branchLabels() {
    const c = this.controller
    return {
      matchValueLabel: c.matchValueLabelValue,
      matchValuePlaceholder: c.matchValuePlaceholderValue,
      branchNameLabel: c.branchNameLabelValue,
      branchNamePlaceholder: c.branchNamePlaceholderValue,
      otherwiseLabel: c.otherwiseLabelValue,
      yesMatchLabel: c.yesMatchLabelValue,
      noMatchLabel: c.noMatchLabelValue,
      removeBranchItemTitle: c.removeBranchItemTitleValue
    }
  }

  collectBranches() {
    const container = this.controller.formFieldsTarget?.querySelector("[data-branches-container]")
    if (!container) return null

    return Array.from(container.querySelectorAll("[data-branch-item]")).map((item) => {
      const otherwise = item.querySelector("[data-branch-otherwise]")?.checked
      const matchInput = item.querySelector("[data-branch-match-value]")
      return {
        name: item.querySelector("[data-branch-name]")?.value || "",
        matchValue: otherwise ? "" : (matchInput?.value || ""),
        elementId: item.dataset.branchElementId || null,
        connectionId: item.dataset.connectionId || ""
      }
    })
  }

  buildBranchesFieldHTML(_fieldName, fieldSchema) {
    this._ensureFormWatch()
    this._lastRouteBy = this._routeBy()
    const outgoing = this._outgoingConnections()
    this.branchIndex = outgoing.length

    const emptyStateText = this.controller.branchesEmptyStateFormatValue
      .replace("{addBranchLabel}", this.controller.addBranchLabelValue)

    const rows = outgoing.map((conn, index) => this.buildBranchItemHTML({
      index,
      branchValue: conn.label || "",
      branchElementId: conn.to || "",
      connectionId: conn.id || "",
      matchValue: conn.matchValue || "",
      routeBy: this._lastRouteBy
    })).join("")

    return `
      <div class="mb-4" data-branches-section data-element-field="branches">
        ${buildSectionHeader({ label: fieldSchema?.label || this.controller.tabBranchesLabelValue, count: outgoing.length })}
        <div data-route-by-notice class="mb-2 hidden rounded-md border border-amber-200 bg-amber-50 px-2 py-1.5 text-xs text-amber-800">
          <span data-route-by-notice-text>${escapeHtml(this.controller.routeByClearedNoticeValue)}</span>
          <button type="button" data-action="click->property-editor#undoRouteByChange"
                  class="ml-2 font-medium text-amber-900 underline underline-offset-2">
            ${escapeHtml(this.controller.undoLabelValue)}
          </button>
        </div>
        <div data-branches-container class="space-y-2">
          <div data-branches-empty class="${outgoing.length > 0 ? "hidden" : ""}">
            ${buildEmptyState(emptyStateText)}
          </div>
          ${rows}
        </div>
        <button type="button"
                data-action="click->property-editor#addBranch"
                class="mt-2 inline-flex w-full items-center justify-center rounded border border-amber-200 bg-amber-50 px-2 py-1.5 text-xs font-medium text-amber-600 hover:bg-amber-100">
          <svg class="mr-1 h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
          </svg>
          ${escapeHtml(this.controller.addBranchLabelValue)}
        </button>
      </div>
    `
  }

  buildBranchItemHTML(params) {
    return buildBranchItemTemplate({ ...params, labels: this._branchLabels() })
  }

  addBranch(event) {
    event?.preventDefault()
    const container = this.controller.formFieldsTarget?.querySelector("[data-branches-container]")
    if (!container) return

    if (this.controller.canvas) this.controller.canvas.onBeforeChange?.()

    const nextIndex = this._outgoingConnections().length
    const name = this._defaultBranchName(nextIndex + 1)
    let branchElementId = ""
    let connectionId = ""

    if (this.controller.canvas && this.controller.currentElement?.type === "decision") {
      const box = this._createBranchElement(name, null, nextIndex)
      if (box) {
        branchElementId = box.id
        const conn = (this.controller.canvas.connections || []).find((c) => (
          c.from === this.controller.currentElement.id && c.to === box.id
        ))
        if (conn) {
          conn.label = name
          delete conn.matchValue
          connectionId = conn.id || ""
        }
      }
    }

    container.querySelector("[data-branches-empty]")?.classList.add("hidden")
    container.insertAdjacentHTML("beforeend", this.buildBranchItemHTML({
      index: nextIndex,
      branchValue: name,
      branchElementId,
      connectionId,
      matchValue: "",
      routeBy: this._routeBy()
    }))
    this.branchIndex = nextIndex + 1

    this._dispatchEvent("branchAdded")
    this._afterGraphChange()
    this._updateBranchSectionCount()
  }

  removeBranch(event) {
    event?.preventDefault()
    const branchItem = event.target.closest("[data-branch-item]")
    if (!branchItem) return

    if (this.controller.canvas) this.controller.canvas.onBeforeChange?.()

    const connectionId = branchItem.dataset.connectionId
    const branchElementId = branchItem.dataset.branchElementId
    if (this.controller.canvas && this.controller.currentElement) {
      this._removeBranchConnectionFromCanvas(connectionId, branchElementId)
    }

    const container = this.controller.formFieldsTarget.querySelector("[data-branches-container]")
    branchItem.remove()
    if (container && container.querySelectorAll("[data-branch-item]").length === 0) {
      container.querySelector("[data-branches-empty]")?.classList.remove("hidden")
    }

    this._dispatchEvent("branchRemoved")
    this._afterGraphChange()
    this._updateBranchSectionCount()
  }

  _afterGraphChange() {
    if (!this.controller.canvas || !this.controller.currentElement) return
    const element = this.controller.currentElement
    this._remapBranchConnections(element)
    this._ensureBranchRowClearance(element)
    this._layoutDecisionBranches(element)
    this._refreshDecisionElement(element)
    this.controller.canvas._hideConnectionHandles?.()
    this.controller.canvas.updateConnections?.()
    const cv = this.controller.canvas
    cv._previewSync = true
    cv.onchange?.()
    cv._previewSync = false
  }

  _applyBranchRow(item) {
    if (!item || !this.controller.canvas) return
    const conn = this._connectionForRow(item)
    if (!conn) return

    const otherwise = item.querySelector("[data-branch-otherwise]")?.checked
    const matchInput = item.querySelector("[data-branch-match-value]")
    conn.label = item.querySelector("[data-branch-name]")?.value || ""
    if (otherwise) {
      conn.matchValue = ""
      if (matchInput) {
        matchInput.value = ""
        matchInput.disabled = true
        matchInput.classList.add("hidden")
      }
    } else {
      conn.matchValue = matchInput?.value || ""
      if (matchInput) {
        matchInput.disabled = false
        matchInput.classList.remove("hidden")
      }
    }
  }

  _connectionForRow(item) {
    const connections = this.controller.canvas?.connections || []
    const byId = item.dataset.connectionId
    if (byId) return connections.find((conn) => conn.id === byId) || null
    const to = item.dataset.branchElementId
    const from = this.controller.currentElement?.id
    return connections.find((conn) => conn.from === from && conn.to === to) || null
  }

  _ensureFormWatch() {
    const form = this.controller.formTarget
    if (!form || this._formWatchBound) return
    this._onFormEvent = (event) => {
      if (event.target?.name === "routeBy") {
        this._handleRouteByChange(event)
        return
      }
      const item = event.target?.closest?.("[data-branch-item]")
      if (!item) return
      if (event.target?.hasAttribute("data-branch-otherwise") && event.target.checked) {
        this._clearOtherOtherwise(item)
      }
      this._applyBranchRow(item)
    }
    form.addEventListener("change", this._onFormEvent)
    form.addEventListener("input", this._onFormEvent)
    this._formWatchBound = true
  }

  _clearOtherOtherwise(keepItem) {
    const container = this.controller.formFieldsTarget?.querySelector("[data-branches-container]")
    if (!container) return
    container.querySelectorAll("[data-branch-item]").forEach((item) => {
      if (item === keepItem) return
      const box = item.querySelector("[data-branch-otherwise]")
      if (box?.checked) {
        box.checked = false
        this._applyBranchRow(item)
      }
    })
  }

  _handleRouteByChange(event) {
    const next = event.target.value
    if (next === this._lastRouteBy) return
    const outgoing = this._outgoingConnections()
    this._routeByUndo = outgoing.map((conn) => ({ id: conn.id, matchValue: conn.matchValue ?? "" }))
    outgoing.forEach((conn) => {
      if (String(conn.matchValue || "").trim() !== "") delete conn.matchValue
    })
    this._lastRouteBy = next
    this._rebuildBranchRows()
    this._showRouteByNotice()
    this._dispatchEvent("branchUpdated")
  }

  undoRouteByChange(event) {
    event?.preventDefault()
    if (!this._routeByUndo) return
    const previous = new Map(this._routeByUndo.map((row) => [row.id, row.matchValue]))
    this._outgoingConnections().forEach((conn) => {
      const matchValue = previous.get(conn.id)
      if (matchValue) conn.matchValue = matchValue
      else delete conn.matchValue
    })
    this._routeByUndo = null
    this._rebuildBranchRows()
    this._hideRouteByNotice()
    this._dispatchEvent("branchUpdated")
  }

  _rebuildBranchRows() {
    const container = this.controller.formFieldsTarget?.querySelector("[data-branches-container]")
    if (!container) return
    const empty = container.querySelector("[data-branches-empty]")
    const outgoing = this._outgoingConnections()
    container.querySelectorAll("[data-branch-item]").forEach((item) => item.remove())
    outgoing.forEach((conn, index) => {
      container.insertAdjacentHTML("beforeend", this.buildBranchItemHTML({
        index,
        branchValue: conn.label || "",
        branchElementId: conn.to || "",
        connectionId: conn.id || "",
        matchValue: conn.matchValue || "",
        routeBy: this._routeBy()
      }))
    })
    if (empty) empty.classList.toggle("hidden", outgoing.length > 0)
    this.branchIndex = outgoing.length
    this._updateBranchSectionCount()
  }

  _showRouteByNotice() {
    this.controller.formFieldsTarget?.querySelector("[data-route-by-notice]")?.classList.remove("hidden")
  }

  _hideRouteByNotice() {
    this.controller.formFieldsTarget?.querySelector("[data-route-by-notice]")?.classList.add("hidden")
  }

  _updateBranchSectionCount() {
    const section = this.controller.formFieldsTarget?.querySelector("[data-branches-section]")
    if (!section) return
    const badge = section.querySelector("[data-section-count]")
    const count = section.querySelectorAll("[data-branch-item]").length
    if (badge) badge.textContent = String(count)
  }
}

Object.assign(BranchManager.prototype, CanvasOperationsMixin)

export default BranchManager
