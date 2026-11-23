import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"
import { getCSRFToken } from "utils"

// Page composer (Website module). Keeps website_page[sections_json] in sync
// with the sortable section list and reloads the admin preview iframe after save.
//
// HTML contract (ComposerComponent):
//   data-controller="website-builder" on the form
//   targets: list, row, handle, kit, json, previewFrame, unsaved, previewLoading, empty, toggleAll,
//            previewStage, viewportBtn, sectionNav, editorPane, previewPane, paneBtn
//   actions: addSection, removeSection, moveUp, moveDown, toggleKit, markDirty,
//            reloadPreview, previewLoaded, addItem, removeItem, confirmSetHome,
//            applyHref, checkHref, previewImage, imageError, clearImage, countChars,
//            duplicateItem, moveItemUp, moveItemDown, resetSection, toggleAllSections,
//            setPreviewViewport, saveShortcut, persist, focusSection (tabs and the
//            data-section-step previous/next buttons), showOutline, focusIdentity,
//            setWorkspacePane, allowImageDrop, dropImage, uploadImage,
//            navigateSectionTabs, navigatePaneTabs, pickStyleColor, resetStyles, toggleStyle
//   Design panels (StylePanelComponent): each hidden [data-style-panel] sits
//   beside its element and opens from the [data-style-trigger] that
//   aria-controls it; its [data-style-target] groups of [data-style-prop]
//   controls fold into props.styles. Clicking a [data-site-el] node in the
//   preview opens the matching panel.

const ROW_SELECTOR = "[data-website-builder-target='row']"
const PLACEHOLDER_ID = "__SECTION_ID__"
const PREVIEW_PROPS = ["headline", "heading", "quote", "kicker", "eyebrow"]
const IDREF_ATTRIBUTES = ["for", "aria-labelledby", "aria-describedby", "aria-controls", "aria-owns", "aria-details", "aria-errormessage", "aria-activedescendant", "aria-flowto"]
const SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/
const ROOT_RELATIVE = /^\/(?!\/)\S*$/
const unsafeHrefCharacter = (character) => {
  const code = character.codePointAt(0)
  return code === 92 || code <= 31 || (code >= 127 && code <= 159)
}

export default class extends Controller {
  static targets = [
    "list", "row", "handle", "kit", "json", "previewFrame", "unsaved", "previewLoading", "empty", "toggleAll",
    "previewStage", "viewportBtn", "sectionNav", "editorPane", "previewPane", "paneBtn"
  ]

  static values = {
    deleteConfirm: { type: String, default: "Remove this section from the page?" },
    setHomeConfirm: {
      type: String,
      default: "Make this the home page? The current home will become an inner page and must keep its slug."
    },
    structureLocked: { type: Boolean, default: false },
    expandAll: { type: String, default: "Expand all" },
    collapseAll: { type: String, default: "Collapse all" },
    charCountFormat: { type: String, default: "{count} characters" },
    itemLabelFormat: { type: String, default: "Item {number}" },
    itemActionFormat: { type: String, default: "{action} item {number}: {title}" },
    itemActions: { type: Object, default: { up: "Move up", down: "Move down", duplicate: "Duplicate", remove: "Remove" } },
    arrayLimitFormat: { type: String, default: "{count} of {max}" },
    imageLoadFailed: { type: String, default: "Image preview unavailable" },
    resetConfirm: {
      type: String,
      default: "Restore this section's starter copy? Your edits in this section will be lost."
    },
    livePreviewMs: { type: Number, default: 450 },
    uploadUrl: { type: String, default: "" },
    uploadFailed: { type: String, default: "The photo could not be uploaded." },
    uploading: { type: String, default: "Uploading..." },
    highlightColor: { type: String, default: "#6366f1" }
  }

  initialize() {
    this.previewRevision = 0
  }

  connect() {
    this.seq = 0
    this.uploads = new Map()
    this.onSectionToggle = () => this.#syncToggleAllLabel()
    this.element.addEventListener("toggle", this.onSectionToggle, true)
    if (this.element.hasAttribute("data-website-workspace")) {
      this.onInvalid = (event) => this.#revealInvalid(event.target)
      this.element.addEventListener("invalid", this.onInvalid, true)
    }
    this.#refreshMoveButtons()
    this.#refreshAllArrayButtons()
    this.element.querySelectorAll("[data-prop]").forEach((el) => this.#refreshFieldChrome(el))
    this.#syncJson()
    this.#syncToggleAllLabel()
    this.#applyPreviewViewport(this.hasPreviewStageTarget ? this.previewStageTarget.dataset.viewport : "desktop")
    this.#applyWorkspacePane("editor")
    if (this.#outline()) this.#showWorkspaceLevel("outline")
    if (this.hasListTarget && !this.structureLockedValue) {
      this.sortable = Sortable.create(this.listTarget, {
        handle: "[data-website-builder-target='handle']",
        draggable: ROW_SELECTOR,
        animation: 150,
        ghostClass: "opacity-40",
        onEnd: () => {
          this.#refreshMoveButtons()
          this.markDirty()
        }
      })
    }
  }

  disconnect() {
    this.uploads.forEach((_upload, field) => this.#cancelUpload(field))
    this.element.removeEventListener("toggle", this.onSectionToggle, true)
    this.onSectionToggle = null
    this.element.removeEventListener("invalid", this.onInvalid, true)
    this.onInvalid = null
    clearTimeout(this.invalidTimer)
    this.revealingInvalid = false
    clearTimeout(this.liveTimer)
    this.liveTimer = null
    this.previewRevision += 1
    this.sortable?.destroy()
    this.sortable = null
  }

  addSection(event) {
    if (this.structureLockedValue) return
    const type = event.currentTarget.dataset.type
    if (!type || !this.hasListTarget) return

    const template = this.element.querySelector(`template[data-section-template="${type}"]`)
    const source = template?.content?.firstElementChild
    if (!source) return

    const node = source.cloneNode(true)
    const id = this.#newId()
    this.#rewritePlaceholder(node, id)
    node.dataset.sectionId = id
    const details = this.#sectionDetails(node)[0]
    if (details) details.open = true
    this.listTarget.appendChild(node)
    node.querySelectorAll("[data-prop]").forEach((el) => this.#refreshFieldChrome(el))
    this.#closeKit()
    this.#syncEmpty()
    this.#refreshMoveButtons()
    if (this.#rail()) {
      this.#showWorkspaceLevel("inspector")
      this.#showRailSection(id, true)
    }
    this.#refreshAllArrayButtons()
    this.#syncToggleAllLabel()
    this.markDirty()
  }

  removeSection(event) {
    if (this.structureLockedValue) return
    if (!window.confirm(this.deleteConfirmValue)) return
    const row = event.currentTarget.closest(ROW_SELECTOR)
    if (!row) return
    this.#clearTransientFields(row)
    row.remove()
    this.#syncEmpty()
    this.#refreshMoveButtons()
    this.#syncToggleAllLabel()
    this.markDirty()
  }

  moveUp(event) {
    if (this.structureLockedValue) return
    const row = event.currentTarget.closest(ROW_SELECTOR)
    if (!row || !this.hasListTarget) return
    const rows = this.rowTargets
    const idx = rows.indexOf(row)
    if (idx <= 0) return
    rows[idx - 1].insertAdjacentElement("beforebegin", row)
    this.#refreshMoveButtons()
    this.markDirty()
  }

  moveDown(event) {
    if (this.structureLockedValue) return
    const row = event.currentTarget.closest(ROW_SELECTOR)
    if (!row || !this.hasListTarget) return
    const rows = this.rowTargets
    const idx = rows.indexOf(row)
    if (idx === -1 || idx >= rows.length - 1) return
    rows[idx + 1].insertAdjacentElement("afterend", row)
    this.#refreshMoveButtons()
    this.markDirty()
  }

  toggleKit(event) {
    if (!this.hasKitTarget) return
    this.kitTarget.classList.toggle("hidden")
    const open = !this.kitTarget.classList.contains("hidden")
    const btn = event?.currentTarget
    if (btn?.setAttribute) btn.setAttribute("aria-expanded", String(open))
  }

  markDirty() {
    this.#refreshAllArrayButtons()
    this.#syncSectionPreviews()
    this.#syncStyleDots()
    this.#setUnsavedVisible(true)
    this.#syncJson()
    this.#scrollPreviewTo(this.#activeSectionId())
    this.#scheduleLivePreview()
  }

  reloadPreview(event) {
    if (event?.type === "turbo:submit-end" && event.detail?.success === false) return
    clearTimeout(this.liveTimer)
    this.previewRevision += 1
    this.#setUnsavedVisible(false)
    if (!this.hasPreviewFrameTarget) return
    if (this.hasPreviewLoadingTarget) this.previewLoadingTarget.classList.remove("hidden")
    const frame = this.previewFrameTarget
    frame.removeAttribute("srcdoc")
    const src = frame.dataset.previewSrc || frame.getAttribute("src") || frame.src
    if (!src) return
    frame.src = src
  }

  previewLoaded() {
    if (this.hasPreviewLoadingTarget) this.previewLoadingTarget.classList.add("hidden")
    this.#scrollPreviewAnchor()
    this.#bindPreviewPicking()
  }

  pickStyleColor(event) {
    const input = event.currentTarget
    const radio = input.parentElement?.querySelector("[data-style-custom-radio]")
    if (!radio) return
    radio.value = input.value
    radio.checked = true
    input.style.background = input.value
    this.markDirty()
  }

  resetStyles(event) {
    const panel = event.currentTarget.closest("[data-style-panel]")
    if (!panel) return
    panel.querySelectorAll("[data-style-prop]").forEach((el) => {
      if (el.type === "radio") {
        el.checked = el.value === ""
        return
      }
      el.value = ""
    })
    panel.querySelectorAll("[data-style-custom-input]").forEach((input) => { input.style.background = "" })
    this.markDirty()
  }

  toggleStyle(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = event.currentTarget.getAttribute("aria-controls")
    const panel = id && this.element.querySelector(`[data-style-panel][id="${this.#attrEscape(id)}"]`)
    if (!panel) return
    if (panel.hidden) {
      this.#openStylePanel(panel)
      return
    }
    const refocus = panel.contains(document.activeElement)
    panel.hidden = true
    this.#styleTriggers(panel).forEach((trigger) => trigger.setAttribute("aria-expanded", "false"))
    if (refocus) this.#styleTriggers(panel)[0]?.focus()
  }

  addItem(event) {
    const list = event.currentTarget.closest("[data-array]")
    if (!list) return
    const max = this.#bound(list.dataset.max, Number.POSITIVE_INFINITY)
    const items = list.querySelectorAll("[data-array-item]")
    if (items.length >= max) return
    const template = list.querySelector("template[data-item-template]")
    const source = template?.content?.firstElementChild
    if (!source) return
    const mount = list.querySelector("[data-array-list]") || list
    const node = this.#stamp(source.cloneNode(true))
    mount.appendChild(node)
    node.querySelectorAll("[data-prop]").forEach((el) => this.#refreshFieldChrome(el))
    this.#refreshArrayButtons(list)
    this.#focusItem(node, true)
    this.markDirty()
  }

  removeItem(event) {
    const list = event.currentTarget.closest("[data-array]")
    if (!list) return
    const item = event.currentTarget.closest("[data-array-item]")
    if (!item) return
    const min = this.#bound(list.dataset.min, 0)
    const count = list.querySelectorAll("[data-array-item]").length
    if (count > min) {
      const items = [...list.querySelectorAll("[data-array-item]")]
      const index = items.indexOf(item)
      const neighbor = items[index + 1] || items[index - 1]
      this.#clearTransientFields(item)
      item.remove()
      this.#refreshArrayButtons(list)
      if (neighbor) this.#focusItem(neighbor)
      else list.querySelector("[data-add-item]")?.focus()
      this.markDirty()
    }
  }

  duplicateItem(event) {
    const list = event.currentTarget.closest("[data-array]")
    const item = event.currentTarget.closest("[data-array-item]")
    if (!list || !item) return
    const max = this.#bound(list.dataset.max, Number.POSITIVE_INFINITY)
    const items = list.querySelectorAll("[data-array-item]")
    if (items.length >= max) return
    const node = this.#stamp(item.cloneNode(true))
    // cloneNode does not consistently copy live select/textarea state across browsers.
    const controls = item.querySelectorAll("input, textarea, select")
    node.querySelectorAll("input, textarea, select").forEach((el, index) => {
      const source = controls[index]
      if (el.type === "file") return
      if (el.tagName === "SELECT") {
        ;[...el.options].forEach((option, i) => { option.selected = source.options[i].selected })
      } else {
        el.value = source.value
        if (el.type === "radio" || el.type === "checkbox") el.checked = source.checked
      }
    })
    this.#clearTransientFields(node)
    item.insertAdjacentElement("afterend", node)
    node.querySelectorAll("[data-prop]").forEach((el) => this.#refreshFieldChrome(el))
    this.#refreshArrayButtons(list)
    this.#focusItem(node, true)
    this.markDirty()
  }

  moveItemUp(event) {
    const item = event.currentTarget.closest("[data-array-item]")
    const list = event.currentTarget.closest("[data-array]")
    if (!item || !list) return
    const prev = item.previousElementSibling
    if (!prev?.hasAttribute("data-array-item")) return
    prev.insertAdjacentElement("beforebegin", item)
    this.#refreshArrayButtons(list)
    this.#focusMovedItem(event, item)
    this.markDirty()
  }

  moveItemDown(event) {
    const item = event.currentTarget.closest("[data-array-item]")
    const list = event.currentTarget.closest("[data-array]")
    if (!item || !list) return
    const next = item.nextElementSibling
    if (!next?.hasAttribute("data-array-item")) return
    next.insertAdjacentElement("afterend", item)
    this.#refreshArrayButtons(list)
    this.#focusMovedItem(event, item)
    this.markDirty()
  }

  applyHref(event) {
    const field = event.currentTarget.closest("[data-href-field]")
    if (!field) return
    const slug = event.currentTarget.value
    if (!slug) return
    const input = field.querySelector("[data-prop]")
    if (!input) return
    input.value = slug
    this.#syncHrefStatus(field, slug)
    if (field.querySelector("[data-href-toggle]")) {
      this.#setHrefPickerOpen(field, false)
      input.focus()
    }
    this.markDirty()
  }

  toggleHrefPicker(event) {
    const field = event.currentTarget.closest("[data-href-field]")
    const panel = field?.querySelector("[data-href-picker]")
    if (!panel) return
    const open = panel.hidden || panel.classList.contains("hidden")
    this.#setHrefPickerOpen(field, open)
    if (open) panel.querySelector("select")?.focus()
  }

  closeHrefPicker(event) {
    const field = event.currentTarget.closest("[data-href-field]")
    if (!field) return
    this.#setHrefPickerOpen(field, false)
    field.querySelector("[data-href-toggle]")?.focus()
  }

  #setHrefPickerOpen(field, open) {
    const panel = field.querySelector("[data-href-picker]")
    if (panel) {
      panel.hidden = !open
      panel.classList.toggle("hidden", !open)
    }
    field.querySelector("[data-href-toggle]")?.setAttribute("aria-expanded", String(open))
  }

  checkHref(event) {
    const field = event.currentTarget.closest("[data-href-field]")
    if (!field) return
    this.#syncHrefStatus(field, event.currentTarget.value)
    this.#syncHrefPicker(field, event.currentTarget.value)
  }

  previewImage(event) {
    const field = event.currentTarget.closest("[data-image-field]")
    if (!field) return
    this.#cancelUpload(field)
    this.#syncImagePreview(field, event.currentTarget.value)
    this.#refreshAllArrayButtons()
  }

  imageError(event) {
    const field = event.currentTarget.closest("[data-image-field]")
    if (!field) return
    if (field.querySelector("[data-image-failed]")) {
      const value = field.querySelector("[data-prop]")?.value
      if (!value) return
      this.#syncImagePreview(field, value, true)
      if (!this.uploads.has(field)) this.#setImageStatus(field, this.imageLoadFailedValue)
    } else this.#showImageEmpty(field)
  }

  imageLoaded(event) {
    const field = event.currentTarget.closest("[data-image-field]")
    if (!field) return
    this.#syncImagePreview(field, field.querySelector("[data-prop]")?.value)
    if (field.querySelector("[data-image-status]")?.textContent === this.imageLoadFailedValue) this.#setImageStatus(field, "")
  }

  itemImageError(event) {
    event.currentTarget.classList.add("hidden")
  }

  clearImage(event) {
    const field = event.currentTarget.closest("[data-image-field]")
    if (!field) return
    const input = field.querySelector("[data-prop]")
    if (input) input.value = ""
    this.#cancelUpload(field)
    this.#syncImagePreview(field, "")
    this.markDirty()
  }

  allowImageDrop(event) {
    event.preventDefault()
    if (!event.currentTarget.closest("[data-image-field]")) return
  }

  dropImage(event) {
    event.preventDefault()
    const field = event.currentTarget.closest("[data-image-field]")
    if (!field) return
    const file = event.dataTransfer?.files?.[0]
    if (!file) return
    this.#uploadFile(field, file)
  }

  uploadImage(event) {
    const field = event.currentTarget.closest("[data-image-field]")
    if (!field) return
    const file = event.currentTarget.files?.[0]
    if (!file) return
    this.#uploadFile(field, file)
    event.currentTarget.value = ""
  }

  countChars(event) {
    const field = event.currentTarget.closest("[data-count-field]")
    if (!field) return
    this.#syncCharCount(field, event.currentTarget.value)
  }

  resetSection(event) {
    const row = event.currentTarget.closest(ROW_SELECTOR)
    if (!row) return
    if (!window.confirm(this.resetConfirmValue)) return
    let defaults
    try {
      defaults = JSON.parse(row.dataset.sectionDefaults || "{}")
    } catch {
      return
    }
    this.#clearTransientFields(row)
    this.#applyPropsToRow(row, defaults)
    this.#refreshAllArrayButtons()
    this.markDirty()
  }

  toggleAllSections() {
    const details = this.#sectionDetails()
    if (!details.length) return
    const expand = details.some((el) => !el.open)
    details.forEach((el) => { el.open = expand })
    this.#syncToggleAllLabel()
  }

  confirmSetHome(event) {
    const box = event.currentTarget
    if (box.checked && !window.confirm(this.setHomeConfirmValue)) {
      box.checked = false
      return
    }
    this.markDirty()
  }

  setPreviewViewport(event) {
    this.#applyPreviewViewport(event.currentTarget?.dataset?.viewport)
  }

  saveShortcut(event) {
    if (event.key !== "s" && event.key !== "S") return
    if (!(event.metaKey || event.ctrlKey)) return
    if (this.element.tagName !== "FORM") return
    event.preventDefault()
    if (typeof this.element.requestSubmit === "function") {
      this.element.requestSubmit()
      return
    }
    this.element.submit()
  }

  persist(event) {
    if (this.element.tagName !== "FORM" || !this.element.hasAttribute("data-website-workspace")) return
    event?.preventDefault()
    if (this.persisting) return
    this.#persist()
  }

  focusSection(event) {
    const id = event.currentTarget?.dataset?.sectionId
    if (!id || !this.hasRowTarget) return
    const row = this.rowTargets.find((item) => item.dataset.sectionId === id)
    if (!row) return
    this.#applyWorkspacePane("editor")
    if (this.#rail()) {
      this.#showWorkspaceLevel("inspector")
      this.#showRailSection(id, true)
      this.#scrollInspectorTop()
      if (event.currentTarget.dataset.sectionStep) this.#focusSectionTab(id)
      this.#scrollPreviewTo(id, true)
      return
    }
    const details = this.#sectionDetails(row)[0]
    if (details) details.open = true
    if (typeof row.scrollIntoView === "function") row.scrollIntoView({ block: "nearest" })
    this.#syncToggleAllLabel()
    this.#syncSectionNav(id)
    this.#scrollPreviewTo(id, true)
  }

  setWorkspacePane(event) {
    this.#applyWorkspacePane(event.currentTarget?.dataset?.pane)
  }

  showOutline(event) {
    event?.preventDefault?.()
    this.#applyWorkspacePane("editor")
    this.#showWorkspaceLevel("outline")
    const id = this.#currentRailId()
    if (id) this.#focusSectionTab(id)
  }

  focusIdentity(event) {
    event?.preventDefault?.()
    this.#applyWorkspacePane("editor")
    this.#showWorkspaceLevel("identity")
    this.#scrollInspectorTop()
  }

  navigateSectionTabs(event) {
    this.#navigateTabs(event, this.sectionNavTargets, true, !this.#outline())
  }

  navigatePaneTabs(event) {
    this.#navigateTabs(event, this.paneBtnTargets)
  }

  // The outline drills into the inspector on activation, hiding itself, so
  // arrow keys there only move a roving focus; Enter, Space or click opens.
  #navigateTabs(event, tabs, vertical = false, activate = true) {
    const index = tabs.indexOf(event.currentTarget)
    if (index < 0) return
    let next
    switch (event.key) {
      case "ArrowLeft":
      case "ArrowUp":
        if (event.key === "ArrowUp" && !vertical) return
        next = (index + tabs.length - 1) % tabs.length
        break
      case "ArrowRight":
      case "ArrowDown":
        if (event.key === "ArrowDown" && !vertical) return
        next = (index + 1) % tabs.length
        break
      case "Home": next = 0; break
      case "End": next = tabs.length - 1; break
      default: return
    }
    event.preventDefault()
    if (!activate) tabs.forEach((tab, position) => tab.setAttribute("tabindex", position === next ? "0" : "-1"))
    tabs[next].focus({ preventScroll: activate })
    if (activate) tabs[next].click()
  }

  #revealInvalid(control) {
    // Native validation fires for every invalid control before focusing the first.
    // Keep that first control's section visible throughout this validation pass.
    if (this.revealingInvalid) return
    this.revealingInvalid = true
    this.invalidTimer = setTimeout(() => { this.revealingInvalid = false }, 0)
    this.#applyWorkspacePane("editor")
    if (control.closest("[data-identity-panel]")) {
      this.#showWorkspaceLevel("identity")
    } else {
      const row = control.closest(ROW_SELECTOR)
      if (row) this.focusSection({ currentTarget: row })
    }
    for (let parent = control; parent !== this.element; parent = parent.parentElement) {
      if (parent.tagName === "DETAILS") parent.open = true
    }
  }

  #newId() {
    if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
      return `sec_${crypto.randomUUID()}`
    }
    this.seq = (this.seq || 0) + 1
    return `sec_${Date.now()}_${this.seq}`
  }

  #cloneElements(node) {
    const elements = [node, ...node.querySelectorAll("*")]
    return elements.flatMap((el) => el.tagName === "TEMPLATE"
      ? [el, ...[...el.content.children].flatMap((child) => this.#cloneElements(child))]
      : [el])
  }

  #rewritePlaceholder(node, id, placeholder = PLACEHOLDER_ID) {
    this.#cloneElements(node).forEach((el) => {
      ;["id", "data-section-id", "name", ...IDREF_ATTRIBUTES].forEach((attr) => {
        const current = el.getAttribute(attr)
        if (current?.includes(placeholder)) el.setAttribute(attr, current.replaceAll(placeholder, id))
      })
    })
  }

  #closeKit() {
    if (this.hasKitTarget) this.kitTarget.classList.add("hidden")
    const btn = this.element.querySelector("[data-kit-toggle]")
    if (btn) btn.setAttribute("aria-expanded", "false")
  }

  #syncEmpty() {
    if (!this.hasEmptyTarget) return
    const hasRows = this.hasRowTarget && this.rowTargets.length > 0
    this.emptyTarget.classList.toggle("hidden", hasRows)
  }

  #refreshMoveButtons() {
    this.#syncWorkspaceSections()
    if (!this.hasRowTarget) return
    this.rowTargets.forEach((row, idx, rows) => {
      const up = row.querySelector("[data-action='click->website-builder#moveUp']")
      const down = row.querySelector("[data-action='click->website-builder#moveDown']")
      if (up) up.disabled = idx === 0
      if (down) down.disabled = idx === rows.length - 1
    })
  }

  #refreshAllArrayButtons() {
    this.element.querySelectorAll("[data-array]").forEach((list) => this.#refreshArrayButtons(list))
  }

  #refreshArrayButtons(list) {
    const items = list.querySelectorAll("[data-array-item]")
    const min = this.#bound(list.dataset.min, 0)
    const max = this.#bound(list.dataset.max, Number.POSITIVE_INFINITY)
    const addBtn = list.querySelector("[data-add-item]")
    if (addBtn) addBtn.disabled = items.length >= max
    const count = list.querySelector("[data-array-count]")
    if (count) count.textContent = String(items.length)
    const limit = list.querySelector("[data-array-limit]")
    if (limit) limit.textContent = Number.isFinite(max)
      ? this.arrayLimitFormatValue.replace("{count}", String(items.length)).replace("{max}", String(max)) : ""
    list.querySelectorAll("[data-remove-item]").forEach((btn) => {
      btn.disabled = items.length <= min
    })
    items.forEach((item, idx) => {
      const up = item.querySelector("[data-action='click->website-builder#moveItemUp']")
      const down = item.querySelector("[data-action='click->website-builder#moveItemDown']")
      const duplicate = item.querySelector("[data-duplicate-item]")
      const remove = item.querySelector("[data-remove-item]")
      if (up) up.disabled = idx === 0
      if (down) down.disabled = idx === items.length - 1
      if (duplicate) duplicate.disabled = items.length >= max
      const number = String(idx + 1)
      const ordinal = item.querySelector("[data-item-number]")
      if (ordinal) ordinal.textContent = number
      const titleInput = [...item.querySelectorAll("[data-prop]")].find((el) => el.dataset.prop === list.dataset.itemTitleKey)
      const title = titleInput?.value.trim() || this.itemLabelFormatValue.replace("{number}", number)
      const summary = item.querySelector("[data-item-title]")
      if (summary) summary.textContent = title
      Object.entries({ up, down, duplicate, remove }).forEach(([action, button]) => {
        if (button) button.setAttribute("aria-label", this.itemActionFormatValue
          .replace("{action}", this.itemActionsValue[action]).replace("{number}", number).replace("{title}", () => title))
      })
      const image = item.querySelector("[data-item-image]")
      if (image) {
        const value = item.querySelector("[data-image-field] [data-prop]")?.value || ""
        if (this.#validMedia(value)) {
          if (image.getAttribute("src") !== value.trim()) {
            image.src = value.trim()
            image.classList.remove("hidden")
          }
        } else {
          image.removeAttribute("src")
          image.classList.add("hidden")
        }
      }
    })
  }

  #focusItem(item, editing = false) {
    if (editing && item.tagName === "DETAILS") item.open = true
    const input = item.querySelector("input:not([type='hidden']):not([type='radio']):not([type='file']), textarea")
    const target = !editing && item.tagName === "DETAILS" ? item.querySelector("summary") : input
    target?.focus()
  }

  #focusMovedItem(event, item) {
    if (event.currentTarget.disabled) this.#focusItem(item)
    else event.currentTarget.focus()
  }

  #bound(raw, fallback) {
    const n = Number(raw)
    return Number.isFinite(n) ? n : fallback
  }

  #syncJson() {
    if (!this.hasJsonTarget) return
    const sections = this.hasRowTarget
      ? this.rowTargets.map((row) => ({
          id: row.dataset.sectionId || "",
          type: row.dataset.sectionType || "",
          props: this.#propsFromRow(row)
        }))
      : []
    this.jsonTarget.value = JSON.stringify(sections)
  }

  #propsFromRow(row) {
    const props = {}
    row.querySelectorAll("[data-prop]").forEach((el) => {
      if (el.closest("[data-array-item]") || el.closest("[data-array]")) return
      if (!this.#controlIncluded(el)) return
      props[el.dataset.prop] = el.value
    })
    row.querySelectorAll("[data-array]").forEach((list) => {
      const key = list.dataset.array
      if (!key) return
      props[key] = [...list.querySelectorAll("[data-array-item]")].map((item) => {
        const obj = {}
        item.querySelectorAll("[data-prop]").forEach((el) => {
          if (!this.#controlIncluded(el)) return
          obj[el.dataset.prop] = el.value
        })
        return obj
      })
    })
    const styles = this.#stylesFromRow(row)
    if (Object.keys(styles).length) props.styles = styles
    return props
  }

  #stylesFromRow(row) {
    const styles = {}
    row.querySelectorAll("[data-style-target]").forEach((group) => {
      const attrs = this.#styleValues(group)
      if (Object.keys(attrs).length) styles[group.dataset.styleTarget] = attrs
    })
    return styles
  }

  #styleValues(group) {
    const attrs = {}
    group.querySelectorAll("[data-style-prop]").forEach((el) => {
      if (!this.#controlIncluded(el) || !el.value) return
      attrs[el.dataset.styleProp] = el.value
    })
    return attrs
  }

  #syncStyleDots() {
    this.element.querySelectorAll("[data-style-target]").forEach((group) => {
      const dot = group.querySelector("[data-style-dot]")
      if (dot) dot.classList.toggle("hidden", !this.#styleEdited(group))
    })
    this.element.querySelectorAll("[data-style-panel]").forEach((panel) => {
      const edited = [...panel.querySelectorAll("[data-style-target]")].some((group) => this.#styleEdited(group))
      this.#styleTriggers(panel).forEach((trigger) => trigger.toggleAttribute("data-edited", edited))
    })
  }

  #styleEdited(group) {
    return Object.keys(this.#styleValues(group)).length > 0
  }

  #styleTriggers(panel) {
    return [...this.element.querySelectorAll(`[data-style-trigger][aria-controls="${this.#attrEscape(panel.id)}"]`)]
  }

  #openStylePanel(panel) {
    panel.hidden = false
    this.#styleTriggers(panel).forEach((trigger) => trigger.setAttribute("aria-expanded", "true"))
    for (let details = panel.closest("details:not([open])"); details; details = details.closest("details:not([open])")) {
      details.open = true
    }
  }

  #controlIncluded(el) {
    return el.type !== "radio" || el.checked
  }

  #setControlValue(el, value) {
    const next = value == null ? "" : String(value)
    if (el.type === "radio") {
      el.checked = el.value === next
      return
    }
    el.value = next
  }

  #httpsUrl(value) {
    try {
      const url = new URL(String(value).trim())
      return url.protocol === "https:" && Boolean(url.hostname)
    } catch {
      return false
    }
  }

  #validHref(value) {
    const raw = String(value || "")
    // Match Websites::Href before trim/URL parsing can normalize an escape.
    if ([...raw].some(unsafeHrefCharacter)) return false
    const s = raw.trim()
    if (!s) return true
    return SLUG.test(s) || ROOT_RELATIVE.test(s) || this.#httpsUrl(s)
  }

  #validMedia(value) {
    const raw = String(value || "")
    // Match Websites::Href's bundled SVG and photo paths on the whole raw value.
    if (/^\/site-images\/anysys\/anysys-[a-z0-9-]+\.svg$/.test(raw)) return true
    if (/^\/site-images\/anysys\/anysys-photo-[a-z0-9-]+\.webp$/.test(raw)) return true
    const s = raw.trim()
    return this.#httpsUrl(s) || this.#mediaPath(s)
  }

  #mediaPath(value) {
    return /^\/\d{8}\/site\/media\/[^/]+$/.test(String(value || "").trim())
  }

  #syncHrefStatus(field, value) {
    const status = field.querySelector("[data-href-status]")
    const ok = this.#validHref(value)
    if (status) status.classList.toggle("hidden", ok)
    const input = field.querySelector("[data-prop]")
    if (input) {
      input.setAttribute("aria-invalid", ok ? "false" : "true")
      if (this.element.hasAttribute("data-website-workspace") && status) {
        input.setCustomValidity(ok ? "" : status.textContent.trim())
      }
    }
  }

  #syncHrefPicker(field, value) {
    const select = field.querySelector("select[data-action~='change->website-builder#applyHref']")
    if (!select) return
    const match = [...select.options].some((opt) => opt.value === value)
    select.value = match ? value : ""
  }

  #syncImagePreview(field, value, failed = false) {
    const img = field.querySelector("[data-image-preview]")
    const empty = field.querySelector("[data-image-empty]")
    const ok = this.#validMedia(value) && !failed
    const compact = field.querySelector("[data-image-failed]")
    const present = Boolean(String(value || "").trim())
    if (img) {
      if (ok) {
        if (img.getAttribute("src") !== String(value).trim()) img.src = String(value).trim()
        img.classList.remove("hidden")
      } else {
        img.removeAttribute("src")
        img.classList.add("hidden")
      }
    }
    if (empty) empty.classList.toggle("hidden", compact ? present : ok)
    const add = field.querySelector("[data-image-add]")
    const replace = field.querySelector("[data-image-replace]")
    if (add) add.classList.toggle("hidden", compact ? present : ok)
    if (replace) replace.classList.toggle("hidden", compact ? !present : !ok)
    if (compact) compact.classList.toggle("hidden", !present || ok)
    field.querySelector("[data-image-present]")?.classList.toggle("hidden", !ok)
    field.querySelector("[data-image-clear]")?.classList.toggle("hidden", !present)
  }

  #showImageEmpty(field) {
    const img = field.querySelector("[data-image-preview]")
    const empty = field.querySelector("[data-image-empty]")
    if (img) {
      img.classList.add("hidden")
      img.removeAttribute("src")
    }
    if (empty) empty.classList.remove("hidden")
    const add = field.querySelector("[data-image-add]")
    const replace = field.querySelector("[data-image-replace]")
    if (add) add.classList.remove("hidden")
    if (replace) replace.classList.add("hidden")
  }

  #syncCharCount(field, value) {
    const node = field.querySelector("[data-char-count]")
    if (!node) return
    node.textContent = this.charCountFormatValue.replace("{count}", String((value || "").length))
  }

  #refreshFieldChrome(el) {
    const hrefField = el.closest("[data-href-field]")
    if (hrefField) {
      this.#syncHrefStatus(hrefField, el.value)
      this.#syncHrefPicker(hrefField, el.value)
    }
    const imageField = el.closest("[data-image-field]")
    if (imageField) this.#syncImagePreview(imageField, el.value)
    const countField = el.closest("[data-count-field]")
    if (countField) this.#syncCharCount(countField, el.value)
  }

  #applyPropsToRow(row, props) {
    const source = props && typeof props === "object" && !Array.isArray(props) ? props : {}
    row.querySelectorAll("[data-prop]").forEach((el) => {
      if (el.closest("[data-array]")) return
      this.#setControlValue(el, source[el.dataset.prop])
      this.#refreshFieldChrome(el)
    })
    row.querySelectorAll("[data-array]").forEach((list) => {
      const key = list.dataset.array
      this.#replaceArrayItems(list, Array.isArray(source[key]) ? source[key] : [])
    })
  }

  #replaceArrayItems(list, items) {
    const mount = list.querySelector("[data-array-list]") || list
    mount.querySelectorAll("[data-array-item]").forEach((item) => item.remove())
    const template = list.querySelector("template[data-item-template]")
    const source = template?.content?.firstElementChild
    if (!source) {
      this.#refreshArrayButtons(list)
      return
    }
    const min = this.#bound(list.dataset.min, 0)
    const next = items.slice()
    while (next.length < min) next.push({})
    next.forEach((raw, index) => {
      const node = this.#stamp(source.cloneNode(true))
      if (node.tagName === "DETAILS") node.open = index === 0
      const obj = raw && typeof raw === "object" ? raw : {}
      node.querySelectorAll("[data-prop]").forEach((el) => {
        this.#setControlValue(el, obj[el.dataset.prop])
        this.#refreshFieldChrome(el)
      })
      mount.appendChild(node)
    })
    this.#refreshArrayButtons(list)
  }

  #sectionDetails(row) {
    if (this.element.hasAttribute("data-website-workspace") || this.#rail()) return []
    const rows = row ? [row] : this.rowTargets
    return rows.flatMap((item) => [...item.querySelectorAll("details[class~='group/section']")])
  }

  #syncToggleAllLabel() {
    if (!this.hasToggleAllTarget) return
    const details = this.#sectionDetails()
    const anyClosed = details.length === 0 || details.some((el) => !el.open)
    this.toggleAllTarget.textContent = anyClosed ? this.expandAllValue : this.collapseAllValue
  }

  #applyPreviewViewport(viewport) {
    const widths = { desktop: "100%", tablet: "768px", mobile: "390px" }
    const next = widths[viewport] ? viewport : "desktop"
    if (this.hasPreviewStageTarget) {
      this.previewStageTarget.style.maxWidth = widths[next]
      this.previewStageTarget.dataset.viewport = next
    }
    if (!this.hasViewportBtnTarget) return
    this.viewportBtnTargets.forEach((btn) => {
      btn.setAttribute("aria-pressed", String(btn.dataset.viewport === next))
    })
  }

  #applyWorkspacePane(pane) {
    const next = pane === "preview" ? "preview" : "editor"
    if (this.hasEditorPaneTarget) {
      this.editorPaneTarget.classList.toggle("max-xl:hidden", next !== "editor")
    }
    if (this.hasPreviewPaneTarget) {
      this.previewPaneTarget.classList.toggle("max-xl:hidden", next !== "preview")
    }
    if (!this.hasPaneBtnTarget) return
    this.paneBtnTargets.forEach((btn) => {
      const selected = btn.dataset.pane === next
      btn.setAttribute("aria-pressed", String(selected))
      btn.setAttribute("aria-selected", String(selected))
      btn.tabIndex = selected ? 0 : -1
    })
  }

  #setUnsavedVisible(visible) {
    if (!this.hasUnsavedTarget) return
    this.unsavedTargets.forEach((el) => el.classList.toggle("hidden", !visible))
  }

  #stamp(node) {
    const stamp = this.#newId().replace(/[^a-z0-9]/gi, "")
    const elements = this.#cloneElements(node)
    const ids = new Map(elements.filter((el) => el.id).map((el) => [el.id, `${el.id}_${stamp}`]))
    elements.forEach((el) => {
      ;["id", "name"].forEach((attr) => {
        const current = el.getAttribute(attr)
        if (current) el.setAttribute(attr, `${current}_${stamp}`)
      })
      IDREF_ATTRIBUTES.forEach((attr) => {
        const current = el.getAttribute(attr)
        if (current) el.setAttribute(attr, current.replace(/\S+/g, (id) => ids.get(id) || id))
      })
    })
    return node
  }

  #syncSectionPreviews() {
    if (!this.hasSectionNavTarget) return
    const tabs = new Map(this.sectionNavTargets.map((btn) => [btn.dataset.sectionId, btn]))
    this.rowTargets.forEach((row) => {
      const tab = tabs.get(row.dataset.sectionId)
      if (tab) this.#syncSectionPreview(row, tab)
    })
  }

  #syncSectionPreview(row, tab) {
    const preview = tab.querySelector("[data-section-preview]")
    if (!preview) return
    let text = ""
    for (const key of PREVIEW_PROPS) {
      const input = row.querySelector(`[data-prop="${key}"]`)
      const value = input?.value?.trim()
      if (value) {
        text = value
        break
      }
    }
    preview.textContent = text
    preview.classList.toggle("hidden", !text)
  }

  #scrollPreviewTo(id, force = false) {
    if (!id) return
    const changed = this.previewAnchor !== id
    this.previewAnchor = id
    if (force || changed) this.#scrollPreviewAnchor()
  }

  #scrollPreviewAnchor() {
    if (!this.previewAnchor || !this.hasPreviewFrameTarget) return
    const doc = this.#previewDocument()
    if (!doc) return
    const node = doc.querySelector(this.#previewSectionSelector(this.previewAnchor))
    if (!node || typeof node.scrollIntoView !== "function") return
    node.scrollIntoView({ block: "start", behavior: "smooth" })
  }

  #previewDocument() {
    try {
      return this.previewFrameTarget.contentDocument
    } catch {
      return null
    }
  }

  #previewSectionSelector(id) {
    return `[data-site-section="${this.#attrEscape(id)}"]`
  }

  #attrEscape(value) {
    return String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
  }

  // Clicking a marked element in the preview opens its Design panel.
  #bindPreviewPicking() {
    const doc = this.#previewDocument()
    if (!doc || doc.documentElement.dataset.websiteBuilderPicking) return
    doc.documentElement.dataset.websiteBuilderPicking = "true"
    doc.addEventListener("click", (event) => this.#pickFromPreview(event), true)
  }

  #pickFromPreview(event) {
    const el = event.target?.closest?.("[data-site-el]")
    const section = el?.closest("[data-site-section]")
    if (!section) return
    const id = section.dataset.siteSection
    const row = this.rowTargets.find((item) => item.dataset.sectionId === id)
    const group = row?.querySelector(`[data-style-target="${this.#attrEscape(el.dataset.siteEl)}"]`)
    if (!group) return
    event.preventDefault()
    event.stopPropagation()
    this.focusSection({ currentTarget: { dataset: { sectionId: id } } })
    this.#openStylePanel(group.closest("[data-style-panel]"))
    if (group.tagName === "DETAILS") group.open = true
    group.scrollIntoView?.({ block: "nearest" })
    group.querySelector("summary, input:checked, select")?.focus()
    this.#highlightPreviewElement(el)
  }

  #highlightPreviewElement(el) {
    if (this.highlightedPreviewElement) this.highlightedPreviewElement.style.outline = ""
    el.style.outline = `2px solid ${this.highlightColorValue}`
    el.style.outlineOffset = "4px"
    this.highlightedPreviewElement = el
  }

  #activeSectionId() {
    return document.activeElement?.closest?.("[data-section-id]")?.dataset?.sectionId || ""
  }

  #syncSectionNav(id, scroll = false) {
    if (!this.hasSectionNavTarget) return
    this.sectionNavTargets.forEach((btn) => {
      const selected = btn.dataset.sectionId === id
      btn.setAttribute("aria-current", String(selected))
      if (this.#rail()) {
        btn.setAttribute("aria-selected", String(selected))
        btn.tabIndex = selected ? 0 : -1
        if (selected && scroll && typeof btn.scrollIntoView === "function") {
          btn.scrollIntoView({ block: "nearest", inline: "nearest" })
        }
      }
    })
  }

  #rail() {
    return this.element.querySelector("[data-workspace-rail]")
  }

  #outline() {
    return this.element.querySelector("[data-workspace-outline]")
  }

  #detail() {
    return this.element.querySelector("[data-workspace-detail]")
  }

  #currentRailId() {
    return this.rowTargets.find((row) => !row.classList.contains("hidden"))?.dataset?.sectionId || ""
  }

  #showWorkspaceLevel(level) {
    const outline = this.#outline()
    const detail = this.#detail()
    if (!outline || !detail) return
    const showOutline = level === "outline"
    outline.classList.toggle("hidden", !showOutline)
    detail.classList.toggle("hidden", showOutline)
    const identity = this.element.querySelector("[data-identity-panel]")
    if (identity) {
      identity.classList.toggle("hidden", level !== "identity")
      if (identity.tagName === "DETAILS") identity.open = level === "identity"
    }
    const identityNav = this.element.querySelector("[data-workspace-identity-nav]")
    if (identityNav) identityNav.setAttribute("aria-current", String(level === "identity"))
    if (level === "identity") {
      this.rowTargets.forEach((row) => row.classList.add("hidden"))
    }
  }

  #syncWorkspaceSections() {
    if (!this.#rail()) return
    const rows = this.rowTargets
    const nav = this.element.querySelector("[data-workspace-section-nav]")
    const source = this.element.querySelector("template[data-section-nav-template]")?.content.firstElementChild
    const tabs = new Map(this.sectionNavTargets.map((btn) => [btn.dataset.sectionId, btn]))
    tabs.forEach((btn, id) => {
      if (!rows.some((row) => row.dataset.sectionId === id)) btn.remove()
    })
    rows.forEach((row, index) => {
      const id = row.dataset.sectionId
      row.id = `website-section-panel-${id}`
      row.setAttribute("role", "tabpanel")
      row.setAttribute("aria-labelledby", `website-section-tab-${id}`)
      let tab = tabs.get(id)
      if (!tab && nav && source) {
        tab = source.cloneNode(true)
        this.#rewritePlaceholder(tab, id, "SECTION_ID")
      }
      if (!tab) return
      tab.id = `website-section-tab-${id}`
      tab.setAttribute("role", "tab")
      tab.setAttribute("aria-controls", row.id)
      const number = tab.querySelector("[data-section-number]")
      const label = tab.querySelector("[data-section-label]")
      if (number) number.textContent = String(index + 1)
      if (label) label.textContent = row.dataset.sectionLabel || ""
      this.#syncSectionPreview(row, tab)
      if (nav) nav.appendChild(tab)
    })
    if (!rows.length) {
      this.#showWorkspaceLevel("outline")
      return
    }
    const current = this.rowTargets.find((row) => !row.classList.contains("hidden")) || this.rowTargets[0]
    this.#showRailSection(current.dataset.sectionId)
  }

  #scrollInspectorTop() {
    this.element.querySelector("[data-workspace-inspector]")?.scrollTo({ top: 0 })
  }

  #focusSectionTab(id) {
    const tab = this.sectionNavTargets.find((btn) => btn.dataset.sectionId === id)
    if (tab) tab.focus({ preventScroll: true })
  }

  #showRailSection(id, scroll = false) {
    this.rowTargets.forEach((row) => {
      row.classList.toggle("hidden", row.dataset.sectionId !== id)
    })
    this.#syncSectionNav(id, scroll)
  }

  #setImageStatus(field, message) {
    const status = field.querySelector("[data-image-status]")
    if (!status) return
    status.textContent = message || ""
    status.classList.toggle("hidden", !message)
  }

  #setImageBusy(field, busy) {
    field.setAttribute("aria-busy", String(busy))
    field.querySelectorAll("input[type='file']").forEach((input) => { input.disabled = busy })
  }

  #cancelUpload(field) {
    this.uploads.get(field)?.abort()
    this.uploads.delete(field)
    this.#setImageBusy(field, false)
    field.querySelectorAll("input[type='file']").forEach((input) => { input.value = "" })
    this.#setImageStatus(field, "")
  }

  #clearTransientFields(root) {
    root.querySelectorAll("[data-item-image]").forEach((image) => image.removeAttribute("src"))
    root.querySelectorAll("[data-image-field]").forEach((field) => this.#cancelUpload(field))
    root.querySelectorAll("[data-href-field]").forEach((field) => this.#setHrefPickerOpen(field, false))
  }

  async #uploadFile(field, file) {
    if (this.uploads.has(field)) return
    if (!this.uploadUrlValue) {
      this.#setImageStatus(field, this.uploadFailedValue)
      return
    }
    const upload = new AbortController()
    this.uploads.set(field, upload)
    const current = () => this.uploads.get(field) === upload && this.element.contains(field)
    this.#setImageBusy(field, true)
    this.#setImageStatus(field, this.uploadingValue)
    const body = new FormData()
    body.append("file", file)
    try {
      const res = await fetch(this.uploadUrlValue, {
        method: "POST",
        signal: upload.signal,
        body,
        headers: {
          "X-CSRF-Token": getCSRFToken(),
          Accept: "application/json"
        }
      })
      let payload = {}
      try {
        payload = await res.json()
      } catch {
        payload = {}
      }
      if (!current()) return
      if (!res.ok || !payload.url) {
        this.#setImageStatus(field, payload.error || this.uploadFailedValue)
        return
      }
      const input = field.querySelector("[data-prop]")
      if (input) input.value = payload.url
      this.#syncImagePreview(field, payload.url)
      this.#setImageStatus(field, "")
      this.markDirty()
    } catch {
      if (current()) this.#setImageStatus(field, this.uploadFailedValue)
    } finally {
      if (this.uploads.get(field) === upload) {
        this.uploads.delete(field)
        this.#setImageBusy(field, false)
      }
    }
  }

  #scheduleLivePreview() {
    if (this.element.tagName !== "FORM" || !this.hasPreviewFrameTarget) return
    // Invalidate immediately on edit, including while the next draft is debouncing.
    this.previewRevision += 1
    clearTimeout(this.liveTimer)
    this.liveTimer = setTimeout(() => this.#pushLivePreview(), this.livePreviewMsValue)
  }

  async #pushLivePreview() {
    if (!this.hasPreviewFrameTarget) return
    const frame = this.previewFrameTarget
    const url = frame.dataset.draftUrl
    if (!url) return
    const revision = this.previewRevision
    if (this.hasPreviewLoadingTarget) this.previewLoadingTarget.classList.remove("hidden")
    try {
      const body = new FormData(this.element)
      body.delete("_method")
      body.set("embed", "1")
      const res = await fetch(url, {
        method: "POST",
        body,
        headers: {
          "X-CSRF-Token": getCSRFToken(),
          Accept: "text/html",
          "X-Website-Composer": "1"
        }
      })
      if (!res.ok) {
        if (revision === this.previewRevision) this.previewLoaded()
        return
      }
      const html = await res.text()
      if (revision !== this.previewRevision) return
      frame.srcdoc = this.#srcdocWithBase(html)
    } catch {
      if (revision === this.previewRevision) this.previewLoaded()
    }
  }

  #srcdocWithBase(html) {
    const source = String(html || "")
    if (/<base\b/i.test(source)) return source
    return source.replace(/<head([^>]*)>/i, `<head$1><base href="${window.location.origin}/">`)
  }

  async #persist() {
    this.persisting = true
    this.#syncJson()
    try {
      const res = await fetch(this.element.action, {
        method: "POST",
        body: new FormData(this.element),
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": getCSRFToken(),
          "X-Website-Composer": "1"
        }
      })
      if (!res.ok) return
      this.#setUnsavedVisible(false)
      this.reloadPreview()
    } catch {
      return
    } finally {
      this.persisting = false
    }
  }
}
