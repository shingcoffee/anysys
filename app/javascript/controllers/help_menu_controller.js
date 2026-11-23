import { Controller } from "@hotwired/stimulus"
import { announceTopbarMenuOpen, onPeerTopbarMenuOpen, TOPBAR_MENU_OPEN } from "controllers/shared/topbar_menu"

const SCROLL_LOCK = "overflow-hidden"

// Top-bar help menu: Notify / Email dialogs plus a docs link.
export default class extends Controller {
  static targets = ["panel", "trigger", "notifyDialog", "emailDialog"]

  connect() {
    this.boundOutside = (e) => { if (!this.element.contains(e.target)) this.closeAll() }
    this.boundKey = (e) => { if (e.key === "Escape") this.closeAll() }
    this.boundPeerOpen = onPeerTopbarMenuOpen(this.element, () => this.closeAll())
    document.addEventListener("click", this.boundOutside)
    document.addEventListener("keydown", this.boundKey)
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutside)
    document.removeEventListener("keydown", this.boundKey)
    document.removeEventListener(TOPBAR_MENU_OPEN, this.boundPeerOpen)
    this.unlockScroll()
  }

  toggle(event) {
    event.stopPropagation()
    const willOpen = this.panelTarget.classList.contains("hidden")
    if (willOpen) announceTopbarMenuOpen(this.element)
    this.panelTarget.classList.toggle("hidden", !willOpen)
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", String(willOpen))
    }
  }

  close() {
    this.panelTarget.classList.add("hidden")
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", "false")
    }
  }

  openNotify(event) {
    this.openDialog(event, this.hasNotifyDialogTarget ? this.notifyDialogTarget : null)
  }

  openEmail(event) {
    this.openDialog(event, this.hasEmailDialogTarget ? this.emailDialogTarget : null)
  }

  closeDialogs() {
    const wasOpen = this.dialogElements().some((dialog) => !dialog.classList.contains("hidden"))
    this.dialogElements().forEach((dialog) => {
      dialog.classList.add("hidden")
      this.resetDialog(dialog)
    })
    this.unlockScroll()
    if (wasOpen) this.restoreTriggerFocus()
  }

  closeAll() {
    this.close()
    this.closeDialogs()
  }

  openDialog(event, dialog) {
    event.preventDefault()
    event.stopPropagation()
    this.close()
    if (!dialog) return
    dialog.classList.remove("hidden")
    this.lockScroll()
    this.focusDialog(dialog)
  }

  dialogElements() {
    const dialogs = []
    if (this.hasNotifyDialogTarget) dialogs.push(this.notifyDialogTarget)
    if (this.hasEmailDialogTarget) dialogs.push(this.emailDialogTarget)
    return dialogs
  }

  focusDialog(dialog) {
    dialog.querySelector("input:not([type='hidden']):not([type='file']), textarea, select")?.focus()
  }

  resetDialog(dialog) {
    dialog.querySelectorAll("form").forEach((form) => form.reset())
    dialog.querySelectorAll("[data-help-attachments-target='list']").forEach((el) => { el.replaceChildren() })
    dialog.querySelectorAll("[data-help-attachments-target='error']").forEach((el) => {
      el.textContent = ""
      el.classList.add("hidden")
    })
    dialog.querySelectorAll("[data-help-attachments-target='submit']").forEach((el) => { el.disabled = false })
  }

  restoreTriggerFocus() {
    if (this.hasTriggerTarget) this.triggerTarget.focus()
  }

  lockScroll() {
    document.documentElement.classList.add(SCROLL_LOCK)
  }

  unlockScroll() {
    document.documentElement.classList.remove(SCROLL_LOCK)
  }
}
