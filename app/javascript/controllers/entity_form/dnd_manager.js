import { BaseManager } from "controllers/entity_form/base_manager"

export class DndManager extends BaseManager {
  constructor(controller) {
    super(controller)
    this.dragKind = null
    this.dragRowEl = null
    this.dragGroupId = null
  }

  dragStartRow(event) {
    const row = event.currentTarget
    if (!row || !row.matches("[data-attribute-item]")) return
    this.dragKind = "row"
    this.dragRowEl = row
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", row.getAttribute("data-attr-name-slug") || "")
    row.classList.add("opacity-50")
  }

  dragOverRow(event) {
    if (this.dragKind !== "row") return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  dropRow(event) {
    if (this.dragKind !== "row") return
    event.preventDefault()
    const targetRow = event.currentTarget
    if (!targetRow || targetRow === this.dragRowEl) return
    const groupId = targetRow.getAttribute("data-attr-group-id") || null
    this.c.schemaManager.moveRowTo(this.dragRowEl, { groupId: groupId || null, beforeRow: targetRow })
  }

  dragEndRow() {
    if (this.dragRowEl) this.dragRowEl.classList.remove("opacity-50")
    this.dragKind = null
    this.dragRowEl = null
  }

  dragStartGroup(event) {
    const header = event.currentTarget.closest
      ? event.currentTarget.closest("[data-attribute-group-header]")
      : event.currentTarget
    if (!header) return
    this.dragKind = "group"
    this.dragGroupId = header.getAttribute("data-group-id")
    event.dataTransfer.effectAllowed = "move"
  }

  dragOverGroupHeader(event) {
    if (this.dragKind !== "group") return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  dropGroup(event) {
    if (this.dragKind !== "group") return
    event.preventDefault()
    const header = event.currentTarget.closest
      ? event.currentTarget.closest("[data-attribute-group-header]")
      : event.currentTarget
    if (!header) return
    const targetGroupId = header.getAttribute("data-group-id") || null
    if (!targetGroupId || targetGroupId === this.dragGroupId) return
    this.c.schemaManager.moveGroupTo(this.dragGroupId, targetGroupId)
  }
}
