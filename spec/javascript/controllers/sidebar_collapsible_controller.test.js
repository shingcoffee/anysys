import { describe, it, expect, beforeEach, afterEach } from "vitest"
import Controller from "controllers/sidebar_collapsible_controller"
import { mountController, controllerFor, click, tick } from "../support/stimulus.js"

const COOKIE = "sidebar_state_maintenance"

const tooltip = `
  <div data-sidebar-collapsible-target="tooltip" role="tooltip" class="hidden">
    <span data-sidebar-collapsible-target="tooltipLabel"></span>
    <kbd data-sidebar-collapsible-target="tooltipShortcut" class="hidden"></kbd>
  </div>`

const html = (collapsed = "false", cookie = COOKIE) => `
  <div data-controller="sidebar-collapsible"
       data-sidebar-collapsible-collapsed-value="${collapsed}"
       data-sidebar-collapsible-cookie-value="${cookie}">
    <div data-sidebar-collapsible-target="full">
      <p>full sidebar</p>
      <button data-sidebar-collapsible-toggle
              data-sidebar-rail-label="Collapse sidebar"
              data-sidebar-rail-shortcut="⌘B"
              data-action="click->sidebar-collapsible#collapse"
              aria-expanded="true">collapse</button>
      <input type="search">
    </div>
    <div data-sidebar-collapsible-target="rail">
      <button data-sidebar-collapsible-toggle
              data-sidebar-rail-label="Expand sidebar"
              data-action="click->sidebar-collapsible#expand"
              aria-expanded="false">expand</button>
    </div>
    <button data-outside>outside</button>
    ${tooltip}
  </div>`

const full = (el) => el.querySelector("[data-sidebar-collapsible-target='full']")
const rail = (el) => el.querySelector("[data-sidebar-collapsible-target='rail']")
const collapseButton = (el) => full(el).querySelector("[data-sidebar-collapsible-toggle]")
const expandButton = (el) => rail(el).querySelector("[data-sidebar-collapsible-toggle]")
const toggles = (el) => [...el.querySelectorAll("[data-sidebar-collapsible-toggle]")]
const cookieValue = (name = COOKIE) =>
  document.cookie.split(/;\s*/).find((pair) => pair.startsWith(`${name}=`))?.split("=")[1]
const clearCookies = () => {
  document.cookie.split(/;\s*/).filter(Boolean).forEach((pair) => {
    document.cookie = `${pair.split("=")[0]}=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/`
  })
}
const press = (target, init) => {
  const event = new KeyboardEvent("keydown", { bubbles: true, cancelable: true, ...init })
  target.dispatchEvent(event)
  return event
}

// The controller listens on `document`; the shared harness stops each
// Application without disconnecting, so disconnect every mount explicitly.
let mounted = []
const mount = async (markup) => {
  const result = await mountController("sidebar-collapsible", Controller, markup)
  mounted.push(controllerFor(result.application, result.element, "sidebar-collapsible"))
  return result
}

describe("sidebar-collapsible controller", () => {
  beforeEach(() => {
    clearCookies()
  })

  afterEach(() => {
    mounted.forEach((ctrl) => ctrl.disconnect())
    mounted = []
  })

  describe("state", () => {
    it("renders the expanded state: data-state, inert rail, aria-expanded on every toggle", async () => {
      const { element } = await mount(html("false"))
      expect(element.dataset.state).toBe("expanded")
      expect(full(element).hasAttribute("inert")).toBe(false)
      expect(rail(element).hasAttribute("inert")).toBe(true)
      expect(toggles(element).map((btn) => btn.getAttribute("aria-expanded"))).toEqual(["true", "true"])
    })

    it("renders the collapsed state: inert full sidebar, interactive rail", async () => {
      const { element } = await mount(html("true"))
      expect(element.dataset.state).toBe("collapsed")
      expect(full(element).hasAttribute("inert")).toBe(true)
      expect(rail(element).hasAttribute("inert")).toBe(false)
      expect(toggles(element).map((btn) => btn.getAttribute("aria-expanded"))).toEqual(["false", "false"])
    })

    it("collapse, expand and toggle switch state and remember it in the session cookie", async () => {
      const { application, element } = await mount(html("false"))

      await click(collapseButton(element))
      expect(element.dataset.state).toBe("collapsed")
      expect(cookieValue()).toBe("collapsed")

      await click(expandButton(element))
      expect(element.dataset.state).toBe("expanded")
      expect(cookieValue()).toBe("expanded")

      const ctrl = controllerFor(application, element, "sidebar-collapsible")
      ctrl.toggle()
      expect(element.dataset.state).toBe("collapsed")
      ctrl.toggle()
      expect(element.dataset.state).toBe("expanded")
    })

    it("restores the cookie over the server value so Turbo snapshots match the latest choice", async () => {
      document.cookie = `${COOKIE}=collapsed; path=/`
      const collapsed = await mount(html("false"))
      expect(collapsed.element.dataset.state).toBe("collapsed")

      document.cookie = `${COOKIE}=expanded; path=/`
      const expanded = await mount(html("true"))
      expect(expanded.element.dataset.state).toBe("expanded")
    })

    it("keeps the server value when the cookie is missing, unrelated or unrecognised", async () => {
      document.cookie = "sidebar_state_modules=expanded; path=/"
      const other = await mount(html("true"))
      expect(other.element.dataset.state).toBe("collapsed")

      document.cookie = `${COOKIE}=garbage; path=/`
      const garbage = await mount(html("true"))
      expect(garbage.element.dataset.state).toBe("collapsed")
    })

    it("falls back to the default cookie name", async () => {
      const { application, element } = await mount(`<div data-controller="sidebar-collapsible"></div>`)
      controllerFor(application, element, "sidebar-collapsible").collapse()
      expect(cookieValue("sidebar_state")).toBe("collapsed")
    })
  })

  describe("focus", () => {
    it("moves focus to the visible toggle when the focused panel hides", async () => {
      const { application, element } = await mount(html("false"))
      const ctrl = controllerFor(application, element, "sidebar-collapsible")

      collapseButton(element).focus()
      ctrl.collapse()
      expect(document.activeElement).toBe(expandButton(element))

      ctrl.expand()
      expect(document.activeElement).toBe(collapseButton(element))
    })

    it("leaves focus alone when it is outside the panel being hidden", async () => {
      const { application, element } = await mount(html("false"))
      const outside = element.querySelector("[data-outside]")
      outside.focus()
      controllerFor(application, element, "sidebar-collapsible").collapse()
      expect(document.activeElement).toBe(outside)
    })

    it("tolerates a missing incoming panel or toggle", async () => {
      const { application, element } = await mount(`
        <div data-controller="sidebar-collapsible">
          <div data-sidebar-collapsible-target="full"><button id="inside">x</button></div>
        </div>`)
      const ctrl = controllerFor(application, element, "sidebar-collapsible")
      element.querySelector("#inside").focus()
      ctrl.collapse()
      expect(ctrl.collapsedValue).toBe(true)

      const noToggle = await mount(`
        <div data-controller="sidebar-collapsible" data-sidebar-collapsible-collapsed-value="true">
          <div data-sidebar-collapsible-target="full"></div>
          <div data-sidebar-collapsible-target="rail"><button id="rail-link">x</button></div>
        </div>`)
      noToggle.element.querySelector("#rail-link").focus()
      controllerFor(noToggle.application, noToggle.element, "sidebar-collapsible").expand()
      expect(noToggle.element.dataset.state).toBe("expanded")
    })
  })

  describe("rail shortcuts", () => {
    it("expandSearch opens the full sidebar and focuses its search field", async () => {
      const { application, element } = await mount(html("true"))
      controllerFor(application, element, "sidebar-collapsible").expandSearch()
      expect(element.dataset.state).toBe("expanded")
      expect(document.activeElement).toBe(element.querySelector("input[type='search']"))
      expect(cookieValue()).toBe("expanded")
    })

    it("expandSearch still expands when there is no search field or full target", async () => {
      const { application, element } = await mount(`
        <div data-controller="sidebar-collapsible" data-sidebar-collapsible-collapsed-value="true">
          <div data-sidebar-collapsible-target="full"></div>
        </div>`)
      controllerFor(application, element, "sidebar-collapsible").expandSearch()
      expect(element.dataset.state).toBe("expanded")

      const bare = await mount(`
        <div data-controller="sidebar-collapsible" data-sidebar-collapsible-collapsed-value="true">
          <div data-sidebar-collapsible-target="rail"></div>
        </div>`)
      const bareCtrl = controllerFor(bare.application, bare.element, "sidebar-collapsible")
      bareCtrl.expandSearch()
      expect(bareCtrl.collapsedValue).toBe(false)
    })

    it("expandGroup opens and focuses only the named group", async () => {
      const { application, element } = await mount(`
        <div data-controller="sidebar-collapsible" data-sidebar-collapsible-collapsed-value="true" data-sidebar-collapsible-cookie-value="sidebar_state_settings">
          <div data-sidebar-collapsible-target="full">
            <details><summary>  Email  </summary></details>
            <details><summary>  SMS  </summary></details>
            <details></details>
          </div>
          <div data-sidebar-collapsible-target="rail"></div>
          <button type="button" data-sidebar-rail-label="Email">Email</button>
          <button type="button" data-sidebar-rail-label="">blank</button>
        </div>`)
      const ctrl = controllerFor(application, element, "sidebar-collapsible")
      const details = element.querySelectorAll("details")

      ctrl.expandGroup({ currentTarget: element.querySelector("[data-sidebar-rail-label='Email']") })
      expect(element.dataset.state).toBe("expanded")
      expect(details[0].open).toBe(true)
      expect(details[1].open).toBe(false)
      expect(details[2].open).toBe(false)
      expect(document.activeElement).toBe(details[0].querySelector("summary"))
      expect(cookieValue("sidebar_state_settings")).toBe("expanded")

      ctrl.collapse()
      ctrl.expandGroup({ currentTarget: element.querySelector("[data-sidebar-rail-label='']") })
      expect(details[1].open).toBe(false)

      ctrl.collapse()
      ctrl.expandGroup({ currentTarget: null })
      expect(element.dataset.state).toBe("expanded")
    })

    it("expandGroup expands even when the full sidebar target is missing", async () => {
      const { application, element } = await mount(`
        <div data-controller="sidebar-collapsible" data-sidebar-collapsible-collapsed-value="true">
          <div data-sidebar-collapsible-target="rail"></div>
          <button type="button" data-sidebar-rail-label="Email">Email</button>
        </div>`)
      const ctrl = controllerFor(application, element, "sidebar-collapsible")
      ctrl.expandGroup({ currentTarget: element.querySelector("button") })
      expect(ctrl.collapsedValue).toBe(false)
      expect(element.querySelector("[data-sidebar-collapsible-target='rail']").hasAttribute("inert")).toBe(true)
    })
  })

  describe("keyboard shortcut", () => {
    it("toggles on Cmd+B and Ctrl+B and claims the keystroke", async () => {
      const { element } = await mount(html("false"))

      const meta = press(document.body, { key: "b", metaKey: true })
      expect(meta.defaultPrevented).toBe(true)
      expect(element.dataset.state).toBe("collapsed")

      press(document.body, { key: "B", ctrlKey: true })
      expect(element.dataset.state).toBe("expanded")
      expect(cookieValue()).toBe("expanded")
    })

    it("ignores other keys, extra modifiers and already-handled events", async () => {
      const { element } = await mount(html("false"))

      press(document.body, { key: "b" })
      press(document.body, { key: "k", metaKey: true })
      press(document.body, { ctrlKey: true })
      press(document.body, { key: "b", ctrlKey: true, shiftKey: true })
      press(document.body, { key: "b", ctrlKey: true, altKey: true })
      const handled = new KeyboardEvent("keydown", { key: "b", ctrlKey: true, bubbles: true, cancelable: true })
      handled.preventDefault()
      document.body.dispatchEvent(handled)
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "b", ctrlKey: true }))

      expect(element.dataset.state).toBe("collapsed")
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "b", ctrlKey: true }))
      expect(element.dataset.state).toBe("expanded")
    })

    it("leaves Ctrl+B to editable fields (rich-text bold)", async () => {
      const { element } = await mount(`
        ${html("false")}
        <textarea></textarea>
        <div contenteditable="true"><b>rich</b></div>
        <div contenteditable="false"><span id="plain">plain</span></div>`)

      const input = press(element.querySelector("input[type='search']"), { key: "b", ctrlKey: true })
      press(document.querySelector("textarea"), { key: "b", metaKey: true })
      press(document.querySelector("[contenteditable='true'] b"), { key: "b", ctrlKey: true })
      expect(input.defaultPrevented).toBe(false)
      expect(element.dataset.state).toBe("expanded")

      press(document.querySelector("#plain"), { key: "b", ctrlKey: true })
      expect(element.dataset.state).toBe("collapsed")
    })

    it("stops listening after disconnect", async () => {
      const { application, element } = await mount(html("false"))
      controllerFor(application, element, "sidebar-collapsible").disconnect()
      press(document.body, { key: "b", ctrlKey: true })
      expect(element.dataset.state).toBe("expanded")
    })
  })

  describe("tooltip", () => {
    const tip = (el) => el.querySelector("[role='tooltip']")
    const label = (el) => el.querySelector("[data-sidebar-collapsible-target='tooltipLabel']")
    const kbd = (el) => el.querySelector("[data-sidebar-collapsible-target='tooltipShortcut']")

    it("shows the label and shortcut beside a hovered control", async () => {
      const { element } = await mount(html("false"))
      const button = collapseButton(element)

      button.dispatchEvent(new MouseEvent("pointerover", { bubbles: true }))
      expect(tip(element).classList.contains("hidden")).toBe(false)
      expect(tip(element).classList.contains("flex")).toBe(true)
      expect(label(element).textContent).toBe("Collapse sidebar")
      expect(kbd(element).textContent).toBe("⌘B")
      expect(kbd(element).classList.contains("hidden")).toBe(false)
      const rect = button.getBoundingClientRect()
      expect(tip(element).style.left).toBe(`${rect.right + 8}px`)
      expect(tip(element).style.top).toBe(`${rect.top + rect.height / 2}px`)
    })

    it("hides the shortcut chip for controls without one", async () => {
      const { element } = await mount(html("true"))
      expandButton(element).dispatchEvent(new MouseEvent("pointerover", { bubbles: true }))
      expect(label(element).textContent).toBe("Expand sidebar")
      expect(kbd(element).textContent).toBe("")
      expect(kbd(element).classList.contains("hidden")).toBe(true)
    })

    it("stays open while the pointer moves within the control and closes when it leaves", async () => {
      const { element } = await mount(`
        <div data-controller="sidebar-collapsible">
          <div data-sidebar-collapsible-target="rail">
            <a data-sidebar-rail-label="Entities"><svg></svg></a>
            <a data-sidebar-rail-label="">blank</a>
          </div>
          ${tooltip}
        </div>`)
      const link = element.querySelector("[data-sidebar-rail-label='Entities']")

      link.dispatchEvent(new MouseEvent("pointerover", { bubbles: true }))
      link.querySelector("svg").dispatchEvent(new MouseEvent("pointerout", { bubbles: true, relatedTarget: link }))
      expect(label(element).textContent).toBe("Entities")

      link.dispatchEvent(new MouseEvent("pointerout", { bubbles: true, relatedTarget: null }))
      expect(tip(element).classList.contains("hidden")).toBe(true)
      expect(label(element).textContent).toBe("")

      element.querySelector("[data-sidebar-rail-label='']").dispatchEvent(new MouseEvent("pointerover", { bubbles: true }))
      element.dispatchEvent(new MouseEvent("pointerover", { bubbles: true }))
      element.dispatchEvent(new MouseEvent("pointerout", { bubbles: true }))
      expect(tip(element).classList.contains("hidden")).toBe(true)
    })

    it("opens on keyboard focus but not on focus without focus-visible", async () => {
      const { element } = await mount(html("false"))
      const button = collapseButton(element)

      button.dispatchEvent(new FocusEvent("focusin", { bubbles: true }))
      expect(tip(element).classList.contains("hidden")).toBe(true)

      button.focus()
      expect(label(element).textContent).toBe("Collapse sidebar")
      button.dispatchEvent(new FocusEvent("focusout", { bubbles: true, relatedTarget: document.body }))
      expect(tip(element).classList.contains("hidden")).toBe(true)
    })

    it("closes when the state changes", async () => {
      const { application, element } = await mount(html("false"))
      collapseButton(element).dispatchEvent(new MouseEvent("pointerover", { bubbles: true }))
      controllerFor(application, element, "sidebar-collapsible").toggle()
      await tick()
      expect(tip(element).classList.contains("hidden")).toBe(true)
      expect(kbd(element).textContent).toBe("")
    })

    it("stops reacting after disconnect", async () => {
      const { application, element } = await mount(html("false"))
      controllerFor(application, element, "sidebar-collapsible").disconnect()
      collapseButton(element).dispatchEvent(new MouseEvent("pointerover", { bubbles: true }))
      expect(tip(element).classList.contains("hidden")).toBe(true)
    })

    it("does nothing without a tooltip target", async () => {
      const { application, element } = await mount(`
        <div data-controller="sidebar-collapsible">
          <button data-sidebar-rail-label="Entities">x</button>
        </div>`)
      const ctrl = controllerFor(application, element, "sidebar-collapsible")
      const button = element.querySelector("button")
      ctrl.showTip({ target: button })
      ctrl.hideTip({ target: button, relatedTarget: null })
      ctrl.toggle()
      expect(element.querySelector("[role='tooltip']")).toBeNull()
    })
  })
})
