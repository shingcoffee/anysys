import { Controller } from "@hotwired/stimulus"
import { getCSRFToken, escapeHtml } from "utils"
import { versionDiff } from "versions/version_diff"

// Resource-agnostic version-history modal. Renders versions as a table and
// offers: open a version in the editor (new tab), set a version as default,
// and a raw JSON side-by-side diff (client-side) of any two versions.
// The resource type (e.g. "flowcharts") is provided via the `resource` value
// and the parent record id/name are supplied at open time via action params.
export default class extends Controller {
  static targets = [
    "modal", "title", "count", "listView", "list", "scroll", "content", "diffButton",
    "clearButton", "selectionInfo", "hint", "error", "errorMessage",
    "pagination", "pageInfo", "prevButton", "nextButton"
  ]
  static values = {
    customerId: String, resource: String,
    pathPrefix: { type: String, default: "admin/maintenance" },

    // ── i18n seam: English defaults keep JS specs green without any
    // data-*-value attribute; the resource index view supplies translated
    // strings via data-versions-<name>-value="<%= t(...) %>". ──
    itemFallbackLabel: { type: String, default: "Item" },
    countSingularFormat: { type: String, default: " · {count} version" },
    countPluralFormat: { type: String, default: " · {count} versions" },
    cannotSetDefaultMsg: { type: String, default: "Cannot set default while the resource is active. Deactivate it first." },
    sharedOwnerOnlyMsg: { type: String, default: "Shared resources can only be changed from Shared Resources." },
    setDefaultFailedFormat: { type: String, default: "Failed to set default ({status})" },
    deleteConfirmFormat: { type: String, default: "Delete version v{version}? This permanently removes the snapshot and cannot be undone." },
    cannotDeleteMsg: { type: String, default: "This version can't be deleted." },
    deleteFailedFormat: { type: String, default: "Failed to delete version ({status})" },
    loadVersionsFailedFormat: { type: String, default: "Failed to load versions ({status})" },
    loadVersionFailedFormat: { type: String, default: "Failed to load version ({status})" },
    networkErrorFormat: { type: String, default: "Network error: {message}" },
    emptyTitleLabel: { type: String, default: "No versions yet." },
    emptyHintLabel: { type: String, default: "Versions appear here as you save changes." },
    defaultBadgeLabel: { type: String, default: "Default" },
    latestBadgeLabel: { type: String, default: "Latest" },
    noDescriptionLabel: { type: String, default: "No description" },
    setDefaultButtonLabel: { type: String, default: "Set default" },
    deleteButtonLabel: { type: String, default: "Delete" },
    openButtonLabel: { type: String, default: "Open" },
    createPageButtonLabel: { type: String, default: "Create page" },
    createPageFailedFormat: { type: String, default: "Failed to create page ({status})" },
    paginationRangeFormat: { type: String, default: "{start}–{end} of {total}" },
    backButtonLabel: { type: String, default: "Back" },
    addedCountFormat: { type: String, default: "+{count} added" },
    removedCountFormat: { type: String, default: "−{count} removed" },
    selectTwoHintLabel: { type: String, default: "Select two versions to compare them." },
    oneSelectedHintLabel: { type: String, default: "1 version selected — pick one more to compare." },
    twoSelectedHintLabel: { type: String, default: "2 versions selected." },
    readyToCompareLabel: { type: String, default: "Ready to compare" },
    pickMoreFormat: { type: String, default: "Pick {count} to compare" }
  }

  PER_PAGE = 10

  connect() {
    this.parentId = null
    this.parentName = null
    this.versions = []
    this.selected = [] // selected version ids (max 2)
    this.page = 1
  }

  open(event) {
    if (event) event.preventDefault()
    const params = event?.params || {}
    this.parentId = params.id
    this.parentName = params.name || this.itemFallbackLabelValue
    this.selected = []
    this.page = 1
    if (this.hasTitleTarget) this.titleTarget.textContent = this.parentName
    if (this.hasCountTarget) this.countTarget.textContent = ""
    this._clearError()
    this._showListView()
    this._renderLoading()
    this.modalTarget.classList.remove("hidden")
    document.documentElement.classList.add("overflow-hidden")
    this.loadVersions()
    this._updateButtons()
  }

  close(event) {
    if (event) event.preventDefault()
    this.modalTarget.classList.add("hidden")
    document.documentElement.classList.remove("overflow-hidden")
    this._showListView()
    if (this.hasContentTarget) this.contentTarget.innerHTML = ""
  }

  async loadVersions(preservePage = false) {
    const res = await this._fetch(this._base(), { headers: { Accept: "application/json" } })
    if (!res) return
    if (!res.ok) return this._error(this.loadVersionsFailedFormatValue.replace("{status}", res.status))
    this.versions = await res.json()
    if (!preservePage) this.page = 1
    if (this.hasCountTarget) {
      this.countTarget.textContent = this.versions.length
        ? (this.versions.length === 1 ? this.countSingularFormatValue : this.countPluralFormatValue).replace("{count}", this.versions.length)
        : ""
    }
    this._renderList()
    this._updateButtons()
  }

  toggleSelect(event) {
    if (event) event.preventDefault()
    const id = String(event.params.id)
    const idx = this.selected.indexOf(id)
    if (idx >= 0) {
      this.selected.splice(idx, 1)
    } else {
      this.selected.push(id)
      if (this.selected.length > 2) this.selected.shift() // keep last two
    }
    this._renderList()
    this._updateButtons()
  }

  clearSelection(event) {
    if (event) event.preventDefault()
    this.selected = []
    this._showListView()
    this._renderList()
    this._updateButtons()
  }

  view(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }
    const id = String(event.params.id)
    window.open(`${this._base()}/${id}/edit`, "_blank")
  }

  async createPage(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }
    const id = String(event.params.id)
    const res = await this._fetch(`${this._base()}/${id}/page.json`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": getCSRFToken(), Accept: "application/json" }
    })
    if (!res) return
    if (res.status === 422) {
      const body = await res.json().catch(() => ({}))
      return this._error(body.message || this.createPageFailedFormatValue.replace("{status}", res.status))
    }
    if (res.status === 403) return this._error(this.sharedOwnerOnlyMsgValue)
    if (!res.ok) return this._error(this.createPageFailedFormatValue.replace("{status}", res.status))
    const body = await res.json().catch(() => ({}))
    this._clearError()
    if (body.url) {
      window.location.assign(body.url)
      return
    }
    await this.loadVersions(true)
  }

  async setDefault(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }
    const id = String(event.params.id)
    const res = await this._fetch(`${this._base()}/${id}/default.json`, {
      method: "PUT",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": getCSRFToken(), Accept: "application/json" }
    })
    if (!res) return
    if (res.status === 422) {
      const body = await res.json().catch(() => ({}))
      return this._error(body.message || this.cannotSetDefaultMsgValue)
    }
    if (res.status === 403) return this._error(this.sharedOwnerOnlyMsgValue)
    if (!res.ok) return this._error(this.setDefaultFailedFormatValue.replace("{status}", res.status))
    this._clearError()
    // Close the modal and refresh the list so the new default version shows
    // in the resource's "Versions" column without a full page reload.
    this.close()
    this._refreshList()
  }

  async destroy(event) {
    if (event) { event.preventDefault(); event.stopPropagation() }
    const id = String(event.params.id)
    const versionNumber = event.params.version
    if (!window.confirm(this.deleteConfirmFormatValue.replace("{version}", versionNumber))) return
    const res = await this._fetch(`${this._base()}/${id}.json`, {
      method: "DELETE",
      headers: { "X-CSRF-Token": getCSRFToken(), Accept: "application/json" }
    })
    if (!res) return
    if (res.status === 422) {
      const body = await res.json().catch(() => ({}))
      return this._error(body.message || this.cannotDeleteMsgValue)
    }
    if (res.status === 403) return this._error(this.sharedOwnerOnlyMsgValue)
    if (!res.ok) return this._error(this.deleteFailedFormatValue.replace("{status}", res.status))
    this._clearError()
    // Drop the removed version from any pending comparison selection.
    this.selected = this.selected.filter((s) => s !== id)
    await this.loadVersions(true) // keep the current page
  }

  async diff(event) {
    if (event) event.preventDefault()
    if (this.selected.length !== 2) return
    const [a, b] = this.selected
    const [va, vb] = await Promise.all([this._showVersion(a), this._showVersion(b)])
    if (!va || !vb) return
    this._renderDiff(va, vb)
    this._showDiffView()
  }

  backToList(event) {
    if (event) event.preventDefault()
    this._showListView()
  }

  prevPage(event) {
    if (event) event.preventDefault()
    if (this.page > 1) { this.page--; this._renderList(); this._scrollTop() }
  }

  nextPage(event) {
    if (event) event.preventDefault()
    if (this.page < this._totalPages()) { this.page++; this._renderList(); this._scrollTop() }
  }

  // ---- private ----

  _base() {
    return `/${this.customerIdValue}/${this.pathPrefixValue}/${this.resourceValue}/${this.parentId}/versions`
  }

  async _showVersion(id) {
    const res = await this._fetch(`${this._base()}/${id}.json`, { headers: { Accept: "application/json" } })
    if (!res) return null
    if (!res.ok) { this._error(this.loadVersionFailedFormatValue.replace("{status}", res.status)); return null }
    return res.json()
  }

  async _fetch(url, opts) {
    try { return await fetch(url, opts) }
    catch (e) { this._error(this.networkErrorFormatValue.replace("{message}", e.message)); return null }
  }

  _showListView() {
    if (this.hasListViewTarget) this.listViewTarget.classList.remove("hidden")
    if (this.hasContentTarget) this.contentTarget.classList.add("hidden")
  }

  _showDiffView() {
    if (this.hasListViewTarget) this.listViewTarget.classList.add("hidden")
    if (this.hasContentTarget) this.contentTarget.classList.remove("hidden")
  }

  _renderLoading() {
    if (!this.hasListTarget) return
    const bar = (w) => `<div class="h-4 ${w} animate-shimmer rounded"></div>`
    const row = `
      <tr>
        <td class="py-3 pl-5 pr-3">${bar("w-6")}</td>
        <td class="px-3 py-3">${bar("w-10")}</td>
        <td class="hidden px-3 py-3 md:table-cell">${bar("w-10")}</td>
        <td class="px-3 py-3">${bar("w-16")}</td>
        <td class="hidden px-3 py-3 sm:table-cell">${bar("w-3/4")}</td>
        <td class="hidden px-3 py-3 md:table-cell">${bar("w-28")}</td>
        <td class="py-3 pl-3 pr-5"><div class="ml-auto">${bar("w-24")}</div></td>
      </tr>`
    this.listTarget.innerHTML = row.repeat(5)
  }

  _renderList() {
    if (!this.hasListTarget) return
    if (this.versions.length === 0) {
      this.listTarget.innerHTML = `
        <tr><td colspan="7" class="px-3 py-12 text-center">
          <p class="text-body-sm text-text-tertiary">${this.emptyTitleLabelValue}</p>
          <p class="text-caption mt-1 text-text-muted">${this.emptyHintLabelValue}</p>
        </td></tr>`
      this._renderPagination()
      return
    }
    const totalPages = this._totalPages()
    if (this.page > totalPages) this.page = totalPages
    if (this.page < 1) this.page = 1
    const start = (this.page - 1) * this.PER_PAGE
    const pageVersions = this.versions.slice(start, start + this.PER_PAGE)
    const latestId = String(this.versions[0].id)
    this.listTarget.innerHTML = pageVersions.map((v) => {
      const id = String(v.id)
      const checked = this.selected.includes(id)
      const order = this.selected.indexOf(id) // 0 → A, 1 → B
      const isLatest = id === latestId
      const rowCls = checked ? "bg-accent-subtle/60" : "hover:bg-surface-hover"

      const pick = checked
        ? `<span class="inline-flex h-6 w-6 items-center justify-center rounded-full bg-accent text-[11px] font-semibold text-white">${order === 0 ? "A" : "B"}</span>`
        : `<span class="inline-flex h-6 w-6 items-center justify-center rounded-full border border-border-strong text-text-muted"><svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="m4.5 12.75 6 6 9-13.5"/></svg></span>`

      const defaultPill = v.is_default ? `<span class="badge badge-success">${this.defaultBadgeLabelValue}</span>` : ""
      const latestPill = (isLatest && !v.is_default) ? `<span class="badge badge-accent">${this.latestBadgeLabelValue}</span>` : ""
      const status = (defaultPill || latestPill) ? `${defaultPill}${latestPill}` : `<span class="text-text-muted">—</span>`

      const hasDesc = !!v.description
      const description = escapeHtml(v.description || this.noDescriptionLabelValue)
      const descCls = hasDesc ? "text-text-secondary" : "italic text-text-muted"

      const basedOn = (v.based_on_version_number != null)
        ? `<span class="inline-flex items-center gap-1 whitespace-nowrap text-xs text-text-secondary">
             <svg class="h-3.5 w-3.5 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.75"><path stroke-linecap="round" stroke-linejoin="round" d="M6.75 3v8.25m0 0a3 3 0 1 0 0 6 3 3 0 0 0 0-6Zm0-8.25a3 3 0 1 1 0 6 3 3 0 0 1 0-6Zm10.5 0a3 3 0 1 1 0 6 3 3 0 0 1 0-6Zm0 6a8.25 8.25 0 0 1-8.25 8.25"/></svg>
             v${escapeHtml(String(v.based_on_version_number))}
           </span>`
        : `<span class="text-text-muted">—</span>`

      const hideCreate = this.resourceValue !== "entities" || v.generated_page_id
      const createPageBtn = hideCreate ? "" :
        `<button type="button" data-action="click->versions#createPage"
                 data-versions-id-param="${escapeHtml(id)}"
                 class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-accent-text transition-base hover:bg-accent-subtle">
           <svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.75"><path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m3.75 9v6m3-3H9m1.5-12H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z"/></svg>
           ${this.createPageButtonLabelValue}
         </button>`

      const writeAllowed = v.writable !== false
      const setDefaultBtn = (v.is_default || !writeAllowed) ? "" :
        `<button type="button" data-action="click->versions#setDefault"
                 data-versions-id-param="${escapeHtml(id)}"
                 class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-success transition-base hover:bg-success-subtle">
           <svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.75"><path stroke-linecap="round" stroke-linejoin="round" d="m11.48 3.5 2.6 5.27 5.82.85-4.21 4.1 1 5.8L11.48 17l-5.2 2.73 1-5.8-4.22-4.1 5.82-.85z"/></svg>
           ${this.setDefaultButtonLabelValue}
         </button>`

      // The default version cannot be deleted (its button is hidden); the server
      // enforces the same rule as a backstop.
      const deleteBtn = (v.is_default || !writeAllowed) ? "" :
        `<button type="button" data-action="click->versions#destroy"
                 data-versions-id-param="${escapeHtml(id)}"
                 data-versions-version-param="${escapeHtml(String(v.version_number))}"
                 class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-danger transition-base hover:bg-danger-subtle">
           <svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.75"><path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"/></svg>
           ${this.deleteButtonLabelValue}
         </button>`

      return `
        <tr data-action="click->versions#toggleSelect"
            data-versions-id-param="${escapeHtml(id)}"
            aria-pressed="${checked}"
            class="cursor-pointer transition-base ${rowCls}">
          <td class="py-3 pl-5 pr-3 align-middle">${pick}</td>
          <td class="whitespace-nowrap px-3 py-3 align-middle"><span class="text-sm font-semibold text-text-primary">v${escapeHtml(String(v.version_number))}</span></td>
          <td class="hidden whitespace-nowrap px-3 py-3 align-middle md:table-cell">${basedOn}</td>
          <td class="px-3 py-3 align-middle"><div class="flex flex-wrap items-center gap-1">${status}</div></td>
          <td class="hidden max-w-xs px-3 py-3 align-middle sm:table-cell"><span class="line-clamp-1 text-xs ${descCls}">${description}</span></td>
          <td class="hidden whitespace-nowrap px-3 py-3 align-middle text-2xs text-text-muted md:table-cell">${escapeHtml(this._formatDate(v.created_at))}</td>
          <td class="whitespace-nowrap py-3 pl-3 pr-5 align-middle text-right">
            <div class="inline-flex items-center gap-1">
              <button type="button" data-action="click->versions#view"
                      data-versions-id-param="${escapeHtml(id)}"
                      class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-accent-text transition-base hover:bg-accent-subtle">
                <svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.75"><path stroke-linecap="round" stroke-linejoin="round" d="M13.5 6H5.25A2.25 2.25 0 0 0 3 8.25v10.5A2.25 2.25 0 0 0 5.25 21h10.5A2.25 2.25 0 0 0 18 18.75V10.5m-7.5 3L21 3m0 0h-5.25M21 3v5.25"/></svg>
                ${this.openButtonLabelValue}
              </button>
              ${createPageBtn}
              ${setDefaultBtn}
              ${deleteBtn}
            </div>
          </td>
        </tr>`
    }).join("")
    this._renderPagination()
  }

  _totalPages() {
    return Math.max(1, Math.ceil(this.versions.length / this.PER_PAGE))
  }

  _renderPagination() {
    if (!this.hasPaginationTarget) return
    const total = this.versions.length
    const multi = total > this.PER_PAGE
    this.paginationTarget.classList.toggle("hidden", !multi)
    this.paginationTarget.classList.toggle("flex", multi)
    if (!multi) return
    const start = (this.page - 1) * this.PER_PAGE
    const end = Math.min(start + this.PER_PAGE, total)
    if (this.hasPageInfoTarget) {
      this.pageInfoTarget.textContent = this.paginationRangeFormatValue
        .replace("{start}", start + 1).replace("{end}", end).replace("{total}", total)
    }
    if (this.hasPrevButtonTarget) this.prevButtonTarget.disabled = this.page <= 1
    if (this.hasNextButtonTarget) this.nextButtonTarget.disabled = this.page >= this._totalPages()
  }

  _scrollTop() {
    if (this.hasScrollTarget) this.scrollTarget.scrollTo({ top: 0 })
  }

  _renderDiff(va, vb) {
    const rows = versionDiff(va.configuration, vb.configuration)
    const side = (text, cls) => `<td class="w-1/2 whitespace-pre px-3 py-0.5 align-top font-mono text-[11px] leading-relaxed ${cls}">${text == null ? "" : escapeHtml(text)}</td>`
    let adds = 0, dels = 0
    const body = rows.map(r => {
      if (r.type === "add") { adds++; return `<tr class="bg-success-subtle">${side("", "")}${side(r.right, "text-success")}</tr>` }
      if (r.type === "del") { dels++; return `<tr class="bg-danger-subtle">${side(r.left, "text-danger")}${side("", "")}</tr>` }
      return `<tr>${side(r.left, "text-text-secondary")}${side(r.right, "text-text-secondary")}</tr>`
    }).join("")

    const badge = (label) => `<span class="inline-flex h-5 w-5 items-center justify-center rounded-full bg-accent text-[11px] font-semibold text-white">${label}</span>`
    const colHead = (label) => `<th class="w-1/2 px-3 py-2 text-left text-xs font-semibold text-text-secondary">${label}</th>`
    this.contentTarget.innerHTML = `
      <div class="sticky top-0 z-10 flex flex-wrap items-center justify-between gap-2 border-b border-border-subtle bg-surface/95 px-4 py-2.5 backdrop-blur">
        <div class="flex items-center gap-2">
          <button type="button" data-action="click->versions#backToList"
                  class="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-text-secondary transition-base hover:bg-surface-active">
            <svg class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18"/></svg>
            ${this.backButtonLabelValue}
          </button>
          <span class="flex items-center gap-1.5 text-xs text-text-secondary">
            ${badge("A")} v${escapeHtml(String(va.version_number))}
            <svg class="h-3.5 w-3.5 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3"/></svg>
            ${badge("B")} v${escapeHtml(String(vb.version_number))}
          </span>
        </div>
        <div class="flex items-center gap-3 text-2xs font-medium">
          <span class="text-success">${this.addedCountFormatValue.replace("{count}", adds)}</span>
          <span class="text-danger">${this.removedCountFormatValue.replace("{count}", dels)}</span>
        </div>
      </div>
      <table class="w-full table-fixed border-collapse">
        <thead class="border-b border-border-subtle bg-canvas-elevated">
          <tr>${colHead("v" + escapeHtml(String(va.version_number)))}${colHead("v" + escapeHtml(String(vb.version_number)))}</tr>
        </thead>
        <tbody>${body}</tbody>
      </table>`
  }

  _formatDate(iso) {
    if (!iso) return ""
    const d = new Date(iso)
    if (isNaN(d)) return iso
    return d.toLocaleString(undefined, {
      year: "numeric", month: "short", day: "numeric", hour: "numeric", minute: "2-digit"
    })
  }

  _updateButtons() {
    const n = this.selected.length
    if (this.hasDiffButtonTarget) this.diffButtonTarget.disabled = n !== 2
    if (this.hasClearButtonTarget) this.clearButtonTarget.classList.toggle("hidden", n === 0)
    if (this.hasSelectionInfoTarget) {
      this.selectionInfoTarget.textContent =
        n === 0 ? this.selectTwoHintLabelValue
        : n === 1 ? this.oneSelectedHintLabelValue
        : this.twoSelectedHintLabelValue
    }
    if (this.hasHintTarget) {
      this.hintTarget.textContent = n === 2 ? this.readyToCompareLabelValue : this.pickMoreFormatValue.replace("{count}", 2 - n)
    }
  }

  _refreshList() {
    // Re-fetch the list page's turbo-frame so the "Versions" column reflects the
    // new default. The frame renders eager content (no initial `src`), so we point
    // it at the current URL — preserving search/sort/page — to trigger the reload.
    const frame = document.querySelector("turbo-frame#admin-table")
    if (!frame) return
    if (frame.src) {
      // Already has a source URL → force a fresh fetch (reload re-fetches even
      // when the URL is unchanged, which a plain `src =` assignment would skip).
      frame.reload?.()
    } else {
      // Eager frame with no initial src → assigning one triggers the first load.
      frame.src = window.location.href
    }
  }

  _error(message) {
    if (!this.hasErrorTarget) return
    if (this.hasErrorMessageTarget) this.errorMessageTarget.textContent = message
    else this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
    this.errorTarget.classList.add("flex")
  }

  _clearError() {
    if (!this.hasErrorTarget) return
    this.errorTarget.classList.add("hidden")
    this.errorTarget.classList.remove("flex")
  }
}
