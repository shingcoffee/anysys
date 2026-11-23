import { Controller } from "@hotwired/stimulus"

// Every successful write is answered by a full re-render of this list over
// Turbo (AiAssistant::Stream.broadcast_conversations), so nothing here patches
// the list on success — it fires the request and lets the stream settle it.
const QUERY_KEY = "conversation"
// The broadcast replaces the element this controller is mounted on, so the
// slide-over state is parked on the nearest ancestor the replacement cannot
// reach. Deliberately not sessionStorage: the list has to start collapsed on
// every page load, and only a mid-session broadcast may preserve it.
const HOST_SELECTOR = "[data-ai-assistant-chats-host]"
const EXPANDED_ATTR = "data-chats-expanded"
const CLOSED_CLASS = "-translate-x-full"
// A write has no visible effect until the broadcast lands, and the round trip
// is long enough to press "New chat" twice and get two empty chats.
const BUSY_CLASSES = [ "opacity-60", "cursor-wait" ]

export default class extends Controller {
  static targets = [ "panel", "row", "toggle", "alert", "deleteDialog", "backdrop" ]

  static values = {
    createUrl: { type: String, default: "" },
    baseUrl: { type: String, default: "" },
    panelId: { type: String, default: "" },
    renameLabel: { type: String, default: "Chat name" },
    saveLabel: { type: String, default: "Save" },
    cancelLabel: { type: String, default: "Cancel" },
    failedLabel: { type: String, default: "Could not update the chat." }
  }

  connect() {
    this.expanded = false
    this.rename_ = null
    this.pending = false
    this.pendingControl = null
    this.pendingDestroy = null
    this.boundKeydown = this.keydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
    this.#applyExpanded(this.#storedExpanded())
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
    this.#closeRename()
  }

  create(event) {
    if (event) event.preventDefault()
    if (!this.createUrlValue) return
    if (!this.#pend(event && event.currentTarget)) return

    void this.#create()
  }

  // Turns the row's label into an inline field. The row itself is left alone
  // otherwise, so a failed rename still shows the thread it belongs to.
  rename(event) {
    if (event) event.preventDefault()

    const params = this.#paramsOf(event)
    const row = this.#rowFor(params.id)
    const url = this.#memberUrl(params)
    if (!row || !url) return

    this.#openRename(row, url, params.title)
  }

  archive(event) {
    if (event) event.preventDefault()

    const params = this.#paramsOf(event)
    if (!params.url) return
    if (!this.#pend(event && event.currentTarget)) return

    void this.#archive(params.url, !params.archived)
  }

  // Deleting takes the whole transcript with it, so it is asked in a dialog
  // that names the action rather than in a native prompt.
  destroy(event) {
    if (event) event.preventDefault()

    const params = this.#paramsOf(event)
    const url = this.#memberUrl(params)
    if (!url || this.pending) return

    this.#askToDelete({ url, id: params.id, trigger: (event && event.currentTarget) || null })
  }

  confirmDestroy(event) {
    if (event) event.preventDefault()

    const request = this.pendingDestroy
    if (!request) return

    this.pendingDestroy = null
    this.#closeDialog()
    if (!this.#pend(request.trigger)) return

    void this.#destroy(request.url, request.id)
  }

  // Also bound to the dialog's own `cancel`, so Escape leaves through here and
  // the reader lands back on the row they opened rather than on the document.
  cancelDestroy(event) {
    if (event) event.preventDefault()

    const request = this.pendingDestroy
    this.pendingDestroy = null
    this.#closeDialog()
    this.#restoreFocus(request)
  }

  // The list is a left slide-over at every width, and this is its control.
  toggle(event) {
    if (event) event.preventDefault()

    const panel = this.#panel()
    if (!panel) return

    this.#applyExpanded(panel.classList.contains(CLOSED_CLASS))
    this.#storeExpanded(this.expanded)
  }

  close(event) {
    if (event) event.preventDefault()

    this.#applyExpanded(false)
    this.#storeExpanded(false)
  }

  // Escape closes the slide-over unless a nested dialog already owns it.
  keydown(event) {
    if (event.key !== "Escape") return
    if (this.rename_) return
    if (!this.expanded) return
    if (this.hasDeleteDialogTarget && this.deleteDialogTarget.open) return

    event.preventDefault()
    this.close()
  }

  async #create() {
    const data = await this.#write(this.createUrlValue, { method: "POST" })
    const id = data && data.conversation && data.conversation.id
    if (!id) {
      // A 2xx carrying no chat is a server bug, not a new chat: there is
      // nothing to open, so it reads as a failure.
      if (data) this.#announceFailure()
      this.#release()
      return
    }

    // Left pending on purpose: the visit below replaces this page.
    this.#openConversation(id)
  }

  async #archive(url, archived) {
    await this.#write(url, { method: "POST", body: { archived } })
    this.#release()
  }

  // Deleting the thread on screen is the one write the list re-render cannot
  // settle: the transcript and the composer's conversationId still point at
  // the deleted row, so the next send would 404. Anything else stays on the
  // page and lets the broadcast do the work.
  async #destroy(url, id) {
    const data = await this.#write(url, { method: "DELETE" })
    if (data && this.#isOpen(id)) {
      this.#openDefault()
      return
    }

    this.#release()
  }

  // A browser with no dialog cannot ask before throwing a transcript away, so
  // it does not get to delete at all. The old prompt-less path treated an
  // absent dialog as consent.
  #askToDelete(request) {
    const dialog = this.hasDeleteDialogTarget ? this.deleteDialogTarget : null
    if (!dialog || typeof dialog.showModal !== "function") return

    this.pendingDestroy = request
    dialog.showModal()
  }

  #closeDialog() {
    if (!this.hasDeleteDialogTarget) return

    const dialog = this.deleteDialogTarget
    if (typeof dialog.close === "function") dialog.close()
  }

  #restoreFocus(request) {
    if (!request) return

    const row = this.#rowFor(request.id)
    const target = request.trigger && request.trigger.isConnected
      ? request.trigger
      : row && row.querySelector("a")
    if (target && target.focus) target.focus()
  }

  #isOpen(id) {
    const panel = document.querySelector("[data-ai-assistant-conversation-id-value]")
    if (!panel || id == null) return false

    return panel.getAttribute("data-ai-assistant-conversation-id-value") === String(id)
  }

  // No `?conversation=`: the server picks the most recently active thread.
  #openDefault() {
    const url = new URL(window.location.href)
    url.searchParams.delete(QUERY_KEY)
    this.#visit(url.toString())
  }

  // The workspace picks its thread from `?conversation=<id>`, so the new chat
  // is opened by asking this page for it again.
  #openConversation(id) {
    const url = new URL(window.location.href)
    url.searchParams.set(QUERY_KEY, String(id))
    this.#visit(url.toString())
  }

  // Turbo keeps the page shell — and with it the ActionCable connection the
  // transcript streams over — instead of tearing both down and rebuilding
  // them just to change which chat is open.
  #visit(url) {
    const turbo = window.Turbo
    if (turbo && typeof turbo.visit === "function") turbo.visit(url)
    else window.location.assign(url)
  }

  #openRename(row, url, title) {
    this.#closeRename()

    const label = row.querySelector("a")
    const input = this.#renameInput(title, label)
    const form = document.createElement("div")
    form.className = "flex items-center gap-1.5 py-1 pl-2.5 pr-1"
    const save = this.#renameButton(this.saveLabelValue, "text-accent-text", () => void this.#saveRename())
    const cancel = this.#renameButton(this.cancelLabelValue, "text-text-muted", () => this.#cancelRename())
    form.append(input, save, cancel)

    if (label) label.classList.add("hidden")
    row.appendChild(form)
    this.rename_ = { row, label, form, input, url, save, cancel, busy: false }
    input.focus()
    input.select()
  }

  #renameInput(title, label) {
    const input = document.createElement("input")
    input.type = "text"
    input.value = title != null ? String(title) : (label ? label.textContent.trim() : "")
    input.setAttribute("aria-label", this.renameLabelValue)
    input.className = [
      "min-w-0 flex-1 rounded-md bg-surface px-2 py-1 text-sm text-text-primary",
      "ring-1 ring-border-subtle focus:outline-none focus-visible:ring-2 focus-visible:ring-accent",
      "pointer-coarse:min-h-11"
    ].join(" ")
    input.addEventListener("keydown", (event) => this.#renameKeydown(event))
    return input
  }

  #renameButton(label, tone, onClick) {
    const button = document.createElement("button")
    button.type = "button"
    button.textContent = label
    button.className = [
      "flex min-h-8 shrink-0 items-center rounded-md px-2 text-caption",
      tone,
      "transition-base hover:bg-surface-hover focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent",
      "pointer-coarse:min-h-11"
    ].join(" ")
    button.addEventListener("click", (event) => {
      event.preventDefault()
      onClick()
    })
    return button
  }

  #renameKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      event.stopPropagation()
      void this.#saveRename()
      return
    }
    if (event.key !== "Escape") return

    event.preventDefault()
    event.stopPropagation()
    this.#cancelRename()
  }

  // The field stays mounted and disabled for the round trip: tearing it down
  // first meant a refused rename threw the typed name away behind a generic
  // error, with nothing left to correct.
  async #saveRename() {
    if (!this.rename_ || this.rename_.busy) return

    const { url, input } = this.rename_
    const title = input.value.trim()
    // The server refuses a blank name anyway; asking it costs a round trip and
    // loses the field.
    if (!title) {
      input.focus()
      return
    }

    this.#setRenameBusy(true)
    const data = await this.#write(url, { method: "PATCH", body: { title } })
    if (!this.rename_) return

    if (data) this.#closeRename()
    else this.#setRenameBusy(false)
  }

  #setRenameBusy(busy) {
    const { input, save, cancel } = this.rename_
    this.rename_.busy = busy
    ;[ input, save, cancel ].forEach((control) => {
      control.disabled = busy
      control.classList.toggle("opacity-60", busy)
    })
  }

  #cancelRename() {
    this.#closeRename()
  }

  // Puts the label back and returns focus to the row, so dismissing the field
  // does not drop the reader out of the list.
  #closeRename() {
    if (!this.rename_) return

    const { label, form } = this.rename_
    this.rename_ = null
    form.remove()
    if (!label) return

    label.classList.remove("hidden")
    label.focus()
  }

  #panel() {
    if (this.hasPanelTarget) return this.panelTarget
    if (!this.panelIdValue) return null

    return document.getElementById(this.panelIdValue)
  }

  #applyExpanded(expanded) {
    const panel = this.#panel()
    if (!panel) return

    this.expanded = expanded
    panel.classList.toggle(CLOSED_CLASS, !expanded)
    panel.setAttribute("aria-hidden", expanded ? "false" : "true")
    panel.inert = !expanded
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", String(expanded))
    this.#applyBackdrop(expanded)
  }

  #applyBackdrop(expanded) {
    if (!this.hasBackdropTarget) return

    this.backdropTarget.classList.toggle("pointer-events-none", !expanded)
    this.backdropTarget.classList.toggle("opacity-0", !expanded)
    this.backdropTarget.setAttribute("aria-hidden", expanded ? "false" : "true")
  }

  #stateHost() {
    return this.element.closest(HOST_SELECTOR)
  }

  #storedExpanded() {
    const host = this.#stateHost()

    return host ? host.getAttribute(EXPANDED_ATTR) === "true" : false
  }

  #storeExpanded(expanded) {
    const host = this.#stateHost()
    if (host) host.setAttribute(EXPANDED_ATTR, String(expanded))
  }

  #rowFor(id) {
    const key = String(id)
    return this.rowTargets.find((row) => row.dataset.conversationId === key) || null
  }

  // Row controls carry their own URL; the collection URL is the fallback for
  // building a member URL from the id alone.
  #memberUrl({ id, url }) {
    if (url) return url
    if (!this.baseUrlValue || id == null) return ""

    return `${this.baseUrlValue}/${id}`
  }

  // One write at a time, and the control that started it says so. `create` can
  // also arrive as a window event, whose currentTarget is this list rather than
  // a button — there is nothing to disable in that case.
  #pend(control) {
    if (this.pending) return false

    this.pending = true
    this.pendingControl = control && "disabled" in control ? control : null
    if (this.pendingControl) {
      this.pendingControl.disabled = true
      this.pendingControl.classList.add(...BUSY_CLASSES)
    }
    return true
  }

  #release() {
    this.pending = false
    if (this.pendingControl) {
      this.pendingControl.disabled = false
      this.pendingControl.classList.remove(...BUSY_CLASSES)
    }
    this.pendingControl = null
  }

  #paramsOf(event) {
    return (event && event.params) || {}
  }

  async #write(url, { method, body } = {}) {
    try {
      const response = await fetch(url, {
        method: method,
        headers: {
          "X-CSRF-Token": this.#csrfToken(),
          Accept: "application/json",
          "Content-Type": "application/json"
        },
        body: body ? JSON.stringify(body) : undefined
      })
      if (!response.ok) {
        this.#announceFailure()
        return null
      }
      this.#clearAlert()
      return await this.#json(response)
    } catch {
      this.#announceFailure()
      return null
    }
  }

  async #json(response) {
    try {
      return await response.json()
    } catch {
      return {}
    }
  }

  // Read from the layout's meta tag rather than a value on this element: the
  // whole list is re-rendered by AiAssistant::Stream, and a token minted by
  // that offline render belongs to a throwaway session, so every write after
  // the first broadcast would be rejected.
  #csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return (meta && meta.getAttribute("content")) || ""
  }

  // The slot is server-rendered, so the broadcast that replaces this list
  // brings it back with it. Cleared by the next successful write.
  #announceFailure() {
    if (!this.hasAlertTarget) return

    this.alertTarget.textContent = this.failedLabelValue
    this.alertTarget.classList.remove("hidden")
  }

  #clearAlert() {
    if (!this.hasAlertTarget) return

    this.alertTarget.textContent = ""
    this.alertTarget.classList.add("hidden")
  }
}
