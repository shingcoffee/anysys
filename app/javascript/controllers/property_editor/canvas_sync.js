/**
 * CanvasSyncMixin — real-time canvas sync, open-snapshot restore, change
 * dispatch, and database persistence helpers. Apply with:
 *   Object.assign(PropertyEditorController.prototype, CanvasSyncMixin)
 */

// Numbers each field focus so refocusing a field never coalesces into the
// undo entry of its previous focus.
let fieldFocusSequence = 0

export const CanvasSyncMixin = {
  /**
   * Set up event listeners on form fields to auto-sync changes to canvas.
   * This ensures changes are reflected on the canvas in real-time without saving.
   */
  _setupFormChangeListeners() {
    if (!this.hasFormTarget) return

    // Use event delegation on the form for input, change, and custom events
    this.formTarget.addEventListener("input", this._boundSyncChanges)
    this.formTarget.addEventListener("change", this._boundSyncChanges)
    this.formTarget.addEventListener("invalid", this._boundRevealInvalidField, true)
    this.formTarget.addEventListener("focusin", this._boundFieldFocusIn)
    this.formTarget.addEventListener("focusout", this._boundFieldFocusOut)

    // Listen for custom events from step/branch/io managers
    this.formTarget.addEventListener("stepAdded", this._boundSyncChanges)
    this.formTarget.addEventListener("stepRemoved", this._boundSyncChanges)
    this.formTarget.addEventListener("stepReordered", this._boundSyncChanges)
    this.formTarget.addEventListener("stepChanged", this._boundSyncChanges)
    this.formTarget.addEventListener("branchAdded", this._boundSyncChanges)
    this.formTarget.addEventListener("branchRemoved", this._boundSyncChanges)
    this.formTarget.addEventListener("branchUpdated", this._boundSyncChanges)
  },

  /**
   * Remove form change listeners when sidebar is hidden.
   */
  _removeFormChangeListeners() {
    if (!this.hasFormTarget) return

    this.formTarget.removeEventListener("input", this._boundSyncChanges)
    this.formTarget.removeEventListener("change", this._boundSyncChanges)
    this.formTarget.removeEventListener("invalid", this._boundRevealInvalidField, true)
    this.formTarget.removeEventListener("focusin", this._boundFieldFocusIn)
    this.formTarget.removeEventListener("focusout", this._boundFieldFocusOut)
    this.formTarget.removeEventListener("stepAdded", this._boundSyncChanges)
    this.formTarget.removeEventListener("stepRemoved", this._boundSyncChanges)
    this.formTarget.removeEventListener("stepReordered", this._boundSyncChanges)
    this.formTarget.removeEventListener("stepChanged", this._boundSyncChanges)
    this.formTarget.removeEventListener("branchAdded", this._boundSyncChanges)
    this.formTarget.removeEventListener("branchRemoved", this._boundSyncChanges)
    this.formTarget.removeEventListener("branchUpdated", this._boundSyncChanges)
  },

  /**
   * While a form control is focused, every sync it triggers carries the
   * canvas undo coalesce key `<elementOrConnectionId>:<field>#<focus>`, so one
   * focused field yields one undo entry.
   */
  _onFieldFocusIn(event) {
    if (!this.canvas) return
    const field = event.target
    const name = /^(INPUT|SELECT|TEXTAREA)$/.test(field.tagName) && (field.name || field.id)
    const source = this.currentElement || this.currentConnection
    this.canvas.undoCoalesceKey = (name && source) ? `${source.id}:${name}#${++fieldFocusSequence}` : null
  },

  /**
   * Commit the field's last debounced edit under its key before clearing it.
   */
  _onFieldFocusOut() {
    this._flushPendingSync()
    this._clearUndoCoalesceKey()
  },

  _clearUndoCoalesceKey() {
    if (this.canvas) this.canvas.undoCoalesceKey = null
  },

  /**
   * Run a pending debounced sync now instead of dropping it.
   */
  _flushPendingSync() {
    if (!this._syncTimeout) return
    clearTimeout(this._syncTimeout)
    this._syncTimeout = null
    if ((this.currentElement || this.currentConnection) && this.canvas && this.hasFormTarget) {
      this._performSync()
    }
  },

  /**
   * Sync current form state to canvas element in real-time.
   * This updates the canvas visualization without saving to database.
   */
  _syncChangesToCanvas() {
    if ((!this.currentElement && !this.currentConnection) || !this.canvas) return

    // Debounce rapid changes
    if (this._syncTimeout) {
      clearTimeout(this._syncTimeout)
    }

    this._syncTimeout = setTimeout(() => {
      this._performSync()
    }, 100)
  },

  /**
   * Perform the actual sync of form data to canvas element or connection.
   */
  _performSync() {
    if (this._isCanvasReadOnly()) return
    // Handle connection sync
    if (this.currentConnection && this.canvas && this.hasFormTarget) {
      this._performConnectionSync()
      return
    }

    if (!this.currentElement || !this.canvas || !this.hasFormTarget) return

    // The retry toggle unchecks itself once a step stops being idempotent; refresh it
    // before collecting so the stored config matches what the form shows.
    if (this.currentElement.type === "process" && this.stepManager) {
      this.stepManager.refreshAllCapabilityChrome()
    }

    const newProperties = this._collectFormData()

    // If label was auto-derived, re-derive from current config
    // If user manually typed a label, use it as-is
    const explicitLabel = this._labelAutoDerived ? "" : (newProperties.label || "")
    delete newProperties.label

    const newLabel = this._deriveLabelFromProperties(newProperties, explicitLabel)

    // Update element properties in canvas (visual update only, no database save).
    // This sync is the single undo-commit path for property-editor edits of
    // every kind (label, step config, branch list, …): updateElementProperties
    // fires the canvas onchange which commits one snapshot. Managers must NOT
    // also commit on top of this (see branch_manager) or one edit yields two
    // undo entries.
    if (this.canvas.updateElementProperties) {
      this.canvas.updateElementProperties(this.currentElement.id, newLabel, newProperties, true)
    } else {
      this._updateElementFallback(newProperties, newLabel)
    }

    // Auto-fill label input and header when auto-deriving
    if (this._labelAutoDerived && newLabel) {
      const labelInput = this.formTarget.querySelector('input[name="label"]')
      if (labelInput && newLabel !== labelInput.value) {
        labelInput.value = newLabel
      }
      if (this.hasTitleTarget) {
        this.titleTarget.textContent = newLabel
      }
    }

    // Dispatch change event to mark flowchart as having unsaved changes
    this._dispatchChange()

    this._updateTabBadges()

    // Keep "N set" badges current while typing; text inputs never reach handleConfigFieldChange.
    if (this.currentElement?.type === "process" && this.stepManager) {
      this.stepManager.refreshMoreOptionsBadges()
    }
  },

  /**
   * Read catalog connection fields (label + Notes). Label is stored on the
   * connection; description stays in properties. `priority` is not read.
   */
  _readConnectionForm() {
    const formData = new FormData(this.formTarget)
    const label = formData.get("label")?.toString().trim() || null
    const description = formData.get("description")?.toString().trim() || ""
    return { label, properties: { description } }
  },

  /**
   * Sync connection form data to canvas in real-time.
   */
  _performConnectionSync() {
    if (!this.currentConnection || !this.canvas || !this.hasFormTarget) return

    const { label, properties } = this._readConnectionForm()
    if (this.canvas.updateConnectionProperties) {
      this.canvas.updateConnectionProperties(this.currentConnection.id, label, properties)
    }

    this._dispatchChange()
  },

  _captureOpenSnapshot(source) {
    this._openSnapshot = structuredClone({
      label: source?.label ?? "",
      properties: source?.properties ?? {},
      elements: this.canvas?.elements ?? [],
      connections: this.canvas?.connections ?? []
    })
  },

  _currentOpenState() {
    const source = this.currentElement || this.currentConnection
    return {
      label: source?.label ?? "",
      properties: structuredClone(source?.properties ?? {}),
      elements: this.canvas?.elements ?? [],
      connections: this.canvas?.connections ?? []
    }
  },

  _graphChanged(current, snapshot) {
    return JSON.stringify(current.elements ?? []) !== JSON.stringify(snapshot.elements ?? [])
      || JSON.stringify(current.connections ?? []) !== JSON.stringify(snapshot.connections ?? [])
  },

  _openStatesEqual(left, right) {
    return JSON.stringify(left) === JSON.stringify(right)
  },

  /**
   * Cancel/close restore: write the open snapshot back when the canvas
   * element (or connection) drifted, otherwise skip so a no-edit close
   * does not call updateElementProperties or fire onchange.
   */
  _restoreOpenSnapshotIfChanged() {
    if (this._isCanvasReadOnly()) return
    if (!this._openSnapshot || !this.canvas) return
    if (!this.currentElement && !this.currentConnection) return
    const current = this._currentOpenState()
    if (this._openStatesEqual(current, this._openSnapshot)) return

    if (this._graphChanged(current, this._openSnapshot)) {
      this.canvas.replaceGraph?.(
        structuredClone(this._openSnapshot.elements),
        structuredClone(this._openSnapshot.connections)
      )
      if (this.currentElement) {
        this.currentElement.label = this._openSnapshot.label
        this.currentElement.properties = structuredClone(this._openSnapshot.properties)
      } else if (this.currentConnection) {
        this.currentConnection.label = this._openSnapshot.label || null
        this.currentConnection.properties = structuredClone(this._openSnapshot.properties)
      }
      return
    }

    const label = this._openSnapshot.label
    const properties = structuredClone(this._openSnapshot.properties)

    if (this.currentElement) {
      if (this.canvas.updateElementProperties) {
        this.canvas.updateElementProperties(this.currentElement.id, label, properties, true)
      } else {
        this._updateElementFallback(properties, label)
      }
      return
    }

    if (this.canvas.updateConnectionProperties) {
      this.canvas.updateConnectionProperties(this.currentConnection.id, label || null, properties)
    } else {
      this.currentConnection.label = label || null
      this.currentConnection.properties = { ...this.currentConnection.properties, ...properties }
    }
  },

  _updateElementFallback(newProperties, newLabel) {
    if (newLabel !== undefined) {
      this.currentElement.label = newLabel
    }
    this.currentElement.properties = { ...newProperties }

    this.canvas.render()
    this._dispatchChange()
  },

  _dispatchChange() {
    const canvasController = this._getCanvasController()
    if (!canvasController) return

    canvasController.element.dispatchEvent(new CustomEvent("flowchartChanged", {
      detail: {
        hasUnsavedChanges: true,
        action: this.currentConnection ? "connectionPropertiesUpdated" : "elementPropertiesUpdated",
        elementId: this.currentElement?.id || null,
        connectionId: this.currentConnection?.id || null
      }
    }))
  },

  _getCanvasController() {
    const canvasElement = document.querySelector('[data-controller*="flowchart-canvas"]')
    if (!canvasElement) return null

    return this.application.getControllerForElementAndIdentifier(
      canvasElement,
      "flowchart-canvas"
    )
  },

  async _saveToDatabase() {
    const canvasController = this._getCanvasController()
    if (!canvasController) return false

    try {
      return await canvasController.save()
    } catch (_error) {
      return false
    }
  }
}
