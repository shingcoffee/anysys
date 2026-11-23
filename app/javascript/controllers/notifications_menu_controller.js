import { Controller } from "@hotwired/stimulus"
import { announceTopbarMenuOpen, onPeerTopbarMenuOpen, TOPBAR_MENU_OPEN } from "controllers/shared/topbar_menu"

const HIDDEN = "hidden"

// Dropdown for the top-bar notification bell. Mirrors help-menu/user-menu:
// toggle on click, close on outside-click or Escape, and close when a peer
// top-bar menu opens. Live help-unread Turbo Stream replacements update the
// visible badge without remounting this controller or touching announcement rows.
export default class extends Controller {
  static targets = ["panel", "trigger", "badge", "headerBadge", "supportTicketUnread", "announcementUnread", "list", "empty"]
  static values = {
    unreadTitleTemplate: { type: String, default: "Notifications, {count} unread" },
    title: { type: String, default: "Notifications" },
    overflow: { type: String, default: "99+" }
  }

  connect() {
    this.boundOutside = (e) => { if (!this.element.contains(e.target)) this.close() }
    this.boundKey = (e) => { if (e.key === "Escape") this.close() }
    this.boundPeerOpen = onPeerTopbarMenuOpen(this.element, () => this.close())
    document.addEventListener("click", this.boundOutside)
    document.addEventListener("keydown", this.boundKey)
    this.observeList()
    this.refreshChrome()
  }

  disconnect() {
    document.removeEventListener("click", this.boundOutside)
    document.removeEventListener("keydown", this.boundKey)
    document.removeEventListener(TOPBAR_MENU_OPEN, this.boundPeerOpen)
    this.listObserver?.disconnect()
  }

  supportTicketUnreadTargetConnected() {
    this.refreshChrome()
  }

  announcementUnreadTargetConnected() {
    this.refreshChrome()
  }

  listTargetConnected() {
    this.observeList()
    this.refreshChrome()
  }

  badgeTargetConnected() {
    this.refreshChrome()
  }

  headerBadgeTargetConnected() {
    this.refreshChrome()
  }

  toggle(event) {
    event.stopPropagation()
    const willOpen = this.panelTarget.classList.contains(HIDDEN)
    if (willOpen) announceTopbarMenuOpen(this.element)
    this.panelTarget.classList.toggle(HIDDEN, !willOpen)
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", String(willOpen))
    }
  }

  close() {
    this.panelTarget.classList.add(HIDDEN)
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", "false")
    }
  }

  observeList() {
    this.listObserver?.disconnect()
    if (!this.hasListTarget) return
    this.listObserver = new MutationObserver(() => this.refreshEmpty())
    this.listObserver.observe(this.listTarget, { childList: true })
    this.refreshEmpty()
  }

  refreshChrome() {
    this.refreshBadge()
    this.refreshEmpty()
  }

  refreshBadge() {
    const total = this.counterFrom(this.hasAnnouncementUnreadTarget ? this.announcementUnreadTarget : null) +
      this.counterFrom(this.hasSupportTicketUnreadTarget ? this.supportTicketUnreadTarget : null)
    const label = total >= 100 ? this.overflowValue : String(total)
    if (this.hasBadgeTarget) this.applyCount(this.badgeTarget, total, label)
    if (this.hasHeaderBadgeTarget) this.applyCount(this.headerBadgeTarget, total, label)
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-label", this.triggerLabel(total))
    }
  }

  applyCount(el, total, label) {
    if (total > 0) {
      el.textContent = label
      el.dataset.badgeCount = String(total)
      el.classList.remove(HIDDEN)
    } else {
      el.textContent = ""
      delete el.dataset.badgeCount
      el.classList.add(HIDDEN)
    }
  }

  refreshEmpty() {
    if (!this.hasEmptyTarget) return
    const hasRows = this.hasListTarget && this.listTarget.children.length > 0
    this.emptyTarget.classList.toggle(HIDDEN, hasRows)
  }

  counterFrom(el) {
    if (!el) return 0
    const parsed = Number(el.dataset.count)
    return Number.isFinite(parsed) ? parsed : 0
  }

  triggerLabel(total) {
    if (total > 0) {
      return this.unreadTitleTemplateValue.replace("{count}", String(total))
    }
    return this.titleValue
  }
}
