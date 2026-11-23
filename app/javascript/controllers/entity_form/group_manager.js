import { BaseManager } from "controllers/entity_form/base_manager"

const COLOR_CLASSES = {
  slate: "bg-slate-500", indigo: "bg-indigo-500", sky: "bg-sky-500", teal: "bg-teal-500",
  emerald: "bg-emerald-500", amber: "bg-amber-500", rose: "bg-rose-500", violet: "bg-violet-500"
}

export class GroupManager extends BaseManager {
  constructor(controller) {
    super(controller)
    this.selected = new Set()
    this.editingGroupId = null
    this.iconChoice = "folder"
    this.colorChoice = "slate"
  }

  colorBarClassFor(color) { return COLOR_CLASSES[color] || COLOR_CLASSES.slate }

  toggleAttributeSelection(event) {
    const row = event.target.closest("[data-attribute-item]")
    if (!row) return
    const key = row.getAttribute("data-attr-name-slug") || row.getAttribute("data-attr-name") || ""
    if (event.target.checked) this.selected.add(key); else this.selected.delete(key)
    this.refreshSelectionUI()
  }

  clearAttributeSelection() {
    this.selected.clear()
    this.c.attributesContainerTarget.querySelectorAll('input[type="checkbox"]').forEach(cb => cb.checked = false)
    this.refreshSelectionUI()
  }

  refreshSelectionUI() {
    if (!this.c.hasGroupingToolbarTarget) return
    if (this.selected.size > 0) {
      this.c.groupingToolbarTarget.classList.remove("hidden")
      if (this.c.hasSelectionCountTarget) this.c.selectionCountTarget.textContent = this.selected.size.toString()
    } else {
      this.c.groupingToolbarTarget.classList.add("hidden")
    }
  }

  openMoveToGroup(event) {
    event.preventDefault()
    const groups = this.c.schemaManager.readAttributeGroups()
    const items = [
      ...groups.map(g => `
        <li><button type="button" class="block w-full text-left px-3 py-1.5 text-sm text-text-primary hover:bg-surface-active"
                    data-action="click->entity-form#chooseGroup" data-group-id="${this.escapeHtml(g.id)}">
              <span class="inline-block w-2 h-2 rounded-full ${this.colorBarClassFor(g.color)} mr-2"></span>${this.escapeHtml(g.name)}
            </button></li>`),
      `<li><button type="button" class="block w-full text-left px-3 py-1.5 text-sm text-text-primary hover:bg-surface-active"
              data-action="click->entity-form#chooseGroup" data-group-id="">${this.escapeHtml(this.c.groupUngroupedLabelValue)}</button></li>`,
      `<li><button type="button" class="block w-full text-left px-3 py-1.5 text-sm text-accent hover:bg-surface-active"
              data-action="click->entity-form#openNewGroupModal">${this.escapeHtml(this.c.groupMenuNewGroupLabelValue)}</button></li>`
    ].join("")
    this.showFloater(event.currentTarget, `<ul class="py-1 min-w-[180px] bg-surface border border-border-subtle rounded-md shadow-lg">${items}</ul>`)
  }

  chooseGroup(event) {
    const gid = event.currentTarget.getAttribute("data-group-id") || ""
    this.assignSelectedToGroup(gid || null)
    this.closeFloater()
  }

  openNewGroupModal(event) {
    event.preventDefault()
    // Create mode: no group is being edited. The currently-selected attribute
    // rows (if any) are assigned to the new group on save.
    this.editingGroupId = null
    this.iconChoice = "folder"
    this.colorChoice = "slate"
    if (this.c.hasGroupEditNameTarget) { this.c.groupEditNameTarget.value = ""; this.c.groupEditNameTarget.setCustomValidity("") }
    if (this.c.hasGroupEditDescriptionTarget) this.c.groupEditDescriptionTarget.value = ""
    if (this.c.hasGroupModalTitleTarget) this.c.groupModalTitleTarget.textContent = this.c.newGroupLabelValue
    if (this.c.hasGroupModalSubmitTarget) this.c.groupModalSubmitTarget.textContent = this.c.createGroupLabelValue
    this.refreshGroupIconSelection()
    this.refreshGroupColorSelection()
    this.closeFloater()
    if (this.c.hasGroupEditModalTarget) this.c.groupEditModalTarget.classList.remove("hidden")
    if (this.c.hasGroupEditNameTarget) this.c.groupEditNameTarget.focus()
  }

  openGroupMenu(event) {
    event.preventDefault()
    event.stopPropagation()
    const gid = event.currentTarget.getAttribute("data-group-id")
    const html = `
      <ul class="py-1 min-w-[160px] bg-surface border border-border-subtle rounded-md shadow-lg">
        <li><button type="button" class="block w-full text-left px-3 py-1.5 text-sm text-text-primary hover:bg-surface-active"
                data-action="click->entity-form#editGroup" data-group-id="${this.escapeHtml(gid)}">${this.escapeHtml(this.c.groupMenuEditLabelValue)}</button></li>
        <li><button type="button" class="block w-full text-left px-3 py-1.5 text-sm text-red-600 hover:bg-red-50"
                data-action="click->entity-form#deleteGroup" data-group-id="${this.escapeHtml(gid)}">${this.escapeHtml(this.c.groupMenuDeleteLabelValue)}</button></li>
      </ul>
    `
    this.showFloater(event.currentTarget, html)
  }

  editGroup(event) {
    const gid = event.currentTarget.getAttribute("data-group-id")
    const groups = this.c.schemaManager.readAttributeGroups()
    const group = groups.find(g => g.id === gid)
    if (!group) return
    this.editingGroupId = gid
    if (this.c.hasGroupEditNameTarget) { this.c.groupEditNameTarget.value = group.name; this.c.groupEditNameTarget.setCustomValidity("") }
    if (this.c.hasGroupEditDescriptionTarget) this.c.groupEditDescriptionTarget.value = group.description || ""
    this.iconChoice = group.icon || "folder"
    this.colorChoice = group.color || "slate"
    if (this.c.hasGroupModalTitleTarget) this.c.groupModalTitleTarget.textContent = this.c.editGroupLabelValue
    if (this.c.hasGroupModalSubmitTarget) this.c.groupModalSubmitTarget.textContent = this.c.saveGroupLabelValue
    this.refreshGroupIconSelection()
    this.refreshGroupColorSelection()
    if (this.c.hasGroupEditModalTarget) this.c.groupEditModalTarget.classList.remove("hidden")
    this.closeFloater()
    if (this.c.hasGroupEditNameTarget) this.c.groupEditNameTarget.focus()
  }

  closeGroupEditModal() {
    if (this.c.hasGroupEditModalTarget) this.c.groupEditModalTarget.classList.add("hidden")
    this.editingGroupId = null
  }

  selectGroupIcon(event) { this.iconChoice = event.currentTarget.getAttribute("data-icon-key"); this.refreshGroupIconSelection() }
  selectGroupColor(event) { this.colorChoice = event.currentTarget.getAttribute("data-color-key"); this.refreshGroupColorSelection() }

  // Highlight the icon button matching the current iconChoice.
  refreshGroupIconSelection() {
    if (!this.c.hasGroupEditIconTarget) return
    this.c.groupEditIconTarget.querySelectorAll(".group-icon-option").forEach(btn => {
      const active = btn.getAttribute("data-icon-key") === this.iconChoice
      btn.classList.toggle("ring-2", active)
      btn.classList.toggle("ring-accent", active)
      btn.classList.toggle("bg-accent-subtle", active)
      btn.classList.toggle("text-accent", active)
      btn.classList.toggle("border-accent", active)
    })
  }

  // Highlight the color swatch matching the current colorChoice.
  refreshGroupColorSelection() {
    if (!this.c.hasGroupEditColorTarget) return
    this.c.groupEditColorTarget.querySelectorAll(".group-color-option").forEach(btn => {
      const active = btn.getAttribute("data-color-key") === this.colorChoice
      btn.classList.toggle("ring-2", active)
      btn.classList.toggle("ring-text-primary", active)
    })
  }

  saveGroupEdit(event) {
    if (event) event.preventDefault()
    if (!this.c.hasGroupEditNameTarget) return
    const nameInput = this.c.groupEditNameTarget
    const name = (nameInput.value || "").trim()
    nameInput.setCustomValidity("")
    if (!name) { nameInput.setCustomValidity(this.c.groupNameRequiredMsgValue); nameInput.reportValidity(); return }
    if (this.nameInUse(name, this.editingGroupId)) {
      nameInput.setCustomValidity(this.c.groupNameUniqueMsgValue)
      nameInput.reportValidity()
      return
    }
    const description = this.c.hasGroupEditDescriptionTarget ? (this.c.groupEditDescriptionTarget.value || "").trim() : ""

    if (this.editingGroupId) {
      // Edit mode — update the existing group in place.
      const groups = this.c.schemaManager.readAttributeGroups().map(g =>
        g.id === this.editingGroupId
          ? { ...g, name, description, icon: this.iconChoice, color: this.colorChoice }
          : g
      )
      this.c.schemaManager.writeAttributeGroups(groups)
      this.c.schemaManager.regroupAttributeRows()
    } else {
      // Create mode — append the new group and assign any selected attributes to it.
      const newGroup = this.buildGroup({ name, description, icon: this.iconChoice, color: this.colorChoice })
      const groups = this.c.schemaManager.readAttributeGroups()
      this.c.schemaManager.writeAttributeGroups([...groups, newGroup])
      this.assignSelectedToGroup(newGroup.id)
    }
    this.closeGroupEditModal()
  }

  deleteGroup(event) {
    const gid = event.currentTarget.getAttribute("data-group-id")
    if (!gid) return
    const groups = this.c.schemaManager.readAttributeGroups().filter(g => g.id !== gid)
    this.c.schemaManager.writeAttributeGroups(groups)
    const safeGid = window.CSS && window.CSS.escape ? CSS.escape(gid) : gid.replace(/"/g, '\\"')
    this.c.attributesContainerTarget.querySelectorAll(`[data-attr-group-id="${safeGid}"]`).forEach(row => {
      row.setAttribute("data-attr-group-id", "")
      row.dataset.attrGroupId = ""
      const input = row.querySelector('input[data-input="group_id"]')
      if (input) input.value = ""
    })
    this.c.schemaManager.regroupAttributeRows()
    this.c.schemaManager.syncPropertySchema()
    this.closeFloater()
  }

  assignSelectedToGroup(groupId) {
    const slugs = this.selected
    this.c.attributesContainerTarget.querySelectorAll("[data-attribute-item]").forEach(row => {
      const slug = row.getAttribute("data-attr-name-slug") || row.getAttribute("data-attr-name") || ""
      if (!slugs.has(slug)) return
      row.setAttribute("data-attr-group-id", groupId || "")
      const input = row.querySelector('input[data-input="group_id"]')
      if (input) input.value = groupId || ""
    })
    this.clearAttributeSelection()
    this.c.schemaManager.regroupAttributeRows()
    this.c.schemaManager.syncPropertySchema()
  }

  buildGroup({ name, description = "", icon = "folder", color = "slate" }) {
    return {
      id: `g_${Math.random().toString(36).slice(2, 9)}`,
      name,
      description,
      icon,
      color
    }
  }

  nameInUse(name, excludingId = null) {
    const target = name.trim().toLowerCase()
    return this.c.schemaManager.readAttributeGroups().some(g => g.id !== excludingId && g.name.trim().toLowerCase() === target)
  }

  showFloater(anchor, html) {
    // Measure the anchor BEFORE closing any open floater. When a floater action
    // chains into another (e.g. "+ New group…" inside the move-to-group menu),
    // the anchor button lives inside the floater we are about to remove; reading
    // its rect afterwards would yield zeros and pin the new floater to the
    // top-left corner of the viewport.
    const rect = anchor.getBoundingClientRect()
    this.closeFloater()
    const f = document.createElement("div")
    f.className = "fixed z-40"
    f.setAttribute("data-entity-form-floater", "")
    f.innerHTML = html
    this.c.element.appendChild(f)

    // Clamp to the viewport so the floater never overflows the right/bottom edge.
    const margin = 8
    const fw = f.offsetWidth
    const fh = f.offsetHeight
    let left = rect.left
    let top = rect.bottom + 4
    if (left + fw > window.innerWidth - margin) left = Math.max(margin, window.innerWidth - fw - margin)
    if (top + fh > window.innerHeight - margin) top = Math.max(margin, rect.top - fh - 4)
    f.style.left = `${left}px`
    f.style.top = `${top}px`

    this._closeFloaterHandler = (e) => { if (!f.contains(e.target)) this.closeFloater() }
    setTimeout(() => document.addEventListener("click", this._closeFloaterHandler), 0)
  }

  closeFloater() {
    document.querySelectorAll("[data-entity-form-floater]").forEach(el => el.remove())
    if (this._closeFloaterHandler) document.removeEventListener("click", this._closeFloaterHandler)
  }

  escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, c => ({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]))
  }
}
