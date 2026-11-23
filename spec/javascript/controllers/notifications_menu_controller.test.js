import { describe, it, expect, beforeEach, vi } from "vitest"
import Controller from "controllers/notifications_menu_controller"
import { mountController, click, tick, controllerFor } from "../support/stimulus.js"

const html = `
  <div data-controller="notifications-menu">
    <button data-notifications-menu-target="trigger" data-action="click->notifications-menu#toggle" data-role="bell" aria-expanded="false">bell</button>
    <span data-notifications-menu-target="badge" data-role="badge" class="hidden"></span>
    <span data-notifications-menu-target="headerBadge" data-role="header-badge" class="hidden"></span>
    <span data-notifications-menu-target="announcementUnread" data-count="0" hidden></span>
    <span data-notifications-menu-target="supportTicketUnread" data-count="0" hidden></span>
    <div data-notifications-menu-target="panel" class="hidden" data-role="panel">
      <div data-notifications-menu-target="list" data-role="list"></div>
      <div data-notifications-menu-target="empty" data-role="empty">caught up</div>
    </div>
  </div>`

const isHidden = (el) => el.querySelector("[data-role='panel']").classList.contains("hidden")

describe("notifications-menu controller", () => {
  let element
  let application
  beforeEach(async () => {
    ;({ element, application } = await mountController("notifications-menu", Controller, html))
  })

  it("toggles the panel open and closed", () => {
    const bell = element.querySelector("[data-role='bell']")
    expect(isHidden(element)).toBe(true)
    click(bell)
    expect(isHidden(element)).toBe(false)
    expect(bell.getAttribute("aria-expanded")).toBe("true")
    click(bell)
    expect(isHidden(element)).toBe(true)
    expect(bell.getAttribute("aria-expanded")).toBe("false")
  })

  it("closes on an outside click", () => {
    click(element.querySelector("[data-role='bell']"))
    document.body.dispatchEvent(new Event("click", { bubbles: true }))
    expect(isHidden(element)).toBe(true)
  })

  it("closes on Escape", () => {
    click(element.querySelector("[data-role='bell']"))
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))
    expect(isHidden(element)).toBe(true)
  })

  it("disconnect removes the document click/keydown listeners", async () => {
    const removeSpy = vi.spyOn(document, "removeEventListener")
    element.remove() // Stimulus disconnects controllers whose element leaves the DOM
    await tick()
    expect(removeSpy).toHaveBeenCalledWith("click", expect.any(Function))
    expect(removeSpy).toHaveBeenCalledWith("keydown", expect.any(Function))
    expect(removeSpy).toHaveBeenCalledWith("anysys:topbar-menu-open", expect.any(Function))
  })

  it("closes when a peer top-bar menu opens", () => {
    click(element.querySelector("[data-role='bell']"))
    expect(isHidden(element)).toBe(false)
    document.dispatchEvent(new CustomEvent("anysys:topbar-menu-open", {
      detail: { source: document.createElement("div") }
    }))
    expect(isHidden(element)).toBe(true)
  })

  it("shows the badge from announcement and help unread counters", async () => {
    const liveHtml = `
      <div data-controller="notifications-menu">
        <button data-notifications-menu-target="trigger" data-action="click->notifications-menu#toggle" data-role="bell" aria-expanded="false">bell</button>
        <span data-notifications-menu-target="badge" data-role="badge" class="hidden"></span>
        <span data-notifications-menu-target="headerBadge" data-role="header-badge" class="hidden"></span>
        <span data-notifications-menu-target="announcementUnread" data-count="2" hidden></span>
        <span data-notifications-menu-target="supportTicketUnread" data-count="0" hidden></span>
        <div data-notifications-menu-target="panel" class="hidden">
          <div data-notifications-menu-target="list"></div>
          <div data-notifications-menu-target="empty">caught up</div>
        </div>
      </div>`
    ;({ element } = await mountController("notifications-menu", Controller, liveHtml))
    const badge = element.querySelector("[data-role='badge']")
    const headerBadge = element.querySelector("[data-role='header-badge']")
    expect(badge.textContent).toBe("2")
    expect(badge.classList.contains("hidden")).toBe(false)
    expect(headerBadge.textContent).toBe("2")
    expect(headerBadge.classList.contains("hidden")).toBe(false)

    const next = document.createElement("span")
    next.setAttribute("data-notifications-menu-target", "supportTicketUnread")
    next.dataset.count = "1"
    next.hidden = true
    element.querySelector("[data-notifications-menu-target='supportTicketUnread']").replaceWith(next)
    await tick()

    expect(badge.textContent).toBe("3")
    expect(badge.dataset.badgeCount).toBe("3")
    expect(headerBadge.textContent).toBe("3")
    expect(element.querySelector("[data-role='bell']").getAttribute("aria-label")).toBe("Notifications, 3 unread")
  })

  it("connects a header badge that arrives after mount", async () => {
    const liveHtml = `
      <div data-controller="notifications-menu">
        <button data-notifications-menu-target="trigger" data-action="click->notifications-menu#toggle" data-role="bell" aria-expanded="false">bell</button>
        <span data-notifications-menu-target="announcementUnread" data-count="2" hidden></span>
        <span data-notifications-menu-target="supportTicketUnread" data-count="1" hidden></span>
        <div data-notifications-menu-target="panel" class="hidden">
          <div data-notifications-menu-target="list"></div>
          <div data-notifications-menu-target="empty">caught up</div>
        </div>
      </div>`
    ;({ element } = await mountController("notifications-menu", Controller, liveHtml))
    const header = document.createElement("span")
    header.setAttribute("data-notifications-menu-target", "headerBadge")
    header.setAttribute("data-role", "header-badge")
    header.className = "hidden"
    element.append(header)
    await tick()
    expect(header.textContent).toBe("3")
    expect(header.classList.contains("hidden")).toBe(false)
  })

  it("hides the empty state when a row is prepended to the list", async () => {
    const list = element.querySelector("[data-role='list']")
    const empty = element.querySelector("[data-role='empty']")
    expect(empty.classList.contains("hidden")).toBe(false)

    const row = document.createElement("div")
    row.id = "notifications-support-ticket-row-9"
    list.append(row)
    await tick()

    expect(empty.classList.contains("hidden")).toBe(true)
  })

  it("uses the overflow label at 100 unread and treats a non-numeric count as zero", async () => {
    const liveHtml = `
      <div data-controller="notifications-menu">
        <button data-notifications-menu-target="trigger" data-action="click->notifications-menu#toggle" data-role="bell" aria-expanded="false">bell</button>
        <span data-notifications-menu-target="badge" data-role="badge" class="hidden"></span>
        <span data-notifications-menu-target="headerBadge" data-role="header-badge" class="hidden"></span>
        <span data-notifications-menu-target="announcementUnread" data-count="99" hidden></span>
        <span data-notifications-menu-target="supportTicketUnread" data-count="1" hidden></span>
        <div data-notifications-menu-target="panel" class="hidden">
          <div data-notifications-menu-target="list"></div>
          <div data-notifications-menu-target="empty">caught up</div>
        </div>
      </div>`
    ;({ element } = await mountController("notifications-menu", Controller, liveHtml))
    const badge = element.querySelector("[data-role='badge']")
    expect(badge.textContent).toBe("99+")

    const next = document.createElement("span")
    next.setAttribute("data-notifications-menu-target", "supportTicketUnread")
    next.dataset.count = "nope"
    next.hidden = true
    element.querySelector("[data-notifications-menu-target='supportTicketUnread']").replaceWith(next)
    await tick()

    expect(badge.textContent).toBe("99")
    expect(element.querySelector("[data-role='bell']").getAttribute("aria-label")).toBe("Notifications, 99 unread")
  })

  it("skips badge updates when the badge target is absent", async () => {
    const sparse = `
      <div data-controller="notifications-menu">
        <button data-notifications-menu-target="trigger" data-action="click->notifications-menu#toggle" data-role="bell" aria-expanded="false">bell</button>
        <div data-notifications-menu-target="panel" class="hidden" data-role="panel"></div>
      </div>`
    ;({ element, application } = await mountController("notifications-menu", Controller, sparse))
    expect(element.querySelector("[data-role='bell']").getAttribute("aria-expanded")).toBe("false")
    click(element.querySelector("[data-role='bell']"))
    expect(element.querySelector("[data-role='panel']").classList.contains("hidden")).toBe(false)
  })

  it("refreshes without a trigger, unread counters, or list", async () => {
    const sparse = `
      <div data-controller="notifications-menu">
        <span data-notifications-menu-target="badge" data-role="badge"></span>
        <div data-notifications-menu-target="panel" class="hidden" data-role="panel"></div>
        <div data-notifications-menu-target="empty" data-role="empty">caught up</div>
      </div>`
    ;({ element, application } = await mountController("notifications-menu", Controller, sparse))
    const ctrl = controllerFor(application, element, "notifications-menu")
    ctrl.toggle({ stopPropagation() {} })
    expect(element.querySelector("[data-role='panel']").classList.contains("hidden")).toBe(false)
    ctrl.close()
    expect(element.querySelector("[data-role='panel']").classList.contains("hidden")).toBe(true)
    expect(element.querySelector("[data-role='empty']").classList.contains("hidden")).toBe(false)
    expect(element.querySelector("[data-role='badge']").classList.contains("hidden")).toBe(true)
  })
})
