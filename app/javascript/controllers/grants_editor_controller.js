import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    updateUrl: String,
    locked: Boolean,

    // ── i18n seam: English defaults keep JS specs green without any
    // data-*-value attribute; the mounting component
    // (grants_editor_component.html.erb) supplies translated strings via
    // data-grants-editor-<name>-value="<%= t(...) %>". ──
    dirtyCountSingularFormat: { type: String, default: "{count} change" },
    dirtyCountPluralFormat: { type: String, default: "{count} changes" },
    grantedCounterFormat: { type: String, default: "{granted} / {total} granted" },
    discardConfirmFormat: { type: String, default: "Discard {count} change(s)?" },
    savingLabel: { type: String, default: "Saving..." },
    saveGrantsLabel: { type: String, default: "Save grants" },
    saveFailedFormat: { type: String, default: "Save failed: {details}" },
    unknownErrorLabel: { type: String, default: "unknown error" },
    addedLabel: { type: String, default: "Added" },
    removedLabel: { type: String, default: "Removed" },
    noChangesYetLabel: { type: String, default: "No changes yet." },
  }

  static targets = [
    "checkbox", "row", "group", "groupCount", "groupDirty",
    "search", "actionFilter", "onlyGrantedFilter", "emptyState",
    "saveBar", "saveButton", "dirtyCount",
    "diffDrawer", "diffContent", "counter",
  ]

  connect() {
    this.activeActionFilters = new Set()
    this.onlyGranted = false
    this.searchTerm = ""
    this._keyHandler = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this._keyHandler)
    this.updateDirtyState()
  }

  disconnect() {
    document.removeEventListener("keydown", this._keyHandler)
  }

  handleKeydown(e) {
    if ((e.metaKey || e.ctrlKey) && e.key === "s" && this.dirtyCount() > 0 && !this.lockedValue) {
      e.preventDefault()
      this.save()
    } else if (e.key === "Escape" && !this.diffDrawerTarget.classList.contains("hidden")) {
      this.closeDiff()
    }
  }

  // ----- Toggle a single checkbox -----
  toggle(event) {
    if (this.lockedValue) return
    this.markCheckbox(event.target)
    this.updateGroupCount(event.params.groupKey)
    this.updateRowGrantedAttr(event.target.closest("[data-grants-editor-target='row']"))
    this.updateDirtyState()
  }

  markCheckbox(checkbox) {
    const original = checkbox.dataset.grantsEditorOriginalCheckedParam === "true"
    const dirty = checkbox.checked !== original
    checkbox.closest(".grants-checkbox-label").classList.toggle("grants-dirty", dirty)
  }

  // ----- Group bulk operations -----
  grantAllInGroup(event) {
    if (this.lockedValue) return
    const groupKey = event.currentTarget.dataset.groupKey
    this.checkboxesInGroup(groupKey).forEach(cb => {
      if (!cb.checked) {
        cb.checked = true
        this.markCheckbox(cb)
      }
    })
    this.updateGroupCount(groupKey)
    this.updateRowsInGroup(groupKey)
    this.updateDirtyState()
  }

  revokeAllInGroup(event) {
    if (this.lockedValue) return
    const groupKey = event.currentTarget.dataset.groupKey
    this.checkboxesInGroup(groupKey).forEach(cb => {
      if (cb.checked) {
        cb.checked = false
        this.markCheckbox(cb)
      }
    })
    this.updateGroupCount(groupKey)
    this.updateRowsInGroup(groupKey)
    this.updateDirtyState()
  }

  checkboxesInGroup(groupKey) {
    return this.checkboxTargets.filter(cb => cb.dataset.grantsEditorGroupKeyParam === groupKey)
  }

  updateRowsInGroup(groupKey) {
    this.rowTargets
      .filter(r => r.dataset.groupKey === groupKey)
      .forEach(r => this.updateRowGrantedAttr(r))
  }

  updateRowGrantedAttr(row) {
    if (!row) return
    const anyChecked = row.querySelectorAll("input.grants-checkbox:checked").length > 0
    row.dataset.rowGranted = String(anyChecked)
    if (this.onlyGranted) this.applyFilters()
  }

  updateGroupCount(groupKey) {
    const counter = this.groupCountTargets.find(el => el.dataset.groupKey === groupKey)
    if (!counter) return
    const checked = this.checkboxesInGroup(groupKey).filter(cb => cb.checked).length
    counter.textContent = String(checked)

    const dirtyInGroup = this.checkboxesInGroup(groupKey)
      .some(cb => cb.checked !== (cb.dataset.grantsEditorOriginalCheckedParam === "true"))
    const dirtyBadge = this.groupDirtyTargets.find(el => el.dataset.groupKey === groupKey)
    if (dirtyBadge) dirtyBadge.classList.toggle("hidden", !dirtyInGroup)
  }

  // ----- Filtering -----
  filter(event) {
    this.searchTerm = (event.target.value || "").toLowerCase().trim()
    this.applyFilters()
  }

  toggleActionFilter(event) {
    const btn = event.currentTarget
    const action = btn.dataset.actionName
    if (this.activeActionFilters.has(action)) {
      this.activeActionFilters.delete(action)
      btn.classList.remove("grants-action-pill-active")
    } else {
      this.activeActionFilters.add(action)
      btn.classList.add("grants-action-pill-active")
    }
    this.applyFilters()
  }

  toggleOnlyGranted(event) {
    this.onlyGranted = !this.onlyGranted
    event.currentTarget.classList.toggle("grants-action-pill-active", this.onlyGranted)
    this.applyFilters()
  }

  applyFilters() {
    let visibleRows = 0
    this.rowTargets.forEach(row => {
      const label = row.dataset.rowLabel || ""
      const actions = (row.dataset.actions || "").split(/\s+/)
      const granted = row.dataset.rowGranted === "true"

      const matchesSearch = !this.searchTerm || label.includes(this.searchTerm)
      const matchesAction = this.activeActionFilters.size === 0 ||
        [...this.activeActionFilters].every(a => actions.includes(a))
      const matchesGranted = !this.onlyGranted || granted

      const visible = matchesSearch && matchesAction && matchesGranted
      row.classList.toggle("hidden", !visible)
      if (visible) visibleRows++
    })

    // Hide empty groups
    this.groupTargets.forEach(g => {
      const hasVisible = g.querySelectorAll("[data-grants-editor-target='row']:not(.hidden)").length > 0
      g.classList.toggle("hidden", !hasVisible)
    })

    // Empty state
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.toggle("hidden", visibleRows > 0)
    }
  }

  // ----- Dirty state -----
  dirtyCheckboxes() {
    return this.checkboxTargets.filter(cb =>
      cb.checked !== (cb.dataset.grantsEditorOriginalCheckedParam === "true")
    )
  }

  dirtyCount() {
    return this.dirtyCheckboxes().length
  }

  totalGranted() {
    return this.checkboxTargets.filter(cb => cb.checked).length
  }

  updateDirtyState() {
    const count = this.dirtyCount()
    if (this.hasDirtyCountTarget) {
      this.dirtyCountTarget.textContent =
        (count === 1 ? this.dirtyCountSingularFormatValue : this.dirtyCountPluralFormatValue).replace("{count}", count)
    }
    if (this.hasSaveBarTarget) {
      this.saveBarTarget.classList.toggle("translate-y-full", count === 0)
    }
    if (this.hasCounterTarget) {
      this.counterTarget.textContent = this.grantedCounterFormatValue
        .replace("{granted}", this.totalGranted()).replace("{total}", this.checkboxTargets.length)
    }
  }

  discard() {
    if (this.dirtyCount() === 0) return
    if (!confirm(this.discardConfirmFormatValue.replace("{count}", this.dirtyCount()))) return
    this.checkboxTargets.forEach(cb => {
      const original = cb.dataset.grantsEditorOriginalCheckedParam === "true"
      cb.checked = original
      this.markCheckbox(cb)
    })
    this.groupTargets.forEach(g => this.updateGroupCount(g.dataset.groupKey))
    this.rowTargets.forEach(r => this.updateRowGrantedAttr(r))
    this.updateDirtyState()
  }

  // ----- Diff drawer -----
  openDiff() {
    if (this.dirtyCount() === 0) return
    const dirty = this.dirtyCheckboxes()
    const added = dirty.filter(cb => cb.checked)
    const removed = dirty.filter(cb => !cb.checked)

    const sectionHtml = (title, list, color) => {
      if (list.length === 0) return ""
      const items = list.map(cb => {
        const row = cb.closest("[data-grants-editor-target='row']")
        const label = row.dataset.displayLabel || ""
        const action = cb.closest("label").querySelector("span").textContent
        return `
          <div class="flex items-center gap-3 py-2 border-b border-border-subtle last:border-0">
            <span class="grants-diff-marker ${color}">${title === this.addedLabelValue ? "+" : "−"}</span>
            <div class="flex-1 min-w-0">
              <p class="text-sm text-text-primary">${this.esc(label)}</p>
            </div>
            <span class="badge badge-default px-1.5 py-0.5 text-xs">${this.esc(action)}</span>
          </div>
        `
      }).join("")
      return `
        <div>
          <h4 class="section-header mb-2">${title} (${list.length})</h4>
          <div class="card p-3">${items}</div>
        </div>
      `
    }

    this.diffContentTarget.innerHTML =
      sectionHtml(this.addedLabelValue, added, "grants-diff-added") +
      sectionHtml(this.removedLabelValue, removed, "grants-diff-removed") ||
      `<p class="text-body-sm">${this.noChangesYetLabelValue}</p>`
    this.diffDrawerTarget.classList.remove("hidden")
  }

  closeDiff() {
    this.diffDrawerTarget.classList.add("hidden")
  }

  closeDiffOnBackdrop(event) {
    if (event.target === this.diffDrawerTarget) this.closeDiff()
  }

  // ----- Save -----
  async save() {
    if (this.lockedValue || this.dirtyCount() === 0) return

    const dirty = this.dirtyCheckboxes()
    const toGrant = (cb) => ({
      subject_type: cb.dataset.grantsEditorSubjectTypeParam,
      subject_key:  cb.dataset.grantsEditorSubjectKeyParam || null,
      subject_id:   cb.dataset.grantsEditorSubjectIdParam ? Number(cb.dataset.grantsEditorSubjectIdParam) : null,
      action:       cb.dataset.actionName,
    })
    const added = dirty.filter(cb => cb.checked).map(toGrant)
    const removed = dirty.filter(cb => !cb.checked).map(toGrant)

    this.saveButtonTargets.forEach(b => { b.disabled = true; b.textContent = this.savingLabelValue })

    try {
      const token = document.querySelector('meta[name="csrf-token"]').content
      const res = await fetch(this.updateUrlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": token,
        },
        body: JSON.stringify({ role_grants: { added, removed } }),
      })
      if (res.ok) {
        window.location.reload()
      } else {
        const data = await res.json().catch(() => ({}))
        alert(this.saveFailedFormatValue.replace("{details}", data.errors ? JSON.stringify(data.errors) : this.unknownErrorLabelValue))
        this.saveButtonTargets.forEach(b => { b.disabled = false; b.textContent = this.saveGrantsLabelValue })
      }
    } catch (e) {
      alert(this.saveFailedFormatValue.replace("{details}", e.message))
      this.saveButtonTargets.forEach(b => { b.disabled = false; b.textContent = this.saveGrantsLabelValue })
    }
  }

  esc(s) {
    return String(s ?? "").replace(/[&<>"']/g, c => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    }[c]))
  }
}
