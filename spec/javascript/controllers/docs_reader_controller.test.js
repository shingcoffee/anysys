import { afterEach, beforeEach, describe, it, expect, vi } from "vitest"
import Controller from "controllers/docs_reader_controller"
import { mountController, controllerFor, click, tick } from "../support/stimulus.js"

const reader = (attributes = "") => `
  <div data-controller="docs-reader" ${attributes}>
    <input type="search" data-docs-reader-target="search" data-surface="desktop">
    <input type="search" data-docs-reader-target="search" data-surface="mobile">
    <nav>
      <a href="#intro" data-docs-reader-target="tocLink">Intro</a>
      <a href="#setup" data-docs-reader-target="tocLink">Setup</a>
      <a href="#missing" data-docs-reader-target="tocLink">Missing</a>
      <a href="#usage" data-docs-reader-target="tocLink">Usage</a>
    </nav>
    <nav><a href="#setup" data-docs-reader-target="tocLink">Setup (inline)</a></nav>
    <div data-docs-reader-target="prose">
      <h2 id="intro">Intro</h2>
      <pre><code>first()</code></pre>
      <h2 id="setup">Setup</h2>
      <h2 id="usage">Usage</h2>
      <pre><code>second()</code></pre>
    </div>
    <template data-docs-reader-target="copyTemplate"><div class="wrapper" data-docs-code><button type="button" data-action="docs-reader#copy"><span data-docs-copy-label>Copy</span></button></div></template>
    <textarea data-editor></textarea>
    <div contenteditable="true" data-rich></div>
  </div>`

const inMain = (markup) => `<main id="main-content">${markup}</main>`

describe("docs-reader controller", () => {
  let application, element, ctrl, observer, visibility, main, headingTops
  const originalVisibility = Object.getOwnPropertyDescriptor(Element.prototype, "checkVisibility")
  const originalExec = document.execCommand

  beforeEach(() => {
    visibility = new WeakMap()
    headingTops = { intro: 130, setup: 600, usage: 1200 }
    Object.defineProperty(Element.prototype, "checkVisibility", {
      configurable: true,
      value: vi.fn(function() { return visibility.get(this) ?? true })
    })
    vi.stubGlobal("ResizeObserver", vi.fn(function(callback) {
      observer = { observe: vi.fn(), disconnect: vi.fn(), callback }
      return observer
    }))
    vi.stubGlobal("requestAnimationFrame", vi.fn((callback) => setTimeout(callback, 0)))
    vi.stubGlobal("cancelAnimationFrame", vi.fn((id) => clearTimeout(id)))
  })

  afterEach(async () => {
    vi.useRealTimers()
    element?.remove()
    await tick()
    application?.stop()
    document.body.innerHTML = ""
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
    if (originalVisibility) Object.defineProperty(Element.prototype, "checkVisibility", originalVisibility)
    else delete Element.prototype.checkVisibility
    document.execCommand = originalExec
  })

  async function mount(markup = inMain(reader()), prepare) {
    if (prepare) {
      const connect = Controller.prototype.connect
      vi.spyOn(Controller.prototype, "connect").mockImplementation(function() {
        prepare(this.element)
        connect.call(this)
      })
    }
    ;({ application, element } = await mountController("docs-reader", Controller, markup))
    ctrl = controllerFor(application, element, "docs-reader")
    main = element.closest("main")
  }

  // Mock the scroll pane and heading geometry: tops move with main.scrollTop.
  function layout(scope, { clientHeight = 800, scrollHeight = 3000, top = 100 } = {}) {
    const pane = scope.closest("main")
    Object.defineProperties(pane, {
      clientHeight: { configurable: true, value: clientHeight },
      scrollHeight: { configurable: true, value: scrollHeight }
    })
    pane.getBoundingClientRect = () => new DOMRect(0, top, 1000, clientHeight)
    Object.keys(headingTops).forEach((id) => {
      const heading = scope.querySelector(`#${id}`)
      if (heading) heading.getBoundingClientRect = () => new DOMRect(0, headingTops[id] - pane.scrollTop, 600, 30)
    })
  }

  const current = () => Array.from(element.querySelectorAll("a[aria-current='location']")).map((link) => link.textContent)

  async function scrollTo(position) {
    main.scrollTop = position
    main.dispatchEvent(new Event("scroll"))
    await tick()
  }

  describe("pane height and scroll-spy", () => {
    it("publishes the scroll pane height and observes it for resizes", async () => {
      await mount(undefined, (scope) => layout(scope))
      expect(element.style.getPropertyValue("--docs-pane-height")).toBe("800px")
      expect(observer.observe).toHaveBeenCalledWith(main)
      Object.defineProperty(main, "clientHeight", { configurable: true, value: 640 })
      observer.callback()
      expect(element.style.getPropertyValue("--docs-pane-height")).toBe("640px")
    })

    it("marks the first heading at the top and follows the last heading passed by the reading line", async () => {
      await mount(undefined, (scope) => layout(scope))
      expect(current()).toEqual(["Intro"])

      await scrollTo(500) // setup at 100 <= 100 + 120
      expect(current()).toEqual(["Setup", "Setup (inline)"])

      await scrollTo(1100)
      expect(current()).toEqual(["Usage"])
      expect(element.querySelector("a[href='#missing']").hasAttribute("aria-current")).toBe(false)
    })

    it("marks the last heading once the pane is scrolled to its end", async () => {
      headingTops.usage = 2900
      await mount(undefined, (scope) => layout(scope))
      await scrollTo(2200)
      expect(current()).toEqual(["Usage"])
    })

    it("keeps the first heading on a page that does not scroll", async () => {
      await mount(undefined, (scope) => layout(scope, { clientHeight: 800, scrollHeight: 800 }))
      expect(current()).toEqual(["Intro"])
    })

    it("honours a configured reading offset", async () => {
      await mount(inMain(reader('data-docs-reader-offset-value="10"')), (scope) => layout(scope))
      await scrollTo(450) // setup at 150, beyond 100 + 10
      expect(current()).toEqual(["Intro"])
    })

    it("coalesces scroll events into one animation frame", async () => {
      await mount(undefined, (scope) => layout(scope))
      const spy = vi.spyOn(ctrl, "spy")
      main.scrollTop = 500
      main.dispatchEvent(new Event("scroll"))
      main.dispatchEvent(new Event("scroll"))
      expect(requestAnimationFrame).toHaveBeenCalledTimes(1)
      await tick()
      expect(spy).toHaveBeenCalledTimes(1)
      expect(current()).toEqual(["Setup", "Setup (inline)"])
    })

    it("does nothing when no TOC link resolves to a heading", async () => {
      const markup = inMain(reader().replace(/id="(intro|setup|usage)"/g, ""))
      await mount(markup, (scope) => layout(scope))
      expect(current()).toEqual([])
      await scrollTo(500)
      expect(current()).toEqual([])
    })

    it("runs only the keyboard and code enhancements outside a scroll pane", async () => {
      await mount(reader())
      expect(main).toBeNull()
      expect(ResizeObserver).not.toHaveBeenCalled()
      expect(element.style.getPropertyValue("--docs-pane-height")).toBe("")
      expect(element.querySelectorAll("[data-docs-code]")).toHaveLength(2)
      element.querySelector("[data-surface='desktop']").blur()
      document.body.dispatchEvent(new KeyboardEvent("keydown", { key: "/", bubbles: true, cancelable: true }))
      expect(document.activeElement).toBe(element.querySelector("[data-surface='desktop']"))
      ctrl.disconnect()
    })

    it("removes listeners, observers and pending frames on disconnect", async () => {
      await mount(undefined, (scope) => layout(scope))
      main.scrollTop = 500
      main.dispatchEvent(new Event("scroll"))
      const spy = vi.spyOn(ctrl, "spy")
      const removal = vi.spyOn(main, "removeEventListener")
      ctrl.disconnect()
      expect(cancelAnimationFrame).toHaveBeenCalled()
      expect(removal).toHaveBeenCalledWith("scroll", ctrl.onScroll)
      expect(observer.disconnect).toHaveBeenCalledOnce()
      await tick()
      expect(spy).not.toHaveBeenCalled()
    })
  })

  describe("search shortcut", () => {
    const press = (target, options = {}) => {
      const event = new KeyboardEvent("keydown", { key: "/", bubbles: true, cancelable: true, ...options })
      target.dispatchEvent(event)
      return event
    }

    it("focuses and selects the first visible search field", async () => {
      await mount()
      const [desktop, mobile] = element.querySelectorAll("input[type='search']")
      visibility.set(desktop, false)
      mobile.value = "auth"
      const select = vi.spyOn(mobile, "select")
      const event = press(document.body)
      expect(event.defaultPrevented).toBe(true)
      expect(document.activeElement).toBe(mobile)
      expect(select).toHaveBeenCalled()
    })

    it.each([
      ["a modified key", { ctrlKey: true }],
      ["meta", { metaKey: true }],
      ["alt", { altKey: true }],
      ["another key", { key: "k" }]
    ])("ignores %s", async (_, options) => {
      await mount()
      expect(press(document.body, options).defaultPrevented).toBe(false)
      expect(document.activeElement).toBe(document.body)
    })

    it.each(["[data-editor]", "input[data-surface='mobile']"])("leaves typing in %s alone", async (selector) => {
      await mount()
      const field = element.querySelector(selector)
      field.focus()
      expect(press(field).defaultPrevented).toBe(false)
      expect(document.activeElement).toBe(field)
    })

    it("leaves contenteditable regions alone", async () => {
      await mount()
      const rich = element.querySelector("[data-rich]")
      Object.defineProperty(rich, "isContentEditable", { configurable: true, value: true })
      expect(press(rich).defaultPrevented).toBe(false)
    })

    it("respects an event another handler already consumed", async () => {
      await mount()
      document.addEventListener("keydown", (event) => event.preventDefault(), { capture: true, once: true })
      press(document.body)
      expect(document.activeElement).toBe(document.body)
    })

    it("does nothing when every search field is hidden, and handles non-element targets", async () => {
      await mount()
      element.querySelectorAll("input[type='search']").forEach((input) => visibility.set(input, false))
      expect(press(document.body).defaultPrevented).toBe(false)
      expect(press(document).defaultPrevented).toBe(false)
      expect(document.activeElement).toBe(document.body)
    })

    it("stops listening after disconnect", async () => {
      await mount()
      ctrl.disconnect()
      expect(press(document.body).defaultPrevented).toBe(false)
    })
  })

  describe("code copy", () => {
    it("wraps each prose code block once, including after reconnecting", async () => {
      await mount()
      const wrappers = element.querySelectorAll("[data-docs-code]")
      expect(wrappers).toHaveLength(2)
      wrappers.forEach((wrapper) => expect(wrapper.firstElementChild.tagName).toBe("PRE"))
      element.removeAttribute("data-controller")
      await tick()
      element.setAttribute("data-controller", "docs-reader")
      await tick()
      expect(element.querySelectorAll("[data-docs-code]")).toHaveLength(2)
    })

    it("skips enhancement without a template", async () => {
      await mount(inMain(reader().replace('data-docs-reader-target="copyTemplate"', "")))
      expect(element.querySelectorAll("[data-docs-code]")).toHaveLength(0)
    })

    it("copies the block text with the clipboard API and resets the label", async () => {
      const writeText = vi.fn(() => Promise.resolve())
      vi.stubGlobal("navigator", { clipboard: { writeText } })
      await mount(inMain(reader('data-docs-reader-copy-label-value="复制" data-docs-reader-copied-label-value="已复制"')))
      await tick() // Stimulus binds actions on the injected buttons after connect.
      vi.useFakeTimers()
      const button = element.querySelectorAll("[data-docs-code] button")[1]
      button.dispatchEvent(new Event("click", { bubbles: true }))
      await vi.advanceTimersByTimeAsync(0)
      expect(writeText).toHaveBeenCalledWith("second()")
      expect(button.textContent).toBe("已复制")
      expect(button.dataset.copied).toBe("true")
      await vi.advanceTimersByTimeAsync(2000)
      expect(button.textContent).toBe("复制")
      expect(button.dataset.copied).toBeUndefined()
      expect(ctrl.timers.size).toBe(0)
    })

    it("uses the default labels and falls back to execCommand without the clipboard API", async () => {
      vi.stubGlobal("navigator", {})
      document.execCommand = vi.fn(() => true)
      await mount()
      const button = element.querySelector("[data-docs-code] button")
      await ctrl.copy({ currentTarget: button })
      expect(document.execCommand).toHaveBeenCalledWith("copy")
      expect(document.querySelector("textarea[readonly]")).toBeNull()
      expect(button.textContent).toBe("Copied")
      ctrl.disconnect()
      expect(ctrl.timers.size).toBe(0)
      expect(button.textContent).toBe("Copied")
    })

    it("leaves the label unchanged when copying fails", async () => {
      vi.stubGlobal("navigator", {})
      document.execCommand = vi.fn(() => false)
      await mount()
      const button = element.querySelector("[data-docs-code] button")
      await ctrl.copy({ currentTarget: button })
      expect(button.textContent).toBe("Copy")
      expect(button.dataset.copied).toBeUndefined()
    })

    it("binds the cloned button action through Stimulus", async () => {
      const writeText = vi.fn(() => Promise.resolve())
      vi.stubGlobal("navigator", { clipboard: { writeText } })
      await mount()
      await tick()
      await click(element.querySelector("[data-docs-code] button"))
      expect(writeText).toHaveBeenCalledWith("first()")
    })
  })
})
