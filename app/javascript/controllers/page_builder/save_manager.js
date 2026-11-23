import { BaseManager } from "controllers/page_builder/base_manager"

// Autosave was intentionally removed from the page builder: saves happen only
// on an explicit user action (Save button / Ctrl+S). Unsaved edits are guarded
// by the beforeunload prompt wired in PageBuilderController.
export class SaveManager extends BaseManager {
  markDirty() {
    this.c.isDirty = true
    this.c.lastDirtyAt = Date.now()

    // Clear any lingering error state when the user makes a new edit. Every Save
    // button (toolbar + settings-modal footer) mirrors the same state.
    this._setSaveText(this.c.saveDirtyLabelValue)
  }

  // Save controls live in more than one place (toolbar + settings-modal footer),
  // so drive them all as a set instead of a single target.
  _setSaveText(text) {
    this.c.saveTextTargets.forEach(el => { el.textContent = text })
  }

  _setSaveDisabled(disabled) {
    this.c.saveBtnTargets.forEach(el => { el.disabled = disabled })
  }

  preview() {
    const pages = this.c.configuration.pages || []
    const activePageId = this.c.activePageValue

    const configurationData = {
      pages: pages,
      metadata: this.c.metadata,
      form_settings: this.c.configuration.form_settings,
      wizard_settings: this.c.configuration.wizard_settings,
      rules: this.c.configuration.rules,
      calculations: this.c.configuration.calculations,
      theme: this.c.configuration.theme,
      preview_active_page: activePageId
    }

    if (this.c.hasPreviewConfigInputTarget) {
      this.c.previewConfigInputTarget.value = JSON.stringify(configurationData)
    }
    if (this.c.hasPreviewFormTarget) {
      this.c.previewFormTarget.submit()
    }
  }

  async save() {
    // Cancel any in-flight save request before starting a new one
    if (this.c.currentSaveAbort) {
      this.c.currentSaveAbort.abort()
      this.c.currentSaveAbort = null
    }
    await this.performSave()
  }

  async performSave() {
    if (this.c.isSaving) return

    this.c.isSaving = true
    const requestStartedAt = Date.now()
    this.c.lastSaveStartedAt = requestStartedAt

    this._setSaveText(this.c.savingLabelValue)
    this._setSaveDisabled(true)
    this.hideModalError() // clear any prior in-modal failure while this attempt runs

    const configurationData = {
      pages: this.c.configuration.pages,
      metadata: this.c.metadata,
      form_settings: this.c.configuration.form_settings,
      wizard_settings: this.c.configuration.wizard_settings,
      rules: this.c.configuration.rules,
      calculations: this.c.configuration.calculations,
      theme: this.c.configuration.theme
    }

    // Preserve existing captcha config so a save can't wipe a historical flag.
    if (this.c.configuration.captcha) {
      configurationData.captcha = this.c.configuration.captcha
    }

    const abortController = new AbortController()
    this.c.currentSaveAbort = abortController

    try {
      const url = `/${this.customerIdValue}/admin/maintenance/pages/${this.idValue}`

      const response = await fetch(url, {
        method: "PATCH",
        signal: abortController.signal,
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('[name="csrf-token"]')?.content,
          "Accept": "application/json",
          "If-Unmodified-Since": this.c.lastSavedAt || ""
        },
        body: JSON.stringify({
          page: {
            configuration: JSON.stringify(configurationData),
            updated_at: this.c.lastSavedAt || null
          }
        })
      })

      const result = await response.json()

      if (response.status === 409) {
        this._handleConflict(result)
        return
      }

      if (response.ok) {
        if (result.updated_at) this.c.lastSavedAt = result.updated_at

        // Only clear the dirty flag if no new edits arrived during the request
        if (this.c.lastDirtyAt === undefined || this.c.lastDirtyAt < requestStartedAt) {
          this.c.isDirty = false
          this._setSaveText(this.c.savedLabelValue)
          setTimeout(() => {
            if (!this.c.isDirty) this._setSaveText(this.c.saveLabelValue)
          }, 2000)
        } else {
          // Edits arrived during the request — keep the unsaved indicator
          this._setSaveText(this.c.saveDirtyLabelValue)
        }
      } else {
        console.error("Save failed:", result)
        this._handleSaveError(result?.errors)
      }
    } catch (error) {
      if (error.name === "AbortError") return
      console.error("Save error:", error)
      this._handleSaveError()
    } finally {
      this.c.isSaving = false
      if (this.c.currentSaveAbort === abortController) {
        this.c.currentSaveAbort = null
      }
      this._setSaveDisabled(false)
    }
  }

  // A save failed. The edits are still unsaved, so the button returns to its
  // plain dirty state (not a cryptic "Error" label). The *reason* is surfaced
  // where the user is: at the top of the settings modal when it's open (that's
  // where the failing config is edited), otherwise as the editor's transient
  // top-right notification.
  _handleSaveError(messages) {
    this.c.isDirty = true
    this._setSaveText(this.c.saveDirtyLabelValue)
    const text = Array.isArray(messages) && messages.length
      ? messages.join(", ")
      : this.c.saveErrorGenericMessageValue

    if (this._settingsModalOpen()) this._showModalError(text)
    else this._notify(text)
  }

  _settingsModalOpen() {
    const panel = this.c.hasSettingsSaveErrorTarget
      ? this.c.settingsSaveErrorTarget.closest('[data-tab-panel="settings"]')
      : null
    return !!panel && !panel.classList.contains("hidden")
  }

  // Reveal the error at the top of the settings modal and scroll its pane up so
  // the banner is in view even when the content overflows the fixed-height modal.
  // textContent (never innerHTML) keeps server-provided text from injecting markup.
  _showModalError(text) {
    this.c.settingsSaveErrorMessageTarget.textContent = text
    this.c.settingsSaveErrorTarget.classList.remove("hidden")
    const scroller = this.c.settingsSaveErrorTarget.closest(".overflow-y-auto")
    if (scroller) scroller.scrollTop = 0
  }

  hideModalError() {
    if (this.c.hasSettingsSaveErrorTarget) this.c.settingsSaveErrorTarget.classList.add("hidden")
  }

  // Top-right, auto-dismissing error banner (mirrors the flowchart editor's
  // save-error notification for a consistent look). Built with textContent so
  // server-provided error text can't inject markup.
  _notify(message) {
    const el = document.createElement("div")
    el.className = "fixed top-4 right-4 z-50 max-w-md px-4 py-2 rounded-lg shadow-lg " +
                   "transition-all duration-300 border text-sm font-medium " +
                   "bg-red-100 text-red-800 border-red-200"
    el.setAttribute("role", "alert")
    el.textContent = message
    document.body.appendChild(el)

    setTimeout(() => {
      el.style.transform = "translateX(100%)"
      el.style.opacity = "0"
      setTimeout(() => el.remove(), 300)
    }, 5000)
  }

  _handleConflict(_result) {
    this._setSaveText(this.c.saveConflictLabelValue)
    const reload = window.confirm(this.c.saveConflictConfirmMsgValue)
    if (reload) window.location.reload()
  }
}
