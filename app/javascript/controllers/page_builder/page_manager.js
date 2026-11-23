import { BaseManager } from "controllers/page_builder/base_manager"

export class PageManager extends BaseManager {
  addPage() {
    this.c.undoRedoManager.saveHistory()

    const pageId = `page_${Date.now()}`
    const pageNumber = this.c.configuration.pages.length + 1

    const newPage = {
      id: pageId,
      name: `Page ${pageNumber}`,
      order: pageNumber,
      fields: []
    }

    this.c.configuration.pages.push(newPage)
    this.c.activePageValue = pageId
    this.c.fields = this.c.currentPageFields
    this.c.selectionManager.deselectAll()
    this.renderPageTabs()
    this.renderCanvas()
    this.updateFormFooter()
  }

  switchPage(event) {
    const pageId = event.currentTarget.dataset.pageId
    if (pageId && pageId !== this.c.activePageValue) {
      this.c.activePageValue = pageId
      this.c.fields = this.c.currentPageFields
      this.c.propertyManager.hideFloatingPanel()
      this.c.selectionManager.deselectAll()
      this.renderPageTabs()
      this.renderCanvas()
    }
  }

  moveFieldsToPage(fieldIds, targetPageId) {
    if (!fieldIds.length || !targetPageId) return

    const targetPage = this.c.configuration.pages.find(p => p.id === targetPageId)
    if (!targetPage) return

    this.c.undoRedoManager.saveState()

    const idSet = new Set(fieldIds)
    const extractedFields = []

    // Collect selected fields in forward document order so the target page
    // preserves the exact source sequence and layout — including section
    // headers and per-field widths. (A selected container is taken whole, with
    // its nested children intact; we only descend into a container when the
    // container itself is not selected.)
    for (const page of this.c.configuration.pages) {
      if (page.id === targetPageId) continue

      for (const field of page.fields) {
        if (idSet.has(field.id)) {
          extractedFields.push(field)
          continue
        }

        if (field.field_type === "columns" && Array.isArray(field.columns)) {
          for (const col of field.columns) {
            for (const child of (col.fields || [])) {
              if (idSet.has(child.id)) extractedFields.push(child)
            }
          }
        } else if (field.type === "field_group" && Array.isArray(field.fields)) {
          for (const child of field.fields) {
            if (idSet.has(child.id)) extractedFields.push(child)
          }
        }
      }
    }

    // Remove the collected fields from their source containers (recurse into
    // columns / field groups for nested child selections).
    const removeSelected = (list) => {
      return list
        .filter(f => !idSet.has(f.id))
        .map(f => {
          if (f.field_type === "columns" && Array.isArray(f.columns)) {
            return { ...f, columns: f.columns.map(col => ({ ...col, fields: removeSelected(col.fields || []) })) }
          }
          if (f.type === "field_group" && Array.isArray(f.fields)) {
            return { ...f, fields: removeSelected(f.fields) }
          }
          return f
        })
    }
    for (const page of this.c.configuration.pages) {
      if (page.id === targetPageId) continue
      page.fields = removeSelected(page.fields)
    }

    // Append to target preserving the collected (source) order.
    const baseOrder = targetPage.fields.length
    extractedFields.forEach((field, idx) => {
      field.order = baseOrder + idx
      targetPage.fields.push(field)
    })

    // Reindex order on all affected pages
    for (const page of this.c.configuration.pages) {
      page.fields.forEach((f, i) => f.order = i)
    }

    this.c.selectionManager.deselectAll()
    this.c.fields = this.c.currentPageFields
    this.renderPageTabs()
    this.renderCanvas()
    this.c.saveManager.markDirty()
  }

  deletePage(event) {
    event.stopPropagation()
    const pageId = event.currentTarget.dataset.pageId

    if (this.c.configuration.pages.length <= 1) return

    const page = this.c.configuration.pages.find(p => p.id === pageId)
    const fieldCount = page?.fields?.length || 0
    const nameFormatted = page?.name ?? this.c.deletePageFallbackNameValue
    const msg = fieldCount > 0
      ? (fieldCount !== 1 ? this.c.deletePageConfirmPluralValue : this.c.deletePageConfirmSingularValue)
          .replace("{name}", page.name).replace("{count}", fieldCount)
      : this.c.deletePageConfirmNoFieldsValue.replace("{name}", nameFormatted)
    if (!confirm(msg)) return

    const pageIndex = this.c.configuration.pages.findIndex(p => p.id === pageId)
    if (pageIndex === -1) return

    // Snapshot state for undo BEFORE mutating, so restoring brings the page back.
    this.c.undoRedoManager.saveHistory()

    // Collect every field id (including nested column/group children) that lives
    // on the page being deleted, so we can prune dangling rule/calculation refs.
    const orphanedIds = this._collectAllFieldIds(page?.fields || [])
    this.c.configuration.pages.splice(pageIndex, 1)
    this._pruneReferences(orphanedIds, pageId)

    if (this.c.activePageValue === pageId) {
      this.c.activePageValue = this.c.configuration.pages[0].id
      this.c.fields = this.c.currentPageFields
    }

    this.c.selectionManager.deselectAll()
    this.renderPageTabs()
    this.renderCanvas()
    this.updateFormFooter()
  }

  _collectAllFieldIds(fields) {
    const ids = new Set()
    const walk = (list) => {
      for (const f of list || []) {
        if (!f) continue
        ids.add(f.id)
        if (f.field_type === "columns") {
          (f.columns || []).forEach(col => walk(col.fields))
        } else if (f.type === "field_group") {
          walk(f.fields)
        }
      }
    }
    walk(fields)
    return ids
  }

  // Public: drop conditions/actions/calculations that point at fields being
  // deleted (no page removed). `removedFields` are field objects; columns and
  // field-groups are expanded so nested children are covered too. Keeps rule
  // references from silently dangling and being stripped on the next rule save.
  pruneReferencesToDeletedFields(removedFields) {
    const ids = this._collectAllFieldIds(removedFields)
    this._pruneReferences(ids, null)
  }

  _pruneReferences(orphanedFieldIds, removedPageId) {
    const config = this.c.configuration

    if (Array.isArray(config.rules)) {
      config.rules = config.rules
        .map(rule => this._pruneRule(rule, orphanedFieldIds, removedPageId))
        .filter(rule => rule && (rule.actions?.length || 0) > 0)
    }

    if (Array.isArray(config.calculations)) {
      config.calculations = config.calculations.filter(calc =>
        calc?.target_field_id && !orphanedFieldIds.has(calc.target_field_id)
      )
    }
  }

  _pruneRule(rule, orphanedFieldIds, removedPageId) {
    if (!rule) return rule
    const groups = (rule.conditions?.groups || [])
      .map(group => ({
        ...group,
        items: (group.items || []).filter(item => !orphanedFieldIds.has(item.field_id))
      }))
      .filter(group => (group.items?.length || 0) > 0)

    const actions = (rule.actions || []).filter(action => {
      if (!action) return false
      // Field-targeted actions: drop if their field was deleted.
      // Page-targeted actions: drop if their page was deleted.
      if (orphanedFieldIds.has(action.target_id)) return false
      if (action.target_id === removedPageId) return false
      return true
    })

    return {
      ...rule,
      conditions: { ...(rule.conditions || { logic: "all" }), groups },
      actions
    }
  }

  renamePage(event) {
    event.stopPropagation()
    const pageId = event.currentTarget.dataset.pageId
    const page = this.c.configuration.pages.find(p => p.id === pageId)
    if (!page) return

    const tab = event.currentTarget.closest(".page-tab")
    const nameSpan = tab?.querySelector("[data-page-name]")
    if (!nameSpan) return

    // Replace span with inline input
    const input = document.createElement("input")
    input.type = "text"
    input.value = page.name
    input.className = "w-20 px-1 py-0 text-sm font-medium border border-indigo-400 rounded outline-none focus:ring-1 focus:ring-indigo-500 bg-white"

    const commit = () => {
      const newName = input.value.trim()
      if (newName && newName !== page.name) {
        // Snapshot BEFORE mutating so Undo restores the previous name.
        this.c.undoRedoManager.saveHistory()
        page.name = newName
        this.c.saveManager.markDirty()
      }
      this.renderPageTabs()
    }

    input.addEventListener("blur", commit)
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); input.blur() }
      if (e.key === "Escape") { input.value = page.name; input.blur() }
    })

    nameSpan.replaceWith(input)
    input.focus()
    input.select()
  }

  // Page tab drag-to-reorder
  pageTabDragStart(event) {
    const tab = event.currentTarget
    this._draggingPageId = tab.dataset.pageId
    tab.classList.add("opacity-50")
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", tab.dataset.pageId)
  }

  pageTabDragEnd(event) {
    event.currentTarget.classList.remove("opacity-50")
    this._draggingPageId = null
    this.c.element.querySelectorAll(".page-tab").forEach(t => t.classList.remove("border-l-2", "border-l-indigo-500"))
  }

  pageTabDragOver(event) {
    event.preventDefault()
    if (!this._draggingPageId) return
    event.dataTransfer.dropEffect = "move"

    const tab = event.currentTarget
    if (tab.dataset.pageId === this._draggingPageId) return

    // Show drop indicator
    this.c.element.querySelectorAll(".page-tab").forEach(t => t.classList.remove("border-l-2", "border-l-indigo-500"))
    tab.classList.add("border-l-2", "border-l-indigo-500")
  }

  pageTabDrop(event) {
    event.preventDefault()
    if (!this._draggingPageId) return

    const targetPageId = event.currentTarget.dataset.pageId
    if (this._draggingPageId === targetPageId) return

    const pages = this.c.configuration.pages
    const dragIndex = pages.findIndex(p => p.id === this._draggingPageId)
    const dropIndex = pages.findIndex(p => p.id === targetPageId)
    if (dragIndex === -1 || dropIndex === -1) return

    this.c.undoRedoManager.saveState()

    const [draggedPage] = pages.splice(dragIndex, 1)
    pages.splice(dropIndex, 0, draggedPage)
    pages.forEach((p, i) => p.order = i + 1)

    this.renderPageTabs()
    this.c.saveManager.markDirty()
    this._draggingPageId = null
  }

  renderPageTabs() {
    if (!this.c.hasPageTabsTarget) return

    const canDelete = this.c.configuration.pages.length > 1

    const tabs = this.c.configuration.pages.map((page) => {
      const isActive = page.id === this.c.activePageValue

      const renameClasses = isActive ? "text-indigo-200 hover:text-white" : "text-gray-400 hover:text-indigo-600"
      const deleteClasses = isActive ? "text-indigo-200 hover:text-white" : "text-gray-400 hover:text-red-500"

      return `
        <div class="page-tab inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-md transition-colors cursor-pointer ${
                  isActive
                    ? "bg-indigo-600 text-white shadow-md"
                    : "text-gray-500 hover:text-gray-700 hover:bg-white/60"
                }"
                draggable="true"
                data-page-id="${page.id}"
                data-action="click->page-builder#switchPage dragstart->page-builder#pageTabDragStart dragend->page-builder#pageTabDragEnd dragover->page-builder#pageTabDragOver drop->page-builder#pageTabDrop">
          <span data-page-name>${page.name}</span>
          ${canDelete ? `
            <div class="flex items-center gap-0.5">
              <button type="button"
                      class="p-0.5 ${renameClasses} transition-colors rounded"
                      data-page-id="${page.id}"
                      data-action="click->page-builder#renamePage"
                      title="${this.escapeHtml(this.c.renamePageTitleValue)}">
                <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                </svg>
              </button>
              <button type="button"
                      class="p-0.5 ${deleteClasses} transition-colors rounded"
                      data-page-id="${page.id}"
                      data-action="click->page-builder#deletePage"
                      title="${this.escapeHtml(this.c.deletePageTitleValue)}">
                <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          ` : ""}
        </div>
      `
    }).join("")

    const addButton = `
      <button type="button"
              class="ml-1 inline-flex items-center p-1.5 text-gray-400 hover:text-gray-600 hover:bg-white/50 rounded-md transition-colors"
              data-action="click->page-builder#addPage"
              title="${this.escapeHtml(this.c.addNewPageTitleValue)}">
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
        </svg>
      </button>
    `

    this.c.pageTabsTarget.innerHTML = `<div class="flex items-center gap-1 overflow-x-auto">${tabs}</div>${addButton}`
  }

  renderCanvas() {
    this.c.fieldManager.renderFields()
  }

  _hasInputFields() {
    const pages = this.c.configuration.pages || []
    return pages.some(page =>
      (page.fields || []).some(f => {
        if (f.field_type === "columns") {
          return (f.columns || []).some(col =>
            (col.fields || []).some(cf => cf.property_type !== "layout")
          )
        }
        return f.property_type !== "layout"
      })
    )
  }

  updateFormFooter() {
    if (!this.c.hasFormFooterTarget) return

    if (!this._hasInputFields()) {
      this.c.formFooterTarget.innerHTML = ""
      this.c.formFooterTarget.classList.add("hidden")
      return
    }

    this.c.formFooterTarget.classList.remove("hidden")

    const pages = this.c.configuration.pages
    const totalPages = pages.length
    const currentPageId = this.c.activePageValue
    const currentIndex = pages.findIndex(p => p.id === currentPageId)
    const settings = this.c.configuration.form_settings || {}
    const submitText = settings.submit_button_text || this.c.defaultSubmitButtonTextValue

    const secondaryBtn = "px-5 py-2.5 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors"
    const primaryBtn = "px-5 py-2.5 text-sm font-medium text-white bg-indigo-600 rounded-lg hover:bg-indigo-700 transition-colors"

    let actionsHtml = ""

    if (totalPages <= 1) {
      actionsHtml = `
        <div></div>
        <div>
          <button type="submit" class="${primaryBtn}">${this._escapeHtml(submitText)}</button>
        </div>
      `
    } else {
      const isFirst = currentIndex <= 0
      const isLast = currentIndex >= totalPages - 1

      const leftHtml = isFirst
        ? `<button type="button" class="${secondaryBtn}">${this._escapeHtml(this.c.cancelLabelValue)}</button>`
        : `<button type="button" class="${secondaryBtn}">${this._escapeHtml(this.c.previousStepLabelValue)}</button>`

      const stepCounter = `<span class="text-sm text-gray-400">${this._escapeHtml(this.c.stepOfFormatValue.replace("{current}", currentIndex + 1).replace("{total}", totalPages))}</span>`
      const rightBtn = isLast
        ? `<button type="submit" class="${primaryBtn}">${this._escapeHtml(submitText)}</button>`
        : `<button type="button" class="${primaryBtn}">${this._escapeHtml(this.c.nextStepLabelValue)}</button>`

      actionsHtml = `
        <div>${leftHtml}</div>
        <div class="flex items-center gap-3">
          ${stepCounter}
          ${rightBtn}
        </div>
      `
    }

    this.c.formFooterTarget.innerHTML = `
      <div class="flex items-center justify-between">
        ${actionsHtml}
      </div>
    `
  }

  _escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
