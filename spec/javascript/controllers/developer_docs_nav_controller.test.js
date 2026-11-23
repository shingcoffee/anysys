import { afterEach, beforeEach, describe, it, expect, vi } from "vitest"
import Controller from "controllers/developer_docs_nav_controller"
import { mountController, controllerFor, click, tick } from "../support/stimulus.js"

const html = `
  <div data-controller="developer-docs-nav">
    <aside data-developer-docs-nav-target="desktop">Desktop contents</aside>
    <button data-developer-docs-nav-target="trigger"
            data-action="click->developer-docs-nav#openDrawer">open</button>
    <div data-developer-docs-nav-target="backdrop"
         data-action="click->developer-docs-nav#closeDrawer" class="hidden"></div>
    <div data-developer-docs-nav-target="drawer" role="dialog" aria-modal="true"
         class="invisible -translate-x-full">
      <button data-action="click->developer-docs-nav#closeDrawer">close</button>
      <input type="search">
      <div data-developer-docs-nav-target="drawerList">
        <details><summary tabindex="0">Closed group</summary>
          <a href="/closed" data-action="click->developer-docs-nav#navigate">Closed page</a>
        </details>
        <details open><summary tabindex="0">Open group</summary>
          <a href="/guide" data-action="click->developer-docs-nav#navigate">A page</a>
        </details>
      </div>
    </div>
    <button data-outside>Outside</button>
    <main id="main-content"></main>
  </div>`

const desktopHtml = html.replace("Desktop contents", `
  <input type="search">
  <div data-docs-nav-list="desktop">
    <details><summary>Another group</summary><a href="/other">Another guide</a></details>
    <a href="/desktop-guide" data-docs-current-guide>Current desktop guide</a>
  </div>`)

const target = (element, name) => element.querySelector(`[data-developer-docs-nav-target='${name}']`)
const key = (name, shiftKey = false) => {
  const event = new KeyboardEvent("keydown", { key: name, shiftKey, bubbles: true, cancelable: true })
  document.activeElement.dispatchEvent(event)
  return event
}

describe("developer-docs-nav controller", () => {
  let application, element, ctrl, observer, visibility
  const originalVisibility = Object.getOwnPropertyDescriptor(Element.prototype, "checkVisibility")

  beforeEach(() => {
    visibility = new WeakMap()
    // happy-dom has no layout/checkVisibility. Mock the native visibility boundary,
    // including the browser's no-box result for closed-details descendants.
    Object.defineProperty(Element.prototype, "checkVisibility", {
      configurable: true,
      value: vi.fn(function() {
        return visibility.get(this) ?? !this.matches("[data-developer-docs-nav-target='desktop']")
      })
    })
    vi.stubGlobal("ResizeObserver", vi.fn(function(callback) {
      observer = { observe: vi.fn(), disconnect: vi.fn(), callback }
      return observer
    }))
    vi.stubGlobal("requestAnimationFrame", vi.fn((callback) => setTimeout(callback, 0)))
    vi.stubGlobal("cancelAnimationFrame", vi.fn((id) => clearTimeout(id)))
    document.body.style.overflow = ""
  })

  afterEach(async () => {
    vi.useRealTimers()
    element?.remove()
    await tick()
    application?.stop()
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
    if (originalVisibility) Object.defineProperty(Element.prototype, "checkVisibility", originalVisibility)
    else delete Element.prototype.checkVisibility
    document.body.style.overflow = ""
  })

  async function mount(markup = html, prepare) {
    if (prepare) {
      const connect = Controller.prototype.connect
      vi.spyOn(Controller.prototype, "connect").mockImplementation(function() {
        prepare(this.element)
        connect.call(this)
      })
    }
    ;({ application, element } = await mountController("developer-docs-nav", Controller, markup))
    ctrl = controllerFor(application, element, "developer-docs-nav")
    const closedLink = element.querySelector("a[href='/closed']")
    if (closedLink) visibility.set(closedLink, false)
    const desktop = target(element, "desktop")
    if (desktop && !visibility.has(desktop)) visibility.set(desktop, false)
  }

  async function open() {
    target(element, "trigger").focus()
    await click(target(element, "trigger"))
  }

  function mockListLayout(list, current, { rowOffset = 350, rowHeight = 44, height = 200 } = {}) {
    // Mock the browser layout boundary with a bordered viewport and a row's
    // content offset. Unlike happy-dom's zero rectangles, these rects respond
    // to list scrolling. Real positioning/main-scroll evidence belongs to e2e.
    list.scrollTop = 100
    Object.defineProperties(list, {
      clientTop: { configurable: true, value: 2 },
      clientHeight: { configurable: true, value: height }
    })
    vi.spyOn(list, "getBoundingClientRect").mockReturnValue(new DOMRect(0, 100, 280, height + 4))
    vi.spyOn(current, "getBoundingClientRect").mockImplementation(() =>
      new DOMRect(0, 102 + rowOffset - list.scrollTop, 240, rowHeight))
  }

  it("starts closed, inert and aria-hidden, with the existing default labels", async () => {
    await mount()
    expect(target(element, "drawer").inert).toBe(true)
    expect(target(element, "drawer").getAttribute("aria-hidden")).toBe("true")
    expect(target(element, "drawer").tabIndex).toBe(-1)
    expect(target(element, "trigger").getAttribute("aria-expanded")).toBe("false")
    expect(target(element, "trigger").getAttribute("aria-label")).toBe("Open contents")
    expect(observer.observe).toHaveBeenCalledWith(element)
    expect(key("Escape").defaultPrevented).toBe(false)
    ctrl.closeDrawer()
    expect(document.body.style.overflow).toBe("")
  })

  it("opens the existing translated state and initially focuses the close control", async () => {
    await mount(html.replace('data-controller="developer-docs-nav"', `data-controller="developer-docs-nav"
      data-developer-docs-nav-open-label-value="打开目录" data-developer-docs-nav-close-label-value="关闭目录"`))
    expect(target(element, "trigger").getAttribute("aria-label")).toBe("打开目录")
    const focus = vi.spyOn(target(element, "drawer").querySelector("button"), "focus")
    await open()
    expect(target(element, "drawer").classList.contains("translate-x-0")).toBe(true)
    expect(target(element, "drawer").classList.contains("invisible")).toBe(true)
    expect(target(element, "drawer").classList.contains("-translate-x-full")).toBe(false)
    expect(target(element, "drawer").inert).toBe(false)
    expect(target(element, "drawer").getAttribute("aria-hidden")).toBe("false")
    expect(target(element, "trigger").getAttribute("aria-expanded")).toBe("true")
    expect(target(element, "trigger").getAttribute("aria-label")).toBe("关闭目录")
    expect(target(element, "backdrop").classList.contains("hidden")).toBe(false)
    expect(target(element, "backdrop").style.opacity).toBe("1")
    expect(document.body.style.overflow).toBe("hidden")
    expect(document.activeElement).toBe(target(element, "drawer").querySelector("button"))
    expect(focus).toHaveBeenCalledWith({ preventScroll: true })
  })

  describe("current guide reveal", () => {
    it.each([
      { position: "above", rowOffset: 60, rowHeight: 44, expected: 60 },
      { position: "below", rowOffset: 350, rowHeight: 44, expected: 194 },
      { position: "visible", rowOffset: 180, rowHeight: 44, expected: 100 },
      { position: "at the top edge", rowOffset: 100, rowHeight: 44, expected: 100 },
      { position: "at the bottom edge", rowOffset: 256, rowHeight: 44, expected: 100 },
      { position: "oversized below", rowOffset: 150, rowHeight: 260, expected: 150 },
      { position: "oversized above", rowOffset: 60, rowHeight: 300, expected: 60 },
      { position: "oversized at the top", rowOffset: 100, rowHeight: 260, expected: 100 }
    ])("reveals a $position customer row using only the list's nearest offset", async ({ rowOffset, rowHeight, expected }) => {
      await mount()
      const list = target(element, "drawerList")
      const current = element.querySelector("a[href='/guide']")
      current.setAttribute("data-docs-current-guide", "")
      list.append(current) // Static customer group: no owning details.
      mockListLayout(list, current, { rowOffset, rowHeight })
      const close = target(element, "drawer").querySelector("button")
      const focus = vi.spyOn(close, "focus")
      const currentFocus = vi.spyOn(current, "focus")
      const scrollIntoView = vi.spyOn(current, "scrollIntoView")
      const windowScroll = vi.spyOn(window, "scrollTo")
      const main = element.querySelector("#main-content")
      main.scrollTop = 321
      main.scrollLeft = 17

      await open()

      expect(list.scrollTop).toBe(expected)
      const row = current.getBoundingClientRect()
      if (rowHeight <= list.clientHeight) {
        expect(row.top).toBeGreaterThanOrEqual(102)
        expect(row.bottom).toBeLessThanOrEqual(302)
      } else {
        expect(row.top).toBe(102)
      }
      expect(document.activeElement).toBe(close)
      expect(focus).toHaveBeenCalledWith({ preventScroll: true })
      expect(focus.mock.invocationCallOrder[0]).toBeLessThan(current.getBoundingClientRect.mock.invocationCallOrder[0])
      expect(currentFocus).not.toHaveBeenCalled()
      expect(scrollIntoView).not.toHaveBeenCalled()
      expect(windowScroll).not.toHaveBeenCalled()
      expect(main.scrollTop).toBe(321)
      expect(main.scrollLeft).toBe(17)
      expect(list.scrollLeft).toBe(0)
    })

    it.each([false, true])("opens only the owning developer group before measuring (initially open: %s)", async (initiallyOpen) => {
      await mount()
      const list = target(element, "drawerList")
      const current = element.querySelector("a[href='/guide']")
      current.setAttribute("data-docs-current-guide", "")
      const group = current.closest("details")
      group.open = initiallyOpen
      mockListLayout(list, current)
      const measure = current.getBoundingClientRect.getMockImplementation()
      current.getBoundingClientRect.mockImplementation(() => {
        expect(group.open).toBe(true)
        return measure()
      })

      await open()

      expect(group.open).toBe(true)
      expect(element.querySelector("details").open).toBe(false)
      expect(list.scrollTop).toBe(194)
      expect(document.activeElement).toBe(target(element, "drawer").querySelector("button"))
    })

    it("starts search results at the top using only the pinned canonical marker", async () => {
      await mount()
      const list = target(element, "drawerList")
      const result = element.querySelector("a[href='/guide']")
      const header = target(element, "drawer").querySelector("input")
      header.insertAdjacentHTML("afterend", '<a href="/guide" data-docs-current-guide aria-current="page">Reading now</a>')
      const current = target(element, "drawer").querySelector("[data-docs-current-guide]")
      list.scrollTop = 180
      result.closest("details").open = false
      const listMeasure = vi.spyOn(list, "getBoundingClientRect")
      const resultMeasure = vi.spyOn(result, "getBoundingClientRect")
      const contextMeasure = vi.spyOn(current, "getBoundingClientRect")

      await open()

      expect(list.scrollTop).toBe(0)
      expect(result.closest("details").open).toBe(false)
      expect(listMeasure).not.toHaveBeenCalled()
      expect(resultMeasure).not.toHaveBeenCalled()
      expect(contextMeasure).not.toHaveBeenCalled()
      expect(document.activeElement).toBe(target(element, "drawer").querySelector("button"))
    })

    it("preserves the list position when only the desktop surface has a current marker", async () => {
      await mount()
      target(element, "desktop").innerHTML = '<a href="/guide" data-docs-current-guide>Current desktop guide</a>'
      const list = target(element, "drawerList")
      list.scrollTop = 180
      const measure = vi.spyOn(list, "getBoundingClientRect")

      await open()

      expect(list.scrollTop).toBe(180)
      expect(measure).not.toHaveBeenCalled()
      expect(document.activeElement).toBe(target(element, "drawer").querySelector("button"))
    })

    it("supports a current marker without the optional list target", async () => {
      await mount(html.replace('data-developer-docs-nav-target="drawerList"', "").replace('href="/guide"', 'href="/guide" data-docs-current-guide'))
      const current = element.querySelector("[data-docs-current-guide]")
      const measure = vi.spyOn(current, "getBoundingClientRect")

      await open()

      expect(ctrl.isOpen).toBe(true)
      expect(measure).not.toHaveBeenCalled()
      expect(document.activeElement).toBe(target(element, "drawer").querySelector("button"))
    })

    it("safely skips geometry for a list with no layout height", async () => {
      await mount()
      const list = target(element, "drawerList")
      const current = element.querySelector("a[href='/guide']")
      current.setAttribute("data-docs-current-guide", "")
      mockListLayout(list, current, { height: 0 })

      await open()

      expect(list.scrollTop).toBe(100)
      expect(list.getBoundingClientRect).not.toHaveBeenCalled()
      expect(current.getBoundingClientRect).not.toHaveBeenCalled()
      expect(document.activeElement).toBe(target(element, "drawer").querySelector("button"))
    })

    it("remeasures on reopening after the owning group was manually closed", async () => {
      await mount()
      const list = target(element, "drawerList")
      const current = element.querySelector("a[href='/guide']")
      current.setAttribute("data-docs-current-guide", "")
      mockListLayout(list, current)
      await open()
      expect(list.scrollTop).toBe(194)
      ctrl.closeDrawer()
      current.closest("details").open = false
      list.scrollTop = 400

      await open()

      expect(list.scrollTop).toBe(350)
      expect(current.closest("details").open).toBe(true)
      expect(current.getBoundingClientRect).toHaveBeenCalledTimes(2)
      expect(document.activeElement).toBe(target(element, "drawer").querySelector("button"))
    })
  })

  describe("desktop current guide reveal", () => {
    async function mountDesktop(markup = desktopHtml, { visible = true, rowOffset = 350 } = {}) {
      let desktop, list, current
      await mount(markup, (scope) => {
        // Prepare the native layout/visibility boundaries before real Stimulus
        // connect, so this exercises initial layout rather than a manual reveal.
        desktop = scope.querySelector("aside")
        list = desktop.querySelector("div")
        current = list.querySelector("a[href='/desktop-guide']")
        visibility.set(desktop, visible)
        const trigger = target(scope, "trigger")
        if (trigger) visibility.set(trigger, !visible)
        mockListLayout(list, current, { rowOffset })
        scope.querySelector("#main-content").scrollTop = 321
        scope.querySelector("[data-outside]").focus()
      })
      return { desktop, list, current }
    }

    function setDesktopVisible(desktop, visible) {
      visibility.set(desktop, visible)
      visibility.set(target(element, "trigger"), !visible)
    }

    it("reveals the initial visible desktop row without focusing or scrolling the article/window", async () => {
      const windowScroll = vi.spyOn(window, "scrollTo")
      const { desktop, list, current } = await mountDesktop()

      expect(list.scrollTop).toBe(194)
      const row = current.getBoundingClientRect()
      expect(row.top).toBeGreaterThanOrEqual(102)
      expect(row.bottom).toBe(302)
      expect(document.activeElement).toBe(element.querySelector("[data-outside]"))
      expect(element.querySelector("#main-content").scrollTop).toBe(321)
      expect(windowScroll).not.toHaveBeenCalled()
      expect(requestAnimationFrame).not.toHaveBeenCalled()
      expect(desktop.tabIndex).toBe(-1)
      expect(target(element, "drawer").inert).toBe(true)
      expect(document.body.style.overflow).toBe("")
    })

    it.each(["observer", "window"])("reveals once when %s enters desktop, preserving later user scroll", async (source) => {
      const { desktop, list, current } = await mountDesktop(desktopHtml, { visible: false, rowOffset: 60 })
      expect(list.scrollTop).toBe(100)
      expect(current.getBoundingClientRect).not.toHaveBeenCalled()
      setDesktopVisible(desktop, true)

      if (source === "observer") observer.callback()
      else window.dispatchEvent(new Event("resize"))

      expect(list.scrollTop).toBe(60)
      expect(document.activeElement).toBe(element.querySelector("[data-outside]"))
      list.scrollTop = 400 // User browses another group.
      list.dispatchEvent(new Event("scroll"))
      observer.callback()
      window.dispatchEvent(new Event("resize"))
      expect(list.scrollTop).toBe(400)
      expect(current.getBoundingClientRect).toHaveBeenCalledOnce()

      setDesktopVisible(desktop, false)
      observer.callback()
      expect(list.scrollTop).toBe(400)
      setDesktopVisible(desktop, true)
      observer.callback()
      expect(list.scrollTop).toBe(60)
      expect(current.getBoundingClientRect).toHaveBeenCalledTimes(2)
    })

    it("waits for the desktop rail to be visible before revealing its initial layout", async () => {
      const { desktop, list, current } = await mountDesktop(desktopHtml, { visible: false })
      visibility.set(target(element, "trigger"), false)
      observer.callback()
      expect(list.scrollTop).toBe(100)
      expect(current.getBoundingClientRect).not.toHaveBeenCalled()

      visibility.set(desktop, true)
      observer.callback()

      expect(list.scrollTop).toBe(194)
      expect(current.getBoundingClientRect).toHaveBeenCalledOnce()
    })

    it("resets pinned-context results only on desktop entry, preserving user scroll on repeated notifications", async () => {
      const markup = desktopHtml.replace("data-docs-current-guide", "").replace('  <input type="search">',
        '  <input type="search"><a href="/desktop-guide" data-docs-current-guide>Reading now</a>')
      const { desktop, list, current } = await mountDesktop(markup)
      expect(list.scrollTop).toBe(0)
      expect(current.getBoundingClientRect).not.toHaveBeenCalled()
      expect(list.getBoundingClientRect).not.toHaveBeenCalled()

      list.scrollTop = 180
      observer.callback()
      window.dispatchEvent(new Event("resize"))
      expect(list.scrollTop).toBe(180)
      expect(document.activeElement).toBe(element.querySelector("[data-outside]"))

      setDesktopVisible(desktop, false)
      observer.callback()
      expect(list.scrollTop).toBe(180)
      setDesktopVisible(desktop, true)
      observer.callback()
      expect(list.scrollTop).toBe(0)
    })

    it("expands only the owning developer details on entry and respects manual closure until the next entry", async () => {
      const markup = desktopHtml.replace('<a href="/desktop-guide" data-docs-current-guide>Current desktop guide</a>',
        '<details data-current-group><summary>Current group</summary><a href="/desktop-guide" data-docs-current-guide>Current desktop guide</a></details>')
      const { desktop, list, current } = await mountDesktop(markup, { visible: false })
      const group = current.closest("details")
      const measure = current.getBoundingClientRect.getMockImplementation()
      current.getBoundingClientRect.mockImplementation(() => {
        expect(group.open).toBe(true)
        return measure()
      })
      setDesktopVisible(desktop, true)
      observer.callback()
      expect(group.open).toBe(true)
      expect(desktop.querySelector("details").open).toBe(false)
      expect(list.scrollTop).toBe(194)

      group.open = false
      list.scrollTop = 400
      observer.callback()
      window.dispatchEvent(new Event("resize"))
      expect(group.open).toBe(false)
      expect(list.scrollTop).toBe(400)
      expect(current.getBoundingClientRect).toHaveBeenCalledOnce()

      setDesktopVisible(desktop, false)
      observer.callback()
      setDesktopVisible(desktop, true)
      observer.callback()
      expect(group.open).toBe(true)
      expect(list.scrollTop).toBe(350)
      expect(desktop.querySelector("details").open).toBe(false)
    })

    it.each(["desktop", "list", "current"])("safely preserves initial position when the optional %s hook is absent", async (missing) => {
      const hooks = {
        desktop: 'data-developer-docs-nav-target="desktop"',
        list: 'data-docs-nav-list="desktop"',
        current: "data-docs-current-guide"
      }
      const { list, current } = await mountDesktop(desktopHtml.replace(hooks[missing], ""))
      // A marker in the other surface is not a desktop current-guide fallback.
      element.querySelector("a[href='/guide']").setAttribute("data-docs-current-guide", "")
      observer.callback()
      expect(list.scrollTop).toBe(100)
      expect(current.getBoundingClientRect).not.toHaveBeenCalled()
      expect(document.activeElement).toBe(element.querySelector("[data-outside]"))
    })

    it("keeps the existing open-drawer dismissal/focus return when desktop becomes visible", async () => {
      const { desktop, list, current } = await mountDesktop(desktopHtml, { visible: false })
      await open()
      setDesktopVisible(desktop, true)

      observer.callback()

      expect(ctrl.isOpen).toBe(false)
      expect(target(element, "drawer").inert).toBe(true)
      expect(document.activeElement).toBe(desktop)
      expect(document.body.style.overflow).toBe("")
      expect(list.scrollTop).toBe(194)
      expect(current.getBoundingClientRect).toHaveBeenCalledOnce()
      expect(element.querySelector("#main-content").scrollTop).toBe(321)
    })

    it("supports the desktop rail without optional drawer, backdrop or trigger targets", async () => {
      const markup = desktopHtml.replace('data-developer-docs-nav-target="drawer"', "")
        .replace('data-developer-docs-nav-target="backdrop"', "")
        .replace('data-developer-docs-nav-target="trigger"', "")
      const { list } = await mountDesktop(markup)
      observer.callback()
      expect(list.scrollTop).toBe(194)
      expect(ctrl.isOpen).toBe(false)
      expect(document.activeElement).toBe(element.querySelector("[data-outside]"))
      expect(element.querySelector("#main-content").scrollTop).toBe(321)
    })

    it("reveals initial desktop layout again on real Stimulus reconnection", async () => {
      const { list } = await mountDesktop()
      expect(list.scrollTop).toBe(194)
      element.removeAttribute("data-controller")
      await tick()
      element.setAttribute("data-controller", "developer-docs-nav")
      await tick()
      expect(observer.observe).toHaveBeenCalledWith(element)
      expect(list.scrollTop).toBe(194)
      expect(document.activeElement).toBe(element.querySelector("[data-outside]"))
    })
  })

  it("uses the close-label default while open", async () => {
    await mount()
    await open()
    expect(target(element, "trigger").getAttribute("aria-label")).toBe("Close contents")
  })

  it.each(["", "auto", "scroll", "hidden"])("restores prior overflow %j even after repeated opening/closing", async (overflow) => {
    await mount()
    document.body.style.overflow = overflow
    await open()
    ctrl.openDrawer()
    ctrl.closeDrawer()
    ctrl.closeDrawer()
    expect(document.body.style.overflow).toBe(overflow)
    expect(target(element, "drawer").inert).toBe(true)
    expect(target(element, "drawer").getAttribute("aria-hidden")).toBe("true")
    expect(document.activeElement).toBe(target(element, "trigger"))
  })

  it("closes on Escape and returns focus without propagating the Escape", async () => {
    await mount()
    await open()
    const bubble = vi.fn()
    element.addEventListener("keydown", bubble)
    expect(key("Escape").defaultPrevented).toBe(true)
    expect(bubble).not.toHaveBeenCalled()
    expect(document.activeElement).toBe(target(element, "trigger"))
    expect(target(element, "drawer").classList.contains("-translate-x-full")).toBe(true)
    expect(target(element, "trigger").getAttribute("aria-expanded")).toBe("false")
  })

  it.each(["backdrop", "close"])("dismisses from %s and restores focus", async (control) => {
    await mount()
    await open()
    await click(control === "close" ? target(element, "drawer").querySelector("button") : target(element, "backdrop"))
    expect(target(element, "drawer").inert).toBe(true)
    expect(document.activeElement).toBe(target(element, "trigger"))
  })

  it("wraps Tab and Shift+Tab while leaving intermediate keys to the browser", async () => {
    await mount()
    await open()
    const first = target(element, "drawer").querySelector("button")
    const last = element.querySelector("a[href='/guide']")
    expect(key("Tab").defaultPrevented).toBe(false)
    expect(key("Tab", true).defaultPrevented).toBe(true)
    expect(document.activeElement).toBe(last)
    expect(key("Tab", true).defaultPrevented).toBe(false)
    expect(key("Tab").defaultPrevented).toBe(true)
    expect(document.activeElement).toBe(first)
    expect(key("Enter").defaultPrevented).toBe(false)
    target(element, "drawer").focus()
    expect(key("Tab").defaultPrevented).toBe(true)
    expect(document.activeElement).toBe(first)
    target(element, "drawer").focus()
    expect(key("Tab", true).defaultPrevented).toBe(true)
    expect(document.activeElement).toBe(last)
  })

  it("includes only rendered, operable controls and refreshes after details expands", async () => {
    await mount()
    target(element, "drawer").insertAdjacentHTML("beforeend", `
      <button disabled>Disabled</button>
      <a href="/disabled" aria-disabled="true">Disabled link</a>
      <button tabindex="-1">Non-tabbable</button><input type="hidden">
      <div inert><a href="/inert">Inert link</a></div><a href="/hidden" hidden>Hidden link</a>`)
    visibility.set(element.querySelector("a[href='/hidden']"), false)
    await open()
    const close = target(element, "drawer").querySelector("button")
    const search = target(element, "drawer").querySelector("input")
    const summaries = Array.from(element.querySelectorAll("summary"))
    const closedLink = element.querySelector("a[href='/closed']")
    const openLink = element.querySelector("a[href='/guide']")
    expect(ctrl.focusableElements()).toEqual([close, search, ...summaries, openLink])
    element.querySelector("details").open = true
    visibility.set(closedLink, true)
    expect(ctrl.focusableElements()).toEqual([close, search, summaries[0], closedLink, summaries[1], openLink])
    expect(closedLink.checkVisibility).toHaveBeenCalledWith({ visibilityProperty: true })
  })

  it("contains programmatic focus escapes, but leaves focus alone when closed", async () => {
    await mount()
    await open()
    element.querySelector("[data-outside]").focus()
    expect(document.activeElement).toBe(target(element, "drawer").querySelector("button"))
    ctrl.closeDrawer()
    element.querySelector("[data-outside]").focus()
    expect(document.activeElement).toBe(element.querySelector("[data-outside]"))
  })

  it("focuses the dialog itself and traps Tab when it has no operable controls", async () => {
    await mount()
    target(element, "drawer").innerHTML = ""
    const focus = vi.spyOn(target(element, "drawer"), "focus")
    await open()
    expect(document.activeElement).toBe(target(element, "drawer"))
    expect(focus).toHaveBeenCalledWith({ preventScroll: true })
    expect(key("Tab").defaultPrevented).toBe(true)
    expect(key("Tab", true).defaultPrevented).toBe(true)
    expect(document.activeElement).toBe(target(element, "drawer"))
  })

  it("closes for navigation without preventing the link or refocusing the opener", async () => {
    await mount()
    ctrl.navigate() // Desktop/closed navigation is a no-op.
    await open()
    const link = element.querySelector("a[href='/guide']")
    link.focus()
    const focus = vi.spyOn(target(element, "trigger"), "focus")
    const event = new MouseEvent("click", { bubbles: true, cancelable: true })
    link.dispatchEvent(event)
    expect(event.defaultPrevented).toBe(false)
    expect(link.getAttribute("href")).toBe("/guide")
    expect(focus).not.toHaveBeenCalled()
    expect(target(element, "drawer").inert).toBe(true)
    expect(document.body.style.overflow).toBe("")
  })

  it.each(["observer", "window"])("closes when %s sees the container-query trigger hidden, focusing the desktop rail", async (source) => {
    await mount()
    observer.callback() // Closed reader.
    await open()
    observer.callback() // Still narrow, including a wide viewport with expanded app sidebar.
    expect(ctrl.isOpen).toBe(true)
    visibility.set(target(element, "trigger"), false)
    visibility.set(target(element, "desktop"), true)
    if (source === "observer") observer.callback()
    else window.dispatchEvent(new Event("resize"))
    expect(ctrl.isOpen).toBe(false)
    expect(document.activeElement).toBe(target(element, "desktop"))
    expect(document.body.style.overflow).toBe("")
    ctrl.openDrawer()
    expect(ctrl.isOpen).toBe(false)
  })

  it.each(["missing", "hidden"])("handles an unavailable %s desktop focus destination", async (state) => {
    await mount(state === "missing" ? html.replace('data-developer-docs-nav-target="desktop"', "") : html)
    await open()
    target(element, "trigger").remove()
    ctrl.closeDrawer()
    expect(ctrl.isOpen).toBe(false)
    expect(document.body.style.overflow).toBe("")
  })

  it("supports the original drawer/backdrop targets without a trigger or desktop target", async () => {
    await mount(html.replace('data-developer-docs-nav-target="trigger"', "").replace('data-developer-docs-nav-target="desktop"', ""))
    const opener = element.querySelector("button")
    opener.focus()
    ctrl.openDrawer()
    await tick()
    observer.callback()
    expect(ctrl.isOpen).toBe(true)
    ctrl.closeDrawer()
    expect(document.activeElement).toBe(opener)
  })

  it.each(["drawer", "backdrop", "both"])("safely ignores opening with missing %s targets", async (missing) => {
    let markup = html
    for (const name of missing === "both" ? ["drawer", "backdrop"] : [missing]) {
      markup = markup.replace(`data-developer-docs-nav-target="${name}"`, "")
    }
    await mount(markup)
    ctrl.openDrawer()
    ctrl.closeDrawer()
    expect(ctrl.isOpen).toBe(false)
    expect(document.body.style.overflow).toBe("")
  })

  it("hides the backdrop after transition and cancels stale closing on immediate reopen", async () => {
    await mount()
    vi.useFakeTimers()
    ctrl.openDrawer()
    await vi.advanceTimersByTimeAsync(0)
    ctrl.closeDrawer()
    expect(target(element, "backdrop").classList.contains("hidden")).toBe(false)
    await vi.advanceTimersByTimeAsync(250)
    expect(target(element, "backdrop").classList.contains("hidden")).toBe(true)
    ctrl.openDrawer()
    ctrl.closeDrawer()
    ctrl.openDrawer()
    await vi.advanceTimersByTimeAsync(300)
    expect(target(element, "backdrop").classList.contains("hidden")).toBe(false)
    expect(target(element, "backdrop").style.opacity).toBe("1")
    expect(ctrl.isOpen).toBe(true)
  })

  it("cancels pending opening so immediate close cannot reveal or focus a closed dialog", async () => {
    await mount(html.replace('href="/guide"', 'href="/guide" data-docs-current-guide'))
    const list = target(element, "drawerList")
    const current = element.querySelector("[data-docs-current-guide]")
    mockListLayout(list, current)
    vi.useFakeTimers()
    ctrl.openDrawer()
    const focus = vi.spyOn(ctrl, "focusDrawer")
    const reveal = vi.spyOn(ctrl, "revealCurrentGuide")
    ctrl.closeDrawer()
    await vi.runAllTimersAsync()
    expect(focus).not.toHaveBeenCalled()
    expect(reveal).not.toHaveBeenCalled()
    expect(list.scrollTop).toBe(100)
    expect(current.getBoundingClientRect).not.toHaveBeenCalled()
    expect(target(element, "drawer").inert).toBe(true)
    expect(target(element, "backdrop").style.opacity).toBe("0")
  })

  it.each(["opening", "open", "closing"])("disconnect cleans up while %s, restoring scroll and removing all listeners", async (state) => {
    await mount(html.replace('href="/guide"', 'href="/guide" data-docs-current-guide'))
    const list = target(element, "drawerList")
    const current = element.querySelector("[data-docs-current-guide]")
    mockListLayout(list, current)
    document.body.style.overflow = "scroll"
    if (state === "open") await open()
    vi.useFakeTimers()
    if (state !== "open") ctrl.openDrawer()
    if (state === "closing") ctrl.closeDrawer()
    const focus = vi.spyOn(ctrl, "focusDrawer")
    const reveal = vi.spyOn(ctrl, "revealCurrentGuide")
    const sync = vi.spyOn(ctrl, "syncLayout")
    const documentRemoval = vi.spyOn(document, "removeEventListener")
    const windowRemoval = vi.spyOn(window, "removeEventListener")
    ctrl.disconnect()
    expect(observer.disconnect).toHaveBeenCalledOnce()
    expect(documentRemoval).toHaveBeenCalledWith("keydown", ctrl.onKeydown, true)
    expect(documentRemoval).toHaveBeenCalledWith("focusin", ctrl.onFocus)
    expect(windowRemoval).toHaveBeenCalledWith("resize", ctrl.onResize)
    expect(document.body.style.overflow).toBe("scroll")
    expect(target(element, "backdrop").classList.contains("hidden")).toBe(true)
    expect(list.scrollTop).toBe(state === "open" ? 194 : 100)
    focus.mockClear()
    await vi.runAllTimersAsync()
    expect(focus).not.toHaveBeenCalled()
    expect(reveal).not.toHaveBeenCalled()
    expect(list.scrollTop).toBe(state === "open" ? 194 : 100)
    window.dispatchEvent(new Event("resize"))
    element.querySelector("[data-outside]").focus()
    expect(key("Escape").defaultPrevented).toBe(false)
    expect(sync).not.toHaveBeenCalled()
    expect(document.activeElement).toBe(element.querySelector("[data-outside]"))
    expect(target(element, "backdrop").style.opacity).toBe("0")
  })

  it("cleans up through a real Stimulus disconnect after its target scope is removed", async () => {
    await mount()
    await open()
    element.removeAttribute("data-controller")
    await tick()
    expect(observer.disconnect).toHaveBeenCalledOnce()
    expect(document.body.style.overflow).toBe("")
    expect(target(element, "drawer").inert).toBe(true)
    expect(target(element, "trigger").getAttribute("aria-expanded")).toBe("false")
    expect(target(element, "backdrop").classList.contains("hidden")).toBe(true)
  })
})
