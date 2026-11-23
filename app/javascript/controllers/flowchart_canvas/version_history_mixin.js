import { getCSRFToken, escapeHtml } from "utils"
import { flowchartUrl } from "flowchart/urls"

/**
 * VersionHistoryMixin
 * Provides version-history panel load, render, and restore operations.
 * Apply with Object.assign(FlowchartCanvasController.prototype, VersionHistoryMixin).
 */
export const VersionHistoryMixin = {
  toggleVersionPanel() { this._toggleBottomTab("history") },
  openVersionPanel() { this.openBottomPanel("history") },
  closeVersionPanel() { this.closeBottomPanel() },

  async loadVersions() {
    if (!this.idValue || !this.customerIdValue) return
    const versionsUrl = flowchartUrl(this, "versions")
    if (!versionsUrl) return

    try {
      const response = await fetch(versionsUrl, {
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": getCSRFToken()
        }
      })

      if (response.ok) {
        const versions = await response.json()
        this._renderVersionList(versions)
      } else {
        this._renderVersionError(this.versionsLoadFailedLabelValue)
      }
    } catch (error) {
      this._renderVersionError(this.networkErrorFormatValue.replace("{message}", error.message))
    }
  },

  _renderVersionList(versions) {
    if (!this.hasVersionListTarget) return

    if (this.hasVersionCountTarget) {
      const format = versions.length === 1 ? this.versionCountSingularFormatValue : this.versionCountPluralFormatValue
      this.versionCountTarget.textContent = format.replace("{count}", versions.length)
    }

    if (versions.length === 0) {
      this.versionListTarget.innerHTML = `<div class="px-4 py-3 text-sm text-slate-500 text-center">${escapeHtml(this.noVersionsSavedLabelValue)}</div>`
      return
    }

    const timestampFormat = new Intl.DateTimeFormat(this.appLocaleValue, { dateStyle: "medium", timeStyle: "short" })
    this.versionListTarget.innerHTML = versions.map(v => {
      const date = new Date(v.created_at)
      const timestamp = Number.isNaN(date.getTime()) ? "" : timestampFormat.format(date)
      const versionLabel = this.versionLabelFormatValue.replaceAll("{number}", () => String(v.version_number))
      return `
        <div class="flex items-center justify-between px-4 py-3 border-b border-slate-100 hover:bg-slate-50">
          <div class="flex-1 min-w-0">
            <div class="flex items-center space-x-2">
              <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-indigo-100 text-indigo-800">${escapeHtml(versionLabel)}</span>
              <span class="text-sm text-slate-900 truncate">${escapeHtml(v.description || this.noDescriptionFallbackValue)}</span>
            </div>
            <div class="text-xs text-slate-500 mt-1">${escapeHtml(timestamp)}</div>
          </div>
          <button data-action="click->flowchart-canvas#restoreVersion"
                  data-version-id="${v.id}"
                  data-version-number="${v.version_number}"
                  class="ml-3 inline-flex items-center px-2.5 py-1.5 border border-slate-300 shadow-sm text-xs font-medium rounded text-slate-700 bg-white hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 transition-colors flex-shrink-0">
            ${escapeHtml(this.restoreButtonLabelValue)}
          </button>
        </div>
      `
    }).join("")
  },

  _renderVersionError(message) {
    if (!this.hasVersionListTarget) return
    this.versionListTarget.innerHTML = `<div class="px-4 py-3 text-sm text-red-600 text-center">${escapeHtml(message)}</div>`
  },

  async restoreVersion(event) {
    const versionId = event.currentTarget.dataset.versionId
    const versionNumber = event.currentTarget.dataset.versionNumber

    if (!versionId || !this.idValue || !this.customerIdValue) return
    if (!confirm(this.restoreVersionConfirmFormatValue.replace("{version}", versionNumber))) return
    this._leavePreviewMode?.({ restore: true })
    if (this.canvas?.canMutate?.() === false) return

    const versionsUrl = flowchartUrl(this, "versions")
    if (!versionsUrl) return

    try {
      const response = await fetch(versionsUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": getCSRFToken(),
          "Accept": "application/json"
        },
        body: JSON.stringify({ version_id: versionId })
      })

      if (response.ok) {
        const data = await response.json()
        this._adoptHeadVersion(data.version_id, data.head_revision)
        // Reload the canvas with restored configuration
        if (data.configuration && this.canvas) {
          this.canvas.loadConfiguration(data.configuration)
          this.hasUnsavedChanges = false
          this._updateUnsavedIndicator()
          // Reset undo history to the restored state. saveInitialState() bails
          // out when undoStack is non-empty (any prior edit), so the restored
          // config would never become the baseline and Undo would jump back to
          // the pre-restore state. Clear both stacks first, then re-capture.
          this.undoRedoManager.undoStack = []
          this.undoRedoManager.redoStack = []
          this.undoRedoManager.saveInitialState()
          if (this.minimapManager) {
            this.minimapManager.update()
          }
        }
        // Refresh version list
        this.loadVersions()
      } else {
        const isJson = (response.headers.get("content-type") || "").includes("json")
        const errorData = isJson ? await response.json() : {}
        this.showToast(errorData.message || this.restoreFailedHttpFormatValue.replace("{status}", response.status), "error")
      }
    } catch (error) {
      this.showToast(this.networkErrorFormatValue.replace("{message}", error.message), "error")
    }
  }
}
